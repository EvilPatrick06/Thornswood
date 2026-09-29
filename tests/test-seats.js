// test-seats.js
//
//     node .\tests\test-seats.js
//
// At most 25 people in the world at once, with staff roles allowed over it
// (#481). Patrick, 28 Sep: cap it at 25 for the alpha, raised later.
//
// THE GAME SERVER. The seats block is lifted out of game\gamemode.js between
// its markers and run in a vm with a stand-in mp and its own clock, the way
// test-join-pass-game.js runs the join pass block. Twenty six people join:
// the first twenty five are seated and the twenty sixth is told a plain line,
// named in the log as "door: full", and ended. A staff role with a join pass
// on hand is seated over the number; one with no pass is given a minute to
// show one and then refused. Nobody already in the world is ever ended by a
// hot reload.
//
// THE SITE. /api/play/join is lifted out of site\server.js and run with
// stand-ins, the way test-play-join.js runs it: with the world full it refuses
// Play for anybody without a staff role, before the game starts, and says the
// same sentence the game server does.
//
// THE NUMBER. records\most-online.json is the one place it lives; this checks
// it says 25, and that the gamemode reads thornswoodMostOnline, the key the
// deploy scripts write (test-max-online.ps1 runs the scripts themselves).
//
// Read only. Nothing connects to anything.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const CR = String.fromCharCode(13);
const ROOT = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(ROOT, 'game', 'gamemode.js'), 'utf8').split(CR).join('');
const site = fs.readFileSync(path.join(ROOT, 'site', 'server.js'), 'utf8').split(CR).join('');
const onlineCs = fs.readFileSync(path.join(ROOT, 'launcher', 'app', 'Online.cs'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

// ------------------------------------------------------------ the number
const record = JSON.parse(fs.readFileSync(path.join(ROOT, 'records', 'most-online.json'), 'utf8').replace(/^﻿/, ''));
yes('records\\most-online.json says 25 people', record.people === 25);
yes('and keeps some seats over it for staff', Number(record.staffSeats) > 0 && record.people + record.staffSeats <= 1000);

// ------------------------------------------------------------ the block
const a = src.indexOf('// ==== thornswood seats ====');
const b = src.indexOf('// ==== end thornswood seats ====');
yes('the seats block is in gamemode.js between its markers', a >= 0 && b > a);
if (!(a >= 0 && b > a)) done();
const block = src.slice(a, b);
yes('the seats block comes after the join pass block, whose passes it reads',
    src.indexOf('// ==== end thornswood join pass ====') >= 0 && src.indexOf('// ==== end thornswood join pass ====') < a);
yes('the chat commands block hands the seats block its staff check',
    /g\.__thornswoodIsStaff = isStaff;/.test(src));
yes('the online count file carries the number as max',
    /thornswoodMostOnline\) \|\| 0/.test(src) && /restarting: restarting, max: max/.test(src));

const ACTOR = 0xff000000;
function rig(settings, keep) {
  const r = { told: [], logged: [], kicked: [], timers: [], online: [], staff: {}, now: 1000000 };
  const box = keep || {};
  box.console = { log: function () { r.logged.push(Array.prototype.join.call(arguments, ' ')); } };
  box.Date = { now: function () { return r.now; } };
  box.Math = Math; box.Number = Number; box.String = String; box.Object = Object; box.Array = Array;
  box.setTimeout = function (fn) { r.timers.push(fn); return r.timers.length; };
  box.setInterval = function (fn) { r.interval = fn; return 1; };
  box.clearInterval = function () { };
  box.mp = {
    getServerSettings: function () { return settings; },
    getUserByActor: function (actorId) {
      for (let i = 0; i < r.online.length; i++) { if (r.online[i].actorId === actorId) { return actorId - ACTOR; } }
      return -1;
    },
    get: function (id, what) {
      if (id === 0 && what === 'onlinePlayers') { return r.online.map(function (o) { return o.actorId; }); }
      for (let i = 0; i < r.online.length; i++) { if (r.online[i].actorId === id) { return r.online[i].profileId; } }
      throw new Error('no such actor');
    },
    kick: function (userId) { r.kicked.push(userId); }
  };
  box.__thornswoodToProfile = function (p, text) { r.told.push({ p: p, text: text }); };
  box.__thornswoodIsStaff = function (p) { return !!r.staff[p]; };
  if (!box.__thornswoodPassSeen) { box.__thornswoodPassSeen = { passes: {}, online: {}, said: {} }; }
  if (!keep) { vm.createContext(box); }
  vm.runInContext(block, box);
  r.box = box;
  r.tick = function (ms) { r.now += (ms || 2000); r.interval(); };
  r.join = function (pid) { r.online.push({ actorId: ACTOR + pid, profileId: pid }); };
  r.leave = function (pid) { r.online = r.online.filter(function (o) { return o.profileId !== pid; }); };
  r.pass = function (pid) { box.__thornswoodPassSeen.passes[pid] = { at: r.now, x: r.now + 600000, v: '1.1.102', d: '1' + pid }; };
  r.runTimers = function () { const t = r.timers; r.timers = []; t.forEach(function (fn) { fn(); }); };
  r.saidTo = function (pid) { return r.told.filter(function (t) { return t.p === pid; }); };
  r.log = function () { return r.logged.join('\n'); };
  return r;
}

const SEATS = { thornswoodMostOnline: 25, maxPlayers: 35 };
let r = rig(SEATS);
yes('it says at startup how many the world holds', /seats: at most 25 in the world at once/.test(r.log()));
r.tick();
const api = r.box.__thornswoodSeats;
yes('it hands its sweep and sentence to the rest of the file', !!(api && api.sweep && api.sentence));
const SENTENCE = api.sentence(25);
yes("the sentence says the world is full and how many it holds ('" + SENTENCE + "')",
    /full/.test(SENTENCE) && /25 people/.test(SENTENCE) && /Try again/.test(SENTENCE));
yes('the sentence has no em dash and never the word the house rules forbid',
    SENTENCE.indexOf(String.fromCharCode(0x2014)) < 0 && !new RegExp('pla' + 'yer', 'i').test(SENTENCE));

// ---- twenty six join, one at a time
for (let p = 1; p <= 25; p++) { r.join(100 + p); r.tick(); }
yes('the first 25 are all seated, nobody told anything', r.told.length === 0 && r.kicked.length === 0);
r.join(126); r.tick();
yes('the 26th is told the sentence', r.saidTo(126).length === 1 && r.saidTo(126)[0].text === SENTENCE);
yes('and the log names it door: full, with the count',
    /door: full, refusing profile 126: 25 of 25 already in the world/.test(r.log()));
yes('the session is not ended in the same breath, so the line lands first', r.kicked.length === 0);
r.runTimers();
yes('then the 26th session is ended', r.kicked.length === 1 && r.kicked[0] === 126);
r.tick();
yes('and it is told once, not every sweep', r.saidTo(126).length === 1);
yes('nobody else was touched', r.told.length === 1);

// ---- 26 at once: whoever the engine lists 26th is the one refused
r = rig(SEATS); r.tick();
for (let p = 1; p <= 26; p++) { r.join(200 + p); }
r.tick();
yes('26 arriving in one sweep: exactly one refused, the 26th',
    r.told.length === 1 && r.told[0].p === 226);

// ---- staff over the number
r = rig(SEATS); r.tick();
for (let p = 1; p <= 25; p++) { r.join(300 + p); }
r.tick();
r.staff[399] = true; r.pass(399);
r.join(399); r.tick();
yes('a staff role with a join pass is seated over the number', r.saidTo(399).length === 0 &&
    /seats: profile 399 holds a staff role, seated over the number \(26 in the world, the number is 25\)/.test(r.log()));
r.runTimers();
yes('and stays', r.kicked.indexOf(399) < 0);
r.join(327); r.tick();
yes('the next person without a staff role is still refused', r.saidTo(327).length === 1 &&
    /door: full, refusing profile 327: 26 of 25/.test(r.log()));

// A staff role with no pass yet is given a minute to show one.
r.staff[398] = true;
r.join(398); r.tick();
yes('a staff role with no pass yet is not refused at once', r.saidTo(398).length === 0);
r.tick(30000);
r.pass(398); r.tick();
yes('and is seated once the pass comes in', r.saidTo(398).length === 0 &&
    /profile 398 holds a staff role, seated over the number/.test(r.log()));
// One that never shows a pass is refused after the minute.
r.staff[397] = true;
r.join(397); r.tick();
r.tick(api.staffWait + 1000);
yes('a staff role that never shows a pass is refused after the wait, and the log says why',
    r.saidTo(397).length === 1 &&
    /door: full, refusing profile 397: .* \(a staff role, but no join pass was shown\)/.test(r.log()));
yes('an expired pass does not count', (function () {
  const q = rig(SEATS); q.tick();
  for (let p = 1; p <= 25; p++) { q.join(400 + p); }
  q.tick();
  q.staff[499] = true;
  q.box.__thornswoodPassSeen.passes[499] = { at: q.now - 700000, x: q.now - 100000 };
  q.join(499); q.tick(); q.tick(api.staffWait + 1000);
  return q.saidTo(499).length === 1;
})());

// ---- a seat frees up
r = rig(SEATS); r.tick();
for (let p = 1; p <= 25; p++) { r.join(500 + p); }
r.tick();
r.join(526); r.tick();
yes('full: the 26th is refused', r.saidTo(526).length === 1);
r.leave(526); r.leave(501); r.tick();
r.join(526); r.tick();
yes('once somebody leaves, the one refused comes back and is seated', r.saidTo(526).length === 1);
r.join(527); r.tick();
yes('and the next after that is refused again', r.saidTo(527).length === 1);

// ---- a hot reload ends nobody
r = rig(SEATS); r.tick();
for (let p = 1; p <= 25; p++) { r.join(600 + p); }
r.staff[699] = true; r.pass(699); r.join(699);
r.tick();
const kept = r.box;
const r2 = rig(SEATS, kept);
r2.online = r.online.slice();
r2.tick();
yes('after a hot reload everybody in the world keeps their seat', r2.told.length === 0);
r2.join(626); r2.tick();
yes('and the next arrival is still judged against the number', r2.saidTo(626).length === 1);

// ---- already over the number when the server starts judging
r = rig(SEATS);
for (let p = 1; p <= 30; p++) { r.join(700 + p); }
r.tick();
yes('30 already in the world when this starts: all keep their seats', r.told.length === 0 &&
    /30 already in the world keep their seats/.test(r.log()));
r.join(731); r.tick();
yes('the 31st is refused', r.saidTo(731).length === 1);

// ---- no number, no limit
r = rig({ maxPlayers: 100 });
yes('with no thornswoodMostOnline it says nobody is turned away for numbers',
    /no thornswoodMostOnline in server-settings.json, so nobody is turned away for numbers/.test(r.log()));
r.tick();
for (let p = 1; p <= 40; p++) { r.join(800 + p); }
r.tick();
yes('and 40 join with nobody refused', r.told.length === 0 && r.kicked.length === 0);
yes('a number that is not a whole number is no number', rig({ thornswoodMostOnline: '25x' }).box.__thornswoodSeats.cap() === 0 &&
    rig({ thornswoodMostOnline: 2.5 }).box.__thornswoodSeats.cap() === 0 &&
    rig({ thornswoodMostOnline: 25 }).box.__thornswoodSeats.cap() === 25);

// ------------------------------------------------------------ the site
function grabFn(name) {
  const at = site.indexOf('\nfunction ' + name + '(');
  if (at < 0) return '';
  const bb = site.indexOf('{', at);
  let depth = 0;
  for (let i = bb; i < site.length; i++) {
    if (site[i] === '{') depth++;
    else if (site[i] === '}') { depth--; if (depth === 0) return site.slice(at + 1, i + 1); }
  }
  return '';
}
const seatsFullSrc = grabFn('seatsFull');
const worldFullSrc = grabFn('worldFull');
yes('server.js has seatsFull and worldFull', !!seatsFullSrc && !!worldFullSrc);
const seatsFull = new Function(seatsFullSrc + '\nreturn seatsFull;')();
const worldFull = new Function(worldFullSrc + '\nreturn worldFull;')();
yes('full at 25 of 25', seatsFull({ up: true, online: 25, max: 25 }) === true);
yes('not full at 24 of 25', seatsFull({ up: true, online: 24, max: 25 }) === false);
yes('not full with no number', seatsFull({ up: true, online: 60, max: 0 }) === false);
yes('not full while the server is down', seatsFull({ up: false, online: 25, max: 25 }) === false);
yes('the site says the same sentence the game server does', worldFull(25) === SENTENCE);
yes('the count poll reads max out of online.json', /o\.max > 0\) max = o\.max/.test(site) &&
    /max: up \? max : 0/.test(site));
yes('the public status carries max', /status: \{ up: gameStatus\.up, online: gameStatus\.online, max: gameStatus\.max \}/.test(site));

const HEAD = "  if (p === '/api/play/join' && req.method === 'POST') {";
const from = site.indexOf(HEAD);
const next = site.indexOf("if ((p === '/api/play/start' || p === '/api/play/end')", from);
let route = (from >= 0 && next > from) ? site.slice(from, next) : '';
if (route) route = route.slice(0, route.lastIndexOf('/*'));
yes('the check in route is in server.js where this expects it', !!route);
if (!route) done();
const fullAt = route.indexOf('seatsFull(gameStatus)');
yes('the full check comes after the ban, role and dev checks, and before anything is written',
    fullAt > route.indexOf("why:'banned'") && fullAt > route.indexOf("why:'role'") &&
    fullAt > route.indexOf("why:'dev'") && fullAt < route.indexOf('putJson('));

const AsyncFunction = Object.getPrototypeOf(async function () { }).constructor;
async function join(standing, status, channel) {
  let sent = null;
  const env = {
    p: '/api/play/join', req: { method: 'POST' }, res: {},
    body: async function () { return JSON.stringify({ ticket: 'D1', profileId: 4242, channel: channel || '' }); },
    readTicket: function (s) { return s ? { d: String(s), n: 'name' } : null; },
    standing: async function () {
      return Object.assign({ id: 'D1', name: 'name', inGuild: true, banned: false, play: true,
                             dev: false, admin: false, roles: ['Playtester'] }, standing || {});
    },
    standCache: new Map(),
    cfg: { discord: { invite: '' }, access: { dev: ['Owner', 'Dev'] } },
    andList: function (l) { return l.join(' and '); },
    notAcceptedYet: function () { return 'not yet'; },
    accountBanned: function () { return 'banned'; },
    gameStatus: status, seatsFull: seatsFull, worldFull: worldFull,
    // Past the full check the route links the id; these only have to not throw.
    departed: async function () { return new Set(); },
    jsonFile: function (f, fallback) { return f === 'linked.json' ? {} : fallback; },
    putJson: function () { },
    LINKED: 'linked.json',
    slotsFor: function () { return 2; },
    sendJson: function (r, c, obj) { sent = { code: c, obj: obj }; return sent; },
    console: { log: function () { }, error: function () { } }
  };
  const names = Object.keys(env);
  const fn = new AsyncFunction(names.join(','), route + '\nreturn "fell through";');
  try { await fn.apply(null, names.map(function (n) { return env[n]; })); }
  catch (e) { return { threw: String(e) }; }
  return sent || { fellThrough: true };
}

(async function () {
  const FULL = { up: true, online: 25, max: 25 };
  let got = await join({}, FULL);
  yes('world full: a person with no staff role is refused Play with why full',
      !!got.obj && got.code === 403 && got.obj.why === 'full');
  yes('and told the plain sentence, before the game starts', !!got.obj && got.obj.message === SENTENCE);
  yes('with the count, for the launcher to show', !!got.obj && got.obj.online === 25 && got.obj.max === 25);
  got = await join({ dev: true }, FULL);
  yes('a staff role is let through when the world is full', !!got.obj && got.obj.why !== 'full' && !got.threw);
  got = await join({ admin: true }, FULL);
  yes('so is an admin', !!got.obj && got.obj.why !== 'full' && !got.threw);
  got = await join({}, { up: true, online: 24, max: 25 });
  yes('24 of 25: let through', !!got.obj && got.obj.why !== 'full' && !got.threw);
  got = await join({}, { up: false, online: 0, max: 0 });
  yes('server down: not refused for numbers', !!got.obj && got.obj.why !== 'full' && !got.threw);
  got = await join({ dev: true }, FULL, 'dev');
  yes('the dev build (staff only) is never refused for numbers', !!got.obj && got.obj.why !== 'full' && !got.threw);

  // ------------------------------------------------------------ the launcher
  yes('the launcher reads the server\'s own number out of online.json', /"\\"max\\"\\\\s\*:\\\\s\*\(\\\\d\+\)"/.test(onlineCs) &&
      /got\.Max = most;/.test(onlineCs));
  done();
})();
