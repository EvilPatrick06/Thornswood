'use strict';
var identityTools=typeof QUEST_TRANSACTIONS!=='undefined'?QUEST_TRANSACTIONS:require('./quest-transactions');
var SPEC=[
  {id:'wolf',hold:'Whiterun',place:'White River Watch',count:1,world:'151f9',refs:{'86a88':'e1672'}},
  {id:'sabre',hold:'Eastmarch',place:'Lost Knife Hideout',count:1,world:'1a337',refs:{'1ce7b':'59397'}},
  {id:'camp',hold:'Whiterun',place:'Halted Stream Camp',count:3,world:'3c',bounds:[14000,18000,16000,22000],
    refs:{'50533':'b623b','50549':'b6fcd','5054a':'1e79f','5054e':'b623b'}},
  {id:'bear',hold:'the Rift',place:'Pinepeak Cavern',count:1,world:'15230',refs:{'19f3e':'1e7a4'}},
  {id:'barrow',hold:'Falkreath',place:'Bleak Falls Temple',count:1,world:'371de',
    refs:{'1d219':'1e7ad','380b3':'4a59a','380b5':'567c8','380b7':'bf7b3','380b8':'a6850'}},
  {id:'giant',hold:'Whiterun',place:'Bleakwind Basin',count:1,world:'3c',bounds:[-500,2500,-1000,3000],
    refs:{'33f9f':'3053f','33fa3':'3053f'}}
];
function own(o,key){return Object.prototype.hasOwnProperty.call(o,key);}
function object(o){return !!o && typeof o==='object' && !Array.isArray(o);}
function copy(o){return JSON.parse(JSON.stringify(o));}
function generation(n){return Number.isSafeInteger(n) && n>=0;}
function point(p){return Array.isArray(p) && p.length===3 && p.every(Number.isFinite);}
function speciesOf(race) {
  if(typeof race!=='string')return '';
  var lower=race.toLowerCase();
  if(lower.indexOf('sabre')>=0)return 'sabre-cat';
  return lower.replace(/race$/,'');
}
var SPECIES={wolf:'wolf',sabre:'sabre-cat',bear:'bear',barrow:'draugr',giant:'giant'};
var BANDITS={'50533':'imperial','50549':'imperial','5054a':'breton','5054e':'imperial'};
function createKillContracts(deps) {
  var mp=deps.mp, sources={},byId={},rows=[];
  if(!deps.population || !Array.isArray(deps.population.keep))throw new Error('Kill source catalogue is unavailable.');
  SPEC.forEach(function(spec){
    var row={id:spec.id,hold:spec.hold,place:spec.place,count:spec.count,world:spec.world+':Skyrim.esm',
      bounds:spec.bounds,refs:[]};
    Object.keys(spec.refs).forEach(function(local){
      var ref=local+':Skyrim.esm',base=spec.refs[local]+':Skyrim.esm';
      var matches=deps.population.keep.filter(function(r){return r[0]===ref;});
      var kept=matches[0];
      var species=spec.id==='camp'?BANDITS[local]:SPECIES[spec.id];
      if(matches.length!==1 || kept[1]!==base || kept[2]!==row.world || !point(kept[3]) ||
          !Number.isFinite(kept[4]) || kept[4]<=0 || kept[12]!==species ||
          spec.id==='camp' && kept[6]!=='enemy')throw new Error('Kill source disagrees with the kept cast: '+ref);
      sources[ref]={row:row,base:base,species:species,role:spec.id==='camp'?'bandit':species,
        pos:kept[3].slice(),leash:kept[4]};row.refs.push(ref);
    });
    byId[row.id]=row;rows.push(row);
  });
  function history(b) {
    var raw=own(b,'killHistory')?b.killHistory:b.expected?b.expected.killHistory:undefined;
    if(raw===undefined)return {};
    if(!object(raw) || Object.keys(raw).some(function(ref){return !own(sources,ref) || !generation(raw[ref]);}))return null;
    return copy(raw);
  }
  function uncertain(b) {
    var raw=own(b,'killUncertain')?b.killUncertain:b.expected?b.expected.killUncertain:undefined;
    if(raw===undefined)return {};
    if(!object(raw) || Object.keys(raw).some(function(id){return !own(byId,id) || raw[id]!==true;}))return null;
    return copy(raw);
  }
  function validEntry(row,entry,retained) {
    if(!object(entry) || !generation(entry.kills) || entry.kills>row.count)return false;
    var credited=entry.credited;
    if(credited===undefined && entry.kills===0)return true;
    if(!Array.isArray(credited) || credited.length!==entry.kills)return false;
    var seen={};
    return credited.every(function(body){
      if(!object(body) || row.refs.indexOf(body.ref)<0 || !generation(body.life) ||
          !retained || !own(retained,body.ref) || retained[body.ref]<body.life)return false;
      var key=JSON.stringify([body.ref,body.life]);
      if(own(seen,key))return false;seen[key]=true;return true;
    });
  }
  function snapshot(id) {
    try {
      var ref=mp.getDescFromId(id),source=sources[ref];
      if(!source)return null;
      var ai=mp.getNpcAIState(id),token=identityTools.targetIdentity(mp,id);
      if(!ai || ai.isHuman!==false || ai.isServerControlled!==true || ai.isDisabled===true ||
          !generation(ai.lifeGeneration) || !point(ai.pos) || typeof token!=='string' ||
          mp.get(id,'baseDesc')!==source.base || mp.get(id,'worldOrCellDesc')!==source.row.world ||
          typeof deps.raceOf!=='function' || speciesOf(deps.raceOf(id))!==source.species)return null;
      var body=JSON.parse(token);
      if(body.desc!==ref || body.life!==ai.lifeGeneration || body.body!==ai.runtimeLifeIdentity)return null;
      var distance=ai.pos.reduce(function(n,v,i){return n+Math.pow(v-source.pos[i],2);},0);
      var box=source.row.bounds;
      if(distance>source.leash*source.leash || box && (ai.pos[0]<box[0] || ai.pos[0]>box[1] || ai.pos[1]<box[2] || ai.pos[1]>box[3]))return null;
      return {ref:ref,life:ai.lifeGeneration,dead:ai.isDead===true,row:source.row};
    } catch(error){return null;}
  }
  function bodies(row) {
    try {
      var result=row.refs.map(function(ref){return snapshot(mp.getIdFromDesc(ref));});
      return result.every(Boolean)?result:null;
    } catch(error){return null;}
  }
  function take(b,id) {
    var row=own(byId,id)?byId[id]:null,retained=history(b),doubt=uncertain(b);
    if(!row)return {ok:false,why:'unknown'};
    if(own(b.open,id))return {ok:false,why:'open'};
    if(!retained || !doubt)return {ok:false,why:'recovery'};
    var current=bodies(row);
    if(!current)return {ok:false,why:'unavailable'};
    current.forEach(function(body){
      if(doubt[id] || body.dead)retained[body.ref]=Math.max(own(retained,body.ref)?retained[body.ref]:-1,body.life);
    });
    delete doubt[id];
    b.killHistory=retained;b.killUncertain=doubt;b.open[id]={drawn:0,kills:0,credited:[]};
    return {ok:true};
  }
  function credit(b,killer,victim) {
    var owner=deps.identity(killer);
    if(typeof owner!=='string' || !owner)return {ok:false,why:'identity'};
    var body=snapshot(victim),retained=history(b),doubt=uncertain(b);
    if(!body || !body.dead)return {ok:false,why:'target'};
    var entry=b.open[body.row.id];
    if(!retained || !doubt || doubt[body.row.id] || !validEntry(body.row,entry,retained))return {ok:false,why:'recovery'};
    if(entry.kills>=body.row.count || own(retained,body.ref) && retained[body.ref]>=body.life)return {ok:false,why:'duplicate'};
    if(deps.identity(killer)!==owner)return {ok:false,why:'identity'};
    entry=copy(entry);entry.kills++;entry.credited=(entry.credited || []).concat([{ref:body.ref,life:body.life}]);
    retained[body.ref]=body.life;b.killHistory=retained;b.open[body.row.id]=entry;
    return {ok:true};
  }
  function ready(b,id) {
    var row=own(byId,id)?byId[id]:null,retained=history(b),doubt=uncertain(b),entry=b.open[id];
    return !!row && !!retained && !!doubt && !doubt[id] && validEntry(row,entry,retained) && entry.kills===row.count;
  }
  function verified(b,id) {
    var row=own(byId,id)?byId[id]:null,retained=history(b),doubt=uncertain(b);
    return !!row && !!retained && !!doubt && (!own(b.open,id) || !doubt[id] && validEntry(row,b.open[id],retained));
  }
  function abandon(b,id) {
    var row=own(byId,id)?byId[id]:null,doubt=uncertain(b);
    if(!row || !own(b.open,id))return {ok:false,why:'none'};
    if(!doubt)return {ok:false,why:'recovery'};
    if(!validEntry(row,b.open[id],history(b)))doubt[id]=true;
    b.killUncertain=doubt;delete b.open[id];return {ok:true};
  }
  return {rows:rows,available:function(id){return own(byId,id) && !!bodies(byId[id]);},
    take:take,credit:credit,ready:ready,verified:verified,abandon:abandon};
}
module.exports={createKillContracts:createKillContracts};
