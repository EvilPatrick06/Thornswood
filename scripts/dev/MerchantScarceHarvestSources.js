'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='8bceec7c8ccc532d13e38051aff94a41925afcfb23326c2c102d6c13c990eb66'||
    !population||loadOrderSha256(population)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
