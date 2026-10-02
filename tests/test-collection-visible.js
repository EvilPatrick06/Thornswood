/*
  test-collection-visible.js

  The way to the collection is never out of reach (Djinn, 2 Oct).

  WHY THIS EXISTS. #599 took the Mods page off the rail, and its card was the
  only button to the collection, and the only place that said what revision
  Vortex had. The card by Play comes up only when CollectionProblem can prove
  something is wrong, and it answers "" when it cannot read the revision at
  all, so on a machine where Vortex's state could not be read there was no
  card, no button and no word anywhere.

  This holds three things to the source:
    - Diagnostics puts the collection card first, with what was found;
    - the bar above Play carries a not-confirmed note with the button when the
      revision cannot be read, and that note never shuts Play;
    - the bar's button opens the collection for the note, and still runs the
      update when an update owns the bar.

  Read only. It reads source files and nothing else.
*/
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

const APP = path.join(REPO_DIR, 'launcher', 'app');
const CR = String.fromCharCode(13);
const read = f => fs.readFileSync(path.join(APP, f), 'utf8').split(CR).join('');
const SHELL = read('Shell.cs');
const PAGES = read('Pages.cs');
const PACKS = read('ShellPacks.cs');

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

// ---- Diagnostics -----------------------------------------------------------
const diag = PAGES.slice(PAGES.indexOf('static void BuildDiag()'));
const clear = diag.indexOf('diagReadings.Children.Clear();');
const card = diag.indexOf('diagReadings.Children.Add(CollectionStatusCard());');
const rows = diag.indexOf('diagReadings.Children.Add(ReadingRow(r));');
yes('BuildDiag adds the collection card', card > 0);
yes('it is added after the clear and before the readings, so it is first', clear >= 0 && card > clear && rows > card);

const status = PACKS.slice(PACKS.indexOf('static UIElement CollectionStatusCard()'));
yes('CollectionStatusCard exists', PACKS.indexOf('static UIElement CollectionStatusCard()') > 0);
yes('it reads the installed revision', /Checks\.CollectionRevision\(cfg\)/.test(status.slice(0, 2500)));
yes('it says when the revision could not be read', status.indexOf('Your mods: not confirmed') > 0);
yes('it is built on the card that has the Open the collection button',
    /return CollectionCard\(/.test(status.slice(0, 2500)) && PACKS.indexOf('b.Content = "Open the collection";') > 0);

// ---- the note above Play ---------------------------------------------------
yes('there is a flag for the note', SHELL.indexOf('static bool collectionNoteUp = false;') > 0);
const unc = SHELL.slice(SHELL.indexOf('static bool CollectionUnconfirmed()'));
yes('CollectionUnconfirmed exists', SHELL.indexOf('static bool CollectionUnconfirmed()') > 0);
yes('it is only true when CollectionProblem found nothing and the revision is unreadable',
    /if \(CollectionProblem\(\)\.Length > 0\) return false;/.test(unc.slice(0, 800)) &&
    /return Checks\.CollectionRevision\(cfg\) <= 0;/.test(unc.slice(0, 800)));

const noteAt = SHELL.indexOf('bool unsure = CollectionUnconfirmed();');
yes('DrawStatus asks it', noteAt > 0);
const note = noteAt > 0 ? SHELL.slice(noteAt, SHELL.indexOf('// Wrong Skyrim build', noteAt)) : '';
yes('the note says the mods could not be confirmed', note.indexOf('Your mods could not be confirmed') >= 0);
yes('the note offers the collection', note.indexOf('btnInstallNow.Content = "Open the collection";') >= 0);
yes('the note never sets collectionBarUp, so it never shuts Play', note.indexOf('collectionBarUp = true') < 0);
yes('the note never touches the Play button', note.indexOf('btnPlay') < 0);
const guard = SHELL.slice(SHELL.lastIndexOf('if (updateBar != null', noteAt), noteAt);
yes('the note stays off while an update or the collection card owns the bar',
    guard.indexOf('!collectionBarUp') >= 0 && guard.indexOf('!updatePending') >= 0);

// Play's own gate is unchanged: the note is not in it.
const gate = /btnPlay\.IsEnabled = all && !playing && !updatePending && !collectionBarUp && !ownGameBusy && !working && feedNotice\.Hold == null;/;
yes('Play is enabled by exactly the same test as before', gate.test(SHELL));

// ---- the bar's button --------------------------------------------------------
yes('the bar\'s button opens the collection for the note but not over an update',
    SHELL.indexOf('if (collectionBarUp || (collectionNoteUp && !updatePending))') > 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
