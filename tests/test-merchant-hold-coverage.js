'use strict';
const assert=require('node:assert/strict');
const roster=require('../game/data/merchant-roster.json').merchants;
const rows=require('../game/data/merchant-quests.json').quests.concat(require('../game/data/merchant-ranked-quests.json').quests);
const holds=['whiterun','riften','markarth','solitude'],ranks=['novice','advanced','expert','master'];
const missing=[];
for(const merchant of roster.filter(row=>holds.includes(row.bookHold)))for(const rank of ranks)
 if(!rows.some(row=>row.merchant.reference===merchant.reference&&row.tier===rank))missing.push(merchant.bookHold+'/'+merchant.role+'/'+rank);
assert.deepEqual(missing,[],'Every specialist in the four admitted holds needs each rank: '+missing.length+' missing');
assert.equal(roster.filter(row=>holds.includes(row.bookHold)).length,24);
console.log('PASS all96 merchant/rank slots in Whiterun, the Rift, the Reach and Haafingar');
