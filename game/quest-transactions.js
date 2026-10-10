'use strict';
var inventoryTools=typeof MERCHANT_SETTLEMENT!=='undefined'?MERCHANT_SETTLEMENT:require('./merchant-settlement');
function same(a,b) {
  if(a===b)return true;
  if(!a || !b || typeof a!=='object' || typeof b!=='object' || Array.isArray(a)!==Array.isArray(b))return false;
  var left=Object.keys(a).sort(),right=Object.keys(b).sort();
  return left.length===right.length && left.every(function(key,i){return key===right[i] && same(a[key],b[key]);});
}
function actorIdentity(mp,actor) {
  try {
    var ai=mp.getNpcAIState(actor),desc=mp.getDescFromId(actor),runtime=mp.getActorRuntimeIdentity(actor);
    if(!ai || ai.isHuman!==true || !Number.isInteger(ai.profileId) || ai.profileId<=0 ||
        !Number.isSafeInteger(ai.lifeGeneration) || ai.lifeGeneration<0 || typeof desc!=='string' || !desc ||
        typeof runtime!=='string' || !runtime || runtime.length>20 || runtime[0]==='0' || /[^0-9]/.test(runtime) ||
        (runtime.length===20 && runtime>'18446744073709551615'))return null;
    return JSON.stringify({desc:desc,profileId:ai.profileId,life:ai.lifeGeneration,runtime:runtime});
  } catch(error) { return null; }
}
function createQuestTransactions(deps) {
  var mp=deps.mp,active=true,property='thornswoodQuests';
  var log=deps.log || function(){};
  function report(message,error) {try{log(message+String(error));}catch(ignored){}}
  function available() {
    return active && typeof deps.withInventoryMutation==='function' && !!mp &&
      ['compareAndSetInventoryAndProperty','getInventoryReceipt','getSavedInventoryReceipt',
        'get','getIdFromDesc','getDescFromId','getNpcAIState','getActorRuntimeIdentity'].every(function(key){return typeof mp[key]==='function';});
  }
  function identity(actor) {
    return active ? actorIdentity(mp,actor) : null;
  }
  function commit(actor,expectedRecord,nextRecord,changes) {
    if(!available())return {ok:false,why:'unavailable'};
    try {
      // Match the addon's JSON boundary, including omitted optional fields.
      nextRecord=JSON.parse(JSON.stringify(nextRecord));
      return deps.withInventoryMutation(actor,function(human,stillActive){
        if(!available() || !stillActive())return {ok:false,why:'unavailable'};
        var token=identity(actor);
        if(!token)return {ok:false,why:'identity'};
        var owner=JSON.parse(token);
        if(owner.desc!==human.desc || owner.profileId!==human.profileId)return {ok:false,why:'identity'};
        var receipt=mp.getInventoryReceipt(actor);
        if(mp.getSavedInventoryReceipt(actor)!==receipt)return {ok:false,why:'waiting'};
        var oldReceipt=JSON.parse(receipt),sequence=1;
        if(oldReceipt!==null) {
          if(!oldReceipt || Object.keys(oldReceipt).length!==3 || oldReceipt.actor!==human.desc ||
              oldReceipt.profile!==human.profileId || !Number.isSafeInteger(oldReceipt.sequence) || oldReceipt.sequence<1)
            throw new Error('Quest inventory receipt cannot be verified.');
          sequence=oldReceipt.sequence+1;
        }
        if(!Number.isSafeInteger(sequence))throw new Error('Quest inventory receipt sequence is exhausted.');
        var before=inventoryTools.inventory(mp.get(actor,'inventory')),next=before;
        changes.forEach(function(change){
          if(!Number.isSafeInteger(change.count) || change.count===0)throw new Error('Invalid quest goods.');
          var baseId=mp.getIdFromDesc(change.item);
          if(!Number.isInteger(baseId) || baseId<=0 || baseId>0xffffffff)throw new Error('Quest goods are unavailable.');
          next=change.count<0?inventoryTools.takeEntries(next,baseId,-change.count).inventory:
            inventoryTools.addEntries(next,[{baseId:baseId,count:change.count}]);
        });
        var nextReceipt=JSON.stringify({actor:human.desc,profile:human.profileId,sequence:sequence});
        if(!stillActive() || !available() || identity(actor)!==token)return {ok:false,why:'identity'};
        try {
          var changed=mp.compareAndSetInventoryAndProperty(actor,before,receipt,next,sequence,human.profileId,
            {name:property,expected:expectedRecord===undefined?null:expectedRecord,replacement:nextRecord,
              expectedLifeGeneration:owner.life,expectedRuntimeIdentity:owner.runtime});
          return {ok:changed===true,why:changed===true?'':'changed'};
        } catch(error) {
          // Publication can fail after the atomic live edit. Read back that
          // identity and receipt; never compensate, replay, or infer a save.
          try {
            if(identity(actor)===token) {
              var live=mp.getInventoryReceipt(actor),record=mp.get(actor,property);
              if(live===nextReceipt && same(record,nextRecord))return {ok:true};
              if(live===receipt && same(record==null?null:record,expectedRecord==null?null:expectedRecord)) {
                report('quest transaction refused: ',error);
                return {ok:false,why:'unwritten'};
              }
            }
          } catch(readError) { /* An unreadable outcome is revoked below before diagnostics. */ }
          active=false;
          report('quest transaction outcome is unknown; service revoked: ',error);
          return {ok:false,why:'unavailable',uncertain:true};
        }
      });
    } catch(error) {
      report('quest transaction unavailable: ',error);
      return {ok:false,why:'unwritten'};
    }
  }
  return {commit:commit,identity:identity,available:available,shutdown:function(){active=false;}};
}
module.exports={createQuestTransactions:createQuestTransactions,actorIdentity:actorIdentity};
