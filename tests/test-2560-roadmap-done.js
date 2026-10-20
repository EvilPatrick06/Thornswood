// test-2560-roadmap-done.js
//
// #2560: the public roadmap drifted from the board twice after #2561.
//   1. The #502 row still promised bounties, though #502 was rewritten on
//      12 Oct (no bounty at all) and #2472 removed the bounty system.
//   2. The Done rows #2561 added never reached /roadmap, because both
//      renderers (home.js and server.js's server-drawn page) skipped any
//      section named Done.
// This holds the data and both renderers. home.js's /roadmap branch is run
// against the real board, and server.js's /roadmap block is checked for any
// Done filter.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const root = path.join(__dirname, '..');
let fails = 0;
function yes(name, ok) { console.log((ok ? 'ok   ' : 'FAIL ') + name); if (!ok) fails++; }
const read = p => fs.readFileSync(path.join(root, p), 'utf8');

const board = JSON.parse(read('site/data/board.json'));
const rm = board.roadmap || { sections: [] };
const secs = rm.sections || [];
const titleOf = (sec, row) => (row.cells || {})[(sec.columns || [])[0] && sec.columns[0].id] || '';
const all = [];
secs.forEach(sec => (sec.rows || []).forEach(row => all.push({ sec, row, title: titleOf(sec, row) })));

// 1. The #502 row
const guards = all.find(x => /^Guards\b/.test(x.title));
yes('the #502 row is titled "Guards and cells run by people"', !!guards && guards.title === 'Guards and cells run by people');
yes('and it is in "Being built now"', !!guards && /being built now/i.test(guards.sec.name || ''));
const roadmapText = JSON.stringify(rm);
yes('no roadmap row or note mentions a bounty', !/bount/i.test(roadmapText));

// 2. Done is in the data, last, with #2561's rows
const done = secs.find(s => /^\s*done\s*$/i.test(s.name || ''));
yes('the roadmap has a Done section', !!done);
yes('Done is the last section', !!done && secs[secs.length - 1] === done);
const doneTitles = done ? done.rows.map(r => titleOf(done, r)) : [];
for (const t of ['Thinning the crowd', 'Parties', 'Voice through a relay', 'An economy with a bottom', 'Seasons', 'Gathering, fishing and mining', 'Speech you hear nearby']) {
  yes('Done carries "' + t + '"', doneTitles.includes(t));
}

// 3. home.js draws Done: run its /roadmap branch on the real board
const home = read('site/public/home.js');
const start = home.indexOf("} else if (here === '/roadmap') {");
const end = home.indexOf("} else if (here === '/news') {");
yes('home.js has its /roadmap branch', start > 0 && end > start);
let drawn = '';
if (start > 0 && end > start) {
  const branch = home.slice(start + "} else ".length, end);
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const thenable = v => ({ then(f) { try { return thenable(f(v)); } catch (e) { return thenable(undefined); } }, catch() { return this; } });
  const ctx = {
    here: '/roadmap', esc,
    request: () => thenable({ json: () => rm }),
    show: html => { drawn = html; }
  };
  vm.runInNewContext(branch + '}', ctx);
}
yes('home.js draws a Done lane', /<h2>Done<\/h2>/.test(drawn));
yes('home.js draws "Thinning the crowd"', drawn.includes('Thinning the crowd'));
yes('home.js draws Done after Later', drawn.indexOf('<h2>Later</h2>') >= 0 && drawn.indexOf('<h2>Done</h2>') > drawn.indexOf('<h2>Later</h2>'));
yes('home.js draws the guards row with no bounty', drawn.includes('Guards and cells run by people') && !/bount/i.test(drawn));

// 4. server.js's server-drawn /roadmap skips no Done section
const srv = read('site/server.js');
const s0 = srv.indexOf("} else if (route === '/roadmap') {");
const s1 = srv.indexOf("} else if (route === '/gallery') {", s0);
const block = s0 > 0 && s1 > s0 ? srv.slice(s0, s1) : '';
yes('server.js has its /roadmap block', !!block);
yes('server.js /roadmap does not skip a Done section', !!block && !/done/i.test(block.replace(/\/\/.*$/gm, '')));

console.log(fails ? fails + ' failed' : 'all passed');
process.exit(fails ? 1 : 0);
