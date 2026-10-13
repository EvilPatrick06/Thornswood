'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../game/gamemode.js'),'utf8').replace(/\r\n/g,'\n');
const begin=source.lastIndexOf('// NPC SERVER STARTUP BEGIN');
assert.ok(begin>=0,'Use the production NPC startup path');
const startup=source.slice(begin,source.indexOf('// NPC SERVER STARTUP END',begin));
const manifest=source.slice(source.indexOf('function npcMerchantManifest('),source.indexOf('function createNpcMerchantPurses('));
for(const failure of ['population','runtime',null]) {
  let active=true,stopped=false;
  const merchant={prepare(){if(!active)throw new Error('unavailable');return 250;},shutdown(){active=false;}};
  const ctx={mp:{getServerSettings:()=>({thornswoodServer:'dev',loadOrder:['Skyrim.esm']}),prepareNpcLoad(){}},
    NPC_POPULATION_DATA:{plugins:['Skyrim.esm'],keep:[['1:Skyrim.esm','a:Skyrim.esm',null,null,null,null,'trader']]},
    createPrivateMerchantLedger:()=>({}),createNpcMerchantPurses:()=>merchant,
    createNpcPopulation(){if(failure==='population')throw new Error('population failure');return {};},
    startSharedNpcServerRuntime(){if(failure==='runtime')throw new Error('runtime failure');return {stop(){stopped=true;}};},
    require,setTimeout,clearTimeout,log() {}};
  vm.createContext(ctx);vm.runInContext(manifest,ctx);vm.runInContext(startup,ctx);
  if(failure) {
    assert.equal(ctx.__thornswoodNpcMerchants,null,'Failed startup must not expose a merchant service');
    assert.throws(()=>merchant.prepare(),/unavailable/,'A retained failed service must also be revoked');
    assert.equal(ctx.__thornswoodNpcPopulation,null);
    assert.equal(ctx.__thornswoodNpcRuntime,null);
  } else {
    assert.equal(ctx.__thornswoodNpcMerchants.prepare(),250);
    assert.ok(ctx.__thornswoodNpcPopulation);assert.ok(ctx.__thornswoodNpcRuntime);assert.equal(stopped,false);
  }
}
{
  let references;
  const ctx={mp:{getServerSettings:()=>({thornswoodServer:'dev',loadOrder:['Skyrim.esm']}),prepareNpcLoad(){}},
    NPC_POPULATION_DATA:{plugins:['Skyrim.esm'],keep:[['2:Skyrim.esm','a:Skyrim.esm',null,null,null,null,'trader']],
      merchantHistory:[['1:Skyrim.esm','a:Skyrim.esm'],['2:Skyrim.esm','a:Skyrim.esm']]},
    createPrivateMerchantLedger(fs,path,settings,refs){references=refs;return {};},
    createNpcMerchantPurses:()=>({shutdown(){}}),createNpcPopulation:()=>({}),startSharedNpcServerRuntime:()=>({stop(){}}),
    require,setTimeout,clearTimeout,log(){}};
  vm.createContext(ctx);vm.runInContext(manifest,ctx);vm.runInContext(startup,ctx);
  assert.deepEqual(Array.from(references),['1:Skyrim.esm','2:Skyrim.esm'],'startup retains the complete historical initialization manifest');
}
{
  let revoked=false;
  const ctx={mp:{getServerSettings:()=>({thornswoodServer:'unsupported'})},
    __thornswoodMerchantTrade:{shutdown(){revoked=true;}}, require,setTimeout,clearTimeout,log(){}};
  vm.createContext(ctx); vm.runInContext(startup,ctx);
  assert.equal(revoked,true,'changing channel must revoke the old native writer before the new channel gate');
  assert.equal(ctx.__thornswoodMerchantTrade,null);
}
console.log('PASS NPC merchant partial startup revocation and successful startup');
