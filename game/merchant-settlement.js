'use strict';

var MAX_PENDING = 25;
var MAX_INVENTORY_BYTES = 128 * 1024;
var MAX_INTENT_BYTES = 512 * 1024;
var MAX_COUNT = 2147483647;
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function equal(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
function merchantSnapshot(value, compact) {
  if(!value || typeof value!=='object' || Array.isArray(value)) throw new Error('Pending merchant snapshot cannot be verified.');
  var supply=value.supply===undefined ? {} : value.supply;
  if(!supply || typeof supply!=='object' || Array.isArray(supply) ||
      (!compact || value.purse!==undefined || value.stock!==undefined) &&
      (!Number.isInteger(value.purse) || value.purse<0 || value.purse>MAX_COUNT || !Array.isArray(value.stock) ||
        !value.stock.every(function(row) {return row && Number.isInteger(row.baseId) && row.baseId>0 && row.baseId<=0xffffffff &&
          row.baseId!==15 && Number.isInteger(row.count) && row.count>0 && row.count<=MAX_COUNT;})))
    throw new Error('Pending merchant snapshot cannot be verified.');
  return {purse:value.purse,stock:value.stock,supply:supply};
}
function bounded(value, limit) {
  if (Buffer.byteLength(JSON.stringify(value), 'utf8') > limit) throw new Error('The trade is too large.');
  return value;
}
function inventory(value) {
  if (!value || !Array.isArray(value.entries) || Object.keys(value).length !== 1) throw new Error('Inventory cannot be verified.');
  var total=0;
  value.entries.forEach(function (row) {
    if (!row || !Number.isInteger(row.baseId) || row.baseId <= 0 || row.baseId > 0xffffffff ||
        !Number.isInteger(row.count) || row.count <= 0 || row.count > MAX_COUNT) throw new Error('Inventory cannot be verified.');
    total+=row.count;
    if(total>0xffffffff) throw new Error('Inventory total is too large.');
  });
  return bounded(copy(value), MAX_INVENTORY_BYTES);
}
function metadataKey(entry) {
  var out = {};
  Object.keys(entry).sort().forEach(function (key) { if (key !== 'count') out[key] = entry[key]; });
  return JSON.stringify(out);
}
function addEntries(snapshot, entries) {
  var next = inventory(snapshot);
  inventory({entries:entries}).entries.forEach(function (entry) {
    var key = metadataKey(entry);
    var held = next.entries.find(function (row) { return metadataKey(row) === key; });
    if (held) {
      if (held.count + entry.count > MAX_COUNT) throw new Error('Inventory count is too large.');
      held.count += entry.count;
    } else next.entries.push(copy(entry));
  });
  return inventory(next);
}
function takeEntries(snapshot, baseId, count) {
  var next = inventory(snapshot), taken = [], left = count;
  for (var i = 0; i < next.entries.length && left > 0; i++) {
    var row = next.entries[i];
    if (row.baseId !== baseId) continue;
    var n = Math.min(left, row.count);
    taken.push(Object.assign({}, copy(row), {count:n}));
    row.count -= n; left -= n;
  }
  if (left) throw new Error('You are not carrying that.');
  next.entries = next.entries.filter(function (row) { return row.count > 0; });
  return {inventory:inventory(next), entries:taken};
}
function receiptAt(human, sequence) {
  return JSON.stringify({actor:human.desc, profile:human.profileId, sequence:sequence});
}
function sequenceOf(receipt, human) {
  var doc = JSON.parse(receipt);
  if (doc === null) return 0;
  if (!doc || Object.keys(doc).length !== 3 || doc.actor !== human.desc || doc.profile !== human.profileId ||
      !Number.isSafeInteger(doc.sequence) || doc.sequence < 1) throw new Error('Inventory receipt cannot be verified.');
  return doc.sequence;
}

// Native receipt writes are atomic with the human inventory. Ledger writes are
// synchronous durable replacements. Neither is inferred from elapsed time.
function createSettlement(deps) {
  var purses = deps.purses, transfer = deps.transfer, world = deps.world;
  var now = deps.now || function () { return Date.now(); };
  var active = true, cursor = 0, busy = false;
  var errors = new Map();
  function report(id, error) {
    var message=String(error.message || error);
    if(errors.get(id)!==message && deps.log) deps.log('merchant settlement ' + id.toString(16) + ': ' + message);
    errors.set(id,message);
  }
  function available() {
    return active && !!world && !!purses && purses.durable !== false && typeof purses.compareAndCommit === 'function' &&
      typeof purses.pendingRecords === 'function' && typeof purses.read === 'function' &&
      !!transfer && typeof transfer.validate==='function' && transfer.available();
  }
  function humanKey(human) {
    if(!human || typeof human.desc!=='string' || !Number.isSafeInteger(human.profileId) || human.profileId<=0 || human.profileId>MAX_COUNT) return '';
    // FormDesc emits local hex alone for runtime humans and hex:plugin for
    // placed forms. Compare numeric ids so leading zeros cannot split a lock.
    var parts=/^([0-9a-f]{1,6})(?::([^:\/\\\x00-\x1f\x7f]+\.(?:esm|esp|esl)))?$/i.exec(human.desc);
    return parts ? JSON.stringify([parseInt(parts[1],16),(parts[2] || '').toLowerCase(),human.profileId]) : '';
  }
  function records() {
    try {
      var all=purses.pendingRecords(), merchants=new Set(), references=new Set(), transactions=new Set(), humans=new Set(), receipts=new Set();
      if(!Array.isArray(all) || all.length>MAX_PENDING) throw new Error('Pending merchant records cannot be verified.');
      all.forEach(function(record) {
        var state=record && record.state, pending=state && state.pending;
        if(!record || !state || !Number.isInteger(record.merchantId) || record.merchantId<=0 || record.merchantId>0xffffffff ||
            record.reference!==state.reference || !valid(pending,state)) throw new Error('Pending merchant records cannot be verified.');
        var previous=merchantSnapshot(pending.previous,pending.phase==='credit'), next=merchantSnapshot(pending.next);
        if(!equal(merchantSnapshot(state),pending.phase==='debit'?previous:next)) throw new Error('Pending merchant records cannot be verified.');
        [[merchants,record.merchantId],[references,record.reference],[transactions,pending.id],[humans,humanKey(pending.human)],
          [receipts,pending.debitReceipt],[receipts,pending.finalReceipt]].forEach(function(pair) {
          if(pair[0].has(pair[1])) throw new Error('Pending merchant records cannot be verified.');
          pair[0].add(pair[1]);
        });
      });
      return all;
    } catch(error) {active=false;throw error;}
  }
  function admitted(human, reference, reserveCapacity) {
    var pending = records(), key = humanKey(human);
    if (!key || reserveCapacity!==false && pending.length >= MAX_PENDING) return false;
    return pending.every(function (record) {
      var other = record.state.pending.human;
      return humanKey(other) && humanKey(other) !== key && record.reference !== reference;
    });
  }
  function save(id, state, next, intentId) {
    if (!active || intentId && (!state.pending || state.pending.id !== intentId)) return null;
    try {
      var committed = purses.compareAndCommit(id, state.revision || 0, next);
      return active ? committed : null;
    } catch (error) {
      // The replacement may be durable even when its acknowledgement failed.
      // Only a newly loaded ledger can decide what happened.
      active = false;
      throw error;
    }
  }
  function identity(pending) {
    var id = transfer.resolve(pending.human.desc);
    if (!id) return 0;
    var human = transfer.identity(id);
    return equal(human, pending.human) ? id : 0;
  }
  function valid(pending, state) {
    return state && pending && pending.version === 2 && pending.world === world &&
      pending.reference === state.reference && pending.base === state.base &&
      typeof pending.id === 'string' && pending.id.length>0 && humanKey(pending.human) &&
      ['buy','sell','supply'].indexOf(pending.kind)>=0 &&
      (pending.phase === 'debit' || pending.phase === 'credit') &&
      Number.isSafeInteger(pending.sequence) && pending.sequence > 0 && pending.sequence < Number.MAX_SAFE_INTEGER &&
      pending.debitReceipt === receiptAt(pending.human, pending.sequence) &&
      pending.finalReceipt === receiptAt(pending.human, pending.sequence + 1) &&
      (pending.phase==='credit' && pending.expectedReceipt===undefined ||
        pending.expectedReceipt===(pending.sequence===1?'null':receiptAt(pending.human,pending.sequence-1)));
  }
  function commitMerchant(id, state) {
    var pending = state.pending;
    if (!equal(merchantSnapshot(state), merchantSnapshot(pending.previous))) return null;
    return save(id, state, creditState(state), pending.id);
  }
  function creditState(state) {
    var next = Object.assign({}, copy(state), merchantSnapshot(copy(state.pending.next)));
    next.pending.phase = 'credit';
    // Saved debit is conclusive. Its original snapshots are no longer read
    // in this phase; retaining them would crowd out the recovery snapshots.
    delete next.pending.expected;
    delete next.pending.debit;
    delete next.pending.expectedReceipt;
    next.pending.previous = {supply:copy(next.pending.previous.supply || {})};
    return next;
  }
  function pruneSupplyHistory(id, state, wait) {
    if (!available() || busy) return null;
    busy = true;
    try {
      records();
      var current = purses.read(id);
      if (!current || current.pending || !equal(current, state)) return null;
      var next = copy(current), changed = false, at = now();
      Object.keys(next.supply || {}).forEach(function (key) {
        var stamp = next.supply[key];
        if (Number.isSafeInteger(stamp) && stamp > 0 && at - stamp >= wait) {
          delete next.supply[key]; changed = true;
        }
      });
      return changed ? save(id, current, next) : current;
    } finally { busy = false; }
  }
  function changedSupplyKey(previous, next) {
    var before = previous.supply || {}, after = next.supply || {};
    var keys = Object.keys(after).filter(function (key) { return before[key] !== after[key]; });
    return keys.length === 1 && Number.isSafeInteger(after[keys[0]]) && after[keys[0]] > 0 ? keys[0] : null;
  }
  function complete(id, state) {
    var pending = state.pending, next = Object.assign({}, copy(state), {pending:null});
    if (pending.kind === 'supply') {
      // Completion, including legacy intents, follows the exact saved final
      // receipt. A disconnect cannot consume the six-hour window in advance.
      var key = changedSupplyKey(pending.previous, pending.next), at = now();
      if (!key || !Number.isSafeInteger(at) || at <= 0) throw new Error('Supply completion cannot be verified.');
      next.supply[key] = at;
    }
    return !!save(id, state, next, pending.id);
  }
  function reconcile(id) {
    if (!available()) return false;
    var state = purses.read(id), pending = state && state.pending;
    if (!valid(pending, state)) return false;
    // Corrupt duplicate reservations must not independently credit one human.
    var key = humanKey(pending.human);
    if (records().filter(function (r) { return humanKey(r.state.pending.human) === key; }).length !== 1) return false;
    var humanId = identity(pending);
    if (!active || !humanId) return false;
    var live = transfer.receipt(humanId), saved = transfer.saved(humanId);
    if (!active) return false;
    if (live === pending.finalReceipt) {
      if (pending.phase !== 'credit' || saved !== pending.finalReceipt ||
          !equal(merchantSnapshot(state), merchantSnapshot(pending.next))) return false;
      return complete(id, state);
    }
    if (pending.phase === 'debit') {
      if (live === pending.expectedReceipt) {
        // Replaying the identical debit is safe only against its original
        // snapshot and receipt. A refused snapshot remains reserved.
        if (!active) return false;
        if (!equal(transfer.inventory(humanId), pending.expected)) {
          // Calls are synchronous and busy fences this instance. An unchanged
          // original receipt proves this transaction never changed inventory,
          // including after restart. No original inventory restoration is needed.
          return !!save(id, state, Object.assign({}, copy(state), {pending:null}), pending.id);
        }
        if (!active || !identity(pending)) return false;
        var changed = transfer.cas(humanId, pending.expected, pending.expectedReceipt, pending.debit, pending.sequence, pending.human.profileId);
        if (!active) return false;
        live = transfer.receipt(humanId); saved = transfer.saved(humanId);
        if (changed === false && live === pending.expectedReceipt)
          return !!save(id, state, Object.assign({}, copy(state), {pending:null}), pending.id);
      }
      if (live !== pending.debitReceipt || saved !== pending.debitReceipt || !active) return false;
      state = commitMerchant(id, state);
      if (!state || !active) return false;
      pending = state.pending;
    }
    if (live !== pending.debitReceipt || saved !== pending.debitReceipt || !active) return false;
    // A pre-upgrade credit intent may still contain the saved debit snapshots.
    // Compact it durably before building or replacing a recovery attempt.
    var compact = creditState(state);
    if (!equal(compact, state)) {
      state = save(id, state, bounded(compact, MAX_INTENT_BYTES), pending.id);
      if (!state || !active) return false;
      pending = state.pending;
    }
    var current = inventory(transfer.inventory(humanId));
    if (!pending.creditAttempt || !equal(pending.creditAttempt.expected, current)) {
      var next = copy(state);
      next.pending.creditAttempt = {expected:current,replacement:addEntries(current, pending.credit)};
      if(transfer.validate(next.pending.creditAttempt.replacement)!==true) throw new Error('Native inventory validation failed.');
      state = save(id, state, bounded(next, MAX_INTENT_BYTES), pending.id);
      if (!state || !active) return false;
      pending = state.pending;
    }
    if (!active || !identity(pending)) return false;
    transfer.cas(humanId, pending.creditAttempt.expected, pending.debitReceipt,
      pending.creditAttempt.replacement, pending.sequence + 1, pending.human.profileId);
    // A notification may throw after CAS changed inventory. The saved intent
    // and final receipt, rather than this return value, determine completion.
    if (!active || transfer.receipt(humanId) !== pending.finalReceipt || transfer.saved(humanId) !== pending.finalReceipt) return false;
    return complete(id, state);
  }
  function begin(offer) {
    if (!available() || busy) return {accepted:false,done:false,reason:'Trading is unavailable.'};
    busy = true;
    try {
      var human = transfer.identity(offer.humanId), state = purses.read(offer.merchantId);
      if (!human || human.profileId !== offer.profileId || !state || state.pending ||
          !equal(state, offer.previous) || !admitted(human, state.reference))
        return {accepted:false,done:false,reason:'A transfer is waiting.'};
      if (offer.kind === 'supply') {
        var key = changedSupplyKey(state, offer.next), owner;
        try { owner = JSON.parse(key); } catch (error) { owner = null; }
        if (!Array.isArray(owner) || owner.length !== 3 || owner[0] !== human.desc ||
            owner[1] !== human.profileId || typeof owner[2] !== 'string' || !owner[2])
          throw new Error('Supply cooldown cannot be verified.');
      }
      var expected = inventory(transfer.inventory(offer.humanId));
      if (!equal(expected, offer.expected)) return {accepted:false,done:false,reason:'Your inventory changed. Choose the trade again.'};
      var receipt = transfer.receipt(offer.humanId), sequence = sequenceOf(receipt, human) + 1;
      if (transfer.saved(offer.humanId) !== receipt)
        return {accepted:false,done:false,reason:'Your previous inventory change is waiting on the save.'};
      if (!Number.isSafeInteger(sequence + 1)) throw new Error('Inventory receipt sequence is exhausted.');
      var pending = {version:2,id:world + ':' + state.reference + ':' + (state.revision || 0),world:world,
        reference:state.reference,base:state.base,human:human,kind:offer.kind,phase:'debit',
        previous:{purse:state.purse,stock:copy(state.stock),supply:copy(state.supply || {})},next:copy(offer.next),
        expected:expected,expectedReceipt:receipt,debit:inventory(offer.debit),credit:inventory({entries:offer.credit}).entries,
        sequence:sequence,debitReceipt:receiptAt(human,sequence),finalReceipt:receiptAt(human,sequence+1)};
      // Use the same native validator as CAS, including its serialized-byte
      // representation. No separate JS estimate can substitute for that check.
      [expected,pending.debit,addEntries(pending.debit,pending.credit)].forEach(function (snapshot) {
        if(transfer.validate(snapshot)!==true) throw new Error('Native inventory validation failed.');
      });
      var armed = Object.assign({}, copy(state), {pending:pending});
      // Either recovery inventory can reach the native/JS inventory limit.
      // Reserve both plus the JSON envelope before charging, including later
      // inventory growth. The 512 KiB intent bound stays unchanged.
      var recovery = creditState(armed);
      if (Buffer.byteLength(JSON.stringify(recovery), 'utf8') + 2 * MAX_INVENTORY_BYTES + 64 > MAX_INTENT_BYTES)
        throw new Error('The trade is too large to recover.');
      if (!save(offer.merchantId, state, bounded(armed, MAX_INTENT_BYTES))) return {accepted:false,done:false,reason:'The offer changed.'};
      var done = false;
      if (active) {
        try { done = reconcile(offer.merchantId); }
        catch (error) { report(offer.merchantId,error); if (!active) throw error; }
      }
      var after = active && purses.read(offer.merchantId);
      var cancelled = after && !after.pending && equal(merchantSnapshot(after),merchantSnapshot(pending.previous));
      return {accepted:!cancelled,done:done && !cancelled,reason:cancelled ? 'Your inventory changed. Choose the trade again.' : done ? '' : 'The transfer is waiting on the save.'};
    } finally { busy = false; }
  }
  function tick() {
    if (!available() || busy) return [];
    busy = true;
    try {
      var all = records(), changed = [];
      for (var i = 0; i < Math.min(MAX_PENDING, all.length) && active; i++) {
        var record = all[(cursor + i) % all.length];
        try { if(reconcile(record.merchantId)) {changed.push(record.merchantId);errors.delete(record.merchantId);} }
        catch (error) { report(record.merchantId,error); if (!active) throw error; }
      }
      cursor = all.length ? (cursor + MAX_PENDING) % all.length : 0;
      return changed;
    } finally { busy = false; }
  }
  function withInventoryMutation(actorId,change) {
    if(!available() || busy)return {ok:false,why:'unavailable'};
    busy=true;
    var leased=true;
    try {
      var human=transfer.identity(actorId);
      if(!human || !admitted(human,'',false))return {ok:false,why:'waiting'};
      if(transfer.saved(actorId)!==transfer.receipt(actorId))return {ok:false,why:'waiting'};
      if(!active)return {ok:false,why:'unavailable'};
      var result=change(human,function(){return active && leased;});
      // Unknown receipts revoke all writers until a reload reads durable state.
      if(result && result.uncertain)active=false;
      return result;
    } finally {leased=false;busy=false;}
  }
  function canInventoryMutation(actorId) {
    if(!available() || busy)return false;
    var human=transfer.identity(actorId);
    return !!human && admitted(human,'',false) && transfer.saved(actorId)===transfer.receipt(actorId);
  }
  return {begin:begin,tick:tick,available:available,pruneSupplyHistory:pruneSupplyHistory,
    withInventoryMutation:withInventoryMutation,canInventoryMutation:canInventoryMutation,shutdown:function () { active=false; }};
}

module.exports = {createSettlement:createSettlement,inventory:inventory,takeEntries:takeEntries,
  addEntries:addEntries,metadataKey:metadataKey,MAX_PENDING:MAX_PENDING};
