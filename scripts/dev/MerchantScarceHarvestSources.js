'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
function validateScarceHarvest(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='2114cf8340e907b5a24e7ab22f413b27261bf4d50f24ccf945d3c730ea6b24c7'||
    !population||loadOrderSha256(population)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce harvest source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceHarvest};
