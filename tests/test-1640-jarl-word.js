// test-1640-jarl-word.js
//
// #1640. /jarl never reached the office. handle() in the chat block hands a
// word to the character block's command, and that hands the property words on
// to the property block from a fixed list. /jarl was answered by the property
// block (jarlCmd) and missing from that list, so it fell through to "No
// command called /jarl". tests/test-offices.js calls jarlCmd directly and
// never saw the route.
//
// This drives the route itself: the character block's command, sliced out of
// the gamemode, hands the word to the property block's command, also sliced,
// which calls the real jarlCmd. And it holds the two lists together, so a word
// the property block answers can never again be left off the list that
// reaches it.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const SRC = process.env.GM || path.join(REPO_DIR, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function slice(src, start, end) {
  if (src === null) { return null; }
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}

const HEAD = '  function command(word, parts, actorId, profileId, toProfile) {';
const propBlock = slice(gm, '// ==== thornswood property ====', '// ==== end thornswood property ====');
const charBlock = slice(gm, '// ==== thornswood character ====', '// ==== end thornswood character ====');
const propCommand = slice(propBlock, HEAD, '\n  }\n');
const charCommand = slice(charBlock, HEAD, '\n  }\n');
const jarlSrc = slice(propBlock, '  function jarlCmd(parts, actorId, profileId, toProfile) {', '\n  }\n');
// The Jarl office is of one hold (#502): jarlCmd reads the hold through these.
// And one Jarl a hold: the seat is in the law register (a fresh one here).
const holdSrc = slice(propBlock, '  var HOLD_TOWN = {', '};') + '\n' +
                slice(propBlock, '  function seatOf(hold) {', '\n  }\n') + '\n' +
                slice(propBlock, '  function seatHeldBy(actorId) {', '\n  }\n') + '\n' +
                slice(propBlock, '  function officeHoldOf(s, actorId) {', '\n  }\n') + '\n' +
                'var law = { guards: {}, cells: {}, jarls: {} };\n' +
                'function saveLaw() { }\nfunction personName() { return "Somebody"; }\n' +
                'function giveUpJarl() { return true; }\n';
yes('the property block\'s command is in the gamemode', propCommand !== null);
yes('the character block\'s command is in the gamemode', charCommand !== null);
yes('jarlCmd is in the property block', jarlSrc !== null);

const JARL = 1, ADMIN = 2, NOBODY = 3;
const ACTOR = 0xff000101, OTHER = 0xff000102;

/*
  One world: the property block (its command and the real jarlCmd, every other
  word a stub that records itself), and the character block's command with
  g.__thornswoodProperty pointing at it. Returns send(word, actorId, profileId).
*/
function world(opts) {
  const states = {};
  states[ACTOR] = { office: null };
  states[OTHER] = { office: null };
  const writes = [];
  const stubbed = [];
  const pbox = {
    plog: function () { },
    __thornswoodIsAdmin: function (pid) { return pid === ADMIN; },
    __thornswoodIsJarl: function (pid) { return pid === JARL; },
    __thornswoodCharacter: {
      stateOf: function (aid) { return states[aid] || null; },
      writeState: function (aid, s) { writes.push(aid); states[aid] = s; }
    },
    here: function () { return opts && opts.atDoor ? 'breezehome' : null; }
  };
  pbox.g = pbox;
  ['deeds', 'setLock', 'mold', 'moldHere', 'cutKey', 'claim', 'stewardCmd', 'guardCmd', 'evict',
   'boxCmd', 'rentCmd', 'sleepHere', 'post', 'board', 'take', 'jobs', 'dropJob',
   'unpin', 'postLetter', 'deliver', 'haulCmd'].forEach(function (n) {
    pbox[n] = function () { stubbed.push(n); return true; };
  });
  vm.runInNewContext(holdSrc + '\n' + propCommand + '\n' + jarlSrc + '\nthis.cmd = command;', pbox);

  const logs = [];
  const cbox = {
    clog: function () { logs.push(Array.prototype.join.call(arguments, ' ')); },
    g: { __thornswoodProperty: { command: pbox.cmd } }
  };
  vm.runInNewContext(charCommand + '\nthis.cmd = command;', cbox);

  return {
    states: states, writes: writes, stubbed: stubbed, logs: logs,
    send: function (word, actorId, profileId) {
      const told = [];
      const parts = word.split(' ');
      const r = cbox.cmd(parts[0], parts, actorId, profileId, function (pid, m) { told.push(m); });
      return { answered: r, told: told };
    }
  };
}

if (propCommand && charCommand && jarlSrc) {
  {
    const w = world();
    const r = w.send('/jarl whiterun', ACTOR, JARL);
    yes('J1 /jarl sent to the character block is answered there, not left for the unknown command reply',
        r.answered === true);
    yes('J1 and a character on a Jarl-role account holds the office',
        w.states[ACTOR].office === 'jarl' && w.writes.length === 1 && w.writes[0] === ACTOR);
    yes('J1 and is told so, with its hold (#502)', r.told.length === 1 &&
        r.told[0] === 'This character holds the Jarl office of Whiterun now. You name its guards on the Office page.' &&
        w.states[ACTOR].officeHold === 'whiterun');
    yes('J1 and no other property word ran', w.stubbed.length === 0);
  }
  {
    const w = world();
    const r = w.send('/jarl riften', ACTOR, ADMIN);
    yes('J2 an admin without the role seats the office too',
        r.answered === true && w.states[ACTOR].office === 'jarl');
  }
  {
    const w = world();
    const r = w.send('/jarl riften', ACTOR, NOBODY);
    yes('J3 an account with neither is refused and the character is untouched',
        r.answered === true && w.states[ACTOR].office === null && w.writes.length === 0);
    yes('J3 and is told who may', r.told[0] === 'Only someone with the Jarl role (or an admin) can take the office.');
  }
  {
    const w = world();
    w.send('/jarl whiterun', ACTOR, JARL);
    const again = w.send('/jarl riften', ACTOR, JARL);
    yes('J4 sending it again does not write twice, nor move the hold',
        w.writes.length === 1 && again.told[0] === 'This character already holds the Jarl office of Whiterun.' &&
        w.states[ACTOR].officeHold === 'whiterun');
    yes('J4 and the other character on the account stays ordinary',
        w.states[OTHER].office === null);
  }
  {
    const w = world();
    const r = w.send('/jarl', 0, JARL);
    yes('J5 with no character found it says so, the same as every property word',
        r.answered === true && w.writes.length === 0 &&
        r.told[0].indexOf('cannot find your character') !== -1);
  }
  {
    const w = world();
    const r = w.send('/steward', ACTOR, JARL);
    yes('J6 the words that already reached the property block still do',
        r.answered === true && w.stubbed.join() === 'stewardCmd');
  }
}

// The cause: two lists that must agree. Every word the property block's
// command answers is on the character block's list that hands words to it.
{
  const strip = function (s) {
    return s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
  };
  const words = function (s) {
    const out = [];
    const re = /word === '(\/[a-z-]+)'/g;
    let m;
    while ((m = re.exec(s)) !== null) { if (out.indexOf(m[1]) === -1) { out.push(m[1]); } }
    return out;
  };
  const answered = propCommand ? words(strip(propCommand)) : [];
  const handOn = charCommand ? strip(charCommand) : '';
  const listEnd = handOn.indexOf('var prop = g.__thornswoodProperty');
  const handed = listEnd > 0 ? words(handOn.slice(0, listEnd)) : [];
  const missing = answered.filter(function (w) { return handed.indexOf(w) === -1; });
  yes('J7 the property block answers /jarl', answered.indexOf('/jarl') !== -1);
  yes('J7 every word the property block answers is on the list that reaches it' +
      (missing.length ? ' (missing: ' + missing.join(', ') + ')' : ''),
      answered.length > 10 && missing.length === 0);

  // The trap: the fix is the route, not a second handler somewhere else.
  const code = strip(gm);
  const seen = code.match(/word === '\/jarl'/g) || [];
  yes('J8 /jarl is matched in exactly two places, the hand-on list and the property block',
      seen.length === 2);
  const handle = code.indexOf('charCmd.command(word, parts, actorId, profileId, toProfile)');
  const unknown = code.indexOf("'No command called ' + word");
  yes('J9 handle() asks the character block before it answers "No command called"',
      handle > 0 && unknown > handle);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
