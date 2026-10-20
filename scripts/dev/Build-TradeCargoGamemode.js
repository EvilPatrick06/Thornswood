'use strict';
/*
  Build-TradeCargoGamemode.js (#511)

      node scripts/dev/Build-TradeCargoGamemode.js           write the bundle
      node scripts/dev/Build-TradeCargoGamemode.js --check   fail when it is stale

  The server loads one file, and native hot reload copies only gamemode.js, so
  the tested trade ship manifest (game\trade-cargo.js) is carried inside it,
  between the TRADE CARGO BUNDLE markers in the trade ships block, the way
  Build-MerchantGamemode.js carries the merchant modules. The markers are
  never moved by this script: a gamemode without them is an error, not a place
  to guess.
*/
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const modePath = path.join(root, 'game/gamemode.js');
const source = fs.readFileSync(path.join(root, 'game/trade-cargo.js'), 'utf8').replace(/\r\n/g, '\n');
const BEGIN = '// TRADE CARGO BUNDLE BEGIN';
const END = '// TRADE CARGO BUNDLE END';
const block = BEGIN + '\n' +
  '// Built by scripts\\dev\\Build-TradeCargoGamemode.js out of game\\trade-cargo.js. Do not hand edit.\n' +
  'const TRADE_CARGO = (function () {\nconst module = { exports: {} };\n' +
  source.trimEnd() + '\nreturn module.exports;\n})();\n' + END;
const old = fs.readFileSync(modePath, 'utf8').replace(/\r\n/g, '\n');
const a = old.indexOf(BEGIN);
const b = old.indexOf(END);
if (a < 0 || b < a || old.indexOf(BEGIN, a + 1) >= 0 || old.indexOf(END, b + 1) >= 0) {
  throw new Error('gamemode.js needs exactly one pair of TRADE CARGO BUNDLE markers, in the trade ships block.');
}
const next = old.slice(0, a) + block + old.slice(b + END.length);
if (process.argv.includes('--check')) {
  if (next !== old) { throw new Error('The trade cargo bundle is stale. Run scripts/dev/Build-TradeCargoGamemode.js.'); }
  console.log('PASS trade cargo bundle matches game/trade-cargo.js');
} else {
  fs.writeFileSync(modePath, next);
}
