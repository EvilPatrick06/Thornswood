'use strict';
/*
  game/hair-dye.js (#2675): hair dye, the data check and the colour sums.

  Pure. It reads only what it is handed: the staff list in
  game/data/hair-dyes.json, what somebody carries, an inventory entry, a
  stored appearance. It names no colour, no ingredient, no item and no bench;
  every one of those is in the data, which is the staff's to change.

  Nothing in play calls it yet. The wiring (the steep at a cooking spot, the
  K panel's button, the offer to dye somebody else, the one mp.set write) is
  the next slice, and it is held like this one until 1.2.4.

  A hair colour is the engine's int32 RGB, 0xRRGGBB. TESModPlatform's
  SetNpcHairColor reads red, green and blue out of bits 16 to 23, 8 to 15 and
  0 to 7 and ignores the top byte, so a stored colour is read by its low
  24 bits and every colour written here is 0 to 0xFFFFFF.
*/
var RANKS = ['novice', 'advanced', 'master'];
var TOP_KEYS = ['about', 'item', 'steepSeconds', 'steepAt', 'who', 'dyes'];
var WHO_KEYS = ['anyone', 'halves'];
var DYE_KEYS = ['id', 'name', 'colour', 'wash', 'strength', 'wander', 'inputs'];
var INPUT_KEYS = ['item', 'count'];
var WANDER_MAX = 64;
var FORM = /^[0-9a-f]{1,8}:[^:\\\/]+\.(esm|esp|esl)$/;
var HEX = /^#[0-9a-f]{6}$/;
var ID = /^[a-z][a-z0-9-]*$/;

function own(o, key) { return Object.prototype.hasOwnProperty.call(o, key); }
function object(o) { return !!o && typeof o === 'object' && !Array.isArray(o); }
function form(s) { return typeof s === 'string' && FORM.test(s); }
function count(n) { return Number.isSafeInteger(n) && n > 0; }
function strays(o, keys, where, out) {
  Object.keys(o).forEach(function (k) { if (keys.indexOf(k) < 0) { out.push(where + ' has a key nobody reads: ' + k); } });
}
function colourOf(n) {
  if (!Number.isSafeInteger(n)) { return null; }
  return (n >>> 0) & 0xFFFFFF;
}
function hexColour(s) { return parseInt(s.slice(1), 16); }

// Every problem with the staff list, as sentences. Empty means it is good.
// Nothing here falls back: a list with any problem is a list nobody uses.
function checkDyes(data) {
  var out = [];
  if (!object(data)) { return ['the dye list is not an object']; }
  strays(data, TOP_KEYS, 'the dye list', out);
  if (own(data, 'about') && typeof data.about !== 'string') { out.push('about is not words'); }
  if (!form(data.item)) { out.push('item is not a record such as 1a2b:Skyrim.esm'); }
  if (!count(data.steepSeconds)) { out.push('steepSeconds is not a whole number above 0'); }
  if (!form(data.steepAt)) { out.push('steepAt is not a bench keyword record'); }
  if (!object(data.who)) { out.push('who is not an object'); }
  else {
    strays(data.who, WHO_KEYS, 'who', out);
    if (typeof data.who.anyone !== 'boolean') { out.push('who.anyone is not true or false'); }
    if (!object(data.who.halves)) { out.push('who.halves is not an object'); }
    else {
      Object.keys(data.who.halves).forEach(function (h) {
        if (!ID.test(h)) { out.push('who.halves names ' + JSON.stringify(h) + ', which is not a half'); }
        if (RANKS.indexOf(data.who.halves[h]) < 0) { out.push('who.halves.' + h + ' is not novice, advanced or master'); }
      });
      if (data.who.anyone === false && !Object.keys(data.who.halves).length) {
        out.push('who lets nobody make a dye: anyone is false and no half is named');
      }
    }
  }
  if (!Array.isArray(data.dyes) || !data.dyes.length) { out.push('dyes is not a list with a dye in it'); return out; }
  var ids = {}, names = {};
  data.dyes.forEach(function (d, i) {
    var at = 'dye ' + (i + 1);
    if (!object(d)) { out.push(at + ' is not an object'); return; }
    if (typeof d.id === 'string') { at += ' (' + d.id + ')'; }
    strays(d, DYE_KEYS, at, out);
    if (typeof d.id !== 'string' || !ID.test(d.id)) { out.push(at + ' has no id of lower-case letters, digits and dashes'); }
    else if (own(ids, d.id)) { out.push(at + ' has the same id as an earlier dye'); }
    else { ids[d.id] = true; }
    if (typeof d.name !== 'string' || !d.name.trim() || d.name !== d.name.trim()) { out.push(at + ' has no name'); }
    else if (own(names, d.name.toLowerCase())) { out.push(at + ' has the same name as an earlier dye'); }
    else { names[d.name.toLowerCase()] = true; }
    if (own(d, 'wash') && d.wash !== true) { out.push(at + ' has wash set to something other than true'); }
    if (d.wash === true) {
      if (own(d, 'colour')) { out.push(at + ' is a wash and has a colour: a wash goes back to the colour somebody was made with'); }
    } else if (typeof d.colour !== 'string' || !HEX.test(d.colour)) {
      out.push(at + ' has no colour written #rrggbb in lower case');
    }
    if (typeof d.strength !== 'number' || !(d.strength > 0 && d.strength <= 1)) { out.push(at + ' has a strength that is not above 0 and at most 1'); }
    if (!Number.isSafeInteger(d.wander) || d.wander < 0 || d.wander > WANDER_MAX) { out.push(at + ' has a wander that is not a whole number from 0 to ' + WANDER_MAX); }
    if (!Array.isArray(d.inputs) || !d.inputs.length) { out.push(at + ' takes nothing to make'); return; }
    var seen = {};
    d.inputs.forEach(function (p, j) {
      var pat = at + ' input ' + (j + 1);
      if (!object(p)) { out.push(pat + ' is not an object'); return; }
      strays(p, INPUT_KEYS, pat, out);
      if (!form(p.item)) { out.push(pat + ' is not a record such as 1a2b:Skyrim.esm'); }
      else if (own(seen, p.item)) { out.push(pat + ' names ' + p.item + ' twice'); }
      else { seen[p.item] = true; }
      if (form(p.item) && p.item === data.item) { out.push(pat + ' is the dye item itself'); }
      if (!count(p.count)) { out.push(pat + ' has a count that is not a whole number above 0'); }
    });
  });
  // A dye whose inputs hold all of an earlier dye's, as many or more of each,
  // can never be made: dyeFor gives the earlier one first.
  if (!out.length) {
    data.dyes.forEach(function (later, b) {
      for (var a = 0; a < b; a++) {
        if (covers(data.dyes[a].inputs, inputsOf(later))) {
          out.push('dye ' + (b + 1) + ' (' + later.id + ') can never be made: it takes everything ' +
                   data.dyes[a].id + ', earlier in the list, takes');
          break;
        }
      }
    });
  }
  return out;
}

function inputsOf(dye) {
  var held = {};
  dye.inputs.forEach(function (p) { held[p.item] = p.count; });
  return held;
}
function covers(inputs, carried) {
  return inputs.every(function (p) { return own(carried, p.item) && count(carried[p.item]) && carried[p.item] >= p.count; });
}

// The first dye in the staff list whose inputs are all carried, or null.
// carried is record -> how many, as the caller counted the pack.
function dyeFor(carried, data) {
  if (!object(carried)) { return null; }
  for (var i = 0; i < data.dyes.length; i++) {
    if (covers(data.dyes[i].inputs, carried)) { return data.dyes[i]; }
  }
  return null;
}

// Whether the list lets this person steep. canWork(half, rank) is the
// caller's: true when they work that half at that rank or above.
function mayMake(data, canWork) {
  if (data.who.anyone === true) { return true; }
  if (typeof canWork !== 'function') { return false; }
  return Object.keys(data.who.halves).some(function (h) { return canWork(h, data.who.halves[h]) === true; });
}

/*
  The colour a dye leaves. old is the colour on the head now, made the colour
  they were made with (the server keeps it from the first dye on), rand the
  caller's random number from 0 up to 1. Each channel goes strength of the way
  from old to the dye's colour, or for a wash to made, then wanders by up to
  wander either way, so two heads under one dye come out a little different.
  null when it cannot be worked out: an old colour that is not a number, a wash
  with no made colour, or a rand that is not a function giving 0 up to 1.
*/
function mixColour(old, dye, made, rand) {
  var from = colourOf(old);
  if (from === null || !object(dye) || typeof rand !== 'function') { return null; }
  var to = dye.wash === true ? colourOf(made) : (typeof dye.colour === 'string' && HEX.test(dye.colour) ? hexColour(dye.colour) : null);
  if (to === null) { return null; }
  var s = dye.strength, w = dye.wander;
  if (typeof s !== 'number' || !(s >= 0 && s <= 1) || !Number.isSafeInteger(w) || w < 0) { return null; }
  var out = 0;
  for (var shift = 16; shift >= 0; shift -= 8) {
    var r = rand();
    if (typeof r !== 'number' || !(r >= 0 && r < 1)) { return null; }
    var o = (from >> shift) & 0xFF, t = (to >> shift) & 0xFF;
    var c = Math.round(o + (t - o) * s + (r * 2 - 1) * w);
    out = out * 256 + Math.max(0, Math.min(255, c));
  }
  return out;
}

// The name a dye's inventory entry carries, the way a deed carries its own.
function dyeName(dye) { return dye.name; }

// The dye an inventory entry is, or null. itemBaseId, when given, is the
// dye item's base as the engine numbers it; an entry on any other base is
// not a dye whatever it is called.
function dyeOf(entry, data, itemBaseId) {
  if (!object(entry) || typeof entry.name !== 'string') { return null; }
  if (itemBaseId !== undefined && entry.baseId !== itemBaseId) { return null; }
  for (var i = 0; i < data.dyes.length; i++) {
    if (data.dyes[i].name === entry.name) { return data.dyes[i]; }
  }
  return null;
}

// A copy of a stored appearance with only its hair colour changed, or null
// when it is not an appearance or the colour is not 0 to 0xFFFFFF. It never
// touches the one it is handed.
function withHairColour(appearance, rgb) {
  if (!object(appearance) || !own(appearance, 'hairColor') || !Number.isSafeInteger(appearance.hairColor) ||
      !own(appearance, 'raceId') || !Array.isArray(appearance.headpartIds)) { return null; }
  if (!Number.isSafeInteger(rgb) || rgb < 0 || rgb > 0xFFFFFF) { return null; }
  var out = JSON.parse(JSON.stringify(appearance));
  out.hairColor = rgb;
  return out;
}

module.exports = {
  checkDyes: checkDyes, dyeFor: dyeFor, mayMake: mayMake, mixColour: mixColour,
  dyeName: dyeName, dyeOf: dyeOf, withHairColour: withHairColour, WANDER_MAX: WANDER_MAX
};
