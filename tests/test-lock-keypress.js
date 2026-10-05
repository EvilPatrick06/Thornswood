// test-lock-keypress.js
//
// #615 leftovers: /lock is a key press logged as /lock, and after a lock
// everybody online hears that the building is locked.
//
// Since #1637 the same key claims, locks or unlocks the door just opened, as
// its line says, and cuts a key at a forge; it sends the word and the id
// under the crosshair. tests/test-1637-door-gui.js drives that whole path.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
const read = function (p) { return fs.readFileSync(p, 'utf8').split(CR).join(''); };

const FRONT = read(path.join(REPO_DIR, 'game', 'plugins', 'thornswood-front.js'));
const GM = read(path.join(REPO_DIR, 'game', 'gamemode.js'));
const INI = read(path.join(REPO_DIR, 'launcher', 'Thornswood.ini'));
const KEYS = read(path.join(REPO_DIR, 'launcher', 'app', 'Keys.cs'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

yes('Thornswood.ini has LockKey = 45', /^\s*LockKey\s*=\s*45\s*$/m.test(INI));
yes('Keys.cs has a Controls row for LockKey at 45', /ThornIni, "LockKey", 45\)/.test(KEYS));
yes('front reads LockKey with default 45', /iniNumber\(ini, 'LockKey', 45\)/.test(FRONT));
yes('front has lockPress', /function lockPress\(\)/.test(FRONT));
yes('lockPress tells the server the line\'s word and the id under the crosshair',
    /tellServer\('\/' \+ sig\)/.test(FRONT) && /const sig = now\.verb \+ ' ' \+ now\.hex;/.test(FRONT));
yes('the key handler runs lockPress for LOCK_KEY', /e\.code === LOCK_KEY && lockPress\(\)/.test(FRONT));

const setAt = GM.indexOf('function setLock(actorId, profileId, toProfile, on)');
const setBody = setAt >= 0 ? GM.slice(setAt, setAt + 2200) : '';
yes('setLock is in the gamemode', setAt >= 0);
yes('setLock still tells the locker You lock / You unlock',
    /toProfile\(profileId, 'You ' \+ \(on \? 'lock' : 'unlock'\)/.test(setBody));
yes('setLock tells every other online profile the building is locked or unlocked',
    /is ' \+ \(on \? 'locked' : 'unlocked'\)/.test(setBody) &&
    /onlinePlayers/.test(setBody) &&
    /opid === profileId/.test(setBody));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);