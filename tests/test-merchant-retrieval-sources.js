'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.join(__dirname,'..');
const {validateRetrievalSources}=require('../scripts/dev/MerchantRetrievalSources');
const doc=require('../game/data/merchant-retrievals.json'),population=require('../game/data/npc-population.json');
const roster=require('../game/data/merchant-roster.json'),content=fs.readFileSync(path.join(root,'game/content/Thornswood-Content.esp'));
const copy=v=>JSON.parse(JSON.stringify(v));
assert.equal(validateRetrievalSources(doc,population,content,roster).sources.length,7);
for(const key of ['reference','base','world','position','item','merchant','destination','gold','hours','provenance']) {
 const bad=copy(doc);bad.sources[0][key]=key==='position'?[0,0,0]:'invalid';
 assert.throws(()=>validateRetrievalSources(bad,population,content,roster),/retrieval/i,key);
}
{
 const bad=copy(population);bad.loadOrder[0].sha256='bad';assert.throws(()=>validateRetrievalSources(doc,bad,content,roster),/retrieval/i);
 const bytes=Buffer.from(content);bytes[bytes.length-1]^=1;assert.throws(()=>validateRetrievalSources(doc,population,bytes,roster),/retrieval/i);
 const changed=copy(roster);changed.merchants.find(r=>r.reference===doc.sources[0].merchant).role='Cook';
 assert.throws(()=>validateRetrievalSources(doc,population,content,changed),/retrieval/i,'appointed role cannot drift');
}
const roles=require('../game/data/merchant-role-tables.json');
for(const source of doc.sources)for(const table of Object.values(roles.tables))for(const direction of ['buy','sell','supply'])
 assert(!table[direction].includes(source.item),'a dedicated token cannot be ordinary merchant stock');
console.log('PASS seven exact retrieval source/merchant/terms proofs, native file provenance and matching Content');
