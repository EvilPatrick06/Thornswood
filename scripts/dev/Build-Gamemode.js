'use strict';
// Build-Gamemode.js — entry for #2181 option D (Patrick, 12 Oct 2026).
// Today: scaffold only. The full split is not started. --check proves the
// pieces that already exist still match (merchant bundle). Later this script
// will read game/gamemode sources and game/data, and write the one file the
// gamemode artifact carries.
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '../..');
const check = process.argv.includes('--check');

function runMerchantCheck() {
  const r = spawnSync(process.execPath, [path.join(__dirname, 'Build-MerchantGamemode.js'), '--check'], {
    cwd: root,
    encoding: 'utf8'
  });
  if (r.stdout) process.stdout.write(r.stdout);
  if (r.stderr) process.stderr.write(r.stderr);
  if (r.status !== 0) process.exit(r.status || 1);
}

if (check) {
  runMerchantCheck();
  console.log('PASS Build-Gamemode scaffold: merchant bundle current; full gamemode split not started (#2181 D)');
  process.exit(0);
}

console.log('Build-Gamemode: nothing to write yet. Option D stages are in docs/GAMEMODE-SOURCE.md.');
console.log('Run with --check to verify the merchant bundle still matches its sources.');
