'use strict';
const crypto=require('node:crypto');
const hash=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
function validateRetrievalSources(doc,population,content,roster) {
 const fail=()=>{throw new Error('Invalid retrieval source evidence');};
 if(!doc||hash(doc)!=='1e03b5bdef0eb04a79fe8d81ba847a39e50c4391f5660f631f714ea13f70202a'||
   !population||hash(population.loadOrder)!==doc.loadOrderSha256||
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
