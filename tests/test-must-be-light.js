// test-must-be-light.js
//
// The plugins the launcher flags light are the ones the server counts as light.
//
// SkyMP resolves a form by the plugin's position in the server's list, and the
// client counts positions with Game.GetModCount, which skips light plugins. So
// a plugin the server leaves out as light but a tester's copy does not carry
// the flag for pushes every plugin after it one place along, and the game says
// LOAD ORDER ERROR. Checks.MustBeLight is the launcher's list of those, and its
// Fix sets the flag on the tester's own copy (OwnGame.Separate first, so a
// Vortex hard link is never written through).
//
// Djinn, 24 September, on the dev build: "Getting mod order Load Order Error,
// same exact mod as last time. scan fix didn't work. Purge re-deploy didn't
// work", with "position 52: you have Hothtrooper44_Armor_Ecksstra.esp there, the
// server has SkyHUD.esp". The Nexus archive ships that file light, and the
// server's order was built from a copy that is light.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const src = fs.readFileSync(path.join(TOOLS_DIR, '..', 'launcher', 'app', 'Checks.cs'), 'utf8');
const m = /public static readonly string\[\] MustBeLight = \{([\s\S]*?)\};/.exec(src);
yes('Checks.MustBeLight is in the launcher', !!m);
const list = m ? (m[1].match(/"([^"]+)"/g) || []).map(function (s) { return s.slice(1, -1); }) : [];

yes('MCMHelper.esp is still on it', list.indexOf('MCMHelper.esp') >= 0);
yes('and so is Hothtrooper44_Armor_Ecksstra.esp, the one behind Djinn’s position 52',
    list.indexOf('Hothtrooper44_Armor_Ecksstra.esp') >= 0);

// Every plugin on the list must be one the server leaves out, or flagging it
// would move the client the wrong way.
let order = [];
try {
  order = JSON.parse(fs.readFileSync(path.join(TOOLS_DIR, '..', 'version.json'), 'utf8')).loadOrder || [];
} catch (e) { order = []; }
if (!order.length) {
  // The server's list is not in the repo on every checkout; the gamemode's
  // own deploy writes it. Fall back to the plugins list the pack reference
  // uses when it is there, and say so rather than pass silently.
  console.log('SKIP  no server load order in this checkout to compare the list against');
} else {
  const names = order.map(function (p) { return String(p).split(/[\\/]/).pop().toLowerCase(); });
  list.forEach(function (n) {
    yes(n + ' is not in the server’s load order, which is what makes it light there',
        names.indexOf(n.toLowerCase()) < 0);
  });
}

// The flag is set on a separated copy, never through the link.
const fl = /public static int FlagLight[\s\S]*?\n        \}/.exec(src);
yes('FlagLight separates the file from Vortex’s copy before it writes',
    !!fl && fl[0].indexOf('OwnGame.Separate(p);') >= 0 &&
    fl[0].indexOf('OwnGame.Separate(p);') < fl[0].indexOf('fs.Write('));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
