'use strict';
/*
  Build-TradeCargoGamemode.js (#511, #2700)

      node scripts/dev/Build-TradeCargoGamemode.js           write the bundles
      node scripts/dev/Build-TradeCargoGamemode.js --check   fail when one is stale

  The server loads one file, and native hot reload copies only gamemode.js, so
  the tested trade ship modules are carried inside it, the way
  Build-MerchantGamemode.js carries the merchant modules:

    game\trade-cargo.js       between the TRADE CARGO BUNDLE markers, as TRADE_CARGO
    game\trade-ship-dock.js   between the TRADE DOCK BUNDLE markers, as TRADE_DOCK

  both in the trade ships block. The markers are never moved by this script:
  a gamemode without exactly one pair of each is an error, not a place to guess.
*/
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const modePath = path.join(root, 'game/gamemode.js');
const BUNDLES = [
  { file: 'trade-cargo.js', name: 'TRADE_CARGO', marker: 'TRADE CARGO BUNDLE' },
  { file: 'trade-ship-dock.js', name: 'TRADE_DOCK', marker: 'TRADE DOCK BUNDLE' }
];
const old = fs.readFileSync(modePath, 'utf8').replace(/\r\n/g, '\n');
let next = old;
for (const b of BUNDLES) {
  const source = fs.readFileSync(path.join(root, 'game', b.file), 'utf8').replace(/\r\n/g, '\n');
  const BEGIN = '// ' + b.marker + ' BEGIN';
  const END = '// ' + b.marker + ' END';
  const block = BEGIN + '\n' +
    '// Built by scripts\\dev\\Build-TradeCargoGamemode.js out of game\\' + b.file + '. Do not hand edit.\n' +
    'const ' + b.name + ' = (function () {\nconst module = { exports: {} };\n' +
    source.trimEnd() + '\nreturn module.exports;\n})();\n' + END;
  const a = next.indexOf(BEGIN);
  const z = next.indexOf(END);
  if (a < 0 || z < a || next.indexOf(BEGIN, a + 1) >= 0 || next.indexOf(END, z + 1) >= 0) {
    throw new Error('gamemode.js needs exactly one pair of ' + b.marker + ' markers, in the trade ships block.');
  }
  next = next.slice(0, a) + block + next.slice(z + END.length);
}
if (process.argv.includes('--check')) {
  if (next !== old) { throw new Error('A trade ship bundle is stale. Run scripts/dev/Build-TradeCargoGamemode.js.'); }
  console.log('PASS trade ship bundles match game/trade-cargo.js and game/trade-ship-dock.js');
} else {
  fs.writeFileSync(modePath, next);
}
