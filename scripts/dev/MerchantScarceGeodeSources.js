'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
function validateScarceGeodes(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='31184dec64a95c45ad6625f4629e8642aa1f19ba31a24af147884218e0722c0c'||!population||loadOrderSha256(population)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce geode source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceGeodes};
