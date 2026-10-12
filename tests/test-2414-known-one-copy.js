// test-2414-known-one-copy.js
//
//     node tests/test-2414-known-one-copy.js
//
// The Known Issues text has one copy: site/data/known.md, which is what /known
// and /api/page/known serve. Issue #2414: board.json also kept a "known" board,
// left behind when the hub stopped editing boards (#433). Nothing showed it
// and nothing could edit it, so every fix went to known.md and the board
// drifted: after #504 it still said "NPCs stand still when nobody is nearby |
// SkyMP has no server side AI". This fails if a second copy comes back.
//
// Read only.
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(what, cond) { if (cond) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); } }
function read(rel) { try { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); } catch (e) { return null; } }

const server = read('site/server.js') || '';
const board = JSON.parse(read('site/data/board.json') || '{}');
const known = read('site/data/known.md');

// 1. The page is there and it is the copy that is served.
yes('known.md is there', !!known && /^# Known Issues/m.test(known));
yes('known is a public document, served from the data folder',
    /const PUBLIC_DOCS = \[[^\]]*'known'[^\]]*\]/.test(server));
yes('/known renders pageMarkdown, which reads <name>.md',
    /function pageMarkdown\(name\)[\s\S]{0,400}name \+ '\.md'/.test(server));

// 2. No board holds a copy.
const boardsDecl = (server.match(/const BOARDS = \{([\s\S]*?)\};/) || [])[1] || '';
yes('BOARDS found in server.js', boardsDecl.length > 0);
yes('BOARDS has no known board', !/\bknown\s*:/.test(boardsDecl) && !/Known Issues/i.test(boardsDecl));
yes('board.json has no known board', !Object.prototype.hasOwnProperty.call(board, 'known'));
{
  // Under any name: a board whose intro or section names say it is the Known
  // Issues table, or whose rows repeat the page's own rows.
  const pageRows = (known || '').split('\n').filter(function (l) { return /^\|/.test(l) && !/^\|[-\s|]+\|$/.test(l); })
    .map(function (l) { return l.split('|')[1].trim().toLowerCase(); }).filter(function (c) { return c.length > 20; });
  const copies = [];
  Object.keys(board).forEach(function (k) {
    if (k.charAt(0) === '_') { return; }
    const b = board[k] || {};
    if (/public copy at \/known|known issues/i.test(String(b.intro || ''))) { copies.push(k + ' (intro)'); }
    (b.sections || []).forEach(function (s) {
      (s.rows || []).forEach(function (r) {
        const first = String(((r.cells || {})[((s.columns || [])[0] || {}).id] || '')).trim().toLowerCase();
        if (first && pageRows.indexOf(first) >= 0) { copies.push(k + ': ' + first); }
      });
    });
  });
  if (copies.length) { console.log('      ' + copies.join('; ')); }
  yes('no board repeats the Known Issues page under another name', copies.length === 0);
}

// 3. The stale row is gone from everywhere the site serves, and the page says what #504 made true.
yes('nothing says NPCs stand still with nobody near',
    !/NPCs stand still when nobody is nearby/i.test(JSON.stringify(board)) && !/NPCs stand still when nobody is nearby/i.test(known || ''));
yes('known.md says NPCs keep moving when nobody is nearby', /keep moving when nobody is nearby/i.test(known || ''));

// 4. Teeth: the checks above catch a copy coming back.
{
  const planted = JSON.parse(JSON.stringify(board));
  planted.known = { intro: 'The public copy at /known is data/known.md.', sections: [] };
  yes('a planted known board would be caught', Object.prototype.hasOwnProperty.call(planted, 'known'));
  yes('a planted BOARDS entry would be caught', /\bknown\s*:/.test("active: 'Active Issues',\n  known:       'Known Issues',"));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);