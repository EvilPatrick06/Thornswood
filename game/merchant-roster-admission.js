'use strict';
// Ledger evidence only. This never authorizes a cut or proves a stopped world.
const {createHash}=require('node:crypto');
const {createSettlement,stockRows}=require('./merchant-settlement');
const ROLES=['Smith','Woodworker','Tailor','Enchanter','Cook','Alchemist'];
const HOLDS={whiterun:'Whiterun',solitude:'Haafingar',riften:'the Rift',markarth:'the Reach',
  windhelm:'Eastmarch',morthal:'Hjaalmarch',dawnstar:'the Pale',winterhold:'Winterhold',
  falkreath:'Falkreath',ravenrock:'Solstheim'};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const copy=value=>JSON.parse(JSON.stringify(value));
const object=value=>value!==null && typeof value==='object' && !Array.isArray(value);
function fail(message) {throw new Error(message+' cannot be verified');}
function bytes(value,limit,label) {
  if(!Buffer.isBuffer(value) || value.length>limit) fail(label);
  return Buffer.from(value);
}
function parse(raw,label) {
  const text=raw.toString('utf8');
  if(!Buffer.from(text,'utf8').equals(raw)) fail(label);
  try {return JSON.parse(text.replace(/^\uFEFF/,''));} catch(error) {fail(label);}
}
function identity(value) {
  const match=typeof value==='string' && /^([0-9a-f]{1,6}):([^:/\\\x00-\x1f\x7f]+\.(?:esm|esp|esl))$/i.exec(value);
  return !!match && parseInt(match[1],16)>0 && match[1]===parseInt(match[1],16).toString(16);
}
function inspectRetirementLedger(options) {
  if(!object(options)) fail('Merchant inspection inputs');
  // Copy evidence before invoking any supplied native dependency.
  const ledgerBytes=bytes(options.ledgerBytes,64*1024*1024,'Saved merchant ledger');
  const markerBytes=bytes(options.markerBytes,1,'Merchant initialization evidence');
  const rosterBytes=bytes(options.rosterBytes,1024*1024,'Merchant roster');
  const {world,resolveMerchant,validateInventory}=options;
  if(markerBytes.toString()!=='1' || typeof world!=='string' || !world ||
      typeof resolveMerchant!=='function' || typeof validateInventory!=='function') fail('Merchant inspection inputs');
  const roster=parse(rosterBytes,'Merchant roster');
  if(!object(roster) || Object.keys(roster).sort().join(',')!=='history,merchants,version,worldMode' ||
      roster.version!==1 || roster.worldMode!=='existing' || !Array.isArray(roster.history) ||
      roster.history.length!==249 || !Array.isArray(roster.merchants) || roster.merchants.length!==60) fail('Merchant roster');
  const history=new Map(),retained=new Set(),coverage=new Set();
  for(const pair of roster.history) {
    if(!Array.isArray(pair) || pair.length!==2 || !pair.every(identity) || history.has(pair[0])) fail('Merchant history');
    history.set(pair[0],pair[1]);
  }
  for(const row of roster.merchants) {
    if(!object(row) || Object.keys(row).sort().join(',')!=='base,bookHold,hold,reference,role' ||
        !identity(row.reference) || !identity(row.base) || history.get(row.reference)!==row.base ||
        retained.has(row.reference) || !ROLES.includes(row.role) || !Object.hasOwn(HOLDS,row.bookHold) ||
        HOLDS[row.bookHold]!==row.hold || coverage.has(row.bookHold+':'+row.role)) fail('Merchant assignments');
    retained.add(row.reference);coverage.add(row.bookHold+':'+row.role);
  }
  const ledger=parse(ledgerBytes,'Saved merchant ledger');
  if(!object(ledger) || ledger.version!==1 || !object(ledger.entries) ||
      typeof ledger.sha256!=='string' || ledger.sha256!==hash(JSON.stringify([ledger.version,ledger.entries])) ||
      Object.keys(ledger.entries).length!==history.size || Object.keys(ledger.entries).some(ref=>!history.has(ref)))
    fail('Saved merchant ledger integrity');
  function validateStock(stock) {
    try {
      const snapshot={entries:stockRows(stock).map(row=>row.entry)};
      if(validateInventory(snapshot)!==true) fail('Native merchant inventory');
    } catch(error) {fail('Native merchant inventory');}
  }
  for(const [reference,base] of history) {
    const state=ledger.entries[reference];
    if(state===null) {if(retained.has(reference)) fail('Retained merchant purse');continue;}
    if(!object(state) || state.version!==1 || state.reference!==reference || state.base!==base ||
        !Number.isInteger(state.purse) || state.purse<0 || state.purse>2147483647 ||
        state.revision!==undefined && (!Number.isSafeInteger(state.revision) || state.revision<0) ||
        state.supply!==undefined && !object(state.supply) || !Array.isArray(state.stock)) fail('Saved merchant state');
    validateStock(state.stock);
  }
  const states=new Map(),pending=[];
  for(const [reference,base] of history) {
    let id;
    // The caller must verify the winning placed record and its base, not just
    // decode a descriptor. Bind its native build/load order outside this module.
    try {id=resolveMerchant(reference,base);} catch(error) {fail('Merchant identities');}
    if(!Number.isInteger(id) || id<=0 || id>=0xff000000 || states.has(id)) fail('Merchant identities');
    const state=ledger.entries[reference];states.set(id,state);
    if(state && state.pending!==undefined && state.pending!==null) pending.push({merchantId:id,reference,state});
  }
  const settlement=createSettlement({world,
    purses:{durable:true,read:id=>copy(states.get(id)),pendingRecords:()=>copy(pending),
      compareAndCommit(){throw new Error('Ledger inspection is read-only');}},
    transfer:{available:()=>true,validate:snapshot=>validateInventory(snapshot)}});
  try {
    if(!settlement.canRetire()) fail('Legacy merchant transfers');
    for(const record of pending) {
      // Compact credit records intentionally omit their old stock snapshot.
      const intent=record.state.pending;
      if(intent.previous.stock!==undefined) validateStock(intent.previous.stock);
      validateStock(intent.next.stock);
    }
  } catch(error) {fail('Saved merchant transfers');}
  finally {settlement.shutdown();}
  return Object.freeze({kind:'merchant-ledger-inspection',version:1,history:history.size,
    retained:retained.size,retired:history.size-retained.size,pending:pending.length,
    ledgerSha256:hash(ledgerBytes),markerSha256:hash(markerBytes),rosterSha256:hash(rosterBytes),worldSha256:hash(world)});
}
module.exports={inspectRetirementLedger};
