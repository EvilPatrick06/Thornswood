// test-ownership.js
//
// docs/OWNERSHIP.md names every credential file the scripts and the launcher
// use, and every row in it has a second holder.
//
// WHY THIS EXISTS. The To Do List entry "Five things exist only on your laptop
// or in your head" asked for one page naming, for each asset, where it lives,
// who holds it, who the second holder is, and how to reissue it. Its done-when
// is that every row has a second holder or an explicit "nobody yet", and that
// every secret-bearing file named in scripts\<area>\*.ps1 and launcher\app\Config.cs
// appears in the table, "checked by grepping for the file names rather than by
// reading". This is that grep, so the page cannot quietly fall behind the
// scripts.
//
// What it measured when it was written, 24 September: the secrets table in
// Developer-Guide.md had seven rows and no row for signing.json,
// dev-webhook.txt, the backup passphrase, token-key.txt, server-secret.txt or
// the launcher's UpdateToken, all of which the scripts name.
//
// It also checks the page carries nothing that looks like a value, because a
// page listing where every secret lives is the one page a pasted secret would
// hurt most on.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

const REPO = REPO_DIR;
const ROOT = REPO;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function read(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch (e) { return ''; }
}

const page = read(path.join(REPO, 'docs', 'OWNERSHIP.md'));
yes('docs/OWNERSHIP.md exists', page.length > 0);

// ------------------------------------------------------------ the table --
const HEADER = ['asset', 'where it lives', 'who holds it', 'second holder', 'how to reissue'];

function cells(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map(function (c) { return c.trim(); });
}

const rows = [];
let tables = 0;
let inTable = false;
page.split(/\r?\n/).forEach(function (line) {
  const t = line.trim();
  if (!t.startsWith('|')) { inTable = false; return; }
  const c = cells(t);
  if (c.length === HEADER.length &&
      c.every(function (x, i) { return x.toLowerCase() === HEADER[i]; })) {
    inTable = true; tables++; return;
  }
  if (!inTable) return;
  if (c.every(function (x) { return /^:?-{3,}:?$/.test(x); })) return;
  rows.push(c);
});

yes('the page has a table headed ' + HEADER.join(' | '), tables >= 1);
yes('the table has rows, ' + rows.length + ' of them', rows.length >= 10);

const short = rows.filter(function (r) { return r.length !== HEADER.length || r.some(function (x) { return !x; }); });
short.forEach(function (r) { console.log('      incomplete row: ' + r[0]); });
yes('every row fills all five columns', rows.length > 0 && short.length === 0);

// "Every row has a second holder or an explicit nobody yet." A dash, a
// question mark or a TBD is a row that was left for later.
const PLACEHOLDER = /^(\?+|-+|tbd|todo|n\/a|none|unknown|x)$/i;
const noSecond = rows.filter(function (r) { return !r[3] || PLACEHOLDER.test(r[3]); });
noSecond.forEach(function (r) { console.log('      no second holder: ' + r[0]); });
yes('every row names a second holder or says nobody yet', rows.length > 0 && noSecond.length === 0);

const tableText = rows.map(function (r) { return r.join(' | '); }).join('\n');

// A name appears on its own, not as the tail of a longer one: key.txt has to
// be there in its own right, not just inside token-key.txt.
function named(text, name) {
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp('(^|[^A-Za-z0-9_.-])' + esc + '(?![A-Za-z0-9_-])', 'i').test(text);
}

// ------------------------------------------------------- the five things --
// The entry never names them, which is what made it hard to pick up cold.
const five = [
  ['the SkyMP fork and its build tree', /skymp fork/i],
  ['the publish baseline', /publish baseline/i],
  ['the #news webhook', /#news webhook/i],
  ['the update token in config.json', /update token/i],
  ['the collection', /\bcollection\b/i]
];
const fiveAt = page.search(/^## The five things/m);
const tableAt = page.search(/^## The table/m);
const fiveText = fiveAt >= 0 ? page.slice(fiveAt, tableAt > fiveAt ? tableAt : undefined) : '';
yes('the page names the five things before the table', fiveAt >= 0 && tableAt > fiveAt);
five.forEach(function (f) {
  yes('the five things include ' + f[0], f[1].test(fiveText));
  yes('and the table has a row for it', rows.some(function (r) { return f[1].test(r[0]); }));
});

// ------------------------------------------- every credential file named --
// Every file name in the scripts and the launcher that sounds like it could
// hold a credential. The list of words is wide on purpose: a name it catches
// that is not a secret goes in NOT_SECRET below with the reason, which is
// cheaper than a secret it misses.
const WORDS = 'webhook|token|secret|key|signing|door|bot\\.env|config|password|passphrase|published|ticket|auth|cred|owners|metadata|discord';
const NAME = new RegExp('[A-Za-z0-9_.-]*(' + WORDS + ')[A-Za-z0-9_.-]*\\.(txt|json|env|pfx|pem|key|js|dat)\\b', 'gi');

// Caught by the words above and not a credential. Each says why.
const NOT_SECRET = {
  'cbpconfig.txt': 'CBP physics settings, a mod\'s own config file',
  'cbpcollisionconfig.txt': 'CBP physics collision settings, the same',
  'config.txt': 'SkyUI\'s settings in the game folder',
  'config.shipped.txt': 'the launcher\'s copy of SkyUI\'s settings as they shipped',
  'door.txt': 'the launcher\'s last yes or no from the site and when, no key in it',
  'discord-name.txt': 'the Discord display name the launcher shows',
  'discord-avatar.txt': 'the Discord avatar hash the launcher shows, the public part of a cdn.discordapp.com address and no key in it',
  'check-secrets.allow.txt': 'the secret scan\'s list of known non-secrets, paths and rule names only',
  'discord-webhook.txt': 'a made-up file test-check-secrets.ps1 writes in its own temp folder to prove the scan catches a webhook',
  'github-token.txt': 'the same, for a GitHub token',
  'test-turn-key.js': 'the voice service\'s harness for the relay key, named by test-voice-turn-url.ps1; it holds no key',
  'open-tickets.json': 'the bot\'s record of which thread is each person\'s open ticket, named by Bot-Service.ps1 when it moves the bot\'s records into data; no key in it',
  'config.js': 'the fork front\'s webpack output folder, which Build-Front.ps1 writes into its own scratch copy of skymp5-front; it holds the path ./dist and nothing else'
};

const sources = [];
function addDir(dir, ext) {
  let list = [];
  try { list = fs.readdirSync(dir); } catch (e) { return; }
  list.filter(function (f) { return f.toLowerCase().endsWith(ext); }).sort().forEach(function (f) {
    sources.push(path.join(dir, f));
  });
}
// The scripts are in scripts\<area> since phase 8 of issue #440.
['release', 'deploy', 'vps', 'ops', 'mods', 'dev'].forEach(function (a) { addDir(path.join(REPO, 'scripts', a), '.ps1'); });
addDir(path.join(REPO, 'launcher', 'app'), '.cs');
yes('there are scripts and launcher sources to read, ' + sources.length + ' of them', sources.length > 50);

const found = {};
sources.forEach(function (f) {
  const text = read(f);
  let m;
  NAME.lastIndex = 0;
  while ((m = NAME.exec(text)) !== null) {
    const n = m[0].replace(/^[.-]+/, '');
    const k = n.toLowerCase();
    if (!found[k]) found[k] = { name: n, where: path.relative(ROOT, f) };
  }
});
const names = Object.keys(found).sort();
yes('the scan finds the webhook files, so it is not reading nothing', !!found['news-webhook.txt'] && !!found['dev-webhook.txt']);
yes('the scan finds ' + names.length + ' names that could be credentials', names.length >= 15);

const missing = names.filter(function (k) { return !NOT_SECRET[k] && !named(tableText, found[k].name); });
missing.forEach(function (k) { console.log('      not in the table: ' + found[k].name + '  (named in ' + found[k].where + ')'); });
yes('every credential file the scripts and the launcher name is in the table', missing.length === 0);

// The launcher's own config: any field whose name says it is a secret.
const configCs = read(path.join(REPO, 'launcher', 'app', 'Config.cs'));
const FIELD = /\[DataMember[^\]]*\]\s*public\s+[\w?<>]+\s+(\w*(?:token|password|secret|key)\w*)\b/gi;
const fields = [];
let fm;
while ((fm = FIELD.exec(configCs)) !== null) fields.push(fm[1]);
yes('Config.cs has secret-named fields to check, ' + fields.join(', '), fields.length >= 1);
const missingFields = fields.filter(function (f) { return !named(tableText, f); });
missingFields.forEach(function (f) { console.log('      Config.cs field not in the table: ' + f); });
yes('every secret-named field in Config.cs is in the table', fields.length > 0 && missingFields.length === 0);

// ---------------------------------------------------------- no values --
const VALUE = [
  ['a Discord webhook address', /discord(app)?\.com\/api\/webhooks\//i],
  ['a GitHub token', /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}/],
  ['a Discord bot token', /[MNO][A-Za-z\d_-]{23,}\.[\w-]{6}\.[\w-]{27,}/],
  ['a long run of key-like characters', /[A-Za-z0-9+=_-]{32,}/]
];
VALUE.forEach(function (v) {
  const m = page.match(v[1]);
  if (m) console.log('      looks like ' + v[0] + ' at offset ' + page.indexOf(m[0]) + ' (not printed)');
  yes('the page carries nothing that looks like ' + v[0], !m);
});

// ------------------------------------------------------------ the words --
yes('the page has no em dash', page.indexOf('—') < 0);
yes('the page never says player', !/\bplayers?\b/i.test(page));

// ------------------------------------------------ Developer-Guide.md --
// It said the fork and its build tree were Patrick's alone. The fork is on
// GitHub; only the configured build and its toolchain are on one disk.
const second = read(path.join(ROOT, 'Developer-Guide.md'));
yes('Developer-Guide.md is there to read', second.length > 0);
yes('Developer-Guide.md no longer says the fork is Patrick\'s alone',
    !/fork and its build tree are Patrick's alone/i.test(second));
yes('Developer-Guide.md says the fork source is on GitHub',
    /github\.com\/EvilPatrick06\/skymp/i.test(second));
yes('Developer-Guide.md points at docs\\OWNERSHIP.md', /docs\\OWNERSHIP\.md/.test(second));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
