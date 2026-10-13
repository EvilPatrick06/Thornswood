'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../game/gamemode.js'), 'utf8');
const begin = source.lastIndexOf('// NPC SERVER STARTUP BEGIN');
const end = source.indexOf('// NPC SERVER STARTUP END', begin);
assert.ok(begin >= 0 && end > begin);
const manifest = source.slice(source.indexOf('function npcMerchantManifest('), source.indexOf('function createNpcMerchantPurses('));
for (const channel of ['main', 'dev', undefined]) {
  let prepared = 0, population = 0, runtime = 0, quotes = 0, shutdowns = 0;
  const ledgerChannels = [], logs = [];
  const settings = { thornswoodServer: channel, loadOrder: ['Skyrim.esm'], privDir: `${channel || 'main'}-private` };
  const ctx = {
    require, setTimeout, clearTimeout, Date,
    log: text => logs.push(text),
    mp: { getServerSettings: () => settings, prepareNpcLoad: () => prepared++ },
    NPC_POPULATION_DATA: { plugins: ['Skyrim.esm'], keep: [['1:Skyrim.esm','a:Skyrim.esm',0,0,0,0,'trader']] },
    createPrivateMerchantLedger: (fs, path, cfg) => { ledgerChannels.push(cfg.privDir); return {}; },
    createNpcMerchantPurses: () => ({ shutdown() {} }),
    createNpcPopulation: () => { population++; return {}; },
    startSharedNpcServerRuntime: () => { runtime++; return { stop() {} }; },
    MERCHANT_TRADING: { installMerchantTrading: () => { quotes++; return { shutdown() { shutdowns++; } }; } }
  };
  vm.createContext(ctx);
  vm.runInContext(manifest, ctx);
  vm.runInContext(source.slice(begin, end), ctx);
  assert.equal(prepared, 1, `${channel || 'legacy Main'} prepares the winning records`);
  assert.equal(population, 1, `${channel || 'legacy Main'} starts the curated population`);
  assert.equal(runtime, 1, `${channel || 'legacy Main'} starts shared NPC authority`);
  assert.equal(quotes, 1, `${channel || 'legacy Main'} installs the quote panel`);
  assert.deepEqual(ledgerChannels, [settings.privDir], 'Each channel uses its own private ledger');
  assert.deepEqual(logs, []);
  ctx.NPC_POPULATION_DATA.plugins = ['Wrong.esm'];
  vm.runInContext(source.slice(begin, end), ctx);
  assert.equal(shutdowns, 1, 'A failed reload revokes the previous merchant service');
  assert.equal(ctx.__thornswoodMerchantTrade, null, 'A failed reload cannot retain the merchant writer');
  assert.equal(runtime, 1, 'A mismatched catalogue cannot start another runtime');
  assert.equal(ctx.__thornswoodNpcRuntime, null, 'Failed startup revokes the active runtime');
  assert.ok(logs.some(line => line.includes('does not match')));
}
console.log('PASS Main and Dev startup, separate private storage and catalogue refusal');
