// test-614-riekling-clothes-remount.js
//
// #614 Goblin/Riekling clothes: neck placement + transparency on rejoin /
// leaving a building. Not race-default gear only, not a clothing form-id list.
//
// Root cause measured: equipment can read as equipped while armor addons for
// these races fail to remount after appearance queueNiNodeUpdate or a cell
// load. Front remounts already-worn Armor by race name and rebuilds NiNodes.
// Gamemode wearScript also queues a NiNode update after server-driven equip.
//
// Race display-name leftover: playable FULL NAMEs from game/data/races.json
// (built from Playable Rieklings.esp) are only Riekling Blue / Riekling Purple.
// No bare Goblin FULL NAME. /riekling|goblin/i covers them; no matcher widen.
//
//   node tests/test-614-riekling-clothes-remount.js
'use strict';
const fs = require('fs');
const path = require('path');
const FRONT = process.env.FRONT ||
  path.join(__dirname, '..', 'game', 'plugins', 'thornswood-front.js');
const GM = process.env.GM ||
  path.join(__dirname, '..', 'game', 'gamemode.js');
const RACES = process.env.RACES ||
  path.join(__dirname, '..', 'game', 'data', 'races.json');
const CR = String.fromCharCode(13);
const front = fs.readFileSync(FRONT, 'utf8').split(CR).join('');
const gm = fs.readFileSync(GM, 'utf8').split(CR).join('');
const races = JSON.parse(fs.readFileSync(RACES, 'utf8'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

yes('front names the #614 remount work',
  /RIEKLING \/ GOBLIN CLOTHES REMOUNT \(#614\)/.test(front));
yes('front matches race by name, not clothing form ids',
  /\/riekling\|goblin\/i\.test\(name\)/.test(front));
yes('front remounts already-worn Armor only',
  /function remountWornClothes\(why\)/.test(front) &&
  /sp\.Armor\.from\(form\)/.test(front) &&
  /ac\.unequipItem\(form, false, true\)/.test(front) &&
  /ac\.equipItem\(form, false, true\)/.test(front));
yes('front calls queueNiNodeUpdate after remount',
  /ac\.queueNiNodeUpdate\(\)/.test(front));
yes('front remounts on cell change',
  /function clothesRemountTick\(\)/.test(front) &&
  (/remountWornClothes\("cell"\)/.test(front) ||
   /remountWornClothes\('cell'\)/.test(front)));
yes('front schedules spawn/rejoin remounts',
  /function scheduleSpawnClothesRemount\(\)/.test(front) &&
  /scheduleSpawnClothesRemount\(\);/.test(front));
yes('front registers the clothes remount tick',
  /guard\('clothes remount', clothesRemountTick\)/.test(front));
yes('front does not invent a clothing form-id list for #614',
  !/SHIFT_IDS.*riekling|rieklingFormIds|GOBLIN_CLOTHES|CLOTHES_IDS\s*=\s*\[/i.test(front));
yes('front documents race-table Goblin display-name confirm',
  /No playable race uses a bare Goblin FULL NAME/.test(front));

yes('gamemode wearScript queues NiNode after equip (#614)',
  /function wearScript\(\)/.test(gm) &&
  /ac\.queueNiNodeUpdate\(\)/.test(gm));

const remountRx = /riekling|goblin/i;
const items = races && races.items ? Object.keys(races.items).map(function (id) {
  return races.items[id];
}) : [];
const playable = items.filter(function (it) { return !!it.p; });
const playableBlue = playable.filter(function (it) {
  return String(it.n || '') === 'Riekling Blue';
});
const playablePurple = playable.filter(function (it) {
  return String(it.n || '') === 'Riekling Purple';
});
const playableGoblinBare = playable.filter(function (it) {
  const n = String(it.n || '');
  return /goblin/i.test(n) && !/riekling/i.test(n);
});
const playableRieklingish = playable.filter(function (it) {
  return remountRx.test(String(it.n || '') + ' ' + String(it.e || ''));
});
const playableFullNameMiss = playableRieklingish.filter(function (it) {
  return !remountRx.test(String(it.n || ''));
});

yes('race table lists playable Riekling Blue',
  playableBlue.length >= 1);
yes('race table lists playable Riekling Purple',
  playablePurple.length >= 1);
yes('no playable bare-Goblin FULL NAME in race table',
  playableGoblinBare.length === 0);
yes('every playable riekling/goblin FULL NAME matches remount regex',
  playableRieklingish.length >= 2 && playableFullNameMiss.length === 0);

console.log(fail ? ('FAILED ' + fail + ' of ' + (pass + fail)) : ('OK ' + pass + ' checks'));
process.exit(fail ? 1 : 0);