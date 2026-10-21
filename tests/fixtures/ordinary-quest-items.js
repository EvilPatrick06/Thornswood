'use strict';
// Older trade/audit fixtures contain Skyrim goods only and do not load the
// whole production bundle. Supply the real policy with those native identities.
// Bound tokens and failed identities are covered in test-quest-item-transfers.
module.exports='var fixtureQuestPolicy=('+require('../../game/quest-items').createQuestItemPolicy.toString()+
 ')({getDescFromId:function(id){return id.toString(16)+":Skyrim.esm";}});\n'+
 'function questItemBlocked(id){return fixtureQuestPolicy.blocked(id);}\n';
