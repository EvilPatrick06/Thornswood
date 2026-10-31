'use strict';
const crypto=require('node:crypto');
const {loadOrderSha256}=require('./MerchantLoadOrderPin.js');
function validateScarceGeodes(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='469c97e3860bf611c3d1790735d7c49114d50daad746a468648a1b6cf929f181'||!population||loadOrderSha256(population)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce geode source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceGeodes};
