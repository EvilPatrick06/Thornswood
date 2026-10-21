'use strict';
const crypto=require('node:crypto');
function validateScarceGeodes(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='a6be7dfc146cfbea26fc63122ed0557a68e33fb54dd0ac2a75108fd72e51cefc'||!population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce geode source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceGeodes};
