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
    'do {\n' + stage + '\n} while (false);');
  fn(actorId, now, firstSeen, appearance, state, mp, log, setChargen, faceMark,
     beginChoosing, NUDGE_MS, GIVEUP_MS, MOVED_ENOUGH_MS, MOVED_UNITS, MOVED_DEGREES);
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

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
