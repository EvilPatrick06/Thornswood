'use strict';
const crypto=require('node:crypto');
function validateScarceGeodes(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='b884454c555725dd520a83cf177caeb890be45ff87cf380eed09f8b3ede02996'||!population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce geode source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceGeodes};
