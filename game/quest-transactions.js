'use strict';
var inventoryTools=typeof MERCHANT_SETTLEMENT!=='undefined'?MERCHANT_SETTLEMENT:require('./merchant-settlement');
function same(a,b) {
  if(a===b)return true;
  if(!a || !b || typeof a!=='object' || typeof b!=='object' || Array.isArray(a)!==Array.isArray(b))return false;
  var left=Object.keys(a).sort(),right=Object.keys(b).sort();
  return left.length===right.length && left.every(function(key,i){return key===right[i] && same(a[key],b[key]);});
}
function createQuestTransactions(deps) {
  var mp=deps.mp,active=true,property='thornswoodQuests';
  var log=deps.log || function(){};
  function available() {
    return active && typeof deps.withInventoryMutation==='function' && !!mp &&
      ['compareAndSetInventoryAndProperty','getInventoryReceipt','getSavedInventoryReceipt',
        'get','getIdFromDesc','getDescFromId','getNpcAIState'].every(function(key){return typeof mp[key]==='function';});
  }
  function identity(actor) {
    if(!active)return null;
    var ai=mp.getNpcAIState(actor),desc=mp.getDescFromId(actor);
    if(!ai || !ai.isHuman || !Number.isInteger(ai.profileId) || ai.profileId<=0 ||
        !Number.isSafeInteger(ai.lifeGeneration) || ai.lifeGeneration<0 || !desc)return null;
    return JSON.stringify({desc:desc,profileId:ai.profileId,life:ai.lifeGeneration});
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
            {name:property,expected:expectedRecord===undefined?null:expectedRecord,replacement:nextRecord});
          return {ok:changed===true,why:changed===true?'':'changed'};
        } catch(error) {
          // Publication can fail after the atomic live edit. Read back that
          // identity and receipt; never compensate, replay, or infer a save.
          try {
            if(identity(actor)===token) {
              var live=mp.getInventoryReceipt(actor),record=mp.get(actor,property);
              if(live===nextReceipt && same(record,nextRecord))return {ok:true};
              if(live===receipt && same(record==null?null:record,expectedRecord==null?null:expectedRecord)) {
                log('quest transaction refused: '+String(error));
                return {ok:false,why:'unwritten'};
              }
            }
          } catch(readError) {log('quest transaction readback failed: '+String(readError));}
          active=false;
          log('quest transaction outcome is unknown; service revoked: '+String(error));
          return {ok:false,why:'unavailable'};
        }
      });
    } catch(error) {
      log('quest transaction unavailable: '+String(error));
      return {ok:false,why:'unwritten'};
    }
  }
  return {commit:commit,identity:identity,available:available,shutdown:function(){active=false;}};
}
module.exports={createQuestTransactions:createQuestTransactions};
