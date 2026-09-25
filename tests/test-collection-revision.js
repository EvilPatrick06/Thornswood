/*
  test-collection-revision.js

  Which revision of the collection a machine has, read from the name Vortex
  gives the collection's own mod folder.

  WHY THIS EXISTS AND WHY IT IS WORTH A TEST. Until 22 September the launcher
  decided "your collection is behind" by asking whether po3_StartOnSave.dll
  was present. That file is not in the collection and never has been:
  Add-Characters.ps1 puts it into a build by hand. So the test was wrong in
  both directions, and it was wrong in the quietest way on the machine that
  matters most.

  Patrick's own machine, which is the one that derives the server's load order
  and the reference plugin list, was sitting on collection revision 2 while
  the collection on Nexus was on revision 4. Nothing on screen said so,
  because the file was there. Two revisions of drift on the shipping machine,
  invisible.

  A number is the honest answer to a question about a revision. This checks
  the parsing of that number, because a folder name is a string from outside
  and every way it can be malformed ends with either a wrong warning or a
  missing one.

  Read only. It makes folder names in a temp directory and reads nothing else.
*/
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const os = require('os');

/*
  The same rule as Checks.CollectionRevision in the launcher and
  Get-CollectionRevision in LoadOrder.ps1. Three copies is two too many, and
  they cannot share code across C#, PowerShell and this, so this is the one
  that fails loudly when they drift: it reads the C# and asserts the shape.
*/
const CS = fs.readFileSync(path.join(TOOLS_DIR, '..', 'launcher', 'app', 'Checks.cs'), 'utf8');
const PS = fs.readFileSync(path.join(TOOLS_DIR, '..', 'scripts', 'mods', 'LoadOrder.ps1'), 'utf8');

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

/* The rule, as this test understands it. */
function revisionFrom(names, slug) {
  const prefix = 'collection_' + slug + '_';
  let best = 0;
  for (const name of names) {
    if (!name.startsWith(prefix)) continue;
    const rest = name.slice(prefix.length);
    const cut = rest.indexOf('_');
    if (cut <= 0) continue;
    const n = Number(rest.slice(0, cut));
    if (!Number.isInteger(n)) continue;
    if (n > best) best = n;
  }
  return best;
}

function slugFrom(url) {
  if (!url) return '';
  const at = url.toLowerCase().lastIndexOf('/collections/');
  if (at < 0) return '';
  let s = url.slice(at + '/collections/'.length).trim();
  const q = s.search(/[/?#]/);
  if (q >= 0) s = s.slice(0, q);
  return /^[A-Za-z0-9]+$/.test(s) ? s : '';
}

// ---- the slug --------------------------------------------------------------
yes('the slug comes out of a collection address',
    slugFrom('https://www.nexusmods.com/games/skyrimspecialedition/collections/ombo2a') === 'ombo2a');
yes('a trailing slash does not become part of it',
    slugFrom('https://www.nexusmods.com/games/skyrimspecialedition/collections/ombo2a/') === 'ombo2a');
yes('a query string does not become part of it',
    slugFrom('https://www.nexusmods.com/games/skyrimspecialedition/collections/ombo2a?tab=mods') === 'ombo2a');
yes('an address that is not a collection gives nothing',
    slugFrom('https://www.nexusmods.com/skyrimspecialedition/mods/12345') === '');
yes('an empty address gives nothing', slugFrom('') === '');
/* A slug is used to build a folder search pattern, so anything that is not
   letters and digits is refused rather than passed through. */
yes('a slug with punctuation in it is refused', slugFrom('https://x/collections/../../evil') === '');

// ---- the revision ----------------------------------------------------------
const real = ['collection_ombo2a_2_2026-09-15T21-08-00Z'];
yes('the real folder on this machine reads as revision 2', revisionFrom(real, 'ombo2a') === 2);

yes('the newest wins when an upgrade leaves the old one behind',
    revisionFrom([
      'collection_ombo2a_2_2026-09-15T21-08-00Z',
      'collection_ombo2a_4_2026-09-22T10-00-00Z',
      'collection_ombo2a_3_2026-09-19T10-00-00Z'
    ], 'ombo2a') === 4);

yes('double figures beat single figures, rather than sorting as text',
    revisionFrom([
      'collection_ombo2a_9_2026-09-15T21-08-00Z',
      'collection_ombo2a_10_2026-09-22T10-00-00Z'
    ], 'ombo2a') === 10);

yes('another collection in the same folder is ignored',
    revisionFrom([
      'collection_ombo2a_2_2026-09-15T21-08-00Z',
      'collection_somebodyelse_99_2026-09-22T10-00-00Z'
    ], 'ombo2a') === 2);

yes('an ordinary mod folder is ignored',
    revisionFrom(['SunHelm Survival-39414-3-1-4-1661703641'], 'ombo2a') === 0);
yes('vortex_collection_* is not a revision', revisionFrom(['vortex_collection_qUAAu3jC3'], 'ombo2a') === 0);
yes('nothing installed reads as 0, which means say nothing', revisionFrom([], 'ombo2a') === 0);
yes('a name with no revision part reads as 0', revisionFrom(['collection_ombo2a_'], 'ombo2a') === 0);
yes('a name whose revision is not a number reads as 0',
    revisionFrom(['collection_ombo2a_two_2026-09-15T21-08-00Z'], 'ombo2a') === 0);

// ---- the three copies must agree ------------------------------------------
/*
  C#, PowerShell and this each carry the rule, because they cannot share code.
  These assert the shape rather than the behaviour, so a rename or a dropped
  step fails here instead of silently telling everybody to reinstall.
*/
yes('the launcher reads the revision from the folder name',
    CS.indexOf('CollectionRevision') >= 0 && CS.indexOf('collection_') >= 0);
yes('the launcher takes the highest revision it finds',
    /if \(n > best\) best = n;/.test(CS));
yes('the launcher refuses a slug that is not letters and digits',
    /IsLetterOrDigit/.test(CS));
yes('the publisher reads it the same way',
    PS.indexOf('Get-CollectionRevision') >= 0 && PS.indexOf('collection_') >= 0);
yes('the publisher takes the highest too', /\$n -gt \$best/.test(PS));
yes('the publisher refuses a bad slug', /\^\[A-Za-z0-9\]\+\$/.test(PS));

/* The thing this replaced must not creep back as the test. */
yes('nothing decides staleness from po3_StartOnSave any more',
    fs.readFileSync(path.join(TOOLS_DIR, '..', 'launcher', 'app', 'Shell.cs'), 'utf8')
      .indexOf('if (!Checks.StartOnSaveInstalled()) return "stale"') < 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
