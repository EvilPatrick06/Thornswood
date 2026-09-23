// test-locks.js
//
// The door locks stopped running sixty times a second without losing a door.
//
// From the To Do List: "The door locks re-lock every door on the list sixty
// times a second... updateOwner scripts run every frame in skymp5-client, not
// on change. Three scripts ride that channel. The swing and the skills panel
// were both fixed; the door locks were not, and deliberately, because that one
// may be LOAD BEARING... WHAT IS NEEDED is to find out whether the re-runs are
// actually what catches a late door, or whether the separate door tick that
// comment mentions already does it."
//
// IT IS LOAD BEARING, and the answer was in the file. The script's own comment
// says "a door in a cell nobody has loaded does not resolve... the tick below
// comes back to it", and there is no tick below: pushAll says "Done on a
// change rather than on a tick: a lock is changed a handful of times a day and
// there is nothing to poll for." So the re-runs were the only thing that ever
// caught a door whose cell streamed in afterwards, and a plain edge trigger
// would have left those doors unlocked with nothing anywhere to notice.
//
// So it keeps running again, on a four second heartbeat instead of every
// frame, and a CHANGE is still instant. This file runs the real script against
// a fake clock and a fake game to prove all three of those at once, because
// the failure being guarded against is a door that quietly never locks.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* Lift the script builder out of the gamemode and run it. */
function lift(name) {
  const a = src.indexOf('  function ' + name + '() {');
  if (a < 0) { return null; }
  const b = src.indexOf('\n  }', a);
  return b > 0 ? src.slice(a, b + 4) : null;
}

const builder = lift('lockScript');
yes('the lock script is in the gamemode', builder !== null);

const everyM = /var LOCK_EVERY_MS = (\d+);/.exec(src);
yes('and the heartbeat is a named number', !!everyM);

if (builder && everyM) {
  const EVERY = Number(everyM[1]);
  /*
    The builder reads LOCK_EVERY_MS out of its own scope, so it is handed in
    here rather than inlined. That is the point of it being a named constant:
    change the number in the gamemode and this follows, instead of two numbers
    drifting apart and nobody noticing which one the client is using.
  */
  const body = new Function('LOCK_EVERY_MS', builder + '\nreturn lockScript();')(EVERY);

  /*
    A world where a door only resolves once its cell has been loaded, which is
    the whole point: getFormEx answers null for anything in a cell nobody is
    standing near.
  */
  function world() {
    const clock = { now: 1700000000000 };
    const loaded = {};        // form id -> true once its cell is in
    const locks = {};         // form id -> true or false, as last set
    let resolves = 0, lockCalls = 0;

    const sp = {
      Game: {
        getFormEx: function (id) {
          resolves++;
          return loaded[id] ? { id: id } : null;
        }
      },
      ObjectReference: {
        from: function (f) {
          if (!f) { return null; }
          return {
            lock: function (on) { lockCalls++; locks[f.id] = !!on; }
          };
        }
      }
    };

    const state = {};
    function frame(value) {
      const ctx = { value: value, state: state, sp: sp };
      new Function('ctx', 'Date',
        body)(ctx, { now: function () { return clock.now; } });
    }
    return {
      clock: clock, loaded: loaded, locks: locks, frame: frame, state: state,
      counts: function () { return { resolves: resolves, lockCalls: lockCalls }; },
      reset: function () { resolves = 0; lockCalls = 0; }
    };
  }

  const A = 0x111, B = 0x222, C = 0x333;

  // ------------------------------------------------- it still locks a door
  {
    const w = world();
    w.loaded[A] = true;
    w.frame({ shut: [A], open: [], at: 1 });
    yes('a door in a loaded cell is locked', w.locks[A] === true);
    w.frame({ shut: [], open: [A], at: 2 });
    yes('and unlocked when it stops being shut to you', w.locks[A] === false);
  }

  // --------------------------------------------- and it stops doing it constantly
  {
    const w = world();
    w.loaded[A] = true; w.loaded[B] = true;
    w.frame({ shut: [A, B], open: [], at: 1 });
    const first = w.counts().lockCalls;
    yes('the first frame does the work', first === 2);

    w.reset();
    for (let i = 0; i < 240; i++) { w.frame({ shut: [A, B], open: [], at: 1 }); }
    yes('four seconds of frames at sixty a second do nothing at all',
        w.counts().lockCalls === 0 && w.counts().resolves === 0);
  }

  /*
    ------------------------------------------------- THE ONE THAT MATTERS

    A door whose cell was not loaded when the list arrived. Nothing on the
    server ever pushes again, so if the script does not come back to this by
    itself the door is unlocked for the rest of the session and nothing
    anywhere says so.
  */
  {
    const w = world();
    w.frame({ shut: [C], open: [], at: 1 });
    yes('a door in a cell nobody has loaded cannot be locked yet',
        w.locks[C] === undefined);

    // The person walks over there. The cell streams in. The server says
    // nothing, because a lock has not changed.
    w.loaded[C] = true;
    for (let i = 0; i < 60; i++) { w.frame({ shut: [C], open: [], at: 1 }); }
    yes('and a second of frames does not lock it, because it is on a heartbeat',
        w.locks[C] === undefined);

    w.clock.now += EVERY;
    w.frame({ shut: [C], open: [], at: 1 });
    yes('but the heartbeat comes back for it', w.locks[C] === true);
  }

  // ------------------------------------------------ a change is still instant
  {
    const w = world();
    w.loaded[A] = true;
    w.frame({ shut: [], open: [A], at: 1 });
    yes('starting unlocked', w.locks[A] === false);

    // Somebody locks it. The server pushes a new list, a moment later.
    w.clock.now += 50;
    w.frame({ shut: [A], open: [], at: 2 });
    yes('locking a door reaches you on the next frame, not in four seconds',
        w.locks[A] === true);

    // And the other way.
    w.clock.now += 50;
    w.frame({ shut: [], open: [A], at: 3 });
    yes('and so does unlocking it', w.locks[A] === false);
  }

  /*
    ------------------------------------------ AND IT FAILS THE SAFE WAY ROUND

    ctx.state is the client's, and a client that does not supply it gets the
    old behaviour: every frame, correct and expensive. A door that is not
    locked is a house anybody can walk into, so that is the right way to fail.
  */
  {
    const clock = { now: 1 };
    const locks = {};
    let calls = 0;
    const sp = {
      Game: { getFormEx: function (id) { return { id: id }; } },
      ObjectReference: {
        from: function (f) { return { lock: function (on) { calls++; locks[f.id] = !!on; } }; }
      }
    };
    for (let i = 0; i < 5; i++) {
      new Function('ctx', 'Date', body)(
        { value: { shut: [A], open: [], at: 1 }, state: null, sp: sp },
        { now: function () { return clock.now; } });
    }
    yes('a client with nowhere to remember does it every time, as it always did',
        calls === 5 && locks[A] === true);
  }

  // ------------------------------------------------ rubbish in, nothing out
  {
    const w = world();
    let threw = false;
    try {
      w.frame(null);
      w.frame({});
      w.frame({ shut: null });
      w.frame({ shut: [A], open: null, at: 9 });
    } catch (e) { threw = true; }
    yes('a missing or broken list is ignored rather than thrown', !threw);
  }

  // --------------------------------------- and the server stamps what it sends
  {
    const push = src.slice(src.indexOf('  function push(actorId, profileId) {'),
                           src.indexOf('  function pushAll() {'));
    yes('the server stamps each push, or a change could not be told from a repeat',
        /v\.at = Date\.now\(\);/.test(push));
    /*
      The claim this whole change rests on. If somebody ever adds a tick that
      re-pushes, the heartbeat becomes redundant and this comment is where they
      will find out why it was there.
    */
    yes('and it still pushes on a change rather than on a tick',
        /Done on a change rather than on a tick/.test(src));
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
