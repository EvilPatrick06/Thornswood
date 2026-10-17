// test-2623-temporary-spawns.js
//
// A creature staff spawn without keeping it is taken out of the world for
// good, in the right order, and only after the engine's death event is over.
//
// WHY. Djinn, 17 October: wolves and a vampire he spawned in The Winking
// Skeever for a test were still there days later and attacked a new character.
// Every commanded spawn was given a saved home and a spawn point there, so it
// stood up again after every death and every restart. "A creature spawned by
// a staff member should never be made permanent unless we want to make it
// permanent."
//
// What this runs: the real serverRunId and removeSpawned, lifted out of
// game/gamemode.js by text, against a stand-in mp that records the calls; and
// the real mp.onDeath block, read as text, for the one thing a harness here
// cannot run: that removal is asked for after the event, not inside it.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
const src = fs.readFileSync(SRC, 'utf8').split(String.fromCharCode(13)).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function lift(name) {
  const a = src.indexOf('\nfunction ' + name + '(');
  if (a < 0) { return null; }
  const b = src.indexOf('\n}\n', a);
  return b < 0 ? null : src.slice(a, b + 3);
}

const runFn = lift('serverRunId');
const removeFn = lift('removeSpawned');
yes('serverRunId is in the gamemode', !!runFn);
yes('removeSpawned is in the gamemode', !!removeFn);

function box(throwOn) {
  const calls = [];
  const ctx = {
    globalThis: null,
    log: function () { calls.push(['log', Array.prototype.slice.call(arguments).join(' ')]); },
    mp: {
      getDescFromId: function (id) { return id.toString(16); },
      callPapyrusFunction: function (kind, cls, fn, self, args) {
        calls.push(['papyrus', cls + '.' + fn, self.type, self.desc, args.length]);
        if (throwOn === 'papyrus') { throw new Error('no such method'); }
      },
      destroyActor: function (id) { calls.push(['destroy', id]); }
    },
    __thornswoodNpcPopulation: { release: function (id) { calls.push(['release', id]); } },
    __thornswoodNpcRuntime: { forget: function (id) { calls.push(['forget', id]); } }
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext((runFn || '') + '\n' + (removeFn || ''), ctx);
  return { ctx: ctx, calls: calls };
}

if (runFn && removeFn) {
  const b = box();
  const first = b.ctx.serverRunId();
  yes('a run id is made once', typeof first === 'string' && first.length > 4);
  yes('and the same one comes back for the rest of the run, as through a gamemode reload',
      b.ctx.serverRunId() === first && b.ctx.__thornswoodServerRun === first);

  const done = b.ctx.removeSpawned(0xff000123);
  const kinds = b.calls.filter(function (c) { return c[0] !== 'log'; }).map(function (c) { return c[0]; }).join(',');
  yes('it lets go of the slot and the runtime, marks the record deleted, then destroys it: ' + kinds,
      kinds === 'release,forget,papyrus,destroy');
  const papyrus = b.calls.filter(function (c) { return c[0] === 'papyrus'; })[0] || [];
  yes('the record is marked deleted through ObjectReference.Delete on that actor',
      papyrus[1] === 'ObjectReference.Delete' && papyrus[2] === 'form' && papyrus[3] === 'ff000123');
  yes('it says it worked', done === true);

  const c = box('papyrus');
  c.ctx.removeSpawned(0xff000124);
  yes('a Delete that throws still leaves the actor destroyed, and is logged',
      c.calls.some(function (x) { return x[0] === 'destroy' && x[1] === 0xff000124; }) &&
      c.calls.some(function (x) { return x[0] === 'log' && /could not mark its record deleted/.test(x[1]); }));
}

// The death handler asks for removal after the event, never inside it.
{
  const a = src.indexOf('mp.onDeath = guard(\'onDeath\'');
  const b = a < 0 ? -1 : src.indexOf('\n});\n', a);
  const body = a >= 0 && b > a ? src.slice(a, b) : '';
  yes('mp.onDeath checks for a temporary spawn',
      /spawnedBy\.isTemporary\(actorId\)/.test(body));
  yes('and asks for removal on the next turn of the event loop',
      /setTimeout\(function \(\) \{ removeSpawned\(actorId\); \}, 0\)/.test(body));
  yes('and never calls removeSpawned directly inside the event',
      !/[^(]\s*removeSpawned\(actorId\);\s*\n/.test(body.replace(/setTimeout\(function \(\) \{ removeSpawned\(actorId\); \}, 0\)/g, '')));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exitCode = fail ? 1 : 0;
