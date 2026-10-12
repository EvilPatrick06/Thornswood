// test-1621-quest-state.js
//
// #1621. An open custom quest, what it has drawn or killed, and each
// person's cooldowns survive a server restart. They are kept on the
// character, in one property beside the pack, the way the perk clocks are.
//
// The custom quests block is run the way the server starts it, over a
// pretend world whose characters are change forms: a pack and the custom
// properties. A restart throws the block away, round-trips every change form
// through JSON the way the database does, and starts the block again from
// that. A record that cannot be read refuses every step and is never
// written over; a step that cannot be written changes nothing.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(path.join(REPO_DIR, 'game', 'gamemode.js'), 'utf8').split(CR).join('');
const questPage = fs.readFileSync(path.join(REPO_DIR, 'docs', 'systems', 'quests.md'), 'utf8').split(CR).join('');
const minerPage = fs.readFileSync(path.join(REPO_DIR, 'docs', 'systems', 'classes', 'miner.md'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}

const block = slice(gm, '// ==== thornswood custom quests ====', '// ==== end thornswood custom quests ====');
yes('the custom quests block is in the gamemode', !!block);
if (!block) { console.log('\n' + pass + ' passed, ' + fail + ' failed'); process.exit(1); }

const PROP = (/var QUEST_PROPERTY = '([^']+)';/.exec(block) || [])[1];
yes('the block names the property it keeps each person\'s quests in', PROP === 'thornswoodQuests');
yes('and keeps no map of people in the process', !/new Map\(\)/.test(block) && !/\bpeople\b/.test(block));
const EBONY_CELL = (/ebony: \{ cell: '([^']+)' \}/.exec(block) || [])[1];
const RUBY_CELL = (/Ruby: '([^']+)'/.exec(block) || [])[1];
yes('the ebony and ruby places are bound by cell', !!EBONY_CELL && !!RUBY_CELL);

const HOUR = 3600000;
const EBONY = { name: 'Ebony Ore', ore: '5ad9d:Skyrim.esm' };
const RUBY = { name: 'Ruby', ore: '63b42:Skyrim.esm' };

/*
  The saved world. forms[actor] is that character's change form: inv is the
  pack, props the custom properties. What a restart reads is what is here.
*/
let forms = {};
const clock = { now: 1000000 };
const ranks = { '1:miner': 'master', '2:miner': 'master', '3:miner': 'master', '4:miner': 'master' };
const veinCell = {};
let nextVein = 0x9000;
function vein(cell) { const ref = nextVein++; veinCell[ref] = cell; return ref; }
function form(id) {
  if (!forms[id]) { forms[id] = { inv: {}, props: {} }; }
  return forms[id];
}
function have(id, item) { return (forms[id] && forms[id].inv[item]) || 0; }
const fault = { read: null, write: false, noAdd: [], throwAdd: [] };
const said = [];
function lastSaid() { return said.length ? said[said.length - 1] : ''; }

function boot(into) {
  const made = {};
  const logged = [];
  const ctx = into || {
    console: { log: function () {} }, Map: Map, Set: Set, Math: Math, Number: Number, String: String,
    Buffer: Buffer, JSON: JSON, Object: Object, Array: Array, RegExp: RegExp, Error: Error,
    Date: { now: function () { return clock.now; } },
    idOf: function () { return 0; },
    classGate: function () { return null; },
    toolGate: function () { return null; },
    mining: function () { return false; },
    stopMining: function () {},
    swinging: function () { return false; },
    toolIdIn: function () { return 1; },
    swing: function (a, anim, done) { done(); },
    SWING_MINE: 'mine',
    notify: function (a, m) { said.push(m); },
    say: function () {},
    creditWork: function () { return null; },
    wearTool: function () { return null; }
  };
  ctx.__made = ctx.__made || made;
  ctx.__logged = logged;
  ctx.log = function () { logged.push([].slice.call(arguments).join(' ')); };
  ctx.mp = {
    makeProperty: function (name, opts) {
      if (ctx.__made[name]) { throw new Error('Property \'' + name + '\' already exists'); }
      ctx.__made[name] = opts;
    },
    get: function (id, key) {
      if (key === 'locationalData') { return veinCell[id] ? { cellOrWorldDesc: veinCell[id], pos: [0, 0, 0] } : undefined; }
      if (key === PROP && fault.read === 'throw') { throw new Error('the change form could not be read'); }
      if (!forms[id] || !(key in forms[id].props)) { return undefined; }
      return JSON.parse(JSON.stringify(forms[id].props[key]));
    },
    set: function (id, key, v) {
      if (!ctx.__made[key]) { throw new Error('Property \'' + key + '\' doesn\'t exist'); }
      if (key === PROP && fault.write) { throw new Error('the write was refused'); }
      form(id).props[key] = JSON.parse(JSON.stringify(v));
    },
    getDescFromId: function () { return ''; }
  };
  ctx.addItem = function (a, item, n) {
    if (fault.throwAdd.indexOf(item) >= 0) throw new Error('native inventory write failed');
    if (fault.noAdd.indexOf(item) >= 0) { return false; }
    const f = form(a);
    f.inv[item] = (f.inv[item] || 0) + n;
    return true;
  };
  ctx.takeItem = function (a, item, n) {
    const f = form(a);
    if ((f.inv[item] || 0) < n) { return false; }
    f.inv[item] -= n;
    return true;
  };
  ctx.MERCHANT_TRADING = {createQuestTransactions: function () {
    return {identity: function (a) {
      if(ctx.__runtimeIdentityApi)return require('../game/quest-transactions').actorIdentity(ctx.__runtimeIdentityApi,a);
      return ctx.__identityToken || 'actor:' + a;
    }, shutdown: function () {},available:function(){return !ctx.__revoked;},
      commit: function (a, expected, next, changes) {
        if (fault.write) throw new Error('the write was refused');
        const current = form(a);
        if (JSON.stringify(current.props[PROP] || null) !== JSON.stringify(expected)) return {ok:false};
        const pack = JSON.parse(JSON.stringify(current.inv));
        for (const change of changes) {
          if (fault.throwAdd.indexOf(change.item) >= 0 && change.count > 0) throw new Error('native inventory write failed');
          if (fault.noAdd.indexOf(change.item) >= 0 && change.count > 0) return {ok:false};
          const count = (pack[change.item] || 0) + change.count;
          if (count < 0) return {ok:false};
          pack[change.item] = count;
        }
        // The native boundary publishes a single complete character snapshot.
        forms[a] = {inv:pack,props:Object.assign({},current.props,{[PROP]:JSON.parse(JSON.stringify(next))})};
        if(ctx.__afterCommit)ctx.__afterCommit();
        return {ok:true};
      }
    };
  }};
  ctx.__thornswoodMerchantTrade={nativeReady:function(){return true;},questReady:function(){return true;}};
  ctx.globalThis = ctx;
  ctx.__thornswoodCharacter = { rankOf: function (a, key) { return ranks[a + ':' + key] || ''; } };
  ctx.__thornswoodDungeonLoot = { GOLD_DESC: 'f:Skyrim.esm' };
  if (!into) { vm.createContext(ctx); }
  vm.runInContext(block, ctx);
  return { svc: ctx.__thornswoodQuests, ctx: ctx, logged: logged };
}
function restart() {
  forms = JSON.parse(JSON.stringify(forms));
  return boot();
}

// ------------------------------------------------------------ the start --
let w = boot();
yes('the server starts the quest service', !!w.svc && !!w.svc.mineRare &&
    !w.logged.some(function (l) { return /failed to start/.test(l); }));
yes('the property is made, seen by nobody\'s client', !!w.ctx.__made[PROP] &&
    w.ctx.__made[PROP].isVisibleByOwner === false && w.ctx.__made[PROP].isVisibleByNeighbors === false);
{
  let threw = false;
  try { w.ctx.__thornswoodCustomQuestsCreate({ now: function () { return 0; } }); } catch (e) { threw = true; }
  yes('the block refuses to start with nowhere on the character to keep the quests', threw);
}

// ------------------------------------------- the draw, then a restart ----
const here = [vein(EBONY_CELL), vein(EBONY_CELL)];
yes('a master miner takes the ebony', w.svc.offer(1, 'ebony').ok === true);
for (let i = 0; i < 5; i++) { w.svc.mineRare(1, here[i % 2], EBONY); }
yes('and draws 5 of the 12', have(1, EBONY.ore) === 5);
yes('the open quest and its draw are on the character, not only in the process',
    forms[1].props[PROP] && forms[1].props[PROP].v === 1 && forms[1].props[PROP].open.ebony.drawn === 5);

w = restart();
yes('after a restart the ebony quest is still open', w.svc.offer(1, 'ebony').why === 'open');
let more = 0;
for (let i = 0; i < 10; i++) { if (w.svc.mineRare(1, here[i % 2], EBONY) === '') { more++; } }
yes('the place gives the 7 it had left and no more (' + more + ')',
    have(1, EBONY.ore) === 12 && /nothing left/.test(w.svc.mineRare(1, here[0], EBONY)));

w = restart();
yes('after a second restart, walking away puts all 12 back',
    w.svc.walkAway(1, 'ebony').ok === true && have(1, EBONY.ore) === 0);
yes('and the cooldown does not start', w.svc.offer(1, 'ebony').ok === true);
w.svc.walkAway(1, 'ebony');

// --------------------------------- the twelve-ebony trick, played out ----
yes('the trick: draw 12, wait for a restart', w.svc.offer(2, 'ebony').ok === true);
for (let i = 0; i < 12; i++) { w.svc.mineRare(2, here[0], EBONY); }
w = restart();
yes('then take the quest again at once: refused, it is still open',
    have(2, EBONY.ore) === 12 && w.svc.offer(2, 'ebony').why === 'open');
yes('and the place still has nothing left for them', /nothing left/.test(w.svc.mineRare(2, here[1], EBONY)));
yes('turned in after the restart, the ask goes and the extra stays',
    w.svc.turnIn(2, 'ebony').ok === true && have(2, EBONY.ore) === 8);
w = restart();
yes('a restart after the turn-in keeps the 24 hour cooldown', w.svc.offer(2, 'ebony').why === 'cooldown' &&
    w.svc.mineRare(2, here[0], EBONY) === 'This place is shut.');
clock.now += 24 * HOUR - 1;
w = restart();
yes('a second short of 24 hours, after another restart, it still holds', w.svc.offer(2, 'ebony').why === 'cooldown');
clock.now += 1;
yes('and at 24 hours the trader can open it again', w.svc.offer(2, 'ebony').ok === true);
w.svc.walkAway(2, 'ebony');
yes('a cooldown that has run out is left off the record',
    !forms[2].props[PROP].cool.ebony);

// ------------------------------------------------ the gem they named -----
yes('a ruby quest', w.svc.offer(3, 'gem', { gem: 'Ruby' }).ok === true);
w = restart();
const ruby = vein(RUBY_CELL);
yes('after a restart the ruby is still the gem, and its place is open to them',
    w.svc.mineRare(3, ruby, RUBY) === '' && have(3, RUBY.ore) === 1);
w.svc.walkAway(3, 'gem');

// -------------------------------------------------------- scene quests ---
w.svc.bindPlace('camp', { cell: 'camp-1' });
yes('anyone takes the camp', w.svc.offer(4, 'camp').ok === true);
const names = { 31: 'Bandit', 32: 'Bandit Outlaw', 33: 'Bandit' };
function bandit(id) { veinCell[id] = 'camp-1'; return id; }
// creatureName is the server's own, which reads the record; give the deaths a name by a stub over it.
function kill(svc, killer, id) { return svc.noteKill(killer, bandit(id)); }
w.ctx.mp.lookupEspmRecordById = function () { return null; };
w.ctx.mp.get = (function (get) {
  return function (id, key) { return key === 'baseDesc' ? names[id] : get(id, key); };
})(w.ctx.mp.get);
kill(w.svc, 4, 31); kill(w.svc, 4, 32);
yes('two of three bandits are counted on the character', forms[4].props[PROP].open.camp.kills === 2);
w = restart();
w.svc.bindPlace('camp', { cell: 'camp-1' });
w.ctx.mp.lookupEspmRecordById = function () { return null; };
w.ctx.mp.get = (function (get) {
  return function (id, key) { return key === 'baseDesc' ? names[id] : get(id, key); };
})(w.ctx.mp.get);
yes('after a restart the camp is not done', w.svc.turnIn(4, 'camp').why === 'short');
kill(w.svc, 4, 33);
yes('the third bandit finishes it and its 45 gold is created once',
    w.svc.turnIn(4, 'camp').ok === true && have(4, 'f:Skyrim.esm') === 45);
w = restart();
yes('a restart keeps the camp\'s 6 hour cooldown, so its gold cannot be taken again',
    w.svc.offer(4, 'camp').why === 'cooldown' && have(4, 'f:Skyrim.esm') === 45);

w.svc.bindPlace('satchel', { ref: 'sack-1', cell: 'road-1', item: 'satchel-item' });
yes('the satchel', w.svc.offer(4, 'satchel').ok === true && w.svc.noteContainer(4, 'sack-1', 'road-1') === 'You take it.');
w = restart();
w.svc.bindPlace('satchel', { ref: 'sack-1', cell: 'road-1', item: 'satchel-item' });
yes('after a restart the satchel taken is still counted: no second one',
    w.svc.noteContainer(4, 'sack-1', 'road-1') === null && have(4, 'satchel-item') === 1);
yes('and walking away puts it back', w.svc.walkAway(4, 'satchel').ok === true && have(4, 'satchel-item') === 0);

// ------------------------------------------------ a record rebuilt -------
forms[5] = { inv: {}, props: {} };
forms[5].props[PROP] = { v: 1, open: { ebony: { drawn: 2.5, kills: -1, itemDesc: 7 }, nothere: { drawn: 3 },
  constructor: { drawn: 1 } }, cool: { stalhrim: clock.now + HOUR, gem: clock.now - 1, nothere: clock.now + HOUR } };
ranks['5:miner'] = 'master';
w = restart();
yes('a record is rebuilt field by field: a count that is not whole reads as none',
    w.svc.offer(5, 'ebony').why === 'open' && w.svc.walkAway(5, 'ebony').ok === true);
function owns(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
yes('a quest the tables do not have, and a cooldown that ran out, are left off',
    !owns(forms[5].props[PROP].open, 'nothere') && !owns(forms[5].props[PROP].open, 'constructor') &&
    !owns(forms[5].props[PROP].cool, 'nothere') && !owns(forms[5].props[PROP].cool, 'gem') &&
    forms[5].props[PROP].cool.stalhrim === clock.now + HOUR);

// --------------------------------------- a record that cannot be read ----
function unread(value, what) {
  forms[6] = { inv: {}, props: {} };
  forms[6].props[PROP] = value;
  ranks['6:miner'] = 'master';
  const before = JSON.stringify(forms[6].props[PROP]);
  w = restart();
  const o = w.svc.offer(6, 'ebony');
  const line = w.svc.mineRare(6, here[0], EBONY);
  yes(what + ': the offer is refused and the place stays shut',
      o.ok === false && o.why === 'unread' && /could not be read/.test(line) && have(6, EBONY.ore) === 0);
  yes(what + ': walking away and turning in are refused too',
      w.svc.walkAway(6, 'ebony').why === 'unread' && w.svc.turnIn(6, 'ebony').why === 'unread');
  yes(what + ': and nothing is written over it', JSON.stringify(forms[6].props[PROP]) === before);
  yes(what + ': and the log says so', w.logged.some(function (l) { return /custom quests:/.test(l) && /6/.test(l); }));
}
unread('a string', 'a value that is not a record');
unread({ v: 2, open: {}, cool: {} }, 'a record of another shape');
{
  forms[7] = { inv: {}, props: {} };
  forms[7].props[PROP] = { v: 1, open: {}, cool: { ebony: clock.now + HOUR } };
  ranks['7:miner'] = 'master';
  w = restart();
  fault.read = 'throw';
  const o = w.svc.offer(7, 'ebony');
  fault.read = null;
  yes('a read that throws refuses the offer rather than handing the cooldown back',
      o.why === 'unread' && forms[7].props[PROP].cool.ebony === clock.now + HOUR);
  yes('and once it reads again the cooldown is there', w.svc.offer(7, 'ebony').why === 'cooldown');
}

// --------------------------------------- a step that cannot be written ---
{
  ranks['8:miner'] = 'master';
  w = restart();
  fault.write = true;
  const o = w.svc.offer(8, 'ebony');
  fault.write = false;
  yes('an offer that cannot be written opens nothing',
      o.why === 'unwritten' && !(forms[8] && forms[8].props[PROP]) && w.svc.offer(8, 'ebony').ok === true);
  fault.write = true;
  w.svc.mineRare(8, here[0], EBONY);
  fault.write = false;
  yes('a draw that cannot be written hands over no ore', /could not be committed/.test(lastSaid()) && have(8, EBONY.ore) === 0 &&
      forms[8].props[PROP].open.ebony.drawn === 0);
  for (let i = 0; i < 4; i++) { w.svc.mineRare(8, here[0], EBONY); }
  fault.write = true;
  const t = w.svc.turnIn(8, 'ebony');
  fault.write = false;
  yes('a turn-in that cannot be written keeps the goods and the quest open',
      t.why === 'unwritten' && have(8, EBONY.ore) === 4 && forms[8].props[PROP].open.ebony.drawn === 4 &&
      !forms[8].props[PROP].cool.ebony);
  fault.write = true;
  const a = w.svc.walkAway(8, 'ebony');
  fault.write = false;
  yes('a walk away that cannot be written leaves the goods with the quest that drew them',
      a.why === 'unwritten' && have(8, EBONY.ore) === 4 && forms[8].props[PROP].open.ebony.drawn === 4);
  fault.noAdd = [EBONY.ore];
  w.svc.mineRare(8, here[0], EBONY);
  fault.noAdd = [];
  yes('ore the load order cannot hand over is not counted as drawn',
      /could not be committed/.test(lastSaid()) && forms[8].props[PROP].open.ebony.drawn === 4 && have(8, EBONY.ore) === 4);
  w.svc.walkAway(8, 'ebony');
}
{
  ranks['9:miner'] = '';
  w = restart();
  w.svc.bindPlace('wolf', { cell: 'pad-1' });
  w.svc.offer(9, 'wolf');
  names[41] = 'Wolf'; veinCell[41] = 'pad-1';
  w.ctx.mp.lookupEspmRecordById = function () { return null; };
  w.ctx.mp.get = (function (get) {
    return function (id, key) { return key === 'baseDesc' ? names[id] : get(id, key); };
  })(w.ctx.mp.get);
  fault.write = true;
  const k = w.svc.noteKill(9, 41);
  fault.write = false;
  yes('a kill that cannot be written is not counted', k.why === 'unwritten' && forms[9].props[PROP].open.wolf.kills === 0);
  w.svc.noteKill(9, 41);
  fault.noAdd = ['f:Skyrim.esm'];
  const t = w.svc.turnIn(9, 'wolf');
  fault.noAdd = [];
  yes('gold that cannot be handed over leaves the quest open, with no cooldown',
      t.why === 'unwritten' && forms[9].props[PROP].open.wolf.kills === 1 && !forms[9].props[PROP].cool.wolf);
  fault.write = true;
  const t2 = w.svc.turnIn(9, 'wolf');
  fault.write = false;
  yes('a scene turn-in that cannot be written creates no gold', t2.why === 'unwritten' && have(9, 'f:Skyrim.esm') === 0);
  yes('and written, it pays the 25 once', w.svc.turnIn(9, 'wolf').ok === true && have(9, 'f:Skyrim.esm') === 25);
}

// A native inventory setter can throw instead of returning false. The
// quest and its payment must remain one state, including after restart.
{
  w = restart();
  w.svc.bindPlace('wolf', { cell: 'pad-1' });
  w.svc.offer(30, 'wolf');
  forms[30].props[PROP].open.wolf.kills = 1;
  fault.throwAdd = ['f:Skyrim.esm'];
  try { w.svc.turnIn(30, 'wolf'); } catch (error) { /* observe saved state below */ }
  fault.throwAdd = [];
  w = restart();
  const saved = forms[30].props[PROP];
  yes('a thrown inventory write cannot save the cooldown without its scene reward',
      !!saved.open.wolf && !saved.cool.wolf && have(30, 'f:Skyrim.esm') === 0);
}

// ------------------------------------------------------- a hot reload ----
{
  ranks['31:miner']='master';w=restart();w.svc.offer(31,'ebony');
  let finish;
  w.ctx.swing=function(a,anim,done){finish=done;};
  const old=w.svc;
  old.mineRare(31,here[0],EBONY);
  boot(w.ctx);
  finish();
  yes('a mining callback from the old controller cannot draw after reload',have(31,EBONY.ore)===0);
}
{
  ranks['32:miner']='master';w=restart();w.svc.offer(32,'ebony');
  let finish;
  w.ctx.swing=function(a,anim,done){finish=done;};
  w.ctx.__identityToken='original';w.svc.mineRare(32,here[0],EBONY);
  w.ctx.__identityToken='replacement';finish();
  yes('a delayed mining callback cannot draw for a replacement identity',have(32,EBONY.ore)===0);
}
{
  ranks['36:miner']='master';w=restart();w.svc.offer(36,'ebony');
  let finish,runtime='100';
  w.ctx.__runtimeIdentityApi={getActorRuntimeIdentity:()=>runtime,
    getDescFromId:()=> 'ff000024:Skyrim.esm',getNpcAIState:()=>({isHuman:true,profileId:36,lifeGeneration:0})};
  w.ctx.swing=function(a,anim,done){finish=done;};
  w.svc.mineRare(36,here[0],EBONY);
  runtime='101';finish();
  yes('a delayed mining callback refuses a new native session with unchanged profile and NPC life',have(36,EBONY.ore)===0);
}
{
  w=restart();
  const ctx = w.ctx;
  const again = boot(ctx);
  yes('a hot reload starts the service again over the property the first load made',
      !!again.svc && !again.logged.some(function (l) { return /failed to start/.test(l); }) &&
      again.svc.offer(2, 'ebony').ok === true && forms[2].props[PROP].open.ebony.drawn === 0);
  again.svc.walkAway(2, 'ebony');
}

// ------------------------------------------------------- the pages -------
{
  const timers=[],writes=[];
  const start=gm.indexOf('function swing(actorId, anim, lands, opts) {');
  const finish=gm.indexOf('\n}\n/*',start)+2;
  const ctx={mp:{set:(...args)=>writes.push(args)},setTimeout:(fn,ms)=>{timers.push({fn,ms});return timers.length;},
    clearTimeout(){},guard:(label,fn)=>fn,SWING_PROPERTY:'swing',SWING_STOP:'stop',SWING_FREE:'free',
    SWING_MS:2500,SWING_LAND_MS:900,SWING_QUIET:{},SWING_IN_AIR:{},SWING_CLEAR:{},log(){}};
  vm.createContext(ctx);vm.runInContext(gm.slice(start,finish),ctx);
  let alive=true;ctx.swing(36,'mine',null,{alive:()=>alive});alive=false;
  const count=writes.length;timers.forEach(t=>t.fn());
  yes('the real swing cleanup cannot write after its owner is revoked',writes.length===count);
}
{
  w=restart();w.svc.bindPlace('wolf',{cell:'pad-1'});w.svc.offer(34,'wolf');
  names[41]='Wolf';veinCell[41]='pad-1';
  const saved=JSON.stringify(forms[34]);w.ctx.__revoked=true;
  w.svc.noteKill(34,41);w.svc.offer(34,'ebony');
  yes('transaction revocation blocks every quest-state writer',JSON.stringify(forms[34])===saved);
}
{
  ranks['35:miner']='master';w=restart();w.svc.offer(35,'ebony');
  let done,valid,credits=0;
  w.ctx.swing=function(a,anim,finish,opts){done=finish;valid=opts.alive;};
  w.ctx.creditWork=function(){credits++;};
  w.svc.mineRare(35,here[0],EBONY);
  yes('a current quest swing owns its cleanup lease',valid());
  w.svc.shutdown();done();
  yes('shutdown revokes mining cleanup and work credit',!valid() && credits===0 && have(35,EBONY.ore)===0);
}
{
  ranks['37:miner']='master';w=restart();w.svc.offer(37,'ebony');
  let credits=0,wear=0;
  w.ctx.creditWork=function(){credits++;};w.ctx.wearTool=function(){wear++;};
  w.ctx.__afterCommit=function(){w.svc.shutdown();};
  w.svc.mineRare(37,here[0],EBONY);
  yes('publication followed by shutdown cannot credit work to the next controller',
      have(37,EBONY.ore)===1 && credits===0 && wear===0);
}
{
  ranks['33:miner']='master';w=restart();
  yes('the trader describes the four authored mine quests',typeof w.svc.describe==='function' &&
      w.svc.describe(33).length===4);
  yes('unbound scarce locations cannot be taken from the trader panel',typeof w.svc.act==='function' &&
      w.svc.act(33,'take','pearl').why==='unbound');
}
function whereThis(md) {
  const at = md.indexOf('## Where this is');
  return at < 0 ? '' : md.slice(at).replace(/\s+/g, ' ');
}
const qWhere = whereThis(questPage);
const mWhere = whereThis(minerPage);
yes('the quests page says the open quests and cooldowns are kept on the character and a restart keeps them',
    /kept on the character/.test(qWhere) && /restart of the server keeps them/.test(qWhere) &&
    !/kept in memory/.test(qWhere) && !/restart of the server clears them/.test(qWhere));
yes('the miner page says the same', /kept on the character/.test(mWhere) &&
    /restart of the server keeps them/.test(mWhere) && !/kept in memory/.test(mWhere) &&
    !/restart of the server clears them/.test(mWhere));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
