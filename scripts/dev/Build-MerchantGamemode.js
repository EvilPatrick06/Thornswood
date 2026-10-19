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
const eligibilitySource = fs.readFileSync(path.join(root, 'game/quest-eligibility.js'), 'utf8').replace(/\r\n/g, '\n');
const killSource = fs.readFileSync(path.join(root, 'game/kill-contracts.js'), 'utf8').replace(/\r\n/g, '\n');
const roleSource = fs.readFileSync(path.join(root, 'game/merchant-role-stage.js'), 'utf8').replace(/\r\n/g, '\n');
const nativeSource = fs.readFileSync(path.join(root, 'game/merchant-ledger-native.js'), 'utf8').replace(/\r\n/g, '\n');
const budgetSource = fs.readFileSync(path.join(root, 'game/scene-reward-budget.js'), 'utf8').replace(/\r\n/g, '\n');
const sites = JSON.parse(fs.readFileSync(path.join(root, 'game/data/guild-sites.json'), 'utf8')).sites;
const traders = JSON.parse(fs.readFileSync(path.join(root, 'game/data/merchant-traders.json'), 'utf8'));
const roster = JSON.parse(fs.readFileSync(path.join(root, 'game/data/merchant-roster.json'), 'utf8'));
const roles = JSON.parse(fs.readFileSync(path.join(root, 'game/data/merchant-role-tables.json'), 'utf8'));
const quests = JSON.parse(fs.readFileSync(path.join(root, 'game/data/merchant-quests.json'), 'utf8'));
const activation = JSON.parse(fs.readFileSync(path.join(root, 'game/data/merchant-quest-activation.json'), 'utf8'));
if(activation.version!==1 || !Array.isArray(activation.killScenes) || activation.killScenes.length>4 ||
    new Set(activation.killScenes.map(row=>row.id)).size!==activation.killScenes.length)
  throw new Error('Invalid merchant quest activation manifest');
const expandedRows = activation.killScenes.map(pin=>{
  const matches=quests.quests.filter(row=>row.id===pin.id),row=matches[0];
  if(matches.length!==1 || row.kind!=='kill' ||
      require('node:crypto').createHash('sha256').update(JSON.stringify(row)).digest('hex')!==pin.sha256)
    throw new Error('An activated merchant quest changed. Preserve published definitions and use a new ID.');
  return Object.assign({},row,{sourceHash:pin.sha256});
});
const roleItems = new Set(Object.values(roles.tables).flatMap(table => Object.values(table).flat()));
const stage = {version:1,history:roster.history,merchants:roster.merchants,tables:roles.tables,
  types:Object.fromEntries(Array.from(roleItems,desc=>[desc,roles.records[desc].type]))};
const block = '// MERCHANT TRADING BUNDLE BEGIN\nconst MERCHANT_TRADING = (function () {\n' +
  'const module = { exports: {} };\nconst MERCHANT_GUILD_SITES = ' + JSON.stringify(sites) + ';\n' +
  'const MERCHANT_SETTLEMENT = (function () { const module = {exports:{}};\n' + settlementSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const QUEST_TRANSACTIONS = (function () { const module = {exports:{}};\n' + questSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const QUEST_ELIGIBILITY = (function () { const module = {exports:{}};\n' + eligibilitySource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const KILL_CONTRACTS = (function () { const module = {exports:{}};\n' + killSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const MERCHANT_ROLES = (function () { const module = {exports:{}};\n' + roleSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const MERCHANT_NATIVE = (function () { const module = {exports:{}};\n' + nativeSource.trimEnd() + '\nreturn module.exports;})();\n' +
  'const SCENE_BUDGET = (function () { const module = {exports:{}};\n' + budgetSource.trimEnd() + '\nreturn module.exports;})();\n' +
  moduleSource.trimEnd() + '\nconst install = module.exports.installMerchantTrading;\n' +
  'module.exports.installMerchantTrading = function (env) {\n' +
  '  return install(Object.assign({ catalog: ' + JSON.stringify(traders) + ' }, env));\n};\n' +
  'module.exports.prepareRoles = function (population, mp) {\n' +
  '  return MERCHANT_ROLES.prepareMerchantRoleStage(population, ' + JSON.stringify(traders) + ', ' + JSON.stringify(stage) +
  ', MERCHANT_NATIVE.createLedgerNativeValidators(mp));\n};\n' +
  'module.exports.createKillContracts = KILL_CONTRACTS.createKillContracts;\n' +
  'module.exports.sceneBudget = SCENE_BUDGET;\n' +
  'module.exports.expandedScenes = function () { return ' + JSON.stringify(expandedRows) + '; };\n' +
  'module.exports.createQuestEligibility = QUEST_ELIGIBILITY.createQuestEligibility;\n' +
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
