// test-home-status.js
//
// The line beside the green dot on the home page says what the dot means.
//
// WHY. Issue #884. With the server up and nobody on, the line read 'The world
// is open', and Djinn read it on 28 September as the game being open to the
// public. It is alpha and application based everywhere else on the site; the
// dot only says the server is up. Patrick: "The green light shows the server
// is up also".
//
// This cuts the status branch out of home.html and runs it with a stand-in
// document for nobody on, one on, three on, and the server down.
//
// Read only.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const SRC = path.join(__dirname, '..', 'site', 'public', 'home.html');
const src = fs.readFileSync(SRC, 'utf8').split(String.fromCharCode(13)).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const START = "    var dot = document.getElementById('dot'), t = document.getElementById('livetext');";
const END = "        t.textContent = 'Server offline';\n      }\n    }\n";
const a = src.indexOf(START);
const b = a < 0 ? -1 : src.indexOf(END, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b + END.length) : null;
yes('home.html still has its status line', block !== null);
if (!block) { console.log('\n' + pass + ' passed, ' + fail + ' failed'); process.exit(1); }

function run(status) {
  const els = {
    dot: { className: 'dot' }, livetext: { textContent: '' },
    figOnline: { textContent: '' }, figOnlineWrap: { hidden: true }
  };
  const document = { getElementById: function (id) { return els[id] || null; } };
  vm.runInNewContext('(function(d){' + block + '})(d);', { document: document, d: { status: status }, String: String });
  return els;
}

let e = run({ up: true, online: 0 });
yes('nobody on: the dot is lit', e.dot.className === 'dot on');
yes("nobody on: it no longer says 'The world is open' (got '" + e.livetext.textContent + "')",
    !/world is open/i.test(e.livetext.textContent));
yes('nobody on: it says the alpha server is up and nobody is in the world',
    /alpha/i.test(e.livetext.textContent) && /server up/i.test(e.livetext.textContent) &&
    /nobody/i.test(e.livetext.textContent));
yes('nobody on: no head count tile', e.figOnlineWrap.hidden === true);

e = run({ up: true, online: 1 });
yes('one on: unchanged', e.livetext.textContent === '1 person in the world');
e = run({ up: true, online: 3 });
yes('three on: unchanged, with the tile', e.livetext.textContent === '3 people in the world' &&
    e.figOnlineWrap.hidden === false && e.figOnline.textContent === '3');
e = run({ up: false });
yes('down: unchanged', e.livetext.textContent === 'Server offline' && e.dot.className === 'dot');

const said = e.livetext.textContent + run({ up: true, online: 0 }).livetext.textContent;
yes('no em dash in what it says', said.indexOf(String.fromCharCode(0x2014)) < 0);
yes('never the word the house rules forbid', !new RegExp('pla' + 'yer', 'i').test(said));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
