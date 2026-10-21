'use strict';
const clone=value=>JSON.parse(JSON.stringify(value));
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function createOrchardPlots(storage,references) {
 if(!storage||storage.durable!==true||!Array.isArray(references)||references.length!==10||new Set(references).size!==10)
  throw Error('Orchard plot storage is unavailable');
 let active=true,busy=false,doc=storage.load();
 function validPlot(value) {
  if(value===null)return true;
  if(!value||Array.isArray(value)||typeof value!=='object'||
   !Number.isSafeInteger(value.by)||value.by<0||typeof value.crop!=='string'||
   !Number.isSafeInteger(value.at)||value.at<0||!Number.isSafeInteger(value.ms)||value.ms<0||
   !Number.isInteger(value.step)||value.step<0||value.step>3)return false;
  return value.crop==='' ? value.by===0&&value.at===0&&value.ms===0&&value.step===0 :
   value.crop==="141081:JK's Whiterun's Outskirts.esp"&&value.by>0&&value.at>0&&value.ms>0;
 }
 if(!doc||doc.version!==1||!doc.entries||Array.isArray(doc.entries)||
  Object.keys(doc.entries).length!==10||!references.every(ref=>Object.hasOwn(doc.entries,ref)&&validPlot(doc.entries[ref])))
  throw Error('Orchard plots cannot be verified');
 doc=clone(doc);
 function usable() {return active&&(!storage.current||storage.current());}
 function read(ref) {
  if(!usable()||busy||!Object.hasOwn(doc.entries,ref))throw Error('Orchard plots are unavailable');
  return clone(doc.entries[ref]);
 }
 function save(next) {
  try {
   if(!usable()||storage.save(clone(next))!==true||!usable())throw Error('Orchard save acknowledgement is unavailable');
   doc=clone(next);return true;
  }catch(error){active=false;return false;}
 }
 function write(ref,value) {
  if(!usable()||busy||!Object.hasOwn(doc.entries,ref)||!validPlot(value))return false;
  busy=true;
  try {const next=clone(doc);next.entries[ref]=clone(value);return save(next);}
  finally {busy=false;}
 }
 function compareWrite(ref,expected,value) {
  if(!usable()||busy||!Object.hasOwn(doc.entries,ref)||!same(doc.entries[ref],expected))return false;
  return write(ref,value);
 }
 function sow(ref,value) {
  if(!usable()||busy||!Object.hasOwn(doc.entries,ref)||doc.entries[ref]&&doc.entries[ref].crop!=='')return false;
  return write(ref,value);
 }
 function sowWithSeed(ref,expected,value,eligible,seed) {
  if(!usable()||busy||!Object.hasOwn(doc.entries,ref)||!validPlot(value)||!value.crop||
   !same(doc.entries[ref],expected)||expected&&expected.crop!=='')return false;
  busy=true;
  try {
   if(!eligible()||!usable())return false;
   let paid;
   try {paid=seed(()=>usable()&&eligible()&&usable()&&same(doc.entries[ref],expected));}
   catch(error){active=false;return false;}
   if(paid!==true){if(paid!==false)active=false;return false;}
   if(!usable()||!eligible()||!same(doc.entries[ref],expected))return false;
   const next=clone(doc);next.entries[ref]=clone(value);return save(next);
  }finally{busy=false;}
 }
 function harvest(ref,expected,eligible,award) {
  if(!usable()||busy||!Object.hasOwn(doc.entries,ref)||!same(doc.entries[ref],expected))return false;
  busy=true;
  try {
   if(!eligible()||!usable()||!same(doc.entries[ref],expected))return false;
   const next=clone(doc),reserved={by:0,crop:'',at:0,ms:0,step:0};
   next.entries[ref]=reserved;
   if(!save(next))return false;
   let paid;
   try {paid=award(()=>usable()&&eligible()&&usable()&&same(doc.entries[ref],reserved));}
   catch(error){active=false;return false;}
   if(paid===true)return usable();
   if(paid!==false){active=false;return false;}
   if(!usable()||!same(doc.entries[ref],reserved))return false;
   const restored=clone(doc);restored.entries[ref]=clone(expected);save(restored);
   return false;
  }finally {busy=false;}
 }
 return Object.freeze({read,write,compareWrite,sow,sowWithSeed,harvest,available:usable,shutdown(){active=false;}});
}
function createOrchardStorage(fs,path,settings,writeWhole,references) {
 if(typeof writeWhole!=='function')throw Error('Durable orchard writes are unavailable');
 const dir=path.resolve(settings.privDir||'private'),served=path.resolve(settings.dataDir||'data');
 const file=path.join(dir,'orchard-plots.json'),marker=file+'.initialized';
 function real(input) {
  let found=input;const tail=[];
  while(!fs.existsSync(found)){const parent=path.dirname(found);if(parent===found)throw Error('Orchard path unavailable');tail.unshift(path.basename(found));found=parent;}
  return path.resolve(fs.realpathSync(found),...tail);
 }
 function privacy() {
  const relative=path.relative(real(served),real(dir));
  if(!relative||relative!=='..'&&!relative.startsWith('..'+path.sep)&&!path.isAbsolute(relative))throw Error('Orchard state must be private');
 }
 const checksum=doc=>require('node:crypto').createHash('sha256').update(JSON.stringify([doc.version,doc.entries])).digest('hex');
 function save(doc) {
  privacy();writeWhole(file,JSON.stringify({version:doc.version,entries:doc.entries,sha256:checksum(doc)}));return true;
 }
 function load() {
  privacy();
  if(!fs.existsSync(file)) {
   if(fs.existsSync(marker))throw Error('Saved orchard plots are missing');
   save({version:1,entries:Object.fromEntries(references.map(ref=>[ref,null]))});
  }
  const doc=JSON.parse(fs.readFileSync(file,'utf8'));
  if(!doc||doc.sha256!==checksum(doc))throw Error('Saved orchard plots are damaged');
  if(!fs.existsSync(marker))writeWhole(marker,'1');
  return {version:doc.version,entries:doc.entries};
 }
 return {load,save,durable:true};
}
module.exports={createOrchardPlots,createOrchardStorage};
