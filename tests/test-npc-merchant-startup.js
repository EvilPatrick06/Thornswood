'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../game/gamemode.js'),'utf8').replace(/\r\n/g,'\n');
const begin=source.lastIndexOf('// NPC SERVER STARTUP BEGIN');
assert.ok(begin>=0,'Use the production NPC startup path');
const startup=source.slice(begin,source.indexOf('// NPC SERVER STARTUP END',begin));
const manifest=source.slice(source.indexOf('function npcMerchantManifest('),source.indexOf('function createNpcMerchantPurses('));
for(const failure of ['trading','native','retirement','population','runtime',null]) {
  let active=true,stopped=false,cuts=0,started=0,populationCalls=0;
  const merchant={prepare(){if(!active)throw new Error('unavailable');return 250;},shutdown(){active=false;}};
  const ctx={mp:{getServerSettings:()=>({thornswoodServer:'dev',loadOrder:['Skyrim.esm']}),prepareNpcLoad(){}},
    NPC_POPULATION_DATA:{plugins:['Skyrim.esm'],keep:[['1:Skyrim.esm','a:Skyrim.esm',null,null,null,null,'trader']],
      merchantRoster:{version:1,worldMode:'existing'}},
    createPrivateMerchantLedger:()=>({}),createNpcMerchantPurses:()=>merchant,
    MERCHANT_TRADING:{installMerchantTrading(env){
      if(failure==='trading')throw new Error('trading failure');
      assert.equal(env.suspended,true,'startup must prevent automatic recovery');
      return {shutdown(){},nativeReady:()=>failure!=='native',retirementReady:()=>failure!=='retirement',start(){started++;}};
    }},
    createNpcPopulation(api,data,plugins,purses,options){
      populationCalls++;
      if(failure==='population')throw new Error('population failure');
      assert.equal(options.suspended,true);
      return {commit(){cuts++;},stop(){}};
    },
    startSharedNpcServerRuntime(api,timers,now,report,population,options){
      if(failure==='runtime')throw new Error('runtime failure');
      assert.equal(options.suspended,true);return {stop(){stopped=true;},start(){return true;}};
    },
    require,setTimeout,clearTimeout,log() {}};
  vm.createContext(ctx);vm.runInContext(manifest,ctx);vm.runInContext(startup,ctx);
  if(failure) {
    assert.equal(ctx.__thornswoodNpcMerchants,null,'Failed startup must not expose a merchant service');
    assert.throws(()=>merchant.prepare(),/unavailable/,'A retained failed service must also be revoked');
    assert.equal(ctx.__thornswoodNpcPopulation,null);
    assert.equal(ctx.__thornswoodNpcRuntime,null);
    assert.equal(cuts,0,'every precommit startup failure leaves exclusions unchanged');
    assert.equal(started,0,'every precommit startup failure leaves settlement suspended');
    if(['trading','native','retirement'].includes(failure))
      assert.equal(populationCalls,0,'failed trading admission cannot continue into population construction');
  } else {
    assert.equal(ctx.__thornswoodNpcMerchants.prepare(),250);
    assert.ok(ctx.__thornswoodNpcPopulation);assert.ok(ctx.__thornswoodNpcRuntime);assert.equal(stopped,false);
    assert.equal(cuts,1);assert.equal(started,1);
  }
}
{
  let references;
  const ctx={mp:{getServerSettings:()=>({thornswoodServer:'dev',loadOrder:['Skyrim.esm']}),prepareNpcLoad(){}},
    NPC_POPULATION_DATA:{plugins:['Skyrim.esm'],keep:[['2:Skyrim.esm','a:Skyrim.esm',null,null,null,null,'trader']],
      merchantHistory:[['1:Skyrim.esm','a:Skyrim.esm'],['2:Skyrim.esm','a:Skyrim.esm']]},
    createPrivateMerchantLedger(fs,path,settings,refs){references=refs;return {};},
    createNpcMerchantPurses:()=>({shutdown(){}}),createNpcPopulation:()=>({commit(){},stop(){}}),
    MERCHANT_TRADING:{installMerchantTrading:()=>({shutdown(){},nativeReady:()=>true,start(){}})},
    startSharedNpcServerRuntime:()=>({stop(){},start:()=>true}),
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
{
  const merchants=[],trades=[],populations=[],runtimes=[];let checks=0,replaced=false;
  const logs=[];
  const ctx={mp:{getServerSettings:()=>({thornswoodServer:'dev',loadOrder:['Skyrim.esm']}),prepareNpcLoad(){}},
    NPC_POPULATION_DATA:{plugins:['Skyrim.esm'],keep:[['1:Skyrim.esm','a:Skyrim.esm',null,null,null,null,'trader']],
      merchantRoster:{version:1,worldMode:'existing'}},createPrivateMerchantLedger:()=>({}),
    createNpcMerchantPurses(){const service={alive:true,shutdown(){this.alive=false;}};merchants.push(service);return service;},
    MERCHANT_TRADING:{installMerchantTrading(){
      const service={alive:true,started:false,shutdown(){this.alive=false;},nativeReady:()=>true,
        retirementReady(){
          if(++checks===2 && !replaced){replaced=true;vm.runInContext(startup,ctx);}
          return true;
        },start(){assert.equal(this.alive,true);this.started=true;}};
      trades.push(service);return service;
    }},
    createNpcPopulation(){const service={alive:true,commits:0,commit(){this.commits++;},stop(){this.alive=false;}};
      populations.push(service);return service;},
    startSharedNpcServerRuntime(){const service={alive:true,started:false,stop(){this.alive=false;},
      start(){this.started=true;return true;}};runtimes.push(service);return service;},
    require,setTimeout,clearTimeout,log:line=>logs.push(line)};
  vm.createContext(ctx);vm.runInContext(manifest,ctx);vm.runInContext(startup,ctx);
  assert.equal(replaced,true,'native preflight callback reproduces a new startup');
  for(const [key,instances] of [['__thornswoodNpcMerchants',merchants],['__thornswoodMerchantTrade',trades],
      ['__thornswoodNpcPopulation',populations],['__thornswoodNpcRuntime',runtimes]]) {
    assert.equal(instances.length,2);assert.equal(instances[0].alive,false);
    assert.equal(instances[1].alive,true,'stale cleanup must not revoke its replacement');
    assert.equal(ctx[key],instances[1],'stale cleanup must not clear its replacement');
  }
  assert.equal(populations[0].commits,0);assert.equal(populations[1].commits,1);
  assert.equal(trades[0].started,false);assert.equal(trades[1].started,true);
  assert.match(logs.join('\n'),/ownership is revoked/);
}
console.log('PASS NPC merchant partial startup revocation and successful startup');
