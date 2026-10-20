'use strict';
/*
  tests/fixtures/company-block.js

  game/gamemode.js's company terms block (#512, #2695), run the way the
  server runs it: in a context of its own, with no require unless one is
  given, so it keeps no file and the terms are the shipped ones. Harnesses
  that lift the property block's haul and sale code hand the API this makes
  to that code as g.__thornswoodCompany, the way the server does.

    load(gm, opts)        { api, ctx }; gm is gamemode.js's text (read when
                          omitted); opts.require stands in for require, and
                          opts.globals are put into the context first
    companyApi(gm, opts)  load(gm, opts).api
    blockOf(gm)           the block's text, or null
*/
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const START = '// ==== thornswood company terms ====';
const END = '// ==== end thornswood company terms ====';

function blockOf(gm) {
  const text = String(gm).split('\r\n').join('\n');
  const a = text.indexOf(START);
  const b = a < 0 ? -1 : text.indexOf(END, a);
  return (a < 0 || b < 0 || text.indexOf(START, a + 1) >= 0) ? null : text.slice(a, b + END.length);
}

function load(gm, opts) {
  opts = opts || {};
  const text = gm || fs.readFileSync(path.join(__dirname, '..', '..', 'game', 'gamemode.js'), 'utf8');
  const block = blockOf(text);
  if (!block) { throw new Error('gamemode.js has no company terms block, once'); }
  const ctx = Object.assign({
    JSON: JSON, Object: Object, Array: Array, String: String, Number: Number, Math: Math, Date: Date,
    Error: Error, RegExp: RegExp, isFinite: isFinite, parseInt: parseInt, isNaN: isNaN,
    console: { log: function () { }, error: function () { } }
  }, opts.globals || {});
  ctx.globalThis = ctx;
  ctx.__fakeRequire = opts.require || function () { throw new Error('no require here'); };
  vm.createContext(ctx);
  vm.runInContext('(function (require) {\n' + block + '\n})(__fakeRequire);', ctx, { filename: 'gamemode.js company terms' });
  return { api: ctx.__thornswoodCompany, ctx: ctx };
}

function companyApi(gm, opts) { return load(gm, opts).api; }

module.exports = { blockOf: blockOf, load: load, companyApi: companyApi };
