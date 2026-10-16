'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const src = fs.readFileSync(path.join(__dirname, '..', 'game', 'gamemode.js'), 'utf8');
const block = src.slice(src.indexOf('/* BOOKS-START */'), src.indexOf('/* BOOKS-END */'));
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tw-guild-safe-'));
let hold = 'whiterun', brokenWrite = false;
const testFs = Object.create(fs);
testFs.writeFileSync = (...args) => { if (brokenWrite) throw new Error('disk full'); return fs.writeFileSync(...args); };
function make() {
  const ctx = { env: { fs: testFs, path, privDir: dir, atBox: () => hold,
    roles: () => ({ business: true, account: 'a' }), nameOf: () => 'Ada', refresh: () => {} } };
  vm.createContext(ctx);
  vm.runInContext(block + '\nthis.api = thornswoodBooks(env);', ctx);
  return ctx.api;
}
try {
  const api = make();
  const cmd = line => api.command({ actorId: 1, profileId: 1, parts: line.split(/\s+/) });
  cmd('/book new business Ore');
  const id = api.books()[0].id;
  cmd('/book price ' + id + ' | Iron Ore | 10 | 20');
  assert.match(cmd('/book submit ' + id), /^Submitted /);
  cmd('/book price ' + id + ' | Iron Ore | 90 | 100');
  brokenWrite = true;
  let refused;
  try { refused = cmd('/book submit ' + id); } catch (e) { refused = e.message; }
  brokenWrite = false;
  assert.strictEqual(api.guildPrice('whiterun', 'Iron Ore').buy, 10, 'failed save leaves live prices unchanged');
  assert(!/^Submitted /.test(refused));
  assert.strictEqual(make().guildPrice('whiterun', 'Iron Ore').buy, 10);
  assert.match(cmd('/book price ' + id + ' | Huge | ' + '9'.repeat(400) + ' | 1'), /whole number/);
  assert.match(cmd('/book price ' + id + ' | Huge | 2147483648 | 1'), /whole number/);
  hold = '__proto__';
  assert(!/^Submitted /.test(cmd('/book submit ' + id)));
  assert.strictEqual(api.guildPrice('__proto__', 'Iron Ore').buy, null);
  hold = 'whiterun';
  assert(!/^Submitted /.test(cmd('/book submit ' + id + ' extra')));
  const goodFile = fs.readFileSync(path.join(dir, 'books.json'), 'utf8');
  const rename = testFs.renameSync;
  testFs.renameSync = () => { throw new Error('rename denied'); };
  try {
    assert(!/^Submitted /.test(cmd('/book submit ' + id)));
    assert.strictEqual(fs.readFileSync(path.join(dir, 'books.json'), 'utf8'), goodFile,
      'failed rename preserves the old saved file');
    assert.strictEqual(api.guildPrice('whiterun', 'Iron Ore').buy, 10);
  } finally { testFs.renameSync = rename; }
  const at = src.indexOf('  function holdStanding(');
  const fn = src.slice(at, src.indexOf('\n  /*', at)).trim();
  let board = '', touched = 2;
  const cells = { 1: 'a:Skyrim.esm', 2: 'a:Skyrim.esm' };
  const pos = { 1: [0, 0, 0], 2: [400, 0, 0] };
  const ctx = { boardHere: () => board, boxAt: () => touched, holdOfBox: () => 'whiterun',
    mp: { get: (id, prop) => prop === 'pos' ? pos[id] : cells[id] } };
  vm.createContext(ctx); vm.runInContext(fn, ctx);
  assert.strictEqual(ctx.holdStanding(1), 'whiterun');
  pos[1] = [-1, 0, 0];
  assert.strictEqual(ctx.holdStanding(1), '', 'cached container cannot authorize a remote submission');
  pos[1] = [0, 0, 0]; cells[1] = 'other:Skyrim.esm';
  assert.strictEqual(ctx.holdStanding(1), '');
  cells[1] = cells[2] = '';
  assert.strictEqual(ctx.holdStanding(1), '');
  board = 'riften';
  assert.strictEqual(ctx.holdStanding(1), 'riften', 'actual board remains a drop box');
  const saved = JSON.parse(goodFile);
  saved.ledgers.whiterun[id].prices[0].buy = -1;
  fs.writeFileSync(path.join(dir, 'books.json'), JSON.stringify(saved));
  assert.throws(make, /ledger prices/i, 'invalid stored financial values refuse startup');
  fs.writeFileSync(path.join(dir, 'books.json'), '{broken');
  assert.throws(make, /book/i, 'corrupt saved price books are not silently emptied');
  fs.writeFileSync(path.join(dir, 'books.json'), '{"books":[null],"ledgers":{}}');
  assert.throws(make, /book/i, 'malformed book entries refuse initialization');
  fs.writeFileSync(path.join(dir, 'books.json'), '{broken');
  const initStart = src.indexOf('(function () {', src.indexOf('/* BOOKS-END */'));
  const initializer = src.slice(initStart, src.indexOf('})();', initStart) + 5);
  const reloadFs = Object.create(fs);
  reloadFs.readFileSync = (file, ...args) => file === 'server-settings.json'
    ? JSON.stringify({ dataDir: path.join(dir, 'served'), privDir: dir }) : fs.readFileSync(file, ...args);
  const reload = { __thornswoodBooks: { command: () => 'old writable API' }, __thornswoodBooksTimer: 4,
    require: name => name === 'fs' ? reloadFs : path, log: () => {},
    clearInterval: id => { assert.strictEqual(id, 4); reload.cleared = true; },
    setInterval: () => { throw new Error('A failed initialization must not start a timer'); } };
  vm.createContext(reload); vm.runInContext(block + '\n' + initializer, reload);
  assert.strictEqual(reload.__thornswoodBooks, null, 'failed reload disables the previous writable API');
  assert.strictEqual(reload.__thornswoodBooksTimer, null);
  assert(reload.cleared);
  console.log('PASS guild ledger save failure, restart, real proximity and corrupt state');
} finally { fs.rmSync(dir, { recursive: true, force: true }); }
