// test-thornswood-keys.js
//
// Thornswood's own keys, held together: the shipped Thornswood.ini, the
// launcher's Controls rows and the plugins' defaults say the same thing, no
// two of them share a key, and every Controls row can be written.
//
// FOUND 24 September by the review of pull request 287 (#529). The template
// put the emote wheel on G, which is also the friend key, while the emote
// plugin and Keys.cs defaulted the wheel to B, which is also the voice mode
// key. PartyKey, JournalKey, FriendKey, TradeWithKey and MuteThemKey were
// not in the template, and Keys.WriteIni only rewrote a line already in the
// file, so those rows failed with "Could not write Thornswood.ini" on every
// install. MoldKey had no Controls row, so the clash check did not know U
// was taken.
//
// Read only.
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
function read(...bits) { return fs.readFileSync(path.join(ROOT, ...bits), 'utf8').split(CR).join(''); }

const ini = read('launcher', 'Thornswood.ini');
const keysCs = read('launcher', 'app', 'Keys.cs');
const front = read('game', 'plugins', 'thornswood-front.js');
const emotes = read('game', 'plugins', 'thornswood-emotes.js');
const voice = read('game', 'plugins', 'thornswood-voice.js');
const mark = read('game', 'plugins', 'thornswood-mark.js');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// Not keys: a port, a switch and a number of seconds.
const NOT_KEYS = ['VoicePort', 'Microphone', 'ChatFade', 'NeedsBars', 'Fov'];

const template = {};
{
  const rx = /^\s*(\w+)\s*=\s*(\d+)\s*$/gm;
  let m;
  while ((m = rx.exec(ini)) !== null) {
    if (NOT_KEYS.indexOf(m[1]) === -1) { template[m[1]] = Number(m[2]); }
  }
}

const rows = {};
{
  const rx = /ThornIni, "(\w+)", (-?\d+)\)/g;
  let m;
  while ((m = rx.exec(keysCs)) !== null) { rows[m[1]] = Number(m[2]); }
}

const plugins = {};
function plugin(name, code, who) { (plugins[name] = plugins[name] || []).push({ code: code, who: who }); }
{
  let m;
  const rxFront = /iniNumber\(ini, '(\w+)', (\d+)\)/g;
  while ((m = rxFront.exec(front)) !== null) {
    if (NOT_KEYS.indexOf(m[1]) === -1) { plugin(m[1], Number(m[2]), 'front'); }
  }
  const rxEm = /key\('(\w+)', (\d+)\)/g;
  while ((m = rxEm.exec(emotes)) !== null) { plugin(m[1], Number(m[2]), 'emotes'); }
  const vars = {};
  const rxVar = /^let (\w+_KEY) = (\d+);/gm;
  while ((m = rxVar.exec(voice)) !== null) { vars[m[1]] = Number(m[2]); }
  const rxGrab = /(\w+_KEY) = grab\('(\w+)', \1\)/g;
  while ((m = rxGrab.exec(voice)) !== null) { plugin(m[2], vars[m[1]], 'voice'); }
  const mk = /^let markKey = (\d+);/m.exec(mark);
  if (mk) { plugin('MarkKey', Number(mk[1]), 'mark'); }
}

yes('the template, the Controls rows and the plugins were all read (' +
    Object.keys(template).length + ' keys, ' + Object.keys(rows).length + ' rows, ' +
    Object.keys(plugins).length + ' plugin keys)',
    Object.keys(template).length >= 15 && Object.keys(rows).length >= 15 && Object.keys(plugins).length >= 15);

// Every Controls row is in the template, at the same value.
Object.keys(rows).forEach(function (k) {
  yes('Controls row ' + k + ' is in the template, at ' + rows[k],
      Object.prototype.hasOwnProperty.call(template, k) && template[k] === rows[k]);
});

// Every key a plugin reads is in the template, at the same value.
Object.keys(plugins).forEach(function (k) {
  plugins[k].forEach(function (p) {
    yes(p.who + ' reads ' + k + ' with the template\'s value, ' + p.code,
        Object.prototype.hasOwnProperty.call(template, k) && template[k] === p.code);
  });
});

// And nothing in the template is read by nobody. MenuKey was, until #831.
const UNREAD_KNOWN = [];
Object.keys(template).forEach(function (k) {
  if (UNREAD_KNOWN.indexOf(k) !== -1) { return; }
  yes('the template\'s ' + k + ' is read by a plugin',
      Object.prototype.hasOwnProperty.call(plugins, k) || new RegExp("['\"]" + k + "['\"]|\\b" + k + '\\s*=').test(front + emotes + voice + mark));
});

// No two keys on one code.
{
  const by = {};
  Object.keys(template).forEach(function (k) { (by[template[k]] = by[template[k]] || []).push(k); });
  const shared = Object.keys(by).filter(function (c) { return by[c].length > 1; })
    .map(function (c) { return c + ': ' + by[c].join(' and '); });
  yes('no two of our keys share a default' + (shared.length ? ' (' + shared.join('; ') + ')' : ''), shared.length === 0);
}

yes('the key mold has a Controls row, so the clash check knows U is taken', rows.MoldKey === 22);
yes('the lock key has a Controls row, so the clash check knows X is taken', rows.LockKey === 45);
yes('the emote wheel is G everywhere', template.WheelKey === 34 && rows.WheelKey === 34);
yes('and the friend key is not', template.FriendKey !== 34);
yes('no row writes MuteKey, which nothing reads', !Object.prototype.hasOwnProperty.call(rows, 'MuteKey'));

// A row for a key an older install's file does not have yet still writes.
{
  const a = keysCs.indexOf('static bool WriteIni(string file, string key, string value)');
  const b = keysCs.indexOf('\n        }\n', a);
  const body = a >= 0 && b > a ? keysCs.slice(a, b) : '';
  yes('WriteIni adds a missing key to Thornswood.ini',
      /Path\.GetFullPath\(ThornIni\)/.test(body) && /lines\.Add\(key \+ " = " \+ value\)/.test(body));
  yes('and only there: another mod\'s file is never added to',
      /if \(!string\.Equals\(Path\.GetFullPath\(file\), Path\.GetFullPath\(ThornIni\)[^)]*\)\)\s*return false;/.test(body));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
