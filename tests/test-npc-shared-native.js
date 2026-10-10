'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const addon = require(path.resolve(process.argv[2]));
const installed = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
// Acceptance fixture: the installed 102-plugin cast (48 full, 54 light since the
// engine loads light plugins, #1715), never a saved live world.
const originalExpectedLoaded = 11273, completionLimitMs = 300000;
let expectedLoaded = originalExpectedLoaded;
const populationMode = process.argv[5] === '--population';
const enumerationMode = process.argv[5] === '--enumerate-native-eligible';
const populationEnumerationMode = process.argv[5] === '--enumerate-population-native-eligible';
assert.ok(!process.argv[5] || populationMode || enumerationMode || populationEnumerationMode,'Known optional acceptance mode');
// One cold native placed-form load cannot yield midway through construction.
// Keep it separate from steady activity and do not accumulate a loading batch.
const maxCallbackMs = 50, maxColdLoadMs = 100, maxRssBytes = 2 * 1024 ** 3;
assert.equal(installed.loadOrder.length, 102, 'Use the actual installed 102-plugin fixture');
const server = new addon.ScampServer(JSON.stringify({port:0,maxPlayers:2,offlineMode:true,
  name:'npc-shared-native-check',dataDir:path.dirname(installed.loadOrder[0]),
  loadOrder:installed.loadOrder,npcEnabled:true,npcAllowEssential:true,npcAllowCrimeFaction:true,
  npcSettings:{},logLevel:'error',
  ...(populationMode || populationEnumerationMode ? {bannedEspmCharacterRaceIds:[0x10760a]} : {})}));
console.log('Native server constructed with '+installed.loadOrder.length+' plugins');
server._setSelf(server);
// Obtain the exact native eligibility set in a separate, short-lived process.
// It exits before the policy process loads any actors, so cut identities never
// remain allocated as disabled old actors in the policy acceptance world.
if(enumerationMode || populationEnumerationMode) {
  let cursor = 0, total = server.prepareNpcLoad(), peak = process.memoryUsage().rss;
  const ids = new Set();
  while(cursor < total) {
    const batch = server.loadNpcBatch(cursor,8);
    assert.ok(batch.nextCursor > cursor && batch.nextCursor <= batch.total);
    cursor = batch.nextCursor;total = batch.total;
    for(const id of batch.actorIds) {
      assert.notEqual(server.getDescFromId(id),'14:Skyrim.esm','Baseline cannot create the human reference');
      assert.ok(!ids.has(id),'Native preload must enumerate identities once');
      ids.add(id);
    }
    peak = Math.max(peak,process.memoryUsage().rss);
    assert.ok(peak <= maxRssBytes,'Baseline native identity enumeration must stay below 2 GiB RSS');
  }
  if(enumerationMode) assert.equal(ids.size,originalExpectedLoaded,'Verify the unchanged native eligibility fixture');
  assert.deepEqual(server.getLoadedNpcIds(),[...ids].sort((a,b) => a-b));
  console.log(JSON.stringify({nativeEligibleIds:[...ids],peakRssMiB:peak/1048576,candidates:total}));
  process.exit(0);
}
// Optional isolated previous source supports RED verification without editing
// the working runtime while its replacement is under review.
const sourcePath = process.argv[4] || path.join(__dirname,'../game/gamemode.js');
const source = fs.readFileSync(sourcePath,'utf8');
const context = {Buffer,Math,Date,Number,Map,Set,JSON};
vm.createContext(context);
vm.runInContext(source.slice(source.indexOf('// NPC SERVER RUNTIME BEGIN'),
  source.indexOf('// NPC SERVER RUNTIME END')),context);
let populationData = null, expectedIds = null, cutIds = null, baselineSummary = null;
const expectedTierById = new Map();
const pluginNames = installed.loadOrder.map(file => path.basename(file));
if(populationMode) {
  const policyBegin = source.indexOf('// NPC POPULATION POLICY BEGIN');
  const policyEnd = source.indexOf('// NPC POPULATION POLICY END');
  const dataBegin = source.indexOf('// NPC POPULATION DATA BEGIN');
  const dataEnd = source.indexOf('// NPC POPULATION DATA END');
  assert.ok(policyBegin >= 0 && policyEnd > policyBegin && dataBegin >= 0 && dataEnd > dataBegin);
  vm.runInContext(source.slice(policyBegin,policyEnd)+'\n'+source.slice(dataBegin,dataEnd)+
    '\n globalThis.populationData=NPC_POPULATION_DATA;',context);
  populationData = context.populationData;
  assert.ok(populationData && populationData.version === 1,'Use generated production population data');
  assert.deepEqual(Array.from(populationData.plugins),pluginNames,'Population catalogue must match all installed plugins in order');
  let exclusionsAttempted = false;
  assert.throws(() => context.createNpcPopulation({setNpcPlacementExclusions() { exclusionsAttempted = true; }},
    populationData,pluginNames.slice().reverse()),/does not match the installed load order/);
  assert.equal(exclusionsAttempted,false,'Reject a stale catalogue before native exclusions change');
  const humanId = server.getIdFromDesc('14:Skyrim.esm');
  assert.throws(() => server.setNpcPlacementExclusions([humanId]),/existing placed NPC identities/,
    'Native policy exclusions must protect the human reference');
  cutIds = new Set(populationData.cut.map(desc => server.getIdFromDesc(desc)));
  const keepIds = new Set(populationData.keep.map(row => server.getIdFromDesc(row[0])));
  for(const row of populationData.keep) expectedTierById.set(server.getIdFromDesc(row[0]),row[8] || 0);
  assert.equal(cutIds.size,populationData.cut.length,'Cut catalogue identities are unique');
  assert.equal(keepIds.size,populationData.keep.length,'Retained catalogue identities are unique');
  assert.ok(!cutIds.has(humanId),'Production catalogue cannot exclude the human reference');
  for(const id of keepIds) assert.ok(!cutIds.has(id),'Retained and cut catalogues cannot overlap');
  const baselineRoot = path.resolve(__dirname,'../../../temp/whiterun-release');
  fs.mkdirSync(baselineRoot,{recursive:true});
  const baselineDirectory = fs.mkdtempSync(path.join(baselineRoot,'npc-baseline-'));
  try {
    const output = require('node:child_process').execFileSync(process.execPath,
      [__filename,process.argv[2],process.argv[3],sourcePath,'--enumerate-population-native-eligible'],
      {cwd:baselineDirectory,encoding:'utf8',maxBuffer:4*1024*1024,timeout:300000});
    const line = output.split(/\r?\n/).find(value => value.startsWith('{"nativeEligibleIds":'));
    assert.ok(line,'Isolated native baseline must report exact identities');
    const baseline = JSON.parse(line), baselineIds = new Set(baseline.nativeEligibleIds);
    assert.equal(baselineIds.size,baseline.nativeEligibleIds.length,'Independent native baseline identities are unique');
    assert.ok(baseline.peakRssMiB <= maxRssBytes/1048576);
    for(const id of baselineIds) assert.ok(keepIds.has(id) || cutIds.has(id),
      'Catalogue must account for each original native-eligible placement');
    expectedIds = new Set([...baselineIds].filter(id => keepIds.has(id)));
    expectedLoaded = expectedIds.size;
    assert.equal(expectedLoaded,keepIds.size,'Every retained source identity must be native eligible with the population race configuration');
    baselineSummary = {nativeEligible:baselineIds.size,originalDefaultRaceNativeEligible:originalExpectedLoaded,
      raceConfigurationDelta:baselineIds.size-originalExpectedLoaded,bannedEspmCharacterRaceIds:[0x10760a],retainedNativeEligible:expectedLoaded,
      excludedNativeEligible:[...baselineIds].filter(id => cutIds.has(id)).length,
      catalogueKeep:keepIds.size,catalogueCut:cutIds.size,baselinePeakRssMiB:baseline.peakRssMiB};
    assert.equal(baselineSummary.retainedNativeEligible+baselineSummary.excludedNativeEligible,baselineIds.size);
    console.log(JSON.stringify({populationAcceptance:baselineSummary}));
  } finally {
    const ownedDirectory = fs.realpathSync(baselineDirectory);
    assert.equal(path.dirname(ownedDirectory),fs.realpathSync(baselineRoot),'Cleanup stays inside the owned baseline fixture root');
    fs.rmSync(ownedDirectory,{recursive:true,force:true});
  }
}
let time = Date.now(), sequence = 0, current = null, callbackAt = 0, callbacks = 0;
let runtime = null, restarting = false, peakRss = process.memoryUsage().rss;
const pending = new Map(), loaded = new Set(), controlled = new Set(), moved = new Set();
const observedNativeIds = new Set();
const protectedHumanId = server.getIdFromDesc('14:Skyrim.esm');
const unavailable = new Set(), lines = [], positions = new Map(), firstWrites = new Map();
const acceptedAttackers = new Set();
const attackAttempts = new Map(), nativeStates = new Map();
const nativeSpeeds = new Map(), stoppedActors = new Set();
const savedBeforeRestart = new Map(), writeSequences = new Map();
const validationFailures = [];
const worst = {callback:0,callbackTask:'',load:0,state:0,nav:0,geometry:0,movement:0,attack:0};
const timers = {
  setTimeout(fn,delay) {
    assert.ok(Number.isFinite(delay) && delay >= 0, 'Scheduled delay is finite and nonnegative');
    const id = ++sequence;
    pending.set(id,{fn,at:time+delay,name:fn.npcRuntimeTask || fn.name || fn.toString().slice(0,120)});
    return id;
  },
  clearTimeout(id) { pending.delete(id); }
};
function sampleRss() {
  peakRss = Math.max(peakRss,process.memoryUsage().rss);
  assert.ok(peakRss <= maxRssBytes,'Native runtime exceeded 2 GiB RSS: '+(peakRss/1048576).toFixed(1)+' MiB');
}
function log(line) {
  lines.push(line);
  const rejection = /^NPC ([0-9a-f]+) remains loaded; activity unavailable:/.exec(line);
  if(rejection) unavailable.add(parseInt(rejection[1],16));
}
const api = {};
if(populationMode) assert.equal(typeof server.setNpcDifficultyTier,'function','Population acceptance requires the native difficulty tier setter');
for(const method of ['makeProperty','get','getIdFromDesc','getDescFromId','getLoadedNpcIds',
  'setNpcPlacementExclusions','getFactionReactions','serverNpcAttack','stopNpcMovement'])
  api[method] = server[method].bind(server);
if(populationMode) api.setNpcDifficultyTier = server.setNpcDifficultyTier.bind(server);
api.getLoadedNpcIds = () => {
  const ids = server.getLoadedNpcIds();
  for(const id of ids) {
    assert.ok(Number.isSafeInteger(id) && id > 0);
    assert.notEqual(id,protectedHumanId,'Native discovery cannot enroll the human reference');
    if(populationMode) assert.ok(expectedIds.has(id),'Fresh policy discovery must stay inside the exact retained intersection');
    observedNativeIds.add(id);
  }
  return ids;
};
api.stopNpcMovement = id => {
  assert.ok(controlled.has(id),'A terminal stop must retain native server authority');
  const position = server.get(id,'locationalData').pos.slice();
  server.stopNpcMovement(id);
  nativeSpeeds.set(id,0);stoppedActors.add(id);
  assert.deepEqual(server.get(id,'locationalData').pos,position,
    'A trusted stop cannot translate an actor onto assumed navigation');
};
api.serverNpcAttack = (id,target) => {
  const count = attackAttempts.get(id) || {attempted:0,accepted:0,rejected:0,errors:0};
  const actorState = nativeStates.get(id), targetState = nativeStates.get(target);
  count.attempted++;
  count.last = {at:time,target:target.toString(16),
    distance:actorState && targetState ? Math.hypot(...actorState.pos.map((v,i) => v-targetState.pos[i])) : null,
    actorPosition:actorState && actorState.pos,targetPosition:targetState && targetState.pos,
    actorReach:actorState && actorState.meleeReach,targetAllowance:targetState && targetState.meleeAllowance};
  attackAttempts.set(id,count);
  try {
    const accepted = timed('attack','serverNpcAttack',[id,target]);
    if(accepted) { acceptedAttackers.add(id);count.accepted++; }
    else count.rejected++;
    return accepted;
  } catch(error) {
    count.errors++;count.last.error = String(error);
    throw error;
  }
};
function timed(key,method,args) {
  const at = performance.now(), out = server[method](...args);
  worst[key] = Math.max(worst[key],performance.now()-at);
  return out;
}
api.loadNpcBatch = (cursor,limit) => {
  const batch = timed('load','loadNpcBatch',[cursor,limit]);
  batch.actorIds.forEach(id => { loaded.add(id);observedNativeIds.add(id); });
  return batch;
};
api.getNpcAIState = id => {
  const state = timed('state','getNpcAIState',[id]);
  nativeStates.set(id,state);
  return state;
};
api.getNavmeshRecords = (cell,pos) => timed('nav','getNavmeshRecords',[cell,pos]);
api.lookupEspmRecordById = id => timed('geometry','lookupEspmRecordById',[id]);
api.setNpcServerControlled = (id,on) => {
  assert.ok(observedNativeIds.has(id),'Authority must use an independently observed existing native identity');
  server.setNpcServerControlled(id,on);
  if(on) {
    controlled.add(id);
    positions.set(id,server.get(id,'locationalData').pos.slice());
  } else controlled.delete(id);
};
api.set = (id,property,value) => {
  server.set(id,property,value);
  if(property !== 'thornswoodNpcActivity') return;
  assert.equal(value.version,2);
  assert.ok(Number.isSafeInteger(value.sequence),'Persist a finite integer activity sequence');
  if(!firstWrites.has(id)) {
    firstWrites.set(id,value.sequence);
    if(restarting && savedBeforeRestart.has(id)) {
      assert.equal(value.sequence,savedBeforeRestart.get(id).sequence,
        'Reload must recover the saved sequence for '+id.toString(16));
    }
  }
  if(writeSequences.has(id)) {
    assert.ok(value.sequence >= writeSequences.get(id),'Saved activity sequence cannot go backwards');
  }
  writeSequences.set(id,value.sequence);
};
api.updateNpcMovement = (id,pos,rot,speed) => {
  assert.ok(controlled.has(id),'Movement requires current native server authority');
  const previous = positions.get(id);
  timed('movement','updateNpcMovement',[id,pos,rot,speed]);
  nativeSpeeds.set(id,speed);
  // Check native positions, rather than treating a speed argument as proof.
  // The engine holds a position as three 32-bit floats (NiPoint3), which past
  // 131072 units from the origin are 1/64 of a unit apart, so a shorter step
  // is stored as no step. The runtime keeps its own position in doubles and
  // steps on from that, so the engine catches up on the next step (#2032: the
  // Castle Volkihar skeletons 2013cc0 and 2013cc2, at x -173213, were asked
  // for 0.011 units on the first tick after the reload).
  const engineCanMove = previous && pos.some((v,i) => Math.fround(v) !== Math.fround(previous[i]));
  if(!moved.has(id) && engineCanMove) {
    const actual = server.get(id,'locationalData').pos;
    assert.ok(Math.hypot(...actual.map((v,i) => v-previous[i])) > 0.000001,
      'Native position must advance for '+id.toString(16));
    assert.ok(Math.hypot(...actual.map((v,i) => v-pos[i])) < 0.25,
      'Native movement must reach the submitted safe position');
    moved.add(id);
  }
  positions.set(id,pos.slice());
  current.moves++;
};
// Production catches actor-local failures. Assertions in these instrumented
// APIs must still fail the test, rather than turning a defect into an exclusion.
for(const method of ['setNpcServerControlled','set','updateNpcMovement','stopNpcMovement','getLoadedNpcIds']) {
  const original = api[method];
  api[method] = (...args) => {
    try { return original(...args); }
    catch(error) {
      if(error instanceof assert.AssertionError) validationFailures.push(error.message);
      throw error;
    }
  };
}
const indexed = performance.now(), candidates = server.prepareNpcLoad();
const indexingMs = performance.now()-indexed;
console.log('Indexed '+candidates+' existing NPC candidates');
sampleRss();
const sampledNow = () => time+(callbackAt ? performance.now()-callbackAt : 0);
function advance(ms) {
  const until = time+ms;
  let calls = 0;
  while(pending.size) {
    const [id,task] = [...pending].sort((a,b) => a[1].at-b[1].at || a[0]-b[0])[0];
    if(task.at > until) break;
    time = task.at;
    pending.delete(id);
    current = {moves:0};
    callbackAt = performance.now();
    let duration=0;
    try { task.fn(); }
    finally {
      duration = performance.now()-callbackAt;
      callbackAt = 0;
      if(duration > worst.callback) { worst.callback = duration; worst.callbackTask = task.name; }
    }
    assert.ok(current.moves <= 96,'A scheduled callback must bound movement work');
    assert.deepEqual(validationFailures,[],'Actor-local catches must not hide acceptance assertion failures');
    const durationLimit=task.name==='preload' ? maxColdLoadMs : maxCallbackMs;
    assert.ok(duration <= durationLimit,
      'Scheduled callback exceeded '+durationLimit+' ms: '+task.name+' '+duration.toFixed(2)+' ms');
    if(++callbacks % 100 === 0) sampleRss();
    assert.ok(++calls < 200000,'Runtime must yield with finitely many scheduled callbacks');
  }
  time = until;
  sampleRss();
}
function status() {
  assert.equal(typeof runtime.getStatus,'function','Expose complete cast preparation and authority diagnostics');
  const state = runtime.getStatus();
  for(const field of ['loaded','controlled','active','unavailable','preparing','pendingMeshes']) {
    assert.ok(Number.isSafeInteger(state[field]) && state[field] >= 0,'Finite diagnostic count: '+field);
  }
  assert.equal(state.loaded,loaded.size,'Diagnostics reflect all unique loaded native identities');
  assert.equal(state.controlled,controlled.size,'Diagnostics reflect current native authority');
  assert.equal(state.unavailable,unavailable.size,'Unavailable identities are unique and observable');
  // Native discovery can enroll existing actors before their preload batch is
  // revisited during gamemode reload. Native observations, not batch order,
  // establish their identity; completion still requires the exact full batch.
  assert.ok(state.controlled <= observedNativeIds.size,'Ownership cannot create extra native identities');
  assert.ok(state.active <= state.controlled,'Every active identity must be server owned');
  assert.ok(state.active+state.unavailable <= observedNativeIds.size,'Active and stationary classifications cannot count a native identity twice');
  assert.ok(typeof state.loadingComplete === 'boolean');
  return state;
}
function finishPreparation(stage) {
  const start = time;
  while(time-start < completionLimitMs) {
    advance(1000);
    const state = status();
    if(state.loadingComplete && state.preparing === 0 && state.pendingMeshes === 0 &&
        state.active+state.unavailable === state.loaded) break;
  }
  const state = status();
  console.log(JSON.stringify({stage,elapsedMs:time-start,status:state,peakRssMiB:peakRss/1048576,worst}));
  assert.equal(loaded.size,expectedLoaded,'Load every identity in the installed cast');
  assert.equal(state.loadingComplete,true,'Native loading must finish');
  assert.equal(state.preparing,0,'Every queued actor must finish preparation within five simulated minutes');
  assert.equal(state.pendingMeshes,0,'Navigation preparation must finish within five simulated minutes');
  assert.equal(controlled.size,expectedLoaded,'Every existing native NPC remains server owned, including stationary actors');
  assert.equal(observedNativeIds.size,expectedLoaded,'Native discovery and preloading must identify exactly the same cast');
  assert.equal(state.active+state.unavailable,expectedLoaded,'Every identity is active or stationary');
  for(const id of loaded) {
    assert.ok(controlled.has(id),'No loaded NPC may return to client hosting');
    const nativeState = server.getNpcAIState(id);
    assert.equal(nativeState.isServerControlled,true,'Native authority must persist for '+id.toString(16));
    if(populationMode) assert.equal(nativeState.difficultyTier,expectedTierById.get(id),
      stage+' native difficulty must match the source row for '+id.toString(16));
  }
  if(populationMode) {
    const nativeLoaded = new Set(server.getLoadedNpcIds());
    assert.equal(nativeLoaded.size,expectedIds.size,'Preparation must load the exact policy cast');
    for(const id of expectedIds) assert.ok(nativeLoaded.has(id) && controlled.has(id),'Every source-retained identity must be loaded and owned');
    for(const id of cutIds) assert.ok(!nativeLoaded.has(id),'Fresh policy world must exclude every cut identity');
    console.log(JSON.stringify({stage,tierVerified:controlled.size,exactRetained:expectedIds.size,cutAbsent:cutIds.size}));
  }
  for(const id of unavailable) {
    assert.ok(loaded.has(id),'Every stationary identity belongs to the loaded cast');
    assert.ok(controlled.has(id),'Unavailable navigation cannot release native authority');
  }
}
function proveActivity(stage) {
  // A fresh window after preparation prevents initial motion alone passing.
  moved.clear();
  acceptedAttackers.clear();
  attackAttempts.clear();
  const stationaryPositions = new Map([...unavailable].map(id =>
    [id,server.get(id,'locationalData').pos.slice()]));
  const eligible = [...controlled].filter(id => {
    if(unavailable.has(id)) return false;
    const state = server.getNpcAIState(id);
    return !state.isDead && !state.isDisabled && !state.immobile;
  });
  assert.ok(eligible.length > 1000,'Exercise a substantial eligible native cast');
  advance(120000);
  // Native combat can kill an eligible actor before its first scheduled turn.
  // Freeze activity evidence at the window boundary, then give terminal actors
  // a bounded fair sweep to publish their native stop and prove it stays still.
  const windowMoved = new Set(moved), windowAttackers = new Set(acceptedAttackers);
  const terminalPositions = new Map();
  for(const id of controlled) {
    if(unavailable.has(id)) continue;
    const state = server.getNpcAIState(id);
    if(state.isDead || state.isDisabled || state.immobile) {
      terminalPositions.set(id,state.pos.slice());
    }
  }
  if(populationMode) {
    const nativeLoaded = new Set(server.getLoadedNpcIds());
    assert.equal(nativeLoaded.size,expectedIds.size,'A fresh policy world cannot keep allocated cut identities');
    for(const id of expectedIds) {
      assert.ok(loaded.has(id) && nativeLoaded.has(id) && controlled.has(id),
        'Each catalogue-retained native-eligible placement must load and remain owned: '+id.toString(16));
    }
    for(const id of loaded) assert.ok(expectedIds.has(id),'Policy cannot load an identity outside the exact retained intersection');
    for(const id of cutIds) assert.ok(!nativeLoaded.has(id) && !loaded.has(id),'Fresh policy world cannot load a cut placement');
  }
  advance(10000);
  for(const [id,position] of terminalPositions) {
    const native = server.getNpcAIState(id), activity = runtime.getActorStatus(id);
    assert.ok(controlled.has(id) && native.isServerControlled,'Terminal actors retain native authority');
    assert.equal(activity && activity.paused,true,'Terminal actor must pause after a fair scheduled sweep: '+id.toString(16));
    assert.deepEqual(Array.from(activity.path),[],'Paused actors cannot retain a route');
    assert.equal(activity.target,0,'Paused actors cannot retain a combat target');
    assert.ok(stoppedActors.has(id),'Terminal actor must call the native trusted stop: '+id.toString(16));
    assert.equal(nativeSpeeds.get(id),0,'Last native movement command must set zero speed');
    assert.deepEqual(native.pos,position,'Terminal actor must remain at its stopped native position');
  }
  for(const [id,position] of stationaryPositions) {
    assert.ok(controlled.has(id),'Stationary actors must remain server owned');
    assert.equal(server.getNpcAIState(id).isServerControlled,true);
    assert.deepEqual(server.get(id,'locationalData').pos,position,
      'Unavailable navigation cannot move a stationary actor: '+id.toString(16));
    assert.ok(!moved.has(id),'A stationary actor cannot enter the movement runtime');
  }
  let progressedSequences = 0;
  for(const id of eligible) {
    assert.ok(controlled.has(id),'Prepared actor must keep working: '+id.toString(16));
    if(terminalPositions.has(id)) continue;
    if(!windowMoved.has(id) && !windowAttackers.has(id)) {
      reportIdleActor(id,stage);
    }
    assert.ok(windowMoved.has(id) || windowAttackers.has(id),stage+' native activity missing for '+id.toString(16));
    const saved = server.get(id,'thornswoodNpcActivity');
    assert.equal(saved.version,2);
    if(saved.sequence > firstWrites.get(id)) progressedSequences++;
    if(saved.mode === 'ambient') {
      assert.ok(saved.sequence > firstWrites.get(id),stage+' must persist actual ambient activity progress');
    }
  }
  assert.ok(windowMoved.size > 1000,stage+' must physically move a substantial native cast');
  assert.ok(progressedSequences > 1000,stage+' must persist sequence progress across the native cast');
  console.log(JSON.stringify({stage,eligible:eligible.length,moved:windowMoved.size,acceptedAttackers:windowAttackers.size,
    terminalPaused:terminalPositions.size,
    progressedSequences,status:status(),peakRssMiB:peakRss/1048576,worst}));
}
function diagnosticRead(fn) {
  try { return fn(); }
  catch(error) { return {diagnosticError:String(error)}; }
}
function actorDetails(id) {
  if(!id) return null;
  return {id:id.toString(16),state:diagnosticRead(() => server.getNpcAIState(id)),
    location:diagnosticRead(() => server.get(id,'locationalData')),
    inventory:diagnosticRead(() => server.get(id,'inventory')),
    equipment:diagnosticRead(() => server.get(id,'equipment')),
    activity:diagnosticRead(() => runtime.getActorStatus(id)),
    saved:diagnosticRead(() => server.get(id,'thornswoodNpcActivity'))};
}
function sourceDetails(equipment) {
  const entries = equipment && equipment.inv && equipment.inv.entries || [];
  const sources = new Set([0x1f4,...entries.map(entry => entry.baseId).filter(Number.isInteger)]);
  return [...sources].map(id => diagnosticRead(() => {
    const record = server.lookupEspmRecordById(id).record;
    return {id:id.toString(16),type:record.type,editorId:record.editorId,
      fields:record.fields.filter(field => ['DNAM','DATA','OBND'].includes(field.type))
        .map(field => ({type:field.type,bytes:Buffer.from(field.data).toString('hex')}))};
  }));
}
function reportIdleActor(id,stage) {
  const actor = actorDetails(id);
  const targetId = actor.activity && actor.activity.target || actor.state && actor.state.combatTarget || 0;
  const target = actorDetails(targetId);
  const distance = target && Array.isArray(actor.state.pos) && Array.isArray(target.state.pos) ?
    Math.hypot(...actor.state.pos.map((v,i) => v-target.state.pos[i])) : null;
  console.log(JSON.stringify({idleId:id.toString(16),stage,actor,target,distance,
    attempts:attackAttempts.get(id) || {attempted:0,accepted:0,rejected:0,errors:0},
    targetAttempts:attackAttempts.get(targetId) || null,equippedSources:sourceDetails(actor.equipment)}));
}
try {
  let population = populationMode ? context.createNpcPopulation(api,populationData,pluginNames) : null;
  runtime = context.startSharedNpcServerRuntime(api,timers,sampledNow,log,population);
  finishPreparation('initial preparation');
  proveActivity('before gamemode reload');
  const originalIds = new Set(loaded);
  runtime.stop();
  assert.equal(pending.size,0,'Stop must cancel every scheduled callback');
  for(const id of controlled) {
    const saved = server.get(id,'thornswoodNpcActivity');
    if(saved && Number.isSafeInteger(saved.sequence)) savedBeforeRestart.set(id,saved);
  }
  server.clear();
  controlled.clear();unavailable.clear();moved.clear();positions.clear();firstWrites.clear();writeSequences.clear();
  nativeSpeeds.clear();stoppedActors.clear();
  loaded.clear();observedNativeIds.clear();restarting = true;
  population = populationMode ? context.createNpcPopulation(api,populationData,pluginNames) : null;
  runtime = context.startSharedNpcServerRuntime(api,timers,sampledNow,log,population);
  finishPreparation('gamemode reload preparation');
  assert.equal(loaded.size,originalIds.size);
  for(const id of loaded) assert.ok(originalIds.has(id),'Reload must preserve each existing cast identity');
  for(const id of controlled) {
    if(savedBeforeRestart.has(id) && firstWrites.has(id)) {
      assert.equal(firstWrites.get(id),savedBeforeRestart.get(id).sequence);
    } else if(savedBeforeRestart.has(id)) {
      const saved = server.get(id,'thornswoodNpcActivity');
      assert.ok(saved,'Stationary ownership cannot discard persisted activity');
      assert.equal(saved.sequence,savedBeforeRestart.get(id).sequence);
    }
  }
  proveActivity('after gamemode reload');
  runtime.stop();
  assert.equal(pending.size,0);
  console.log(JSON.stringify({passed:true,population:baselineSummary,candidates,indexingMs,loadedForms:server.getLoadedFormCount(),
    loaded:loaded.size,controlled:controlled.size,unavailable:unavailable.size,peakRssMiB:peakRss/1048576,worst,
    reasons:lines.filter(line => line.includes('activity unavailable')).slice(0,30)}));
  process.exit(0);
} catch(error) {
  if(runtime) runtime.stop();
  console.error(JSON.stringify({passed:false,error:error.stack,loaded:loaded.size,controlled:controlled.size,
    unavailable:unavailable.size,peakRssMiB:peakRss/1048576,worst,
    status:runtime && typeof runtime.getStatus === 'function' ? runtime.getStatus() : null}));
  process.exit(1);
}
