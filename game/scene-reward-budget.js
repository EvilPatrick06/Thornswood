'use strict';
// Pure, currently unbundled projection. Only the caller's fenced native CAS
// can commit this state together with original quest terms and any reward.
var DAY = 86400000, LIMIT = 150;
function integer(n, min) { return Number.isSafeInteger(n) && n >= min; }
function gold(n) { return integer(n, 10) && n <= LIMIT; }
function id(s) {
  return typeof s === 'string' && s.length <= 48 && s.slice(0, 2) === 'q-' &&
    !/[^a-z0-9-]|--|-$/.test(s);
}
function object(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}
function data(value, key) {
  var d = Object.getOwnPropertyDescriptor(value, key);
  return d && d.enumerable && Object.prototype.hasOwnProperty.call(d, 'value') ? d.value : undefined;
}
function shape(value, fields) {
  return object(value) && Reflect.ownKeys(value).length === fields.length && fields.every(function(key) {
    return data(value, key) !== undefined;
  });
}
function array(value, length) {
  return Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype &&
    value.length === length && Reflect.ownKeys(value).length === length + 1;
}
function read(raw) {
  if (!shape(raw, ['v', 'clock', 'serial', 'held', 'paid']) || data(raw, 'v') !== 1) return null;
  var clock = data(raw, 'clock'), serial = data(raw, 'serial'), held = data(raw, 'held'), paid = data(raw, 'paid');
  if (!integer(clock, 1) || !integer(serial, 0) || !object(held) ||
      !Array.isArray(paid) || paid.length > 15 || !array(paid, paid.length)) return null;
  var keys = Reflect.ownKeys(held), copy = {v: 1, clock: clock, serial: serial, held: {}, paid: []};
  if (keys.length > 3 || serial < keys.length + paid.length) return null;
  var tokens = [], used = 0, last = 0;
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i], row = typeof key === 'string' ? data(held, key) : undefined;
    if (!id(key) || !shape(row, ['gold', 'at', 'token'])) return null;
    var amount = data(row, 'gold'), at = data(row, 'at'), token = data(row, 'token');
    if (!gold(amount) || !integer(at, 1) || at > clock || !integer(token, 1) || token > serial || tokens.indexOf(token) >= 0) return null;
    tokens.push(token); used += amount;
    copy.held[key] = {gold: amount, at: at, token: token};
  }
  for (var j = 0; j < paid.length; j++) {
    var pair = data(paid, String(j));
    if (!array(pair, 2)) return null;
    var stamp = data(pair, '0'), value = data(pair, '1');
    if (!integer(stamp, 1) || stamp > clock || stamp < last || !gold(value)) return null;
    last = stamp;
    if (stamp > clock - DAY) used += value;
    copy.paid.push([stamp, value]);
  }
  return used <= LIMIT ? copy : null;
}
function prepare(raw, now) {
  if (!integer(now, 1)) return {ok: false, why: 'time'};
  var next = raw === undefined ? {v: 1, clock: now, serial: 0, held: {}, paid: []} : read(raw);
  if (!next) return {ok: false, why: 'state'};
  if (now < next.clock) return {ok: false, why: 'time'};
  next.paid = next.paid.filter(function(pair) { return pair[0] > now - DAY; });
  next.clock = now;
  return {ok: true, next: next};
}
function inspect(raw, now) {
  var result = prepare(raw, now);
  if (!result.ok) return result;
  var next = result.next, keys = Object.keys(next.held);
  var paid = next.paid.reduce(function(n, pair) { return n + pair[1]; }, 0);
  var reserved = keys.reduce(function(n, key) { return n + next.held[key].gold; }, 0);
  return {ok: true, paidGold: paid, reservedGold: reserved, availableGold: LIMIT - paid - reserved, openCount: keys.length};
}
function reserve(raw, key, amount, now) {
  if (!id(key) || !gold(amount)) return {ok: false, why: 'request'};
  var result = prepare(raw, now);
  if (!result.ok) return result;
  var next = result.next, view = inspect(next, now);
  if (Object.prototype.hasOwnProperty.call(next.held, key)) return {ok: false, why: 'open'};
  if (view.openCount >= 3) return {ok: false, why: 'open-limit'};
  if (view.availableGold < amount) return {ok: false, why: 'allowance'};
  if (next.serial === Number.MAX_SAFE_INTEGER) return {ok: false, why: 'counter'};
  var token = ++next.serial;
  next.held[key] = {gold: amount, at: now, token: token};
  return {ok: true, next: next, token: token};
}
function close(raw, key, token, now, pay) {
  if (!id(key) || !integer(token, 1)) return {ok: false, why: 'request'};
  var result = prepare(raw, now);
  if (!result.ok) return result;
  var next = result.next, row = next.held[key];
  if (!row || row.token !== token) return {ok: false, why: 'reservation'};
  delete next.held[key];
  if (pay) next.paid.push([now, row.gold]);
  return {ok: true, next: next, gold: pay ? row.gold : 0};
}
module.exports = Object.freeze({reserve: reserve, inspect: inspect,
  complete: function(raw, key, token, now) { return close(raw, key, token, now, true); },
  cancel: function(raw, key, token, now) { return close(raw, key, token, now, false); }});
