// test-black-wine-theme.js
//
// Black Wine is a named launcher theme in Themes.All, with the palette it
// was given. Custom and the other named themes are not this check.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(path.join(REPO_DIR, 'launcher', 'app', 'Themes.cs'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const WANT = {
  Bg: '#000000',
  Panel: '#000000',
  Card: '#000000',
  CardHover: '#1A0A10',
  Deep: '#000000',
  Line: '#6B1D33',
  Edge: '#8C2A45',
  Ink: '#F4E6EA',
  Muted: '#8C2A45',
  Faint: '#6B1D33',
  Accent: '#6B1D33',
  AccentSoft: '#3C6B1D33',
  AccentInk: '#F6E8EA',
  Ok: '#5C9C66',
  Warn: '#B9903F',
  Bad: '#B8483C'
};

const allAt = src.indexOf('public static readonly Theme[] All');
const open = allAt >= 0 ? src.indexOf('{', allAt) : -1;
let close = -1;
if (open >= 0) {
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) { close = i; break; }
    }
  }
}
const all = (open >= 0 && close >= 0) ? src.slice(open, close + 1) : '';

const names = [];
const makeRx = /Make\("([^"]+)"/g;
let m;
while ((m = makeRx.exec(all)) !== null) names.push(m[1]);

yes('Themes.All is in launcher/app/Themes.cs', all.length > 0);
yes('Black Wine is in Themes.All', names.indexOf('Black Wine') >= 0);
yes('Black Wine is in Themes.All once', names.filter(function (n) { return n === 'Black Wine'; }).length === 1);

const blockRx = /Make\("Black Wine",\s*"[^"]*",\s*(?:true|false),\s*new string\[\] \{([^}]*)\}/;
const block = blockRx.exec(all);
yes('Black Wine is declared the same way as the other named themes', block !== null);

const got = {};
if (block) {
  const pairRx = /"([^"]+)","(#[0-9A-Fa-f]+)"/g;
  let p;
  while ((p = pairRx.exec(block[1])) !== null) got[p[1]] = p[2];
}

const slots = Object.keys(WANT);
yes('Black Wine fills the sixteen colour names',
    block !== null && slots.length === 16 && slots.every(function (k) { return got[k]; }));
slots.forEach(function (k) {
  yes('Black Wine ' + k + ' is ' + WANT[k], got[k] === WANT[k]);
});

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
