// test-load-order-refusal.js
//
// A mismatched session is told where its load order parts from the server's,
// in one sentence, and is refused when the server is set to refuse (#402).
//
// The game's own check paints LOAD ORDER ERROR in red and carries on. On
// 17 Sep a tester's screenshot of the mining bug had that caption on it, so he
// was reporting bugs from a session where every custom object could resolve to
// something else, and nothing on screen told him to stop and press Fix.
//
// This lifts the load order refusal block out of gamemode.js and runs it over
// a pretend server: a fake mp, a manifest the shape the live one has, and the
// lines the front plugin would send, built with the front plugin's own copy of
// loadOrderMark. An altered list must come back as a refusal, not a caption.
//
// GAMEMODE=<path> runs it against another copy.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const CR = String.fromCharCode(13);
const GM = process.env.GAMEMODE || path.join(TOOLS_DIR, '..', 'game', 'gamemode.js');
const FRONT = path.join(TOOLS_DIR, '..', 'game', 'plugins', 'thornswood-front.js');
const VERIFY = path.join(TOOLS_DIR, '..', 'launcher', 'app', 'Verify.cs');
const VOICE = path.join(TOOLS_DIR, '..', 'voice', 'voice-server.js');
const src = fs.readFileSync(GM, 'utf8').split(CR).join('');
const front = fs.readFileSync(FRONT, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* The function from its first line to the closing brace at its own indent. */
function lift(text, name) {
  const a = text.indexOf('  function ' + name + '(');
  if (a < 0) { return null; }
  const b = text.indexOf('\n  }\n', a);
  return b < 0 ? null : text.slice(a, b + 4);
}

// ------------------------------------------------ the two copies of the mark

const gmMarkText = lift(src, 'loadOrderMark');
const frontMarkText = lift(front, 'loadOrderMark');
yes('the gamemode has loadOrderMark', !!gmMarkText);
yes('the front plugin has loadOrderMark', !!frontMarkText);
yes('and the two are the same function, letter for letter', !!gmMarkText && gmMarkText === frontMarkText);

const mark = frontMarkText ? new Function(frontMarkText + '\nreturn loadOrderMark;')() : function () { return ''; };
yes('a mark is five hex', /^[0-9a-f]{5}$/.test(mark('Skyrim.esm', 249753412, 616253901)));
yes('the name is read without case, as the game reads it',
    mark('JKs Skyrim.esp', 10, -5) === mark('jks skyrim.esp', 10, -5));
yes('a signed crc32 and its unsigned twin are the same mark',
    mark('Update.esm', 18874041, -423982917) === mark('Update.esm', 18874041, -423982917 >>> 0));
yes('other bytes are another mark', mark('Riften Expansion.esp', 100, 7) !== mark('Riften Expansion.esp', 100, 8));
yes('and so is the name alone', mark('Riften Expansion.esp') !== mark('Riften Expansion.esp', 100, 7));

// ------------------------------------------------ the front plugin's half

{
  const verify = fs.readFileSync(VERIFY, 'utf8');
  const m = /Storefront = new HashSet<string>\([^)]*\)\s*\{([\s\S]*?)\};/.exec(verify);
  const launcher = m ? (m[1].match(/"([^"]+)"/g) || []).map(function (s) { return s.slice(1, -1).toLowerCase(); }).sort() : [];
  const f = /const LOAD_ORDER_STOREFRONT = (\[[\s\S]*?\]);/.exec(front);
  const plugin = f ? new Function('return ' + f[1])().map(function (s) { return s.toLowerCase(); }).sort() : [];
  yes('Verify.cs still names the files Steam owns', launcher.length === 10);
  yes('the front marks by name alone exactly the files Verify.cs leaves out of its byte check',
      launcher.length > 0 && JSON.stringify(launcher) === JSON.stringify(plugin));

  yes('the front sends the list as /loadorder <total> <from> <marks>',
      /tellServer\('\/loadorder ' \+ total \+ ' ' \+ from \+ ' ' \+/.test(front));
  yes('it reads each plugin with getFileInfo, one a frame', /sp\.getFileInfo\(name\)/.test(front) &&
      /orderMarks\.push\(mark\);\s*return;/.test(front));
  yes('the list it sends is the one it wrote to thornswood-loadorder.txt',
      /names\.join\('\\n'\) \+ '\\n'\);\s*orderToReport = names\.slice\(\);/.test(front));

  const chunk = /const LOAD_ORDER_CHUNK = (\d+);/.exec(front);
  const n = chunk ? Number(chunk[1]) : 0;
  const voice = fs.readFileSync(VOICE, 'utf8');
  const cap = /msg\.text == null \? '' : msg\.text\)\.slice\(0, (\d+)\)/.exec(voice);
  const longest = '/loadorder 4096 4032 ' + new Array(n + 1).join('fffff');
  yes('a full line fits under the voice service\u2019s chat cap (' + longest.length + ' of ' +
      (cap ? cap[1] : '?') + ')', n > 0 && !!cap && longest.length < Number(cap[1]));
}

// ------------------------------------------------ the gamemode's half

const a = src.indexOf('// ==== thornswood load order refusal ====');
const b = src.indexOf('// ==== end thornswood load order refusal ====');
yes('the refusal block is in the gamemode', a >= 0 && b > a);

{
  const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  const words = /^const WORDS = (\[[\s\S]*?\]);$/m.exec(src);
  const player = /^const PLAYER_WORDS = (\[[\s\S]*?\]);$/m.exec(src);
  const W = words ? new Function('return ' + words[1])() : [];
  const P = player ? new Function('return ' + player[1])() : [];
  yes('/loadorder is a word the server answers', W.indexOf('/loadorder') >= 0);
  yes('and /help never offers it to anybody', P.indexOf('/loadorder') < 0);
  yes('handle() hands it to the refusal block with the character',
      /word === '\/loadorder'[\s\S]{0,400}lo\.take\(profileId, parts, actorId,/.test(code));
  yes('a held report never says "your character is not back" to somebody who typed nothing',
      /word !== '\/loadorder'/.test(code));
  yes('the manifest block keeps the published list for it',
      /globalThis\.__thornswoodManifestMods = mods;/.test(code));
}

const NAMES = ['Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm',
               'Water for ENB.esm', 'Embers XD.esm', 'RaceCompatibility.esm',
               'Immersive Sounds - Compendium.esp', 'IcePenguinWorldMap.esp', 'JKs Skyrim.esp',
               'WindhelmSSE.esp', 'CWE - JK - United.esp', "JK's Whiterun's Outskirts.esp",
               'Riften Expansion.esp', 'Thornswood-Content.esp', 'Playable Rieklings.esp'];
const STOREFRONT = ['skyrim.esm', 'update.esm', 'dawnguard.esm', 'hearthfires.esm', 'dragonborn.esm'];

function manifest(count) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const name = i < NAMES.length ? NAMES[i] : ('Filler ' + i + '.esp');
    out.push({ filename: name, size: 1000 + i * 37, crc32: ((i * 2654435761) | 0) });
  }
  return out;
}

/* What the front plugin would send for this list: the same marks, the same lines. */
function linesFor(list) {
  const marks = list.map(function (m) {
    return STOREFRONT.indexOf(m.filename.toLowerCase()) >= 0 ? mark(m.filename) : mark(m.filename, m.size, m.crc32);
  });
  const out = [];
  for (let from = 0; from < marks.length; from += 64) {
    out.push('/loadorder ' + marks.length + ' ' + from + ' ' + marks.slice(from, from + 64).join(''));
  }
  return out;
}

function rig(settings, mods) {
  const r = { told: [], logged: [], kicked: [], timers: [] };
  const box = {
    console: { log: function () { r.logged.push(Array.prototype.join.call(arguments, ' ')); } },
    Date: Date, Math: Math, Number: Number, String: String, Array: Array, Object: Object,
    setTimeout: function (fn) { r.timers.push(fn); return r.timers.length; },
    mp: {
      getServerSettings: function () { return settings; },
      getUserByActor: function (actorId) { return actorId === 0xff000a01 ? 7 : -1; },
      kick: function (userId) { r.kicked.push(userId); }
    }
  };
  vm.createContext(box);
  vm.runInContext(src.slice(a, b), box, { filename: 'gamemode.js (load order refusal)' });
  box.__thornswoodManifestMods = mods;
  r.lo = box.__thornswoodLoadOrder;
  r.send = function (profileId, lines) {
    let last;
    lines.forEach(function (line) {
      last = r.lo.take(profileId, line.split(/\s+/), 0xff000a01, function (t) { r.told.push(t); });
    });
    return last;
  };
  r.fire = function () { const t = r.timers.splice(0); t.forEach(function (fn) { fn(); }); };
  return r;
}

if (a >= 0 && b > a) {
  const mods = manifest(48);

  {
    const r = rig({}, mods);
    yes('the block publishes take, verdict and mark', !!(r.lo && r.lo.take && r.lo.verdict && r.lo.mark));
    const v = r.send(1, linesFor(mods));
    yes('a list that matches the server\u2019s is passed', v === null);
    yes('and nothing is said to that person', r.told.length === 0);
    r.fire();
    yes('and nobody is disconnected', r.kicked.length === 0);
  }

  {
    const r = rig({}, mods);
    const extra = mods.concat([{ filename: 'SkyHUD.esp', size: 5, crc32: 5 }]);
    yes('plugins after the server\u2019s last are left alone, as the game leaves them',
        r.send(2, linesFor(extra)) === null && r.told.length === 0);
  }

  // The altered lists. Each must be a refusal, not a caption.
  const altered = [
    ['two plugins swapped', function (l) { const t = l[9]; l[9] = l[10]; l[10] = t; return l; }, 9],
    ['one plugin with other bytes under the same name',
      function (l) { l[14] = { filename: l[14].filename, size: l[14].size, crc32: l[14].crc32 + 1 }; return l; }, 14],
    ['a plugin missing from the middle', function (l) { l.splice(12, 1); return l; }, 12],
    ['the list cut short', function (l) { return l.slice(0, 30); }, 30]
  ];
  altered.forEach(function (c) {
    const r = rig({}, mods);
    const list = c[1](mods.map(function (m) { return Object.assign({}, m); }));
    const v = r.send(3, linesFor(list));
    yes(c[0] + ': refused at position ' + c[2], !!v && v.at === c[2] && v.theirs === mods[c[2]].filename);
    yes(c[0] + ': told in one sentence naming the position and the plugin',
        r.told.length === 1 && r.told[0].indexOf('position ' + c[2]) >= 0 &&
        r.told[0].indexOf(mods[c[2]].filename) >= 0 && /press Fix in the launcher, then Play again\.$/.test(r.told[0]));
    r.fire();
    yes(c[0] + ': while the server is only watching, they stay and the log says WOULD REFUSE',
        r.kicked.length === 0 && r.logged.some(function (s) { return /WOULD REFUSE profile 3/.test(s); }));
  });

  {
    const r = rig({ thornswoodLoadOrderRefuse: true }, mods);
    const list = mods.map(function (m) { return Object.assign({}, m); });
    list[20] = { filename: list[20].filename, size: list[20].size + 1, crc32: list[20].crc32 };
    const v = r.send(4, linesFor(list));
    yes('with thornswoodLoadOrderRefuse on, an altered list is refused', !!v && v.at === 20);
    yes('the sentence says the session is ending', r.told.length === 1 && /this session is being ended/.test(r.told[0]));
    yes('the connection is not cut before the sentence has had time to land', r.kicked.length === 0);
    r.fire();
    yes('and then the session is ended', r.kicked.length === 1 && r.kicked[0] === 7);
  }

  {
    const r = rig({ thornswoodLoadOrderRefuse: 'yes' }, mods);
    const list = mods.slice(0, 10);
    r.send(5, linesFor(list));
    r.fire();
    yes('only true turns refusing on; any other value watches', r.kicked.length === 0);
  }

  {
    const r = rig({ thornswoodLoadOrderRefuse: true }, mods);
    const list = mods.map(function (m) { return Object.assign({}, m); });
    list[0] = { filename: 'Skyrim.esm', size: 1, crc32: 1 };
    yes('the files Steam owns pass by name, since Fix cannot mend them',
        r.send(6, linesFor(list)) === null && r.told.length === 0);
    const unread = linesFor(mods);
    const marks = unread[0].split(' ')[3];
    const at = 15 * 5;
    const nameOnly = marks.slice(0, at) + mark(mods[15].filename) + marks.slice(at + 5);
    yes('a plugin the client could not read passes by name',
        r.send(6, ['/loadorder 48 0 ' + nameOnly]) === null && r.told.length === 0);
  }

  {
    const big = manifest(150);
    const r = rig({}, big);
    const lines = linesFor(big);
    yes('a long list goes as several lines', lines.length === 3);
    yes('the first lines judge nothing', r.lo.take(7, lines[0].split(' '), 1, function () { }) === undefined &&
        r.lo.take(7, lines[1].split(' '), 1, function () { }) === undefined);
    yes('the last one judges the whole list', r.lo.take(7, lines[2].split(' '), 1, function () { }) === null);

    const r2 = rig({}, big);
    r2.lo.take(8, lines[0].split(' '), 1, function () { });
    yes('a line out of order is dropped rather than judged',
        r2.lo.take(8, lines[2].split(' '), 1, function (t) { r2.told.push(t); }) === undefined &&
        r2.told.length === 0);
  }

  {
    const r = rig({}, undefined);
    yes('with no manifest published nothing is judged and nobody is told',
        r.send(9, linesFor(mods.slice(0, 3))) === undefined && r.told.length === 0);
  }

  {
    const r = rig({}, mods);
    const s = [r.lo.sentence({ at: 3, theirs: 'X.esp' }, false), r.lo.sentence({ at: 3, theirs: 'X.esp' }, true)];
    s.forEach(function (t, i) {
      yes('the ' + (i ? 'refusing' : 'watching') + ' sentence is one sentence, with no em dash and no "player"',
          t.split('. ').length === 1 && t.indexOf('\u2014') < 0 && !/player/i.test(t));
    });
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
