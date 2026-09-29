// test-help-parties.js
//
// The launcher's Help page says what parties are, and every number on it is
// the gamemode's.
//
// From the To Do List, entry 336: "Parties: travel as a group in game rather
// than a Discord call and a guess about who is where", with the note that "the
// launcher's Help page currently explains why there is no party system by
// comparing it to the old project".
//
// Parties arrived on 23 September (#133), and the green names, the map
// markers and the compass strip the same morning (#139). The Help item went on
// saying "There is no party system", measured against the old multiplayer mod. It is
// copy, so nothing failed and nothing told anybody. This file reads the Help
// items out of launcher\app\Help.cs and holds the party ones to the code they
// describe: the cap, the bonus, how long an ask stands and the keys are read
// out of the gamemode, the plugin and the Controls page rather than typed in
// here, and the real party block is run over a fake mp to show the cap, the
// lapse, the logout rule and the bonus do what the page says they do.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
function read(...bits) {
  return fs.readFileSync(path.join(TOOLS_DIR, ...bits), 'utf8').split(CR).join('');
}
const SRC = process.env.GM || path.join(TOOLS_DIR, '..', 'game', 'gamemode.js');
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');
const helpCs = read('..', 'launcher', 'app', 'Help.cs');
const keysCs = read('..', 'launcher', 'app', 'Keys.cs');
const front = read('..', 'game', 'plugins', 'thornswood-front.js');
const panel = read('..', 'game', 'ui', 'thornswood-party.js');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function code(s) {
  return s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

/*
  A number the way this repo writes one for people, "forty five" and not
  "forty-five", or as digits. The page is allowed either.
*/
const SMALL = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
               'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
               'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
              'eighty', 'ninety'];
function spoken(n) {
  if (n < 20) { return SMALL[n]; }
  if (n < 100) { return TENS[Math.floor(n / 10)] + (n % 10 ? ' ' + SMALL[n % 10] : ''); }
  return String(n);
}
function says(text, n, before, after) {
  return [String(n), spoken(n)].some(function (f) {
    return new RegExp('\\b' + before + f + after, 'i').test(text);
  });
}

// ------------------------------------------------------------ the Help items
/*
  Every new HelpItem("Section", "Title", "Body") in the file, with the C#
  escapes taken back out. Help.cs uses plain literals only, so a backslash
  followed by one character is the whole of the escaping there is.
*/
const items = [];
{
  const lit = '"((?:[^"\\\\]|\\\\.)*)"';
  const re = new RegExp('new HelpItem\\(\\s*' + lit + '\\s*,\\s*' + lit + '\\s*,\\s*' + lit + '\\s*\\)', 'g');
  const unq = function (s) { return s.replace(/\\(.)/g, '$1'); };
  let m;
  while ((m = re.exec(helpCs)) !== null) {
    items.push({ section: unq(m[1]), title: unq(m[2]), body: unq(m[3]) });
  }
}
yes('the Help page has its items, ' + items.length + ' of them', items.length > 20);

/*
  The party items are found by what they are about rather than by where they
  sit, so a rewrite of the page that moves them to another section still
  holds them to the same numbers.
*/
const partyItems = items.filter(function (h) {
  return /\bpart(y|ies)\b/i.test(h.title) || h.body.indexOf('/party') !== -1;
});
const together = items.filter(function (h) { return h.section === 'Playing together'; });
const text = partyItems.map(function (h) { return h.title + '. ' + h.body; }).join(' ');
const aboutTogether = together.concat(partyItems)
  .map(function (h) { return h.title + '. ' + h.body; }).join(' ');

{
  yes('there is an item about parties', partyItems.length > 0);
  yes('and nothing on the page says there is no party system',
      !items.some(function (h) {
        return /no party system|nobody to invite|adds none of it/i.test(h.title + ' ' + h.body);
      }));
  yes('nothing about playing together is measured against the old multiplayer mod',
      !/Skyrim\s*Together/i.test(aboutTogether));
}

// ------------------------------------------------- the numbers are the code's
const social = (function () {
  const a = src.indexOf('// ==== thornswood social:');
  const b = a < 0 ? -1 : src.indexOf('// ==== end thornswood social ====', a);
  return (a >= 0 && b >= 0) ? src.slice(a, b) : null;
})();
yes('the social block is in the gamemode', social !== null);

function number(re) {
  const m = social ? code(social).match(re) : null;
  return m ? Number(m[1]) : NaN;
}
const CAP = number(/mostParty:\s*([0-9]+)/);
const BONUS = Math.round(number(/partyBonus:\s*([0-9.]+)/) * 100);
const LAPSE = Math.round(number(/offerFor:\s*([0-9]+)/) / 1000);

yes('the gamemode has a party cap, ' + CAP, CAP > 1);
yes('the page gives the same cap, up to ' + spoken(CAP), says(text, CAP, 'up to ', '\\b'));
yes('the gamemode pays a party bonus, ' + BONUS + ' per cent', BONUS > 0);
yes('the page gives the same bonus', says(text, BONUS, '', ' per cent'));
yes('an ask stands for ' + LAPSE + ' seconds in the gamemode', LAPSE > 0);
yes('and the page says ' + spoken(LAPSE) + ' seconds', says(text, LAPSE, '', ' seconds'));

// ---------------------------------------------------------------- the keys
/*
  The letter on the page is the plugin's default and the Controls page's
  default, read out of both. A rebind in one of them and not the other would
  make the page true on one side only.
*/
{
  const fm = front.match(/iniNumber\(ini, 'PartyKey', ([0-9]+)\)/);
  const km = keysCs.match(/"PartyKey",\s*([0-9]+)\)/);
  const cm = front.match(/iniNumber\(ini, 'ChatKey', ([0-9]+)\)/);
  const lm = front.match(/const letters = (\{[\s\S]*?\});/);
  const frontKey = fm ? Number(fm[1]) : NaN;
  const keysKey = km ? Number(km[1]) : NaN;
  let letters = {};
  try { letters = lm ? new Function('return ' + lm[1])() : {}; } catch (e) { letters = {}; }
  const letter = letters[frontKey] || '';

  yes('the plugin and the Controls page start the party key on the same key, ' + letter,
      !!letter && frontKey === keysKey);
  yes('the page names that key, and says it can be moved',
      new RegExp('\\b' + letter + ', unless you have moved it on the Controls page').test(text));
  // 28 is the DirectInput scan code for Enter.
  yes('the page says Enter, and Enter is the chat key',
      /press Enter\b/.test(text) && cm && Number(cm[1]) === 28);

  /*
    THE LOOK PROMPT. The panel drawn over somebody under the crosshair says
    "Ask to party" beside the party key, but the key handler only opens the
    P panel: it never sends /party for the person being looked at. Until it
    does, the page must not tell anybody to look at somebody and press P to
    bring them in. When the key is changed to ask, this lets the page say so.
  */
  const branch = front.match(/if \(e\.code === PARTY_KEY\) \{([\s\S]*?)\n\s*\}/);
  const keyAsks = !!(branch && /lookVerb\('party'\)/.test(branch[1]));
  const promises = /look at (somebody|them|someone)[^.]*press/i.test(text);
  yes('the page only says look at somebody and press the key if the key does that',
      !promises || keyAsks);
}

// ------------------------------------------------------------ the commands
{
  const pm = src.match(/const PLAYER_WORDS = (\[[\s\S]*?\]);/);
  let words = [];
  try { words = pm ? new Function('return ' + code(pm[1]))() : []; } catch (e) { words = []; }
  yes('the gamemode says which commands everybody may use', words.length > 10);

  const named = (text.match(/\/[a-z]+/g) || []).filter(function (w, i, all) {
    return all.indexOf(w) === i;
  });
  yes('the page names /party, /yes and /no',
      named.indexOf('/party') !== -1 && named.indexOf('/yes') !== -1 && named.indexOf('/no') !== -1);
  const refused = named.filter(function (w) { return words.indexOf(w) === -1; });
  yes('every command the page names is one everybody may use' +
      (refused.length ? ' (not: ' + refused.join(', ') + ')' : ''), refused.length === 0);

  yes('/party on its own answers with who is in yours',
      /\/party on its own/.test(text) &&
      src.indexOf("word === '/party' && (rest === '' || rest === 'list')") !== -1);
  yes('/party leave takes you out',
      /\/party leave/.test(text) &&
      src.indexOf("word === '/party' && rest === 'leave'") !== -1);
}

// --------------------------------------------------------------- the panel
{
  const p = code(panel);
  yes('the P panel has the Ask to party button the page names',
      /Ask to party beside a friend who is online/.test(text) &&
      /f\.on && !f\.party \? '<button data-do="ask"/.test(p) &&
      /verb === 'ask'\) \{ net\('\/party ' \+ who\); \}/.test(p));
  yes('and the Yes and No buttons for an ask',
      /press Yes or No on their own P panel/.test(text) &&
      p.indexOf('data-do="yes">Yes</button>') !== -1 &&
      p.indexOf('data-do="no">No</button>') !== -1);
}

// --------------------------------------------------- finding your party
{
  const f = front;
  yes('names in green: the plugin colours party members\' name tags',
      /name in green above their head/.test(text) &&
      /sp\.setTextColor\(textId, PARTY_COLOUR\)/.test(f));
  yes('a map marker you cannot fast travel to',
      /a marker on your map/.test(text) && /cannot fast travel/.test(text) &&
      /ref\.addToMap\(false\)/.test(f));
  yes('the strip: green for the same place, gold for somewhere else',
      /Green on the strip means the same place as you, gold means somewhere else/.test(text) &&
      /sameRoom \? '#9fcf92' : '#e9d19b'/.test(code(panel)));
}

// ------------------------------------------------ run the real party block
/*
  Over a fake mp and a fake clock, the way test-social.js does, so the page's
  sentences are checked against what the block does and not only against the
  numbers in its table.
*/
if (social) {
  const store = {};
  const clock = { now: 1700000000000 };
  const g = {};
  const mp = {
    makeProperty: function () { },
    get: function (id, key) {
      if (id === 0 && key === 'onlinePlayers') {
        return Object.keys(store).filter(function (k) { return store[k].here; }).map(Number);
      }
      const row = store[id];
      return row ? row[key] : undefined;
    },
    set: function (id, key, v) {
      if (!store[id]) { store[id] = {}; }
      store[id][key] = v;
    }
  };
  new Function(
    'globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
    'guard', 'say', 'notify', 'Math', 'Number', 'String', 'Object', 'Array',
    'JSON', 'isFinite', 'parseInt',
    social)(
    g, mp, { now: function () { return clock.now; } },
    { log: function () { } },
    function () { return 1; }, function () { },
    function (n, fn) { return fn; },
    function () { }, function () { },
    Math, Number, String, Object, Array, JSON, isFinite, parseInt);
  const soc = g.__thornswoodSocial;
  yes('the social block runs', !!soc);

  if (soc) {
    const people = [];
    for (let i = 0; i <= CAP; i++) {
      const id = 0xff000001 + i;
      store[id] = { here: true, profileId: 101 + i, appearance: { name: 'P' + i },
                    worldOrCellDesc: 'inn:X.esm', pos: [0, 0, 0] };
      people.push(id);
    }
    const pid = function (id) { return soc.profileOf(id); };

    // An ask stands for as long as the page says, and not a moment longer.
    soc.offer('party', people[0], people[1]);
    clock.now += LAPSE * 1000;
    yes('an ask still stands at ' + LAPSE + ' seconds', !!soc.standingOffer(pid(people[1])));
    clock.now += 1;
    yes('and has lapsed a moment after', !soc.standingOffer(pid(people[1])));

    let refusedAt = -1;
    for (let j = 1; j < people.length; j++) {
      const why = soc.joinParty(pid(people[0]), pid(people[j]));
      if (why && refusedAt === -1) { refusedAt = j; }
    }
    const p = soc.partyOf(pid(people[0]));
    yes('a party holds ' + spoken(CAP), !!p && p.members.length === CAP);
    yes('and the next person asked is turned away', refusedAt === CAP);

    // The same place: work counts the bonus more. Somewhere else: it does not.
    yes('work done with your party in the same place counts ' + BONUS + ' per cent more',
        Math.round((soc.workBonus(people[0]) - 1) * 100) === BONUS);
    for (let k = 1; k < CAP; k++) { store[people[k]].worldOrCellDesc = 'field:X.esm'; }
    yes('and with nobody from it in the same place it counts the same as alone',
        soc.workBonus(people[0]) === 1);

    // /party leave, and logging out, both take you out.
    yes('leaving takes you out', soc.leaveParty(pid(people[1])) === true &&
        !soc.partyOf(pid(people[1])));
    store[people[2]].here = false;
    soc.tick();
    yes('logging out takes you out too', !soc.partyOf(pid(people[2])) &&
        !!soc.partyOf(pid(people[0])));
  }
}

// ---------------------------------------------------------------- the words
{
  yes('the party items never say player', !/\bplayers?\b/i.test(text));
  yes('and have no em dash in them', text.indexOf(String.fromCharCode(0x2014)) === -1);
  yes('Help.cs uses no string interpolation, which C# 5 does not have',
      helpCs.indexOf('$"') === -1);
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
