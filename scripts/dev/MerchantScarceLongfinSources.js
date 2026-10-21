'use strict';
function longfinSources(content) {
 const sources=[];
 if(!content||content.version!==1||!content.sites)throw new Error('Longfin content evidence is missing');
 for(let i=0;i<8;i++) {
  const row=content.sites['longfin'+(i+1)];
  if(!row||row.ref!==(0x17200+i).toString(16)+':Thornswood-Content.esp'||row.base!=='154a5:Thornswood-Content.esp'||
     row.interior!==false||row.space!=='3c:Skyrim.esm'||!Array.isArray(row.pos)||row.pos.length!==3||!row.pos.every(Number.isFinite))
   throw new Error('Longfin source differs from its authored marker');
  sources.push({reference:row.ref,base:row.base,world:row.space,position:row.pos.slice(),item:'106e1b:Skyrim.esm',itemType:'INGR',rank:'master',returnMinutes:240});
 }
 return {version:1,quest:'longfin',label:'Haafingar northern sea',sources};
}
module.exports={longfinSources};
