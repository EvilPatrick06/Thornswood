'use strict';
// Explicit pre-existing legacy world for filesystem/native fixtures only.
module.exports=function seedMerchantLedger(fs,path,privateDir,references) {
 const entries=Object.fromEntries(references.map(reference=>[reference,null]));
 const doc={version:1,entries};
 doc.sha256=require('node:crypto').createHash('sha256').update(JSON.stringify([doc.version,doc.entries])).digest('hex');
 fs.mkdirSync(privateDir,{recursive:true});
 fs.writeFileSync(path.join(privateDir,'merchant-ledger.json'),JSON.stringify(doc),{flag:'wx'});
 fs.writeFileSync(path.join(privateDir,'merchant-ledger.initialized'),'1',{flag:'wx'});
};
