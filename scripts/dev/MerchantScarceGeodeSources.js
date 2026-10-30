'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
function validateScarceGeodes(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='7e0bc6e1c27b0a8b0e80ee16a138c7c72cd48b15b3729b844b70a08fdb4333c3'||!population||loadOrderSha256(population)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce geode source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceGeodes};
