'use strict';
const crypto=require('node:crypto');
function validateScarceGeodes(doc,population) {
 const sha=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
 if(!doc||sha(doc)!=='698c97d253c23bc7f6bdd3dd4395eaccd057148ec369b28ef3c23f425f8665ff'||!population||sha(population.loadOrder)!==doc.loadOrderSha256)
  throw new Error('Invalid scarce geode source evidence');
 return JSON.parse(JSON.stringify(doc));
}
module.exports={validateScarceGeodes};
