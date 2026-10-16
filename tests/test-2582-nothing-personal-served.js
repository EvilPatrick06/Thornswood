/*
  test-2582-nothing-personal-served.js

  Issue #2582, 16 Oct. The resources port of each game server (3000 live,
  7788 dev) hands anything under the server's data folder to anybody who
  asks. That morning last-left.json answered 200 on both, a profile id and
  the moment it last left for every character (3 on live, 43 on dev), and
  books.json, which names every member of a book, was written to the same
  folder. #541 had moved the property register, the farm claims and the door
  list out of data for the same reason on 25 Sep; the books came later and
  were written against data.

  Three checks:

  1. Every file the game server's code names under its data folder is one of
     the files below, each read and found to hold nobody (what it holds is
     written beside it), or a name kept in private whose data copy is only
     ever taken out. A new file under data fails here until somebody has
     looked at what it holds and added it with the reason. A planted file
     proves the scan sees one.
  2. The real books (thornswoodBooks and its start, out of game/gamemode.js)
     keep books.json and last-left.json in the private folder and write
     nothing under data.
  3. The start removes the copies an older gamemode left in data.
*/
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const GAME = process.env.GAME_DIR || path.join(ROOT, 'game');
const CR = String.fromCharCode(13);
const read = f => fs.readFileSync(f, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond, more) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what + (more ? ': ' + more : '')); }
}

// ---- 1. what the code names under data

// Read on 16 Oct over HTTP from One, shapes only, on both ports.
const PUBLIC = {
  'thornswood-log.json': 'whether the gamemode log works and when: { ok, at }',
  'server-bases.json': 'the server handled base form ids for the client: { at, bases }',
  'online.json': 'how many are on and the queue: { now, at, restarting, max, line, full }, no names (the names go to private, #520)',
  'manifest.json': 'the load order the client checks against',
  'api': 'api/servers/thornswood: the published manifest and Thornswood\'s own plugins, nothing about anybody',
  'restart.json': 'the drop box Ship writes a restart request into; read and deleted, never written by the gamemode',
};
// Shipped with the gamemode from game\data in the repository, read only.
const SHIPPED = {
  'guild-sites.json': 'the ten guild sites, from the repository',
  'merchant-traders.json': 'the merchant table, from the repository',
};
// Kept in private. The data copy an older gamemode wrote is only taken out.
const TAKEN_OUT = ['farm-claims.json', 'property.json'];
// Not a literal name: the books start walks this list to take the old copies out.
const TAKEN_OUT_LIST = /var served = \[('[^']+'(?:, '[^']+')*)\];\s*for \(var si = 0; si < served\.length; si\+\+\) \{\s*var old = path\.join\(dataDir, served\[si\]\);\s*if \(fs\.existsSync\(old\)\) \{\s*fs\.unlinkSync\(old\);/;

function scan(text) {
  const out = [];
  const lines = text.split('\n');
  const join = /join\(\s*(?:String\()?[A-Za-z_.]*[dD]ataDir[A-Za-z]*\)?\s*,\s*([^)]*)\)/g;
  const literal = /['"]data\/([^'"]+)['"]/g;
  const shipped = /join\(\s*[A-Za-z_]+\s*,\s*'data'\s*,\s*'([^']+)'\s*\)/g;
  lines.forEach((line, i) => {
    let m;
    while ((m = join.exec(line))) {
      const arg = m[1].trim();
      const lit = /^'([^']+)'/.exec(arg);
      out.push({ line: i + 1, text: line.trim(), name: lit ? lit[1] : null, expr: lit ? null : arg, kind: 'data' });
    }
    while ((m = literal.exec(line))) out.push({ line: i + 1, text: line.trim(), name: m[1], kind: 'data' });
    while ((m = shipped.exec(line))) out.push({ line: i + 1, text: line.trim(), name: m[1], kind: 'shipped' });
  });
  return out;
}

function judge(text) {
  const bad = [];
  const seen = [];
  const takenOut = new Set(TAKEN_OUT);
  const list = TAKEN_OUT_LIST.exec(text);
  const listed = list ? list[1].split(',').map(s => s.trim().replace(/'/g, '')) : [];
  for (const hit of scan(text)) {
    if (hit.kind === 'shipped') {
      if (!SHIPPED[hit.name]) bad.push('line ' + hit.line + ' reads ' + hit.name + ' beside the gamemode, not in the shipped list');
      continue;
    }
    if (hit.name === null) {
      if (hit.expr === 'served[si]' && list) continue;
      bad.push('line ' + hit.line + ' names something under data this check cannot read: ' + hit.text);
      continue;
    }
    if (PUBLIC[hit.name]) continue;
    if (takenOut.has(hit.name) && /^var from = /.test(hit.text)) { seen.push(hit.name); continue; }
    bad.push('line ' + hit.line + ' keeps ' + hit.name + ' under data');
  }
  for (const name of seen.concat(listed)) {
    const kept = new RegExp("join\\(\\s*privDir\\s*,\\s*'" + name.replace(/\./g, '\\.') + "'").test(text);
    if (!kept) bad.push(name + ' is taken out of data but not kept in private');
  }
  return { bad, listed };
}

const files = fs.readdirSync(GAME).filter(f => /\.js$/.test(f)).map(f => path.join(GAME, f));
yes('the game server code is found', files.some(f => /gamemode\.js$/.test(f)) && files.length > 1, files.length + ' files');
const gm = read(path.join(GAME, 'gamemode.js'));
let allBad = [];
for (const f of files) {
  const r = judge(read(f));
  allBad = allBad.concat(r.bad.map(b => path.basename(f) + ' ' + b));
}
yes('every file the game server names under data is one read and found to hold nobody', allBad.length === 0, allBad.join('; '));
const gmJudge = judge(gm);
yes('the books start takes books.json and last-left.json out of data',
    gmJudge.listed.indexOf('books.json') >= 0 && gmJudge.listed.indexOf('last-left.json') >= 0, gmJudge.listed.join(', '));

// The scan sees a file somebody adds under data.
const planted = gm + "\nfs.writeFileSync(path.join(dataDir, 'who-was-on.json'), JSON.stringify(seen));\n";
yes('a planted file naming people under data is caught', judge(planted).bad.some(b => /who-was-on\.json/.test(b)));
const planted2 = gm.replace("function booksFile() { return path.join(privDir, 'books.json'); }",
                            "function booksFile() { return path.join(dataDir, 'books.json'); }");
yes('the books file moved back to data is caught', planted2 !== gm && judge(planted2).bad.some(b => /books\.json/.test(b)));
const planted3 = gm + "\nvar f = path.join(dataDir, name);\n";
yes('a name under data the scan cannot read is caught', judge(planted3).bad.some(b => /cannot read/.test(b)));

// ---- 2 and 3. the real books, against a real folder

const start = gm.indexOf('/* BOOKS-START */');
const end = gm.indexOf('/* BOOKS-END */');
const block = gm.slice(start, end);
const initStart = gm.indexOf('(function () {', end);
const initializer = gm.slice(initStart, gm.indexOf('})();', initStart) + 5);
yes('the book block and its start are in gamemode.js', start > 0 && end > start && initStart > end);

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tw-2582-'));
try {
  const dataDir = path.join(tmp, 'data');
  const privDir = path.join(tmp, 'private');
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'last-left.json'), '{"101":1790000000000}');
  fs.writeFileSync(path.join(dataDir, 'books.json'), '{"books":[],"ledgers":{}}');
  fs.writeFileSync(path.join(dataDir, 'online.json'), '{"now":0}');

  const io = Object.create(fs);
  io.readFileSync = (f, ...a) => f === 'server-settings.json'
    ? JSON.stringify({ dataDir: dataDir, privDir: privDir }) : fs.readFileSync(f, ...a);
  const logged = [];
  const online = { 1: 'Ada', 2: 'Ben' };
  const box = {
    require: n => n === 'fs' ? io : path,
    log: (...a) => logged.push(a.join(' ')),
    setInterval: () => 7, clearInterval: () => { },
    mp: { get: (id, k) => k === 'onlinePlayers' ? Object.keys(online).map(Number) : (k === 'profileId' ? id : null) },
    __thornswoodSocial: {
      profileOf: id => id, nameOfPerson: id => online[id] || 'somebody',
      findPerson: () => ({ actorId: 2, why: '' }), push: () => { }
    },
    __thornswoodBookRoles: pid => ({ business: true, faction: true, account: 'a' + pid })
  };
  box.globalThis = box;
  vm.createContext(box);
  vm.runInContext(block + '\n' + initializer, box, { filename: 'books.js' });
  const api = box.__thornswoodBooks;
  yes('the books start with the old data copies there', !!api, logged.join(' | '));
  yes('the old last-left.json and books.json in data are gone', !fs.existsSync(path.join(dataDir, 'last-left.json')) && !fs.existsSync(path.join(dataDir, 'books.json')));
  yes('  and saying so in the log', logged.filter(l => /removed .*served to anybody/.test(l)).length === 2, logged.join(' | '));
  yes('  and nothing that is not theirs is touched', fs.existsSync(path.join(dataDir, 'online.json')));
  yes('  and nothing of the old copy is carried into private', !fs.existsSync(path.join(privDir, 'last-left.json')));

  api.noteTick();           // the first tick only notes who is on
  delete online[2];
  api.noteTick();           // Ben left
  const left = path.join(privDir, 'last-left.json');
  yes('when somebody leaves, last-left.json is written in private', fs.existsSync(left));
  let doc = null; try { doc = JSON.parse(fs.readFileSync(left, 'utf8')); } catch (e) { }
  yes('  with the profile that left', !!doc && Number(doc[2]) > 0 && doc[1] === undefined);

  const reply = api.command({ actorId: 1, profileId: 1, parts: ['/book', 'new', 'business', 'Ore'] });
  yes('a new book is saved in private', fs.existsSync(path.join(privDir, 'books.json')), String(reply));
  yes('nothing about anybody is written under data', fs.readdirSync(dataDir).join(',') === 'online.json', fs.readdirSync(dataDir).join(','));

  // A start whose old copy cannot be removed does not run with it still served.
  fs.writeFileSync(path.join(dataDir, 'last-left.json'), '{}');
  const stuck = Object.create(io);
  stuck.unlinkSync = () => { const e = new Error('EPERM: operation not permitted'); e.code = 'EPERM'; throw e; };
  const box2 = Object.assign({}, box, { require: n => n === 'fs' ? stuck : path, __thornswoodBooks: null });
  box2.globalThis = box2;
  const said = [];
  box2.log = (...a) => said.push(a.join(' '));
  vm.createContext(box2);
  vm.runInContext(block + '\n' + initializer, box2, { filename: 'books.js' });
  yes('an old copy that cannot be removed stops the books, with the reason in the log',
      box2.__thornswoodBooks === null && said.some(l => /^books: .*EPERM/.test(l)), said.join(' | '));
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
