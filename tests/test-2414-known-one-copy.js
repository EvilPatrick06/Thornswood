// test-2414-known-one-copy.js
//
//     node tests/test-2414-known-one-copy.js
//
// The Known Issues text has one copy: the "known" board in
// site/data/board.json, which the hub edits at /hub/known, and which /known
// and /api/page/known write out through knownMarkdown in site/server.js.
//
// Issue #2414: the text was kept twice, site/data/known.md for the page and a
// known board that nothing showed and, after the hub stopped editing boards
// (#433), nothing could edit. The board went stale: after #504 it still said
// "NPCs stand still when nobody is nearby | SkyMP has no server side AI".
// #2415 kept the file and deleted the board; Patrick decided on 12 October
// that the hub board is the one source, so the board came back, seeded from
// known.md as it stood (with #504's wording), and known.md went.
//
// This fails if a second copy comes back, if the page stops being the board,
// or if the hub can no longer edit it. It also runs the page writer on planted
// boards, and the step Deploy-Docs -Board runs on the box on planted files.
//
// Read only, apart from a scratch folder it removes.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const { knownPage, knownWriter } = require('./fixtures/known-page');

const ROOT = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(what, cond) { if (cond) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); } }
function read(rel) { try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').replace(/\r\n/g, '\n'); } catch (e) { return null; } }

const server = read('site/server.js') || '';
const hub = read('site/public/hub.js') || '';
const deploy = read('scripts/deploy/Deploy-Docs.ps1') || '';
const board = JSON.parse(read('site/data/board.json') || '{}');
const page = knownPage();

// 1. The board is the copy, and the page is the board.
yes('there is no site/data/known.md', read('site/data/known.md') === null);
const boardsDecl = (server.match(/const BOARDS = \{([\s\S]*?)\};/) || [])[1] || '';
yes('BOARDS has the Known Issues board', /\bknown:\s*'Known Issues'/.test(boardsDecl));
yes('board.json has the known board, with sections', !!board.known && Array.isArray(board.known.sections) && board.known.sections.length > 0);
yes('known is no longer a document read off the disk',
    !/const PUBLIC_DOCS = \[[^\]]*'known'[^\]]*\]/.test(server));
yes('pageMarkdown writes /known out of the board through knownMarkdown',
    /function pageMarkdown\(name\) \{\s*if \(name === 'known'\) \{[\s\S]{0,200}readBoard\(\)\.known[\s\S]{0,200}knownMarkdown\(BOARDS\.known, b\)/.test(server));
yes('the writer sits between its markers in server.js', !!knownWriter(server));
yes('the page is there and starts with its title', !!page && /^# Known Issues\n/.test(page));

// 2. The hub edits it.
yes('the hub edits the known board', /var BOARDKEYS = \['known'\];/.test(hub));
yes('at /hub/known, in the hub and in the server', /'\/hub\/known':\s*'known'/.test(hub) && /'\/hub\/known':\s*'known'/.test(server));
yes('as an admin page, since a board is saved through the admins-only door',
    /const LEVEL = \{[\s\S]*?known:\s*'admin'[\s\S]*?\};/.test(server));
yes('its intro and section notes can be changed there too, not only its cells',
    /data-intro=/.test(hub) && /data-note=/.test(hub) && /function openText\(k, holder, was, put\)/.test(hub));

// 3. No second copy under any name.
{
  const rowsOf = (md) => (md || '').split('\n').filter((l) => /^\|/.test(l) && !/^\|[-\s|]+\|$/.test(l))
    .map((l) => l.split('|')[1].trim().toLowerCase()).filter((c) => c.length > 20);
  const pageRows = rowsOf(page);
  const copies = [];
  Object.keys(board).forEach(function (k) {
    if (k === 'known' || k.charAt(0) === '_') { return; }
    const b = board[k] || {};
    if (/known issues/i.test(String(b.intro || ''))) { copies.push(k + ' (intro)'); }
    (b.sections || []).forEach(function (s) {
      (s.rows || []).forEach(function (r) {
        const first = String(((r.cells || {})[((s.columns || [])[0] || {}).id] || '')).trim().toLowerCase();
        if (first && pageRows.indexOf(first) >= 0) { copies.push(k + ': ' + first); }
      });
    });
  });
  fs.readdirSync(path.join(ROOT, 'site', 'data')).filter((f) => /\.md$/.test(f)).forEach(function (f) {
    const t = read('site/data/' + f) || '';
    if (/^# Known Issues/m.test(t) || rowsOf(t).some((r) => pageRows.indexOf(r) >= 0)) { copies.push('site/data/' + f); }
  });
  if (copies.length) { console.log('      ' + copies.join('; ')); }
  yes('no other board and no document repeats the Known Issues page', pageRows.length > 0 && copies.length === 0);
}

// 4. The stale row is gone, and the page says what #504 made true.
yes('nothing says NPCs stand still with nobody near',
    !/NPCs stand still when nobody is nearby/i.test(JSON.stringify(board)) && !/NPCs stand still when nobody is nearby/i.test(page || ''));
yes('the page says NPCs keep moving when nobody is nearby', /keep moving when nobody is nearby/i.test(page || ''));

// 5. The writer, on planted boards.
{
  const w = knownWriter(server) || function () { return ''; };
  const one = (sec) => w('Known Issues', { intro: 'Hello.', sections: [sec] });
  const cols = [{ id: 'a', name: 'Behaviour' }, { id: 'b', name: 'Reason' }];
  yes('an empty board is the title alone', w('Known Issues', {}) === '# Known Issues\n');
  yes('a section is its heading, note and table',
      one({ name: 'S', note: 'A note.', columns: cols, rows: [{ id: 'r', cells: { a: 'x', b: 'y' } }] }) ===
      '# Known Issues\n\nHello.\n\n## S\n\nA note.\n\n| Behaviour | Reason |\n|---|---|\n| x | y |\n');
  yes('a row ticked done in the hub leaves the page',
      one({ name: 'S', note: '', columns: cols, rows: [{ id: 'r', done: true, cells: { a: 'fixed', b: 'y' } }, { id: 's', cells: { a: 'open', b: 'z' } }] })
        .indexOf('fixed') < 0);
  yes('a section with no note and every row done is left out',
      one({ name: 'Gone', note: '', columns: cols, rows: [{ id: 'r', done: true, cells: { a: 'x', b: 'y' } }] }) === '# Known Issues\n\nHello.\n');
  yes('a section of prose alone has no table',
      one({ name: 'P', note: 'Only words.', columns: [], rows: [] }) === '# Known Issues\n\nHello.\n\n## P\n\nOnly words.\n');
  yes('a | typed into a cell cannot split the table, and a line break in a cell is a space',
      one({ name: 'S', note: '', columns: cols, rows: [{ id: 'r', cells: { a: 'one | two', b: 'first\nsecond' } }] })
        .indexOf('| one \\| two | first second |') >= 0);
}

// 6. Deploy-Docs puts the board on the box: once by itself, then as typed.
yes('the repo\'s known board carries the seeded mark Deploy-Docs looks for', board.known && board.known.seeded === '2414');
yes('Deploy-Docs takes -Board', /\[string\[\]\]\$Board,/.test(deploy));
yes('and refuses it beside -Boards or -SeedDocs', /if \(\$Board -and \(\$Boards -or \$SeedDocs\)\) \{\s*throw/.test(deploy));
yes('every plain deploy asks for the boards the repo marks seeded',
    /\$bp\.Value\.PSObject\.Properties\.Name -contains 'seeded'\) \{ \$seedNames \+= \$bp\.Name \}/.test(deploy) &&
    /\$boardArgs = @\(\$boardNames \| ForEach-Object \{ \$_ \+ '=force' \}\) \+ @\(\$seedNames \| ForEach-Object \{ \$_ \+ '=seed' \}\)/.test(deploy));
yes('the step on the box is plain ASCII, as Set-Content -Encoding ASCII writes it',
    /^[\x00-\x7F]*$/.test((/Set-Content -LiteralPath `\$js -Encoding ASCII -Value @'\n([\s\S]*?)\n'@/.exec(deploy) || [])[1] || String.fromCharCode(255)));
{
  const js = (/^(var fs = require\('fs'\);[\s\S]*?^\}\n)'@$/m.exec(deploy) || [])[1] || '';
  yes('the step it runs on the box is in the script', js.length > 0);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-2414-'));
  try {
    const step = path.join(tmp, 'step.js');
    fs.writeFileSync(step, js);
    const live = path.join(tmp, 'board.json'), repo = path.join(tmp, 'board.json.from-repo');
    const typed = { active: { intro: 'typed on the site', sections: [] }, known: { intro: 'stale', sections: [] }, _rev: { active: 4, known: 9 } };
    fs.writeFileSync(live, String.fromCharCode(0xFEFF) + JSON.stringify(typed, null, 2));
    fs.writeFileSync(repo, JSON.stringify({ active: { intro: 'the repo copy', sections: [] }, known: board.known }, null, 2));
    const run = (asks) => cp.spawnSync(process.execPath, [step, live, repo].concat(asks), { encoding: 'utf8' });
    const now = () => JSON.parse(fs.readFileSync(live, 'utf8'));

    let r = run(['known=seed']);
    let after = now();
    yes('a live board without the mark is seeded from the repo', r.status === 0 && JSON.stringify(after.known) === JSON.stringify(board.known));
    yes('every other board is left as it was typed', after.active.intro === 'typed on the site');
    yes('that board\'s revision moves on, and only that one', after._rev.known === 10 && after._rev.active === 4);
    yes('what was there is kept in board.json.bak', /"stale"/.test(fs.readFileSync(live + '.bak', 'utf8')));
    yes('and it says so', /BOARD REPLACED known, now at revision 10/.test(r.stdout));

    // Somebody edits it in the hub: the save keeps the mark.
    after.known.sections[0].rows.push({ id: 'typed', done: false, cells: {}, at: 1, by: 'a person' });
    fs.writeFileSync(live, JSON.stringify(after, null, 2));
    r = run(['known=seed']);
    yes('the next deploy finds it seeded and leaves what was typed', r.status === 0 && /BOARD KEPT known/.test(r.stdout) &&
        now().known.sections[0].rows.some((x) => x.id === 'typed') && now()._rev.known === 10);

    r = run(['known=force']);
    yes('-Board puts the repo copy in all the same', r.status === 0 && /BOARD REPLACED known, now at revision 11/.test(r.stdout) &&
        !now().known.sections[0].rows.some((x) => x.id === 'typed'));

    const before = fs.readFileSync(live, 'utf8');
    r = run(['nosuch=force']);
    yes('a board the repo does not have is refused, and the file is left alone',
        r.status !== 0 && /BOARD NOT REPLACED/.test(r.stdout) && fs.readFileSync(live, 'utf8') === before);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
