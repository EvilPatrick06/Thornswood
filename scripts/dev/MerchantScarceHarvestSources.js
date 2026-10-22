'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='03ee0848c69cb616541dfe5e0a3a07ebc39024a188d84251e9da51fda005c476'||
    !population||loadOrderSha256(population)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
