// stucktest.js
//
// Somebody who never moves must still get out of the creation hall.
//
// MEASURED IN THE LIVE SERVER LOG, 21 September, four sessions, one shape:
//
//   13:35:33  chargen ff000056 profile 933578397 is new, in the hall
//   13:35:33  chargen ff000056 -> appearance (already in the hall)
//   13:41:55  disconnect 2
//
// Six minutes and nothing in between. The five minute give up should have
// fired at 13:40:33. It could not: every rescue in the appearance stage sat
// under `if (!state.liveSince) { continue; }`, and liveSince is only set when
// the server watches somebody MOVE. A person stuck at a menu, on a load
// screen, or in a race menu that never opened is by definition not moving, so
// the rescues written for exactly that person were the ones they could never
// reach. A playtester described the same evening from the other side.
//
// chargentest.js beside this covers the new-or-returning decision and has 17
// checks, none of which go near this, which is why it passed throughout.
//
// This lifts the appearance stage out of the shipped file and drives it with a
// clock. Nothing is stubbed that decides anything: the stage is the real text.
//
// Read only.
const fs = require('fs');
const path = require('path');
// Beside this file, not a path off one machine. The harness this was modelled
// on shipped pointing at /mnt/user-data/outputs, a sandbox that exists nowhere,
// and would not run for anybody who checked it out.
const SRC = process.env.GM || path.join(__dirname, 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

const START = "    if (state.stage === 'appearance') {";
const a = src.indexOf(START);
if (a < 0) throw new Error('could not find the appearance stage');
// It ends where the stage's own brace closes, at four spaces.
const END = '\n    }\n';
const b = src.indexOf(END, a);
if (b < 0) throw new Error('could not find the end of the appearance stage');
const stage = src.slice(a, b + END.length);
if (!/GIVEUP_MS/.test(stage)) throw new Error('lifted block has no give up in it');

function num(name) {
  const m = new RegExp('const ' + name + ' = (\\d+)').exec(src);
  if (!m) throw new Error('no ' + name + ' in the gamemode');
  return Number(m[1]);
}
const NUDGE_MS = num('NUDGE_MS');
const GIVEUP_MS = num('GIVEUP_MS');
const MOVED_ENOUGH_MS = num('MOVED_ENOUGH_MS');
const MOVED_UNITS = num('MOVED_UNITS');
const MOVED_DEGREES = num('MOVED_DEGREES');
// The race menu hold (entry 43). Read without throwing, so a gamemode from
// before it still runs every check and fails the ones that are about it.
function numOr(name) {
  const m = new RegExp('const ' + name + ' = (\\d+)').exec(src);
  return m ? Number(m[1]) : null;
}
const FACE_SEEN_MS = numOr('FACE_SEEN_MS');
const FACE_CAP_MS = numOr('FACE_CAP_MS');

/*
  One run of the appearance stage, at a given moment.

  The stage uses `continue`, so it runs inside a do/while(false): a continue
  there jumps to the condition, which is false, so it leaves exactly the way
  the real one leaves an iteration. Same trick chargentest.js uses.
*/
function tick(opts) {
  const out = { chose: null, nudged: false, log: [], state: opts.state };
  const actorId = 0xff000056;
  const now = opts.now;
  const firstSeen = new Map([[actorId, opts.state.seenAt || 1]]);
  const appearance = opts.appearance || null;
  const state = opts.state;
  const mp = {
    get(id, key) {
      if (key === 'pos') { return opts.pos || [0, 0, 0]; }
      if (key === 'angle') { return opts.angle || [0, 0, 0]; }
      return null;
    },
    setRaceMenuOpen() { out.nudged = true; }
  };
  const log = (...a) => out.log.push(a.join(' '));
  const setChargen = (id, s) => { out.state = s; };
  const faceMark = (ap) => (ap && ap.mark) ? String(ap.mark) : '';
  const beginChoosing = (id, s, why) => { out.chose = why; };

  const fn = new Function(
    'actorId', 'now', 'firstSeen', 'appearance', 'state', 'mp', 'log',
    'setChargen', 'faceMark', 'beginChoosing',
    'NUDGE_MS', 'GIVEUP_MS', 'MOVED_ENOUGH_MS', 'MOVED_UNITS', 'MOVED_DEGREES',
    'FACE_SEEN_MS', 'FACE_CAP_MS',
    'do {\n' + stage + '\n} while (false);');
  fn(actorId, now, firstSeen, appearance, state, mp, log, setChargen, faceMark,
     beginChoosing, NUDGE_MS, GIVEUP_MS, MOVED_ENOUGH_MS, MOVED_UNITS, MOVED_DEGREES,
     FACE_SEEN_MS, FACE_CAP_MS);
  return out;
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/** A character in the hall who has been asked for a face and never moves. */
function stuck(at) {
  return { stage: 'appearance', at: at, seenAt: 1, askedAt: at, faceWas: '' };
}

console.log('nudge at ' + (NUDGE_MS / 1000) + 's, give up at ' + (GIVEUP_MS / 1000) + 's');
console.log('');

// S1: THE ONE THE LOG SHOWED. Never moves, no face, and the clock runs past
//     the give up. They must be let out.
{
  const t0 = 1000000;
  let st = stuck(t0);
  let out = tick({ state: st, now: t0 + 1000 });
  yes('S1 a second in, nothing happens yet', out.chose === null);

  out = tick({ state: st, now: t0 + GIVEUP_MS + 1000 });
  yes('S1 past the give up they are moved on', out.chose !== null);
  yes('S1 and the log says the face never arrived',
      out.log.join(' ').indexOf('never arrived') !== -1);
  console.log('S1   ' + (out.log[0] || '(nothing logged)'));
}

// S2: and they are NOT nudged, because the nudge opens a race menu and a
//     second race menu over a first one took the game down with an access
//     violation in a head part call. Not moving is the proxy for "a menu may
//     be open", so the nudge keeps that guard even though the give up does not.
{
  const t0 = 2000000;
  const st = stuck(t0);
  const out = tick({ state: st, now: t0 + NUDGE_MS + 1000 });
  yes('S2 somebody who never moved is not sent a second race menu', !out.nudged);
  yes('S2 and is not moved on before the give up either', out.chose === null);
}

// S3: somebody who IS on their feet is moved on almost at once, and is NOT
//     nudged, because the walking branch ends the stage after MOVED_ENOUGH_MS.
//
//     This is what showed the nudge to be unreachable by anybody. It needs
//     liveSince and 120 seconds; a character with liveSince has been gone for
//     119 and a half of them. Not moving is guarded out. There is no path to
//     it, and the gamemode says so over the code now rather than leaving it
//     reading like a rescue that runs.
{
  const t0 = 3000000;
  const st = stuck(t0);
  st.liveSince = t0;
  const out = tick({ state: st, now: t0 + MOVED_ENOUGH_MS + 100 });
  yes('S3 a walking character is moved on within a second', out.chose !== null);
  yes('S3 and is never nudged, because they have already gone', !out.nudged);

  const late = tick({ state: stuck(t0), now: t0 + NUDGE_MS + 1000 });
  yes('S3 and a still character has not been nudged at the nudge time either',
      !late.nudged);
}

// S4: the face arriving is still the ordinary way out, whatever the clock says.
{
  const t0 = 4000000;
  const st = stuck(t0);
  const out = tick({ state: st, now: t0 + 2000, appearance: { mark: 'a-new-face' } });
  yes('S4 a face that arrives ends the stage at once', out.chose !== null);
  yes('S4 and nothing was nudged to get it', !out.nudged);
}

// S5: and so is the plugin saying the race menu closed.
{
  const t0 = 5000000;
  const st = stuck(t0);
  st.faceDone = true;
  const out = tick({ state: st, now: t0 + 2000 });
  yes('S5 the race menu closing ends the stage', out.chose !== null);
}

// S6: the guard is gone from the give up, in the shipped text. A check that
//     only drives the code can be satisfied by a stub; this reads the file.
//
//     COMMENTS ARE STRIPPED FIRST. The fix quotes the removed line in the
//     comment explaining why it went, so a plain search for the text finds it
//     in the prose and calls the fix a failure. That happened on the first run
//     of this file and is exactly the sort of check that gets muted rather
//     than fixed.
{
  const code = stage
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('S6 no bare liveSince guard stands anywhere in the code',
      code.indexOf('if (!state.liveSince) { continue; }') === -1);
  yes('S6 and the nudge still asks for liveSince',
      /waited > NUDGE_MS && state\.liveSince/.test(code));
  yes('S6 the give up is still there', /waited > GIVEUP_MS/.test(code));
}

/*
  ENTRY 43. THE GIVE UP FIRED ON SOMEBODY MAKING A FACE.

  Djinn, 22 September: "Sitting in the selector window, it automatically timed
  me out to name choice without any input commands". The live log has his
  session: appearance at 19:50:42, and at 19:55:43 "appearance never arrived
  after 300s, going on to the choices anyway". He was in the race menu. The
  plugin now reports the race menu as /racemenu, once when it opens and once
  a minute while it stays, and the give up holds while those are fresh.
*/
console.log('');
console.log('race menu reports fresh for ' + (FACE_SEEN_MS / 1000) + 's, hold capped at ' +
            (FACE_CAP_MS / 60000) + ' minutes');
yes('S7 the gamemode says how fresh a race menu report must be',
    FACE_SEEN_MS !== null && FACE_SEEN_MS >= 90000 && FACE_SEEN_MS <= 300000);
yes('S7 and how long the hold may last',
    FACE_CAP_MS !== null && FACE_CAP_MS > GIVEUP_MS);

/** A person sitting in a race menu the plugin keeps reporting, from `opened`. */
function inRaceMenu(t0, opened, lastSeen) {
  const st = stuck(t0);
  st.faceOpenAt = opened;
  st.faceSeenAt = lastSeen;
  return st;
}

// S8: DJINN'S SESSION. Five minutes and a second in, touching nothing, with the
//     race menu reported a few seconds ago. Nobody is moved on.
{
  const t0 = 8000000;
  const at = t0 + GIVEUP_MS + 1000;
  const st = inRaceMenu(t0, t0 + 5000, at - 20000);
  const out = tick({ state: st, now: at });
  yes('S8 sitting still in a reported race menu past five minutes moves nobody on',
      out.chose === null);
  yes('S8 and the log says why', out.log.join(' ').indexOf('race menu is still up') !== -1);
  console.log('S8   ' + (out.log[0] || '(nothing logged)'));

  // The next tick, and a minute later with a fresh beat: still held, and the
  // hold is said once rather than twice a second for half an hour.
  const again = tick({ state: out.state, now: at + 500 });
  yes('S8 the hold is logged once, not every tick', again.chose === null && again.log.length === 0);
  out.state.faceSeenAt = at + 60000;
  const later = tick({ state: out.state, now: at + 61000 });
  yes('S8 a minute later with the next report, still held', later.chose === null);
}

// S9: the reports stopped. The client crashed, quit, or its race menu closed
//     and the /face done line was lost. The give up runs as it always did.
{
  const t0 = 9000000;
  const at = t0 + GIVEUP_MS + 1000;
  const st = inRaceMenu(t0, t0 + 5000, at - FACE_SEEN_MS - 1000);
  const out = tick({ state: st, now: at });
  yes('S9 a race menu report older than the freshness window does not hold anybody',
      out.chose !== null);
}

// S10: the race menu has been reported for longer than the cap. It is up and
//      wedged, and the panel is the only way out left, so they go on.
{
  const t0 = 10000000;
  const at = t0 + FACE_CAP_MS + 60000;
  const st = inRaceMenu(t0, t0 + 5000, at - 10000);
  const out = tick({ state: st, now: at });
  yes('S10 past the cap the give up goes on even with the race menu reported',
      out.chose !== null);
  yes('S10 and the log says how long it was up',
      out.log.join(' ').indexOf('race menu has been up for') !== -1);
}

// S11: a race menu that was never reported is the case the five minutes were
//      written for, and S1 still covers it. This is the same clock with a
//      report that arrived before the give up: before five minutes, nothing
//      changes either way.
{
  const t0 = 11000000;
  const st = inRaceMenu(t0, t0 + 5000, t0 + 60000);
  const out = tick({ state: st, now: t0 + 120000 });
  yes('S11 before the give up a reported race menu changes nothing', out.chose === null &&
      out.log.length === 0);
}

// S12: a reconnect starts the report over, because the old session's race
//      menu went with it.
{
  const t0 = 12000000;
  const same = inRaceMenu(t0, t0 + 5000, t0 + 250000);
  same.faceHeld = t0 + 301000;
  const stayed = tick({ state: same, now: t0 + 310000 });
  yes('S12 (without a reconnect, that state is still held)', stayed.chose === null);

  // tick() puts the person online at state.seenAt, which is no reconnect.
  // tickAs puts them online at a later moment, which is one.
  const back = inRaceMenu(t0, t0 + 5000, t0 + 250000);
  back.faceHeld = t0 + 301000;
  const out = tickAs(back, t0 + 310000, 2);
  yes('S12 a reconnect clears the last session\'s race menu report',
      out.chose === null && !out.state.faceOpenAt && !out.state.faceSeenAt && !out.state.faceHeld);
}

/** tick(), but with the actor seen online at `cameOn` rather than seenAt. */
function tickAs(state, now, cameOn) {
  const out = { chose: null, nudged: false, log: [], state: state };
  const actorId = 0xff000056;
  const firstSeen = new Map([[actorId, cameOn]]);
  const mp = {
    get(id, key) { return key === 'pos' || key === 'angle' ? [0, 0, 0] : null; },
    setRaceMenuOpen() { out.nudged = true; }
  };
  const fn = new Function(
    'actorId', 'now', 'firstSeen', 'appearance', 'state', 'mp', 'log',
    'setChargen', 'faceMark', 'beginChoosing',
    'NUDGE_MS', 'GIVEUP_MS', 'MOVED_ENOUGH_MS', 'MOVED_UNITS', 'MOVED_DEGREES',
    'FACE_SEEN_MS', 'FACE_CAP_MS',
    'do {\n' + stage + '\n} while (false);');
  fn(actorId, now, firstSeen, null, state, mp,
     function () { out.log.push(Array.prototype.join.call(arguments, ' ')); },
     function (id, s) { out.state = s; }, function () { return ''; },
     function (id, s, why) { out.chose = why; },
     NUDGE_MS, GIVEUP_MS, MOVED_ENOUGH_MS, MOVED_UNITS, MOVED_DEGREES,
     FACE_SEEN_MS, FACE_CAP_MS);
  return out;
}

// S13: faceOpen, lifted from the chargen block, records the report only while
//      the face is awaited, keeps the first sighting and moves the last.
{
  const a = src.indexOf('  faceOpen: function (actorId) {');
  const b = a < 0 ? -1 : src.indexOf('\n  },\n', a);
  yes('S13 the chargen block has faceOpen', a >= 0 && b > a);
  if (a >= 0 && b > a) {
    const body = src.slice(a + '  faceOpen: '.length, b + 4);
    const clock = { t: 5000 };
    const store = {};
    const logs = [];
    const faceOpen = new Function('chargenOf', 'setChargen', 'log', 'Date',
      'return ' + body + ';')(
      function (id) { return store[id] || null; },
      function (id, s) { store[id] = s; },
      function () { logs.push(Array.prototype.join.call(arguments, ' ')); },
      { now: function () { return clock.t; } });
    store[7] = { stage: 'appearance' };
    yes('S13 the first report is recorded', faceOpen(7) === true &&
        store[7].faceOpenAt === 5000 && store[7].faceSeenAt === 5000);
    clock.t = 65000;
    faceOpen(7);
    yes('S13 a later one moves the last sighting and keeps the first',
        store[7].faceOpenAt === 5000 && store[7].faceSeenAt === 65000);
    yes('S13 only the first is logged', logs.length === 1);
    store[8] = { stage: 'choosing' };
    yes('S13 a report after the face is made does nothing', faceOpen(8) === false &&
        !store[8].faceSeenAt);
    yes('S13 nor for somebody with no creation at all', faceOpen(9) === false);
  }
}

// S14: the wire. /racemenu reaches faceOpen, is never held for a character
//      still on its way back, and is a different word from /face, which a
//      gamemode from before this reads as the race menu closing.
{
  // The handler's branch, not the one line in runsNow that starts the same.
  const r = src.indexOf("    if (word === '/racemenu') {\n      try {");
  const rEnd = r < 0 ? -1 : src.indexOf('\n    }\n', r);
  yes('S14 the command handler answers /racemenu', r >= 0 && rEnd > r);
  if (r >= 0 && rEnd > r) {
    const branch = src.slice(r, rEnd + 7);
    const seen = [];
    const g = { __thornswoodChargen: { faceOpen: function (id) { seen.push(id); } } };
    const run = new Function('globalThis', 'word', 'profileId', 'actorOf', 'log',
      'return (function () {\n' + branch + '\n  return "fell through";\n})();');
    const said = run(g, '/racemenu', 44, function (p) { return p === 44 ? 0xff000009 : 0; },
                     function () { });
    yes('S14 /racemenu calls faceOpen on that person\'s character',
        seen.length === 1 && seen[0] === 0xff000009 && said === undefined);
    run(g, '/racemenu', 45, function () { return 0; }, function () { });
    yes('S14 and with no character it does nothing, and says nothing', seen.length === 1);
  }
  const ra = src.indexOf('  function runsNow(word, parts) {');
  const rb = ra < 0 ? -1 : src.indexOf('\n  }\n', ra);
  const wm = /^const WORDS = (\[[\s\S]*?\]);$/m.exec(src);
  const WORDS = wm ? new Function('return ' + wm[1])() : [];
  yes('S14 /racemenu is in the list of words the server answers',
      WORDS.indexOf('/racemenu') !== -1);
  if (ra >= 0 && rb > ra) {
    const runsNow = new Function('WORDS', 'return ' + src.slice(ra + 2, rb + 4) + ';')(WORDS);
    yes('S14 /racemenu runs at once and is never held to be replayed late',
        runsNow('/racemenu', ['/racemenu']) === true);
  } else {
    yes('S14 runsNow is in the gamemode', false);
  }
}

// S15: the plugin's half, lifted from thornswood-front.js: told when the race
//      menu opens, once a minute while it stays, not before the overlays are in,
//      and /face done when it closes.
{
  const FRONT = process.env.FRONT || path.join(__dirname, 'ts-plugins', 'thornswood-front.js');
  const fsrc = fs.readFileSync(FRONT, 'utf8').split(CR).join('');
  const a = fsrc.indexOf('  let raceWasOpen = false;');
  // To the end of the race menu's own handler, and no further: the code after
  // it changes (closing Skyrim while making a face went in there on 24
  // September and needs iniNumber, which is nothing to do with this watcher).
  const endAt = a < 0 ? -1 : fsrc.indexOf('\n  }));\n', a);
  const b = endAt < 0 ? -1 : endAt + '\n  }));\n'.length;
  yes('S15 the plugin\'s race menu watcher is there', a >= 0 && b > a);
  if (a >= 0 && b > a) {
    const clock = { t: 1000000 };
    const told = [];
    const T = { ready: false };
    const menu = { open: false };
    let handler = null;
    const sp = { on: function (ev, fn) { if (ev === 'update') { handler = fn; } } };
    // closingGame is the flag closeGame sets while Skyrim is being closed from
    // the face and body menu; this watcher reads it, and it is false here.
    new Function('sp', 'guard', 'raceMenuOpen', 'log', 'tellServer', 'T', 'Date', 'closingGame',
      fsrc.slice(a, b))(
      sp, function (n, fn) { return fn; }, function () { return menu.open; },
      function () { }, function (l) { told.push(l); }, T,
      { now: function () { return clock.t; } }, false);
    function frames(ms) {
      const end = clock.t + ms;
      while (clock.t < end) { handler(); clock.t += 16; }
    }
    menu.open = true;
    frames(2000);
    yes('S15 nothing is told before the overlays are in', told.length === 0);
    T.ready = true;
    frames(100);
    yes('S15 the race menu being up is told as soon as it can be',
        told.length === 1 && told[0] === '/racemenu');
    frames(59000);
    yes('S15 and not again inside the minute', told.length === 1);
    frames(2000);
    yes('S15 then once more a minute on', told.length === 2 && told[1] === '/racemenu');
    frames(5 * 60000);
    const beats = told.filter(function (l) { return l === '/racemenu'; }).length;
    yes('S15 about once a minute, not once a frame (' + beats + ' in seven minutes)',
        beats >= 6 && beats <= 8);
    menu.open = false;
    frames(100);
    yes('S15 closing it tells the server /face done', told[told.length - 1] === '/face done');
    const after = told.length;
    frames(120000);
    yes('S15 and nothing more while it is shut', told.length === after);
    menu.open = true;
    frames(100);
    yes('S15 a second race menu is told at once, not a minute later',
        told.length === after + 1 && told[after] === '/racemenu');
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
