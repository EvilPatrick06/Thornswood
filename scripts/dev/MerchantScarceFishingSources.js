'use strict';
function validateScarceFishing(doc,locations) {
 const refs=['3828e:Dragonborn.esm','38894:Dragonborn.esm','3919c:Dragonborn.esm'];
 const fail=()=>{throw new Error('Invalid scarce fishing source evidence');};
 if(!doc||doc.version!==1||doc.quest!=='pearl'||doc.label!=='Raven Rock coast'||
   !Array.isArray(doc.sources)||doc.sources.length!==3)fail();
 for(let i=0;i<refs.length;i++) {
  const actual=locations.fishing.find(row=>row.ref===refs[i]);if(!actual)fail();
  const expected={reference:actual.ref,base:actual.base,world:actual.world,position:[actual.x,actual.y,actual.z],
   item:actual.item,itemType:'INGR',rank:actual.rank,returnMinutes:actual.returnMinutes};
  if(JSON.stringify(doc.sources[i])!==JSON.stringify(expected)||actual.sharedStock!==1||actual.access!=='Fisher')fail();
 }
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceFishing};
