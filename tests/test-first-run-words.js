// test-first-run-words.js
//
// The launcher tells a new person to give their character a Skyrim name, and
// never tells them to save before connecting.
//
// From the To Do List, entry 163: "The Play page tells a new person to name the
// character after themselves, and to save before connecting." The first-run
// card on the Play page said "Create a character and name it after yourself"
// and "Save once before connecting. Joining from an unsaved game drops you back
// to the menu." Both were the old multiplayer mod's advice, carried over. The name is
// what everybody sees above your head, so somebody who followed the card walked
// into Whiterun under their own name. And there is no saving here: the site's
// hints say "There is no saving. The server holds your character, so quitting
// is safe." (site\data\site\lines.md, the one copy of the hints, #3147; Help's
// list of what is normal here, which said it too, was removed on 26 Oct).
//
// The same name advice was in the Help page's first Joining item, two pages
// away, and its third item still explained saving by what the old
// multiplayer mod used to refuse. Fixing the card alone would have left the launcher telling
// two different stories, so this reads both files and checks they agree.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
function read(rel) {
  return fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split(CR).join('');
}
const xaml = read('launcher/ui.xaml');
const help = read(path.join('launcher', 'app', 'Help.cs'));
const site = read(path.join('site', 'data', 'site', 'lines.md'));
const shell = read(path.join('launcher', 'app', 'Shell.cs'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// The words every place has to share. Written once here, so the card and the
// help page are checked against the same rule rather than against each other.
const RULE_SKYRIM = 'a name that belongs in Skyrim';
const RULE_SHAPE = 'a first name and a family name or a byname';
const RULE_NOT_OWN = 'not your own';

// ---------------------------------------------------------------- the card
// Shell.cs finds the card by its name and hides it once the person has played,
// so the StackPanel has to survive whatever happens to the words inside it.
// Found by its name alone: the tag has since gained a Margin, and whatever
// else it gains is not what this is about.
const a = xaml.search(/<StackPanel x:Name="FirstRunCard"[\s>]/);
const b = a < 0 ? -1 : xaml.indexOf('<StackPanel x:Name="QuickKeysCard"', a);
const card = (a >= 0 && b > a) ? xaml.slice(a, b) : '';
yes('ui.xaml still has the FirstRunCard StackPanel', card !== '');
yes('Shell.cs still looks the card up by that name',
    shell.indexOf('F<StackPanel>("FirstRunCard")') >= 0);

// Only what a person reads: the Text attributes, not the markup or comments.
const cardWords = [];
card.replace(/\bText="([^"]*)"/g, function (m, t) { cardWords.push(t); return m; });
const cardText = cardWords.join(' ');
yes('the card has words in it', cardWords.length >= 2);

yes('the card no longer says to name the character after yourself',
    !/after yourself/i.test(cardText));
yes('the card no longer says to save before connecting',
    !/\bsav(e|ed|ing)\b/i.test(cardText) && !/unsaved/i.test(cardText));
yes('the card gives the rule: ' + RULE_SKYRIM, cardText.indexOf(RULE_SKYRIM) >= 0);
yes('the card gives the rule: ' + RULE_SHAPE, cardText.indexOf(RULE_SHAPE) >= 0);
yes('the card gives the rule: ' + RULE_NOT_OWN, cardText.indexOf(RULE_NOT_OWN) >= 0);
yes('the card still says the name cannot be changed later',
    /cannot be changed later/.test(cardText));
yes('the separator that stood between the two lines went with the save line',
    card.indexOf('<Rectangle') < 0);

// ------------------------------------------------------ the Joining items
// new HelpItem("Joining", "title",
//     "body"),
const joining = [];
help.replace(/new HelpItem\("Joining",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)/g,
  function (m, title, body) { joining.push({ title: title, body: body }); return m; });
yes('Help.cs has its Joining items, ' + joining.length + ' of them', joining.length >= 5);

// Found by its title rather than its place. It was the first item while the
// items were numbered; entry 164 rebuilt the page so Joining runs in the order
// things happen (open the launcher, Discord, Play, then the menu), which puts
// the character pick fourth. The rule it has to give is the same either way.
const picks = joining.filter(function (j) { return /pick your character/i.test(j.title); });
const first = picks.length ? picks[0] : { title: '', body: '' };
yes('one Joining item is the one about picking a character', picks.length === 1);
yes('no Joining item says to name the character after yourself',
    joining.every(function (j) { return !/after yourself/i.test(j.title + ' ' + j.body); }));
yes('the character pick item gives the same rule as the card: ' + RULE_SKYRIM,
    first.body.indexOf(RULE_SKYRIM) >= 0);
yes('the character pick item gives the same rule as the card: ' + RULE_SHAPE,
    first.body.indexOf(RULE_SHAPE) >= 0);
yes('the character pick item gives the same rule as the card: ' + RULE_NOT_OWN,
    first.body.indexOf(RULE_NOT_OWN) >= 0);

// The save item: it has to say what the site says, and it cannot start from
// what the old engine did. The entry allowed deleting it rather than
// rewriting it, so a Help page with no save item at all is not a failure; one
// that still has one has to agree with the site.
const saving = joining.filter(function (j) { return /\bsav(e|ed|ing)\b/i.test(j.title); });
yes('at most one Joining item is about saving', saving.length <= 1);
yes('the site\'s hints still say there is no saving, so there is something to agree with',
    /There is no saving\. The server holds your character\b/.test(site));
yes('any Joining item about saving says there is no saving, as the site does',
    saving.every(function (j) { return /no saving/i.test(j.title + ' ' + j.body); }));
yes('any Joining item about saving says the server holds the character',
    saving.every(function (j) { return /server holds your character/i.test(j.body); }));
yes('no Joining item is explained by the old multiplayer mod',
    joining.every(function (j) { return !/Skyrim\s*Together|\bTogether\b/.test(j.title + ' ' + j.body); }));
yes('no Joining item calls saving worth doing',
    joining.every(function (j) { return !/saving is still worth/i.test(j.body); }));

// ------------------------------------------------------------- the words
// People read all of this. No em dash, and nobody is a player.
const shown = [cardText].concat(joining.map(function (j) { return j.title + ' ' + j.body; })).join(' ');
yes('no em dash in the card or the Joining items', shown.indexOf(String.fromCharCode(0x2014)) < 0);
yes('nobody is called a player in the card or the Joining items', !/\bplayers?\b/i.test(shown));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
