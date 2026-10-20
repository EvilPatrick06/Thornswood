'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
// Execute the real pure rules in the controller's realm. Host factory stubs
// would give JSON gate objects a different Object.prototype from the caller.
module.exports = function installEligibility(ctx, gm) {
  const begin = gm.indexOf('// ==== thornswood progression ====');
  const end = gm.indexOf('// ==== end thornswood progression ====');
  assert.ok(begin >= 0 && end > begin);
  ctx.Object = vm.runInContext('({}).constructor', ctx);
  vm.runInContext(gm.slice(begin, end), ctx);
  const source = fs.readFileSync(path.join(__dirname, '../game/quest-eligibility.js'), 'utf8');
  const factory = vm.runInContext('(function(){var module={exports:{}};\n' + source +
    '\nreturn module.exports.createQuestEligibility;})()', ctx);
  ctx.MERCHANT_TRADING = ctx.MERCHANT_TRADING || {};
  ctx.MERCHANT_TRADING.createQuestEligibility = factory;
  const P = ctx.__thornswoodProgression;
  return factory({table: P.TABLE, spellIds: P.SPELL_IDS});
};
