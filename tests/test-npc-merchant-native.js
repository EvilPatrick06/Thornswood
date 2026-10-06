'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const addon=require(path.resolve(process.argv[2]));
const installed=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
assert.equal(installed.loadOrder.length,102,'Use the verified installed plugin cast');
const fixture=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'thornswood-merchant-native-'));
process.chdir(fixture);
const dataDir=path.join(fixture,'data');fs.mkdirSync(path.join(dataDir,'scripts'),{recursive:true});
const server=new addon.ScampServer(JSON.stringify({port:0,maxPlayers:2,offlineMode:true,
  name:'merchant-purse-check',dataDir,loadOrder:installed.loadOrder,
  npcEnabled:true,npcAllowEssential:true,npcAllowCrimeFaction:true,npcSettings:{},
  bannedEspmCharacterRaceIds:[0x10760a],logLevel:'error'}));
server._setSelf(server);
const source=fs.readFileSync(path.join(__dirname,'../game/gamemode.js'),'utf8');
const ctx={Map,Set,Number,Math,JSON,require};vm.createContext(ctx);
for(const marker of ['NPC MERCHANT PURSES','NPC POPULATION POLICY','NPC POPULATION DATA']) {
  vm.runInContext(source.slice(source.indexOf('// '+marker+' BEGIN'),source.indexOf('// '+marker+' END')),ctx);
}
vm.runInContext('globalThis.catalogue=NPC_POPULATION_DATA;',ctx);
const api={};
for(const method of ['makeProperty','get','set','getIdFromDesc','getNpcAIState',
  'setNpcPlacementExclusions','setNpcServerControlled','setNpcDifficultyTier']) api[method]=server[method].bind(server);
const data=ctx.catalogue,plugins=installed.loadOrder.map(file=>path.basename(file));
assert.deepEqual(Array.from(data.plugins),plugins);
const references=Array.from(data.keep.filter(row=>row[6]==='trader'),row=>row[0]);
const storage=ctx.createPrivateMerchantLedger(fs,path,{privDir:path.join(fixture,'private'),dataDir},references);
const merchants=ctx.createNpcMerchantPurses(api,data,storage);
const population=ctx.createNpcPopulation(api,data,plugins,merchants);
let cursor=0,total=server.prepareNpcLoad(),loaded=0,merchantIds=[];
while(cursor<total) {
  const batch=server.loadNpcBatch(cursor,16);
  assert.ok(batch.nextCursor>cursor);cursor=batch.nextCursor;total=batch.total;
  for(const id of batch.actorIds) {
    const state=server.getNpcAIState(id);
    assert.equal(population.admit(id,state),true);
    loaded++;
    const purse=merchants.prepare(id);
    if(purse) {assert.equal(purse.purse,250);assert.equal(purse.stock.length,0);merchantIds.push(id);}
  }
}
assert.equal(loaded,5075);assert.equal(merchantIds.length,249);
assert.equal(merchants.stats().verified,249);assert.equal(merchants.stats().initialized,249);
const chosen=merchantIds[0],reference=server.getDescFromId(chosen),doc=storage.load();
doc.entries[reference].purse=0;doc.entries[reference].stock=[{baseId:0x12eb7,count:5}];storage.save(doc);
merchants.shutdown();assert.throws(()=>merchants.prepare(chosen),/unavailable/);
server.set(chosen,'thornswoodMerchant',null);
server.clear(); // The normal gamemode reload clears property registrations.
const restored=ctx.createNpcMerchantPurses(api,data,storage);
assert.equal(restored.prepare(chosen).purse,0);
assert.equal(restored.prepare(chosen).stock[0].count,5);
assert.equal(restored.stats().initialized,0,'Recovering a lost native save is not another grant');
assert.equal(server.get(chosen,'thornswoodMerchant').purse,0);
console.log(JSON.stringify({passed:true,plugins:plugins.length,loaded,merchants:merchantIds.length,
  purseTotal:249*250,initialStock:0,recoveredPurse:0,recoveredStock:5,nativeMirrorRestored:true}));
restored.shutdown();
const target=fs.realpathSync(fixture);
assert.equal(path.dirname(target),fs.realpathSync(require('node:os').tmpdir()));
process.chdir(require('node:os').tmpdir());fs.rmSync(target,{recursive:true,force:true});
process.exit(0);
