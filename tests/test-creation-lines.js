// test-creation-lines.js
//
// Every step of creation says one line to the person, beside its log line.
//
// WHY. Issue #416: "The whole of character creation is narrated to a log file
// on the VPS and to nothing the person can see." A stranger's first minutes
// were a stone room with nobody in it, a race menu, silence, clothes turning
// up in the pack and a teleport, and the server wrote every one of those to
// its own log and to nobody else. arriveAt got its line on 24 September
// (test-arrival-line.js). This covers the rest:
//
//   nothing -> appearance   beginAppearance: the hall, and the move into it
//   appearance -> choosing  beginChoosing: the clothes, and what the pick does
//   choosing -> done        arriveAt: the town and the inn
//   nothing -> done         the returning stamp in chargenTick: welcome back
//
// The legacy 'arriving' -> done stamp is left silent on purpose: nothing
// changes for the person there, it only tidies a record from before the kits
// went on 20 September.
//
// Each piece is the real text lifted out of gamemode.js and run against a
// stand-in mp and a stand-in say, the way test-online-names.js drives its
// block. GM points it at another copy of the file, which is how it was shown
// to fail on the code before the change.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

// ------------------------------------------------------- lifted by text
function fnOf(head) {
  const a = src.indexOf(head);
  const b = a < 0 ? -1 : src.indexOf('\n}\n', a);
  return (a >= 0 && b >= 0) ? src.slice(a, b + 2) : null;
}
const APPEAR = fnOf('function beginAppearance(actorId) {');
const CHOOSE = fnOf('function beginChoosing(actorId, state, why) {');
const ARRIVE = fnOf('function arriveAt(actorId, townKey) {');
const HALL_TO = fnOf('function sendToHall(actorId) {');
const SHIFT_FN = fnOf('function giveShift(actorId) {');
// The no-record branch of chargenTick, through its closing brace at four spaces.
const NEW_START = '    if (!state) {';
const na = src.indexOf(NEW_START);
const nb = na < 0 ? -1 : src.indexOf('\n    }\n', na);
const NEWBRANCH = (na >= 0 && nb >= 0) ? src.slice(na, nb + 7) : null;
const HALL_SRC = (/\nconst HALL = (\{[\s\S]*?\n\});/.exec(src) || [])[1] || null;
let CHARGEN = null;
{
  const m = /\nconst CHARGEN = (\{.*\});\n/.exec(src);
  try { CHARGEN = m ? JSON.parse(m[1]) : null; } catch (e) { CHARGEN = null; }
}

yes('beginAppearance, beginChoosing, arriveAt, sendToHall, giveShift, the new-or-returning ' +
    'branch, HALL and the town table are all in gamemode.js',
    !!(APPEAR && CHOOSE && ARRIVE && HALL_TO && SHIFT_FN && NEWBRANCH && HALL_SRC && CHARGEN));
if (!(APPEAR && CHOOSE && ARRIVE && HALL_TO && SHIFT_FN && NEWBRANCH && HALL_SRC && CHARGEN)) { done(); }

const HALL = new Function('return ' + HALL_SRC)();
const PASSAGES = CHARGEN.towns;
const SHIFT = CHARGEN.shift;
const TOWN_BY_KEY = {};
for (const desc in PASSAGES) { TOWN_BY_KEY[PASSAGES[desc].key] = desc; }

/*
  One world: a stand-in mp keeping each actor's properties, a clock, and
  every say, notify and log recorded. The real functions are built over it
  and wired to each other the way the gamemode wires them.
*/
function world(opts) {
  opts = opts || {};
  const clock = { now: 1790000000000 };
  const props = {};
  const out = { said: [], notified: [], logs: [], opened: opts.panel !== false };
  const mp = {
    get: function (id, key) {
      const p = props[id] || {};
      return p[key] === undefined ? undefined : JSON.parse(JSON.stringify(p[key]));
    },
    set: function (id, key, v) {
      if (!props[id]) { props[id] = {}; }
      props[id][key] = JSON.parse(JSON.stringify(v));
    },
    setRaceMenuOpen: function () { }
  };
  const FakeDate = { now: function () { return clock.now; } };
  const firstSeen = new Map();
  const say = function (id, text) { out.said.push({ id: id, text: String(text) }); };
  const notify = function (id, text) { out.notified.push({ id: id, text: String(text) }); };
  const log = function () { out.logs.push(Array.prototype.slice.call(arguments).join(' ')); };
  const setChargen = function (id, st) { mp.set(id, 'thornswoodChargen', st); };
  const chargenOf = function (id) {
    const s = mp.get(id, 'thornswoodChargen');
    return (s && typeof s === 'object') ? s : null;
  };
  const ids = {};
  const idOf = function (desc) {
    if (!desc) { return 0; }
    if (!ids[desc]) { ids[desc] = 0x1000 + Object.keys(ids).length; }
    return ids[desc];
  };
  const closeRaceMenu = function () { };
  const openCreation = function () { return out.opened; };
  const wearThese = function () { };
  const faceMark = function (a) { return (a && a.mark) ? String(a.mark) : ''; };

  const sendToHall = new Function('mp', 'idOf', 'HALL', 'log',
    HALL_TO + '\nreturn sendToHall;')(mp, idOf, HALL, log);
  const giveShift = new Function('mp', 'idOf', 'SHIFT', 'wearThese', 'log',
    SHIFT_FN + '\nreturn giveShift;')(mp, idOf, SHIFT, wearThese, log);
  const beginAppearance = new Function(
    'mp', 'Date', 'firstSeen', 'faceMark', 'HALL', 'sendToHall', 'setChargen', 'log', 'say', 'notify',
    APPEAR + '\nreturn beginAppearance;')(
    mp, FakeDate, firstSeen, faceMark, HALL, sendToHall, setChargen, log, say, notify);
  const beginChoosing = new Function(
    'Date', 'giveShift', 'setChargen', 'closeRaceMenu', 'openCreation', 'log', 'say', 'notify',
    'CHOOSE_REMIND_MS',
    CHOOSE + '\nreturn beginChoosing;')(
    FakeDate, giveShift, setChargen, closeRaceMenu, openCreation, log, say, notify, 30000);
  const arriveAt = new Function(
    'mp', 'Date', 'chargenOf', 'setChargen', 'closeRaceMenu', 'log', 'say', 'notify',
    'TOWN_BY_KEY', 'PASSAGES',
    ARRIVE + '\nreturn arriveAt;')(
    mp, FakeDate, chargenOf, setChargen, closeRaceMenu, log, say, notify, TOWN_BY_KEY, PASSAGES);

  // The branch uses continue, so it runs inside a do/while(false), which a
  // continue leaves the way the real loop leaves one person.
  const g = { __thornswoodSpoils: { GOLD: 0x0000000F } };
  const firstPass = new Function(
    'actorId', 'now', 'state', 'appearance', 'mp', 'globalThis', 'HALL', 'log', 'setChargen',
    'closeRaceMenu', 'beginAppearance', 'say', 'notify',
    'do {\n' + NEWBRANCH + '\n} while (false);');

  return {
    out: out, mp: mp, clock: clock, firstSeen: firstSeen,
    beginChoosing: beginChoosing, arriveAt: arriveAt, chargenOf: chargenOf,
    place: function (id, desc, pid, pack) {
      mp.set(id, 'worldOrCellDesc', desc);
      mp.set(id, 'profileId', pid);
      mp.set(id, 'inventory', { entries: pack || [] });
      firstSeen.set(id, clock.now);
    },
    // The first settled pass of chargenTick for somebody with no record.
    settle: function (id) {
      firstPass(id, clock.now, chargenOf(id), mp.get(id, 'appearance'), mp, g, HALL, log,
                setChargen, closeRaceMenu, beginAppearance, say, notify);
    },
    to: function (id) { return out.said.filter(function (s) { return s.id === id; }); }
  };
}

const EM = String.fromCharCode(0x2014);
function clean(line) {
  return !!line && line.text.length > 0 && !/player/i.test(line.text) &&
    line.text.indexOf(EM) < 0 && !/\n/.test(line.text);
}

// ------------------------------------------- a whole creation, start to inn
{
  const ME = 0xff000058;
  const w = world();
  w.place(ME, HALL.desc, 744947683, []);

  w.settle(ME);
  const st1 = w.chargenOf(ME);
  yes('a new person in the hall is put in the appearance stage', !!st1 && st1.stage === 'appearance');
  yes('1 entering the hall says one line to them', w.to(ME).length === 1);
  const l1 = w.to(ME)[0];
  yes('1 it welcomes them and names the creation hall',
      !!l1 && /Welcome to Thornswood/.test(l1.text) && /creation hall/.test(l1.text));
  yes('1 and the log line is still written beside it',
      w.out.logs.some(function (l) { return /-> appearance \(already in the hall\)/.test(l); }));

  w.clock.now += 60000;
  w.beginChoosing(ME, w.chargenOf(ME), 'the face arrived');
  const st2 = w.chargenOf(ME);
  yes('the face made, they are choosing', !!st2 && st2.stage === 'choosing');
  yes('2 moving to the choices says one more line, one only', w.to(ME).length === 2);
  const l2 = w.to(ME)[1];
  yes('2 it says the clothes were given, which is the pack changing under them',
      !!l2 && /plain clothes/.test(l2.text));
  yes('2 and what the town pick does, since the panel is already on the screen',
      !!l2 && /home town/.test(l2.text) && /\binn\b/.test(l2.text) && !/Press K/.test(l2.text));
  yes('2 the shift was really handed over (the log says so)',
      w.out.logs.some(function (l) { return /shift: 2 handed over/.test(l); }));
  yes('2 and the choosing log line is still written',
      w.out.logs.some(function (l) { return /-> choosing \(the face arrived\), panel opened/.test(l); }));

  w.clock.now += 60000;
  const sent = w.arriveAt(ME, 'riften');
  const st3 = w.chargenOf(ME);
  yes('picking Riften sends them and marks them done', sent === true && !!st3 && st3.stage === 'done');
  yes('3 the arrival says one more line', w.to(ME).length === 3);
  const l3 = w.to(ME)[2];
  yes('3 it names Riften and the inn', !!l3 && /Riften/.test(l3.text) && /\binn\b/.test(l3.text));

  yes('one line per step: three steps, three lines, all to this person',
      w.out.said.length === 3 && w.out.said.every(function (s) { return s.id === ME; }));
  yes('all through say, none through notify, which does nothing from here',
      w.out.notified.length === 0);
  yes('no two of the lines are the same',
      !!(l1 && l2 && l3) && l1.text !== l2.text && l2.text !== l3.text);
  yes('every line is plain: no player, no em dash, one line each',
      [l1, l2, l3].every(clean));
}

// ------------------------------------------- the teleport into the hall
{
  const ME = 0xff000059;
  const w = world();
  w.place(ME, HALL.desc, 11, []);
  // Standing somewhere that is not the hall when the stage opens: beginAppearance
  // is what moves them. The new-or-returning branch reads that as returning, so
  // this one drives beginAppearance through the branch's own hand-off: in the
  // hall for the decision, somewhere else by the time the stage opens.
  const realGet = w.mp.get;
  let calls = 0;
  w.mp.get = function (id, key) {
    if (key === 'worldOrCellDesc' && ++calls > 1) { return 'a5a5:Skyrim.esm'; }
    return realGet(id, key);
  };
  w.settle(ME);
  w.mp.get = realGet;
  const st = w.chargenOf(ME);
  yes('somebody not in the hall when the stage opens is moved there', !!st && st.moved === true &&
      (w.mp.get(ME, 'locationalData') || {}).cellOrWorldDesc === HALL.desc);
  yes('and is told once where they are going, not left with a silent load screen',
      w.to(ME).length === 1 && /going to the creation hall/.test(w.to(ME)[0].text));
  yes('that line is plain too', clean(w.to(ME)[0]));
}

// ------------------------------------------- the panel that did not open
{
  const ME = 0xff00005a;
  const w = world({ panel: false });
  w.place(ME, HALL.desc, 12, []);
  w.settle(ME);
  w.beginChoosing(ME, w.chargenOf(ME), 'the race menu closed');
  const lines = w.to(ME);
  yes('with the panel not open, the step still says exactly one line', lines.length === 2);
  yes('it says the clothes were given and how to open the panel',
      !!lines[1] && /plain clothes/.test(lines[1].text) && /Press K/.test(lines[1].text));
  yes('and does not welcome them a second time', !!lines[1] && !/Welcome/.test(lines[1].text));
  yes('that line is plain too', clean(lines[1]));
}

// ------------------------------------------- somebody who has played before
{
  const ME = 0xff00005b;
  const w = world();
  // A pack with a tunic in it, standing in Whiterun.
  w.place(ME, '1605e:Skyrim.esm', 13, [{ baseId: 0x12345, count: 1 }]);
  w.settle(ME);
  const st = w.chargenOf(ME);
  yes('a returning character is stamped done and not put through creation',
      !!st && st.stage === 'done' && st.legacy === true);
  yes('they are told once, and welcomed back rather than welcomed',
      w.to(ME).length === 1 && /Welcome back/.test(w.to(ME)[0].text));
  yes('the log still says why creation was skipped',
      w.out.logs.some(function (l) { return /creation is skipped for them/.test(l); }));
  yes('that line is plain too', clean(w.to(ME)[0]));

  // Gold on its own is no proof of having played, and the hall means new.
  const NEW = 0xff00005c;
  w.place(NEW, HALL.desc, 14, [{ baseId: 0x0000000F, count: 40 }]);
  w.settle(NEW);
  yes('a new one holding only the starting purse is still new, and welcomed, not welcomed back',
      w.to(NEW).length === 1 && !/Welcome back/.test(w.to(NEW)[0].text) &&
      (w.chargenOf(NEW) || {}).stage === 'appearance');
}

// ------------------------------------------- once, and only when it moves
{
  const ME = 0xff00005d;
  const w = world();
  w.place(ME, HALL.desc, 15, []);
  w.settle(ME);
  w.beginChoosing(ME, w.chargenOf(ME), 'the face arrived');
  w.arriveAt(ME, 'whiterun');
  const before = w.to(ME).length;
  w.settle(ME);
  w.arriveAt(ME, 'whiterun');
  w.arriveAt(ME, 'nowhere');
  yes('a finished character is not narrated again by a second pass or a second pick',
      w.to(ME).length === before && before === 3);
}

done();
