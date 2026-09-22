// test-town-gates.js
//
// A town you cannot walk into.
//
// Patrick, 21 September, playing it: "The gate into the whiterun inner city
// needs to be unlocked", and when asked which door, "it is the front gate
// into the city".
//
// MEASURED IN THE DOOR TABLE, which is read below rather than described:
// the Whiterun main gate, base WRDoorMainGate01, is placed twice, and the
// leaf standing outside carries a lock of level 255 out of Skyrim.esm itself.
// In a single game a quest script opens it. Under SkyMP no Papyrus quest runs
// at all, so nothing ever opens it, and activationService.ts refuses to
// announce a press on a locked reference, so the server is never even told.
// The press is dead and the town has no way in.
//
// The Riften main gate is the same defect at the same kind of door.
//
// This drives the shipped openTheGates out of thornswood-front.js against a
// pretend game, and checks the ids it carries against tools\doors.json.
//
// Read only.
const fs = require('fs');
const path = require('path');
const FRONT = process.env.FRONT ||
              path.join(__dirname, 'ts-plugins', 'thornswood-front.js');
const TABLE = process.env.DOORS || path.join(__dirname, 'doors.json');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(FRONT, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const a = src.indexOf('  const TOWN_GATES = [');
const b = a < 0 ? -1 : src.indexOf('\n  }\n', src.indexOf('function openTheGates', a));
const block = (a >= 0 && b >= 0) ? src.slice(a, b + 5) : null;

yes('the gate opener is in the plugin', block !== null);

/** The real function, over a world of pretend references. */
function rig(world) {
  const said = [];
  const fn = new Function(
    'sp', 'say', 'Date',
    block + '\nreturn { open: openTheGates, ids: TOWN_GATES, ' +
            'every: GATE_EVERY_MS };');
  const api = fn(
    { Game: { getFormEx: function (id) { return world[id] || null; } },
      ObjectReference: { from: function (f) { return f; } } },
    function (line) { said.push(line); },
    { now: function () { return 1; } });
  api.said = said;
  return api;
}

/** A gate that starts locked and remembers being opened. */
function gate(locked) {
  return {
    state: !!locked,
    isLocked: function () { return this.state; },
    lock: function (on) { this.state = !!on; this.calls = (this.calls || 0) + 1; }
  };
}

if (block !== null) {
  const WHITERUN = 0x1b1f1;

  // S1: the gate Patrick walked up to.
  {
    const g = gate(true);
    const world = {}; world[WHITERUN] = g;
    const r = rig(world);
    yes('S1 the Whiterun main gate is one of the gates it opens',
        r.ids.indexOf(WHITERUN) >= 0);
    r.open();
    yes('S1 and a pass opens it', g.state === false);
    yes('S1 and says so once', r.said.length === 1);
  }

  // S2: it does not keep opening a gate that is already open, and it does not
  //     say the same line every thirty seconds for the rest of the session.
  {
    const g = gate(true);
    const world = {}; world[WHITERUN] = g;
    const r = rig(world);
    r.open(); r.open(); r.open();
    yes('S2 an open gate is left alone', g.calls === 1);
    yes('S2 and the line is said once, not once a pass', r.said.length === 1);
  }

  // S3: THE REASON IT IS ON A CLOCK. A persistent reference keeps its lock,
  //     so a gate that comes back locked is opened again.
  {
    const g = gate(true);
    const world = {}; world[WHITERUN] = g;
    const r = rig(world);
    r.open();
    g.state = true;
    r.open();
    yes('S3 a gate that relocks is opened again', g.state === false && g.calls === 2);
  }

  // S4: a gate whose cell is not loaded is not a failure. It is most of the
  //     time: somebody standing in Riften has no Whiterun gate in memory.
  {
    const r = rig({});
    r.open();
    yes('S4 a gate that is not loaded says nothing and throws nothing',
        r.said.length === 0);
  }

  // S5: a reference that throws on every call does not take the pass with it,
  //     and does not fill the log with the same line forever.
  {
    const bad = { isLocked: function () { throw new Error('no'); } };
    const world = {}; world[WHITERUN] = bad;
    const r = rig(world);
    r.open(); r.open();
    yes('S5 a gate that throws is reported once and not every pass',
        r.said.length === 1);
  }

  // S6: half a minute, not every frame. This runs inside sp.on('update').
  {
    const r = rig({});
    yes('S6 the pass is on a thirty second clock', r.every === 30000);
  }

  // ---------------------------------------------------- against the door table
  {
    let table = null;
    try { table = JSON.parse(fs.readFileSync(TABLE, 'utf8')); } catch (e) { }
    yes('the door table is beside this', table !== null);
    if (table) {
      const r = rig({});
      let allLocked = true, named = [];
      for (let i = 0; i < r.ids.length; i++) {
        const key = r.ids[i].toString(16) + ':Skyrim.esm';
        const row = table.doors[key];
        if (!row) { allLocked = false; named.push(key + ' is not a door'); continue; }
        if (!row.lock || !row.lock.level) {
          allLocked = false; named.push(key + ' is not locked');
        }
      }
      yes('every id it opens is a door Bethesda ships locked: ' +
          (named.length ? named.join(', ') : 'all of them'), allLocked);

      const wr = table.doors['1b1f1:Skyrim.esm'];
      yes('and the Whiterun one wants a key, which is why a press did nothing',
          !!(wr && wr.lock && wr.lock.level === 255 && wr.lock.key));
    }
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
