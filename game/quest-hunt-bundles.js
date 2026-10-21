'use strict';
const refs=new Set(['33fa6:Skyrim.esm','846ea:Skyrim.esm','846eb:Skyrim.esm']);
const items=['3ad6c:Skyrim.esm','669a4:Skyrim.esm'];
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const clone=v=>JSON.parse(JSON.stringify(v));
function readMammothDraw(entry) {
 try {
  if(!object(entry)||!Number.isInteger(entry.drawn)||entry.drawn<0||entry.drawn>3||entry.kills!==0||entry.itemDesc!==null||
    !Array.isArray(entry.bundles)||entry.bundles.length!==entry.drawn)return null;
  const seen=new Set();
  for(const row of entry.bundles) {
   if(!object(row)||!refs.has(row.ref)||!Number.isSafeInteger(row.life)||row.life<0||
     typeof row.body!=='string'||!/^[1-9][0-9]{0,19}$/.test(row.body)||row.body.length===20&&row.body>'18446744073709551615'||
     !Array.isArray(row.goods)||row.goods.length!==2||[0,1].some(i=>!Number.isInteger(row.goods[i])||row.goods[i]<1||row.goods[i]>5))return null;
   const key=JSON.stringify([row.ref,row.life,row.body]);
   if(seen.has(key))return null;seen.add(key);
  }
  return clone(entry);
 }catch(error){return null;}
}
function appendMammothDraw(entry,body) {
 const before=readMammothDraw(entry),one=readMammothDraw({drawn:1,kills:0,itemDesc:null,bundles:[body]});
 if(!before||!one||before.drawn>=3)return {ok:false};
 before.drawn++;before.bundles.push(one.bundles[0]);
 return readMammothDraw(before)?{ok:true,next:before}:{ok:false};
}
function changes(rows) {
 const totals=[0,0];rows.forEach(row=>row.goods.forEach((n,i)=>{totals[i]+=n;}));
 return items.flatMap((item,i)=>totals[i]?[{item,count:-totals[i]}]:[]);
}
function mammothReturn(entry) {
 const value=readMammothDraw(entry);
 return value&&value.drawn>0?{ok:true,changes:changes(value.bundles.slice(0,1))}:{ok:false};
}
function mammothAbandon(entry) {
 const value=readMammothDraw(entry);
 return value?{ok:true,changes:changes(value.bundles)}:{ok:false};
}
module.exports={readMammothDraw,appendMammothDraw,mammothReturn,mammothAbandon};
