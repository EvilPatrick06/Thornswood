'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
const hash=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
// The pin covers what was measured, not the Content plugin's bytes: those are
// checked against the file itself below, so a change to Content (a header, a
// record elsewhere in it) is a rebuild of the manifest, not a new pin (#2993).
const measured=doc=>{
 const m=JSON.parse(JSON.stringify(doc));m.contentSha256='';
 for(const row of m.sources||[])if(row.provenance&&row.provenance.plugin==='Thornswood-Content.esp')row.provenance.pluginSha256='';
 return m;
};
function validateRetrievalSources(doc,population,content,roster) {
 const fail=()=>{throw new Error('Invalid retrieval source evidence');};
 if(!doc||hash(measured(doc))!=='bf81b78390d00bfffbdab7125f80cd7e989a546e150777fb2d2f974e879e3d32'||
   !population||loadOrderSha256(population)!==doc.loadOrderSha256||
   !Buffer.isBuffer(content)||crypto.createHash('sha256').update(content).digest('hex')!==doc.contentSha256||
   !roster||!Array.isArray(roster.merchants))fail();
 for(const row of doc.sources) {
  for(const [ref,hold] of [[row.merchant,row.hold],[row.destination,row.quest==='dispatch'?'Eastmarch':row.hold]]) {
   const matches=roster.merchants.filter(r=>r.reference===ref);
   if(matches.length!==1||matches[0].hold!==hold||matches[0].role!==row.role||
     ref===row.destination&&matches[0].bookHold!==row.destinationHold)fail();
  }
  const source=population.loadOrder[row.provenance.fileIndex];
  if(!source||source.name!==row.provenance.plugin||
    (source.name!=='Thornswood-Content.esp'&&source.sha256!==row.provenance.pluginSha256)||
    (source.name==='Thornswood-Content.esp'&&doc.contentSha256!==row.provenance.pluginSha256))fail();
 }
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateRetrievalSources};
