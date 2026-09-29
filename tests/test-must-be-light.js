// test-must-be-light.js
//
// The plugins the launcher flags light are the ones the server counts as light.
//
// SkyMP resolves a form by the plugin's position in the server's list, and the
// client counts positions with Game.GetModCount, which skips light plugins. So
// a plugin the server leaves out as light but a tester's copy does not carry
// the flag for pushes every plugin after it one place along, and the game says
// LOAD ORDER ERROR.
//
// Djinn, 24 September, on the dev build: "Getting mod order Load Order Error,
// same exact mod as last time. scan fix didn't work. Purge re-deploy didn't
// work", with "position 52: you have Hothtrooper44_Armor_Ecksstra.esp there, the
// server has SkyHUD.esp". The Nexus archive ships that file light, and the
// server's order was built from a copy that is light.
//
// Issue #388's hardening: the set is no longer only a hand-maintained array.
// Verify.MustBeLight DERIVES it from the server, so the next plugin that ships
// light on the server but not on a tester's disk is caught without editing
// Checks: any plugin the collection reference (Paths.Golden) enables that the
// server leaves out of its manifest must be light here too. The hand list in
// Checks.MustBeLight stays as the fallback for when the server cannot be asked.
// This harness fails on the old hand-list-only behaviour and passes on the new.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const appDir = path.join(REPO_DIR, 'launcher', 'app');
const checks = fs.readFileSync(path.join(appDir, 'Checks.cs'), 'utf8');
const verify = fs.readFileSync(path.join(appDir, 'Verify.cs'), 'utf8');

// The hand list is still there and still carries the two names found by hand,
// because it is the fallback for when the server cannot be asked.
const m = /public static readonly string\[\] MustBeLight = \{([\s\S]*?)\};/.exec(checks);
yes('Checks.MustBeLight is still in the launcher, as the fallback', !!m);
const list = m ? (m[1].match(/"([^"]+)"/g) || []).map(function (s) { return s.slice(1, -1); }) : [];
yes('MCMHelper.esp is still on the fallback list', list.indexOf('MCMHelper.esp') >= 0);
yes('and so is Hothtrooper44_Armor_Ecksstra.esp, the one behind Djinn\u2019s position 52',
    list.indexOf('Hothtrooper44_Armor_Ecksstra.esp') >= 0);

// The new behaviour: Verify.MustBeLight derives the set from the server. This
// is what the old code did not have, so these checks fail on it.
const mbl = /public static List<string> MustBeLight\(Config[^)]*\)\s*\{([\s\S]*?)\n        \}/.exec(verify);
yes('Verify.MustBeLight derives the set from the server', !!mbl);
const body = mbl ? mbl[1] : '';
yes('it starts from the collection reference, Paths.Golden\\plugins.txt',
    body.indexOf('Paths.Golden') >= 0);
yes('it asks the server for its manifest', body.indexOf('Manifest(cfg)') >= 0);
yes('it leaves out the plugins the manifest counts (the server is not light there)',
    /counted\.Contains|Names\(mods\)/.test(body));
yes('it still folds the hand list in as the fallback',
    body.indexOf('Checks.MustBeLight') >= 0);

// Run and Fix must drive the flag off the derived set, not the bare hand list.
// The old code called Checks.NotLight() and Checks.FlagLight(null).
yes('Verify.Run flags off the derived set (Checks.NotLight(MustBeLight(cfg)))',
    verify.indexOf('Checks.NotLight(MustBeLight(cfg))') >= 0);
yes('Verify.Fix flags off the derived set (Checks.FlagLight(MustBeLight(cfg), ...))',
    /Checks\.FlagLight\(MustBeLight\(cfg\)/.test(verify));

// The flag is set on a separated copy, never through the link. The server
// derives WHICH plugins; how they are written must not change.
const fl = /public static int FlagLight\(IEnumerable[\s\S]*?\n        \}/.exec(checks);
yes('FlagLight separates the file from Vortex\u2019s copy before it writes',
    !!fl && fl[0].indexOf('OwnGame.Separate(p);') >= 0 &&
    fl[0].indexOf('OwnGame.Separate(p);') < fl[0].indexOf('fs.Write('));

// Every plugin the hand list names must be one the server leaves out, or
// flagging it would move the client the wrong way. When the server's order is
// in this checkout, check it; otherwise say so rather than pass silently.
let order = [];
try {
  order = JSON.parse(fs.readFileSync(path.join(REPO_DIR, 'version.json'), 'utf8')).loadOrder || [];
} catch (e) { order = []; }
if (!order.length) {
  console.log('SKIP  no server load order in this checkout to compare the list against');
} else {
  const names = order.map(function (p) { return String(p).split(/[\\/]/).pop().toLowerCase(); });
  list.forEach(function (n) {
    yes(n + ' is not in the server\u2019s load order, which is what makes it light there',
        names.indexOf(n.toLowerCase()) < 0);
  });
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
