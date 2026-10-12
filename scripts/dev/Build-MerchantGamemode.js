'use strict';
// Native hot reload copies only gamemode.js into a temporary directory.
// Keep the standalone, tested module and its catalogues embedded in that file.
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const modePath = path.join(root, 'game/gamemode.js');
const moduleSource = fs.readFileSync(path.join(root, 'game/merchant-trading.js'), 'utf8').replace(/\r\n/g, '\n');
const settlementSource = fs.readFileSync(path.join(root, 'game/merchant-settlement.js'), 'utf8').replace(/\r\n/g, '\n');
const questSource = fs.readFileSync(path.join(root, 'game/quest-transactions.js'), 'utf8').replace(/\r\n/g, '\n');
const killSource = fs.readFileSync(path.join(root, 'game/kill-contracts.js'), 'utf8').replace(/\r\n/g, '\n');
const sites = JSON.parse(fs.readFileSync(path.join(root, 'game/data/guild-sites.json'), 'utf8')).sites;
const traders = JSON.parse(fs.readFileSync(path.join(root, 'game/data/merchant-traders.json'), 'utf8'));
const block = '// MERCHANT TRADING BUNDLE BEGIN\nconst MERCHANT_TRADING = (function () {\n' +
  'const module = { exports: {} };\nconst MERCHANT_GUILD_SITES = ' + JSON.stringify(sites) + ';\n' +
  'const MERCHANT_SETTLEMENT = (function () { const module = {exports:{}};\n' + settlementSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const QUEST_TRANSACTIONS = (function () { const module = {exports:{}};\n' + questSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const KILL_CONTRACTS = (function () { const module = {exports:{}};\n' + killSource.trimEnd() + '\nreturn module.exports;})();\n' +
  moduleSource.trimEnd() + '\nconst install = module.exports.installMerchantTrading;\n' +
  'module.exports.installMerchantTrading = function (env) {\n' +
  '  return install(Object.assign({}, env, { catalog: ' + JSON.stringify(traders) + ' }));\n};\n' +
  'module.exports.createKillContracts = KILL_CONTRACTS.createKillContracts;\n' +
  'return module.exports;\n})();\n// MERCHANT TRADING BUNDLE END';
const old = fs.readFileSync(modePath, 'utf8').replace(/\r\n/g, '\n');
const existing = /\/\/ MERCHANT TRADING BUNDLE BEGIN[\s\S]*?\/\/ MERCHANT TRADING BUNDLE END/;
const startup = '// NPC SERVER STARTUP BEGIN';
const matched = existing.exec(old);
let next;
if (matched && matched.index < old.lastIndexOf(startup)) next = old.replace(existing, () => block);
else {
  const without = old.replace(existing, '').trimEnd() + '\n';
  const at = without.lastIndexOf(startup);
  if (at < 0) throw new Error('NPC startup marker is missing.');
  next = without.slice(0, at) + block + '\n\n' + without.slice(at);
}
if (process.argv.includes('--check')) {
  if (next !== old) throw new Error('Merchant gamemode bundle is stale. Run scripts/dev/Build-MerchantGamemode.js.');
  console.log('PASS merchant gamemode bundle matches its source and catalogues');
} else fs.writeFileSync(modePath, next);
