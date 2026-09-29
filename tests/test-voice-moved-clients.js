// test-voice-moved-clients.js
//
// Issue #482: after the whole view on the first tick, the voice service sends
// { t: 'moved' } with only the rows that changed and the ids that left the
// view (gone), and nothing when nothing changed. A client that still replaced
// its table with each message would keep only the people who moved, and
// everybody standing still would fall silent.
//
// Each of the three clients is checked here: the launcher's voice page, the
// game's overlay (whose table the party strip reads too) and the plain
// browser page. The two that share a helper have it run; all three have to
// route 'moved' to it rather than to the replace. voice/test-moved.js checks
// the same thing against the real service. Read only.
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const CR = String.fromCharCode(13);
function read(rel) { return fs.readFileSync(path.join(__dirname, rel), 'utf8').split(CR).join(''); }

function helper(src, name) {
  // Up to the brace at the function's own indent, not the first inner one.
  const m = /^([ \t]*)function applyMoved\(table, m\) \{[\s\S]*?\n\1\}\n/m.exec(src);
  yes(name + ' has the helper', !!m);
  if (!m) { return null; }
  return new Function('Object', m[0] + '\nreturn applyMoved;')(Object);
}

function exercise(apply, name) {
  if (!apply) { return; }
  const table = {
    1: { pos: [0, 0, 0], angleZ: 0, cell: 'c', name: 'me' },
    2: { pos: [100, 0, 0], angleZ: 0, cell: 'c', name: 'still' },
    3: { pos: [200, 0, 0], angleZ: 0, cell: 'c', name: 'walker' },
    4: { pos: [300, 0, 0], angleZ: 0, cell: 'c', name: 'leaver' }
  };
  apply(table, { t: 'moved', at: 1, who: { 3: { pos: [210, 0, 0], angleZ: 5, cell: 'c', name: 'walker' },
                                           5: { pos: [50, 0, 0], angleZ: 0, cell: 'c', name: 'arrival' } },
                 gone: [4] });
  yes(name + ': somebody standing still is kept', !!table[2] && table[2].pos[0] === 100);
  yes(name + ': somebody who moved is where they moved to', table[3].pos[0] === 210 && table[3].angleZ === 5);
  yes(name + ': somebody new in range is added', !!table[5]);
  yes(name + ': somebody in gone is dropped', !table[4]);
  yes(name + ': and their own row is still there', !!table[1]);
}

const host = read('../launcher/voice-host.html');
exercise(helper(host, 'the launcher voice page'), 'the launcher voice page');
yes('the launcher voice page sends moved to the helper, not the replace',
    /if \(m\.t === 'moved'\) \{ applyMoved\(places, m\); place\(\); return; \}/.test(host));

const overlay = read('../game/ui/thornswood-voice.js');
exercise(helper(overlay, 'the game overlay'), 'the game overlay');
yes('the game overlay sends moved to the helper, and the party strip reads the same table',
    /if \(m\.t === 'moved'\) \{ applyMoved\(lastWho, m\); place\(\); return; \}/.test(overlay) &&
    /who: function \(\) \{ return lastWho; \}/.test(overlay));

const page = read('../voice/public/voice.js');
const branch = /if \(m\.t === 'moved'\) \{([\s\S]*?)return;\s*\}/.exec(page);
yes('the browser page has a moved branch', !!branch);
if (branch) {
  const apply = new Function('lastWho', 'm', 'place', branch[1]);
  const table = { 1: { pos: [0, 0, 0] }, 2: { pos: [1, 0, 0] }, 4: { pos: [2, 0, 0] } };
  apply(table, { who: { 2: { pos: [9, 0, 0] } }, gone: [4] }, function () { });
  yes('the browser page keeps the still, moves the walker and drops the gone',
      !!table[1] && table[2].pos[0] === 9 && !table[4]);
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exitCode = fail ? 1 : 0;
