'use strict';
function createQuestItemPolicy(mp) {
 if(!mp||typeof mp.getDescFromId!=='function')throw new Error('Quest item identity lookup is unavailable');
 const lookup=mp.getDescFromId;
 const tokens=new Set(Array.from({length:7},(_,i)=>(0x17000+i).toString(16)+':thornswood-content.esp'));
 return Object.freeze({blocked(baseId) {
  if(!Number.isInteger(baseId)||baseId<=0||baseId>0xffffffff)return true;
  try {
   const desc=Reflect.apply(lookup,mp,[baseId]);
   if(typeof desc!=='string'||!/^[0-9a-f]{1,8}:[^:\0\r\n]+\.(?:esm|esp|esl)$/i.test(desc))return true;
   const colon=desc.indexOf(':'),canonical=parseInt(desc.slice(0,colon),16).toString(16)+desc.slice(colon).toLowerCase();
   return tokens.has(canonical);
  }catch(error){return true;}
 }});
}
module.exports={createQuestItemPolicy};
