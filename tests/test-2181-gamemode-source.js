'use strict';
// test-2181-gamemode-source.js — docs and Build-Gamemode scaffold for #2181 D.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const root = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(w, ok) { if (ok) { pass++; console.log('PASS  ' + w); } else { fail++; console.log('FAIL  ' + w); } }

const doc = fs.readFileSync(path.join(root, 'docs', 'GAMEMODE-SOURCE.md'), 'utf8');
yes('GAMEMODE-SOURCE records Patrick decision D', /Decision \(Patrick, 12 Oct 2026\): D/.test(doc));
yes('D uses a bundler and the gamemode artifact', /bundler/i.test(doc) && /artifact hash/i.test(doc));
yes('Build-Gamemode.js exists', fs.existsSync(path.join(root, 'scripts', 'dev', 'Build-Gamemode.js')));
const r = spawnSync(process.execPath, [path.join(root, 'scripts', 'dev', 'Build-Gamemode.js'), '--check'], { cwd: root, encoding: 'utf8' });
yes('Build-Gamemode --check exits 0', r.status === 0);
yes('Build-Gamemode --check mentions scaffold / not started', /not started|#2181/i.test(r.stdout || ''));

console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
