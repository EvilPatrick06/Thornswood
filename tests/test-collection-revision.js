/*
  test-collection-revision.js

  Which revision of the collection a machine has installed.

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

  WHERE THE NUMBER COMES FROM, rewritten 27 September. The first fix read the
  revision out of the mod folder name, collection_<slug>_<rev>_<when>. Current
  Vortex does not name the folder that way any more: it is vortex_collection_
  <opaque id>_, with no slug and no number in it, so the folder name could no
  longer answer and Have went to 0 on every up to date machine. The honest
  source is Vortex's own state.v2, which records the slug and the revision
  NUMBER against the collection's mod, independent of the folder name. This
  checks both readers: the state scan (the source of truth now) and the old
  folder-name parse (the legacy fallback), plus that the C# and PowerShell
  copies still carry both.

  Read only. It builds strings in memory and reads the two source files.
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

/* The legacy folder-name rule, as this test understands it. Current Vortex
   does not write these folders any more; this is the fallback for a machine
   that still has them and no readable state. */
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

/* The state.v2 rule, the source of truth now. Vortex flattens its state into
   LevelDB keys joined by ###, each key then a length byte (a control char)
   then the value's JSON. The slug and the revision number are separate keys
   tied together only by the mod id both carry, so this matches the slug to
   its mod id and takes the highest revision recorded against a mod id whose
   slug is the one asked for. The same rule as Get-CollectionRevisionFromState
   in LoadOrder.ps1 and CollectionRevisionFromState in Checks.cs. */
function revisionFromState(text, slug) {
  const esc = slug.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const slugRe = new RegExp('mods###skyrimse###([^#]+)###attributes###collectionSlug[\\x00-\\x1F]{1,4}"' + esc + '"', 'g');
  const revRe = /mods###skyrimse###([^#]+)###attributes###revisionNumber[\x00-\x1F]{1,4}(\d+)/g;
  const mine = new Set();
  const rev = new Map();
  let m;
  while ((m = slugRe.exec(text)) !== null) mine.add(m[1]);
  while ((m = revRe.exec(text)) !== null) {
    const id = m[1];
    const n = Number(m[2]);
    if (!Number.isInteger(n)) continue;
    if (!rev.has(id) || n > rev.get(id)) rev.set(id, n);
  }
  let best = 0;
  for (const id of mine) if (rev.has(id) && rev.get(id) > best) best = rev.get(id);
  if (best > 0) return best;

  // Authoring shape: newestFileId on the collection mod -> collections###revisions.
  const revSlugRe = new RegExp(
    'collections###revisions###([^#]+)###info###collection###slug[\\x00-\\x1F]{1,4}"' + esc + '"', 'g');
  const fileIdRe = /mods###skyrimse###([^#]+)###attributes###newestFileId[\x00-\x1F]{1,4}(\d+)/g;
  const verRe = /mods###skyrimse###([^#]+)###attributes###newestVersion[\x00-\x1F]{1,4}"(\d+)"/g;
  const revIds = new Set();
  const fileIdMods = new Map();
  const modVer = new Map();
  while ((m = revSlugRe.exec(text)) !== null) revIds.add(m[1]);
  while ((m = fileIdRe.exec(text)) !== null) {
    const fid = m[2];
    if (!fileIdMods.has(fid)) fileIdMods.set(fid, []);
    if (!fileIdMods.get(fid).includes(m[1])) fileIdMods.get(fid).push(m[1]);
  }
  while ((m = verRe.exec(text)) !== null) {
    const n = Number(m[2]);
    if (!Number.isInteger(n)) continue;
    if (!modVer.has(m[1]) || n > modVer.get(m[1])) modVer.set(m[1], n);
  }
  if (revIds.size === 0) return 0;
  const revNum = new Map();
  for (const rid of revIds) {
    const numRe = new RegExp(
      'collections###revisions###' + rid.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') +
      '###info###revisionNumber[\\x00-\\x1F]{1,4}(\\d+)', 'g');
    while ((m = numRe.exec(text)) !== null) {
      const n = Number(m[1]);
      if (!Number.isInteger(n)) continue;
      if (!revNum.has(rid) || n > revNum.get(rid)) revNum.set(rid, n);
    }
  }
  for (const rid of revIds) {
    if (!fileIdMods.has(rid)) continue;
    let n = revNum.has(rid) ? revNum.get(rid) : 0;
    if (n <= 0) {
      for (const mid of fileIdMods.get(rid)) {
        if (modVer.has(mid) && modVer.get(mid) > n) n = modVer.get(mid);
      }
    }
    if (n > best) best = n;
  }
  return best;
}

/* One flattened key and its value, byte for byte as Vortex writes it into
   the LevelDB log: the key, one length byte, the value's JSON, then the start
   of the next key so the value is bounded. */
function attr(modId, name, valueJson) {
  return 'persistent###mods###skyrimse###' + modId + '###attributes###' + name +
    String.fromCharCode(valueJson.length) + valueJson +
    '\x01persistent###mods###skyrimse';
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
    slugFrom('https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf') === '7essxf');
yes('a trailing slash does not become part of it',
    slugFrom('https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf/') === '7essxf');
yes('a query string does not become part of it',
    slugFrom('https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf?tab=mods') === '7essxf');
yes('an address that is not a collection gives nothing',
    slugFrom('https://www.nexusmods.com/skyrimspecialedition/mods/12345') === '');
yes('an empty address gives nothing', slugFrom('') === '');
/* A slug is used to build a folder search pattern, so anything that is not
   letters and digits is refused rather than passed through. */
yes('a slug with punctuation in it is refused', slugFrom('https://x/collections/../../evil') === '');

// ---- the revision from state, the source of truth now ----------------------
/* The folder Vortex writes today carries no number, so the number lives in
   state and this is where it is read. */
const newState = attr('vortex_collection_ZRT7NjhN_', 'collectionSlug', '"7essxf"') +
                 attr('vortex_collection_ZRT7NjhN_', 'revisionNumber', '5');
yes('the installed revision is read from Vortex state under the new folder naming',
    revisionFromState(newState, '7essxf') === 5);

yes('an upgrade in place, the same mod on a newer revision, reads the newer one',
    revisionFromState(
      attr('vortex_collection_ZRT7NjhN_', 'collectionSlug', '"7essxf"') +
      attr('vortex_collection_ZRT7NjhN_', 'revisionNumber', '5') +
      attr('vortex_collection_ZRT7NjhN_', 'revisionNumber', '6'), '7essxf') === 6);

yes('two digit revisions read whole, not truncated',
    revisionFromState(
      attr('vortex_collection_ZRT7NjhN_', 'collectionSlug', '"7essxf"') +
      attr('vortex_collection_ZRT7NjhN_', 'revisionNumber', '12'), '7essxf') === 12);

/* Two collections installed at once, this machine on 7essxf and another on
   ombo2a: each answers about its own, tied by the mod id, never mixed up. This
   is the whole reason the slug and the number are correlated rather than taking
   the highest number in the file. */
const two = attr('vortex_collection_ZRT7NjhN_', 'collectionSlug', '"7essxf"') +
            attr('vortex_collection_ZRT7NjhN_', 'revisionNumber', '5') +
            attr('vortex_collection_AAbb99xx_', 'collectionSlug', '"ombo2a"') +
            attr('vortex_collection_AAbb99xx_', 'revisionNumber', '12');
yes('with two collections installed, 7essxf reads its own 5, not the other 12',
    revisionFromState(two, '7essxf') === 5);
yes('and ombo2a reads its own 12', revisionFromState(two, 'ombo2a') === 12);

yes('nothing installed reads as 0, which means say nothing', revisionFromState('', '7essxf') === 0);
yes('a slug with no revision recorded reads as 0',
    revisionFromState(attr('vortex_collection_ZRT7NjhN_', 'collectionSlug', '"7essxf"'), '7essxf') === 0);
yes('a revision recorded against another slug is not read as ours',
    revisionFromState(
      attr('vortex_collection_AAbb99xx_', 'collectionSlug', '"ombo2a"') +
      attr('vortex_collection_AAbb99xx_', 'revisionNumber', '12'), '7essxf') === 0);
// Authoring shape on the ship PC: no collectionSlug / revisionNumber attrs.
function revInfo(revId, slug, num) {
  return 'persistent###collections###revisions###' + revId + '###info###collection###slug' +
    String.fromCharCode(('"' + slug + '"').length) + '"' + slug + '"' +
    '\x01persistent###collections###revisions###' + revId + '###info###revisionNumber' +
    String.fromCharCode(String(num).length) + String(num) +
    '\x01persistent###mods###skyrimse';
}
const authored = attr('vortex_collection_ZRT7NjhN_', 'newestFileId', '796316') +
  attr('vortex_collection_ZRT7NjhN_', 'newestVersion', '"1"') +
  revInfo('796316', '7essxf', 1);
yes('authoring shape (newestFileId, no collectionSlug) still reads Have 1',
  revisionFromState(authored, '7essxf') === 1);
yes('and does not cross to ombo2a', revisionFromState(authored, 'ombo2a') === 0);


// ---- the revision from the legacy folder name, the fallback ----------------
const real = ['collection_7essxf_2_2026-09-15T21-08-00Z'];
yes('the legacy folder still reads as revision 2', revisionFrom(real, '7essxf') === 2);

yes('the newest wins when an upgrade leaves the old one behind',
    revisionFrom([
      'collection_7essxf_2_2026-09-15T21-08-00Z',
      'collection_7essxf_4_2026-09-22T10-00-00Z',
      'collection_7essxf_3_2026-09-19T10-00-00Z'
    ], '7essxf') === 4);

yes('double figures beat single figures, rather than sorting as text',
    revisionFrom([
      'collection_7essxf_9_2026-09-15T21-08-00Z',
      'collection_7essxf_10_2026-09-22T10-00-00Z'
    ], '7essxf') === 10);

yes('another collection in the same folder is ignored',
    revisionFrom([
      'collection_7essxf_2_2026-09-15T21-08-00Z',
      'collection_somebodyelse_99_2026-09-22T10-00-00Z'
    ], '7essxf') === 2);

yes('an ordinary mod folder is ignored',
    revisionFrom(['SunHelm Survival-39414-3-1-4-1661703641'], '7essxf') === 0);
/* The opaque folder name carries no number, so the legacy parser says nothing
   about it, and that is now correct: the revision comes from state instead
   (proved above), not from this name. */
yes('the opaque vortex_collection_* folder name has no revision to parse',
    revisionFrom(['vortex_collection_qUAAu3jC3'], '7essxf') === 0);
yes('nothing installed reads as 0, which means say nothing', revisionFrom([], '7essxf') === 0);
yes('a name with no revision part reads as 0', revisionFrom(['collection_7essxf_'], '7essxf') === 0);
yes('a name whose revision is not a number reads as 0',
    revisionFrom(['collection_7essxf_two_2026-09-15T21-08-00Z'], '7essxf') === 0);

// ---- the three copies must agree ------------------------------------------
/*
  C#, PowerShell and this each carry the rule, because they cannot share code.
  These assert the shape rather than the behaviour, so a rename or a dropped
  step fails here instead of silently telling everybody to reinstall.
*/
yes('the launcher reads the installed revision from Vortex state',
    CS.indexOf('CollectionRevisionFromState') >= 0 &&
    CS.indexOf('collectionSlug') >= 0 && CS.indexOf('revisionNumber') >= 0 &&
  CS.indexOf('newestFileId') >= 0);
yes('the launcher ties the slug to its mod id, not the highest number in the file',
    /mods###skyrimse###\(\[\^#\]\+\)###attributes###collectionSlug/.test(CS));
yes('the launcher keeps the legacy folder parse as a fallback',
    CS.indexOf('CollectionRevisionFromFolder') >= 0 && CS.indexOf('collection_') >= 0);
yes('the launcher refuses a slug that is not letters and digits',
    /IsLetterOrDigit/.test(CS));
yes('the publisher reads it the same way, from state',
    PS.indexOf('Get-CollectionRevisionFromState') >= 0 &&
    PS.indexOf('collectionSlug') >= 0 && PS.indexOf('revisionNumber') >= 0 &&
  PS.indexOf('newestFileId') >= 0);
yes('the publisher ties the slug to its mod id too',
    /mods###skyrimse###\(\[\^#\]\+\)###attributes###collectionSlug/.test(PS));
yes('the publisher keeps the legacy folder parse as a fallback',
    PS.indexOf('Get-CollectionRevisionFromFolder') >= 0 && PS.indexOf('collection_') >= 0);
yes('the publisher refuses a bad slug', /\^\[A-Za-z0-9\]\+\$/.test(PS));

/* The thing this replaced must not creep back as the test. */
yes('nothing decides staleness from po3_StartOnSave any more',
    fs.readFileSync(path.join(TOOLS_DIR, '..', 'launcher', 'app', 'Shell.cs'), 'utf8')
      .indexOf('if (!Checks.StartOnSaveInstalled()) return "stale"') < 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
