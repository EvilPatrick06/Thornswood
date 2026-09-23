// test-temp.js
//
// Temperature: where you are standing, what you are wearing, and the fire.
//
// Patrick, 23 September, with five screenshots of the meter reading Fine 50
// outside at night, beside a brazier, inside the Bannered Mare and standing in
// its fire pit: "not any warmer when near or in fire or in a building also
// make so if you are in a fire you catch on fire". Then "yeah forges and stuff
// like that should be included too because they are hot", and "also clothing
// should affect temperature depening on what clothes and if you are weaing
// them no clothes should equal colder some clothes/armor should be hotter than
// others etc".
//
// THE METER WAS NEVER WRONG. Nothing ever told it where anybody was standing,
// so every one of those screenshots is the same bug: n.place was '' and the
// target was always comfort. So the first thing this checks is that the two
// halves are actually joined up - that the client reports, that the server has
// a number for every word the client can send, and that the fire table the
// client scans with is the one the builder wrote.
//
// It drives the REAL needs block out of gamemode.js over a fake mp and a fake
// clock, the way test-needs.js does.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');
const FRONT = fs.readFileSync(path.join(__dirname, 'ts-plugins', 'thornswood-front.js'), 'utf8');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const A = '// ==== thornswood needs: hunger, thirst and exhaustion ====';
const B = '// ==== end thornswood needs ====';
const a = src.indexOf(A);
const b = a < 0 ? -1 : src.indexOf(B, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b) : null;
yes('the needs block is in the gamemode', block !== null);

// The installed table, lifted rather than re-read from warmth.json, because
// what the server runs on is the line in gamemode.js.
const warmLine = /^const WARMTH = (\{.*\});$/m.exec(src);
yes('the warmth table is installed in the gamemode', !!warmLine);
const WARMTH = warmLine ? JSON.parse(warmLine[1]) : { items: {} };
const skyLine = /^const WEATHER = (\{.*\});$/m.exec(src);
const WEATHER = skyLine ? JSON.parse(skyLine[1]) : { most: 0, mid: 0, items: {} };
const wetLine = /^const WATERS = (\{.*\});$/m.exec(src);
const WATERS = wetLine ? JSON.parse(wetLine[1]) : { items: {} };

/*
  The rig.

  idOf and the inventory are the two things the clothing half needs and that
  test-needs.js does not supply: descriptors are resolved to numbers on a live
  server out of the load order, so here every descriptor resolves to its own
  index, and the fake mp answers 'inventory' with whatever the test dressed
  somebody in.
*/
function rig() {
  const store = {};
  const worn = {};
  const cells = {};
  const pos = {};
  const props = {};
  const clock = { now: 1700000000000 };
  const ids = {};
  let nextId = 0x10;
  function idOf(desc) {
    if (!ids[desc]) { ids[desc] = nextId++; }
    return ids[desc];
  }
  const Fake = {
    getOnlinePlayers: function () { return Object.keys(store).map(Number); },
    makeProperty: function () { },
    get: function (id, key) {
      if (key === 'worldOrCellDesc') { return cells[id] || 'cell:X.esm'; }
      if (key === 'inventory') { return { entries: worn[id] || [] }; }
      if (key === 'pos') { return pos[id] || [0, 0, 0]; }
      return store[id] ? store[id].v : undefined;
    },
    set: function (id, key, v) {
      if (key === 'thornswoodBurn') {
        if (!props[id]) { props[id] = []; }
        props[id].push(v);
        return;
      }
      if (!store[id]) { store[id] = {}; }
      store[id].v = v;
    }
  };
  let ticker = null;
  const fn = new Function(
    'globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
    'guard', 'notify', 'say', 'Math', 'Number', 'String', 'Object', 'isFinite',
    'idOf', 'WARMTH', 'WEATHER', 'WATERS',
    block + '\nreturn globalThis.__thornswoodNeeds;');
  const api = fn(
    {}, Fake, { now: function () { return clock.now; } },
    { log: function () { } },
    // The burn timer is caught rather than run, so a test can beat it by hand.
    function (f, ms) { if (ms <= 3000) { ticker = f; } return 0; },
    function () { },
    function (n, f) { return f; },
    function () { }, function () { },
    Math, Number, String, Object, isFinite,
    idOf, WARMTH, WEATHER, WATERS);
  api.clock = clock;
  api.idOf = idOf;
  api.cellOf = function (id, desc) { cells[id] = desc; };
  api.putAt = function (id, xyz) { pos[id] = xyz; if (!store[id]) { store[id] = {}; } };
  api.caught = function (id) { return props[id] || []; };
  api.burnTick = function () { if (ticker) { ticker(); } };
  /** Put a set of descriptors on somebody's back. */
  api.dress = function (id, descs) {
    worn[id] = descs.map(function (d) { return { baseId: idOf(d), worn: true }; });
  };
  /** The same things, in the pack rather than on. */
  api.carry = function (id, descs) {
    worn[id] = descs.map(function (d) { return { baseId: idOf(d), worn: false }; });
  };
  api.minutes = function (m) { clock.now += m * 60000; };
  return api;
}

/*
  One descriptor out of the installed table, by material and by EXACTLY what it
  covers.

  Exactly, not "contains", and that is the second time coverage has been the
  thing that broke a comparison in this file. Asking for any heavy piece
  covering a body and any cloth piece covering a body got a cuirass that also
  covered arms and a shirt that did not, so "metal is worse than cloth" was
  being measured against two different amounts of skin and came out backwards.
  Two things that differ in two ways measure neither.
*/
function oneOf(material, covers) {
  for (const d in WARMTH.items) {
    if (!Object.prototype.hasOwnProperty.call(WARMTH.items, d)) { continue; }
    const r = WARMTH.items[d];
    if (r.m === material && (!covers || r.c === covers)) { return d; }
  }
  return null;
}

if (block) {
  const NEEDS = rig().NEEDS;

  // ------------------------------------------------ the two halves joined up
  {
    /*
      EVERY WORD THE CLIENT CAN SEND HAS A NUMBER HERE.

      This is the check that would have caught the original bug if the client
      had ever been written: place() refuses a word it has no number for and
      answers '' without saying anything, so a client reporting 'outdoors' to a
      server that has never heard of it looks exactly like a client that is not
      reporting at all.
    */
    /*
      THE PLACE BLOCK, NOT THE WHOLE PLUGIN. The first version of this searched
      the file for `kind = '...'` and found the jump and sprint state machines
      several hundred lines away, then reported the server as missing numbers
      for "jump" and "sprint". Scope the search to the block that is being
      tested; this file has now made that mistake once and test-hud.js twice.
    */
    const from = FRONT.indexOf('const FIRE_BASES');
    const to = FRONT.indexOf('let stuckKeys', from);
    const where = (from >= 0 && to > from) ? FRONT.slice(from, to) : '';
    yes('the place block is findable in the plugin', !!where);
    const sends = (where.match(/kind = '([a-z]+)'/g) || [])
      .map(function (s) { return /'([a-z]+)'/.exec(s)[1]; });
    yes('the client reports a place at all', sends.length >= 5);
    const missing = sends.filter(function (w) { return typeof NEEDS.place[w] !== 'number'; });
    yes('and the server has a number for every word it sends' +
        (missing.length ? ' (missing ' + missing.join(', ') + ')' : ''),
        missing.length === 0);
    yes('the client sends it over the one channel there is',
        /'\/place '/.test(where) && /tellServer\(line\)/.test(where));
    yes('and the server answers that command',
        /word === '\/place'/.test(src));
    // The line carries the weather, the clock, the roof and the height as
    // well as the word, and the server has to read all five.
    yes('the line carries the weather, the clock, the roof and the height',
        /skyId/.test(where) && /night/.test(where) &&
        /indoors \? 1 : 0/.test(where) && /pz \/ 500/.test(where));
    yes('and the server takes all five off the command',
        /pl\.place\(actorId, String\(parts\[1\] \|\| ''\), parts\[2\], parts\[3\],/.test(src));
  }

  // ------------------------------------------------------ the fire table
  {
    let fires = null;
    try { fires = JSON.parse(fs.readFileSync(path.join(__dirname, 'fires.json'), 'utf8')); }
    catch (e) { fires = null; }
    yes('the fire table has been built', !!fires && Array.isArray(fires.fires));
    if (fires) {
      const listed = /const FIRE_BASES = \[([^\]]*)\]/.exec(FRONT);
      yes('the plugin carries a list of fire bases', !!listed);
      if (listed) {
        const inPlugin = (listed[1].match(/0x[0-9a-f]+/g) || []).sort();
        const inTable = fires.fires.map(function (f) { return f.id; }).sort();
        /*
          THE ONE THING KEEPING A HAND EDIT HONEST. The list in the plugin is
          what the client actually scans with; fires.json is what the builder
          measured. If somebody adds an id to the plugin by hand, or rebuilds
          the table and forgets the plugin, this is where it shows up.
        */
        yes('and it is exactly what the builder measured (' + inTable.length + ')',
            inPlugin.length === inTable.length &&
            inPlugin.every(function (v, i) { return v === inTable[i]; }));
      }
      // The unlit ones are the trap: a name match would have warmed people up
      // at a dead campfire.
      const out = fires.fires.filter(function (f) { return /(off|out)\d*$/i.test(f.edid); });
      yes('no unlit fire made it into the table', out.length === 0);
      const craft = fires.fires.filter(function (f) { return f.kind === 'craft'; });
      yes('forges and smelters are in it, which Patrick asked for by name',
          craft.length >= 4 &&
          craft.some(function (f) { return /Forge/i.test(f.edid); }) &&
          craft.some(function (f) { return /Smelter/i.test(f.edid); }));
    }
  }

  // ---------------------------------------------------- the meter actually moves
  {
    const api = rig();
    api.seedAt = 1;
    api.view(1);                       // make a state
    api.place(1, 'fire');
    const before = api.view(1).temp;
    api.minutes(3);
    const after = api.view(1).temp;
    /*
      THE HALF LIFE, AND THE OLD NUMBER WAS NOT ONE.

      It read warmth: 60 "per real hour" and fed it to a power of a half, which
      worked out at about half a point a minute: an hour of standing in a fire
      to read as warm. Three minutes is halfway to the target by definition, so
      a fresh character at 50 in a fire whose target is 92 should be near 71.
    */
    yes('standing in a fire actually warms you up', after > before + 10);
    yes('and it is halfway there in the half life, not in an hour',
        Math.abs(after - (50 + (92 - 50) / 2)) < 4);

    api.place(1, 'snow');
    api.minutes(9);
    yes('and walking into a blizzard takes it back down', api.view(1).temp < 30);
  }

  // ---------------------------------------------------------- outdoors is cool
  {
    const api = rig();
    api.view(2);
    api.place(2, 'outdoors');
    api.minutes(30);
    const out = api.view(2).temp;
    const api2 = rig();
    api2.view(3);
    api2.place(3, 'indoors');
    api2.minutes(30);
    yes('being outside is cooler than being under a roof', out < api2.view(3).temp);
    yes('but standing in a field is not an emergency', out >= 35);
  }

  // ------------------------------------------------------------- the clothes
  {
    const fur = oneOf('fur', 'body');
    const heavy = oneOf('heavy', 'body');
    const cloth = oneOf('cloth', 'body');
    yes('the table has a fur, a metal and a cloth body piece to test with',
        !!fur && !!heavy && !!cloth);

    function coldAfter(descs, wearIt) {
      const api = rig();
      api.view(9);
      if (descs) { (wearIt ? api.dress : api.carry)(9, descs); }
      api.place(9, 'snow');
      api.minutes(60);
      /*
        THE RAW NUMBER, NOT THE ROUNDED ONE. view() rounds for the screen, and
        a shirt and a steel cuirass over the same skin differ by less than half
        a point, so comparing what the HUD would print reported them as
        identical and "metal is worse than cloth" failed on the rounding rather
        than on the arithmetic.
      */
      return api.settle(9).temp;
    }

    if (fur && heavy && cloth) {
      const bare = coldAfter(null, true);
      const inFur = coldAfter([fur], true);
      const inSteel = coldAfter([heavy], true);
      const inCloth = coldAfter([cloth], true);

      yes('bare skin in a blizzard is the coldest there is', bare < inCloth);
      yes('fur is the warmest thing in the game', inFur > inCloth && inFur > inSteel);
      yes('and metal is the worst of the things that are not nothing',
          inSteel < inCloth);
      // Patrick's own words: "if you are weaing them".
      const carried = coldAfter([fur], false);
      yes('a coat in your pack keeps nobody warm', Math.abs(carried - bare) < 0.01);
      // Nothing makes a blizzard comfortable.
      yes('and no outfit turns a blizzard into a spring day', inFur < 45);
    }

    /*
      EVERY PIECE ON ITS OWN, WHICH IS WHAT PATRICK ASKED FOR.

      23 September: "different types of clothes and wether one is on and others
      are like a hat, helmet, scarf, cape, shirt, pants, boots, gloves, etc are
      all counted individually and not grouped".

      The table names the part each record covers and NEEDS.wear.perPart prices
      it. A part with no price is a silent zero: a cloak worth nothing looks
      exactly like a cloak nobody is wearing, which is the bug this catches.
    */
    {
      const seen = {};
      for (const d in WARMTH.items) {
        if (!Object.prototype.hasOwnProperty.call(WARMTH.items, d)) { continue; }
        WARMTH.items[d].c.split(',').forEach(function (p) { seen[p] = true; });
      }
      const parts = Object.keys(seen).sort();
      const unpriced = parts.filter(function (p) {
        return typeof NEEDS.wear.perPart[p] !== 'number';
      });
      yes('every part the table produces has a price' +
          (unpriced.length ? ' (missing ' + unpriced.join(', ') + ')' : ''),
          unpriced.length === 0);
      yes('and the pieces Patrick named are in there separately (' + parts.length + ' parts)',
          seen.head && seen.body && seen.feet && seen.hands && seen.neck && seen.back);

      // Two pieces on different skin are worth more than either alone.
      const boots = oneOf('fur', 'feet');
      const shirt = oneOf('fur', 'body');
      yes('the table has a fur body piece and fur boots', !!boots && !!shirt);
      if (boots && shirt) {
        function cold(descs) {
          const api = rig();
          api.view(11);
          api.dress(11, descs);
          api.place(11, 'snow');
          api.minutes(60);
          return api.settle(11).temp;
        }
        const both = cold([shirt, boots]);
        yes('boots and a shirt beat a shirt on its own',
            both > cold([shirt]));
        yes('and barefoot costs exactly the boots', both > cold([shirt]) &&
            cold([boots]) > cold([]));
      }
    }

    /*
      AND IT COUNTS IN THE WATER. Patrick: "Make sure clothing affects temp
      while swimming or wading too like barefoot but still has clothes on or
      heavy armor etc".
    */
    if (fur) {
      function swimming(descs, place) {
        const api = rig();
        api.view(12);
        if (descs) { api.dress(12, descs); }
        api.place(12, place, '-', '0', '1', '0');
        api.minutes(60);
        return api.settle(12).temp;
      }
      yes('clothes still count when you are swimming',
          swimming([fur], 'water') > swimming(null, 'water'));
      yes('and when you are wading',
          swimming([fur], 'shallow') > swimming(null, 'shallow'));
    }

    // AND IT CUTS BOTH WAYS. This is the half that makes it a choice.
    if (fur) {
      function hotAfter(descs) {
        const api = rig();
        api.view(8);
        if (descs) { api.dress(8, descs); }
        api.place(8, 'fire');
        api.minutes(60);
        return api.settle(8).temp;
      }
      yes('and the same coat at a forge makes it worse, not better',
          hotAfter([fur]) > hotAfter(null));
    }
  }

  // --------------------------------------------- wind, night and altitude
  {
    let sky = null;
    try { sky = JSON.parse(fs.readFileSync(path.join(__dirname, 'weather.json'), 'utf8')); }
    catch (e) { sky = null; }
    yes('the weather table has been built', !!sky && !!sky.items);
    yes('and is installed in the gamemode', !!skyLine);
    const W = skyLine ? WEATHER : null;

    if (W) {
      /*
        THE MIDDLE IS NOT ZERO, which is the whole reason it is in the table.

        Cathedral Weathers overrides SkyrimClear's wind from 25 to 150 and
        SkyrimStormSnow's from 178 to 150. Scaled against the maximum, a clear
        afternoon would have read as most of a gale. Scaled against the median
        of the load order it reads as nothing, which is what it is.
      */
      yes('the wind is measured against this load order, not against 255',
          W.mid > 0 && W.most > W.mid);

      /*
        TWO WEATHERS OF THE SAME KIND, one calm and one blowing.

        The first version took any weather at or under the median and any at
        the maximum, and the pair it happened to pick were a snowy calm and a
        pleasant gale: the classification term swamped the wind term and the
        check reported the gale as WARMER. Comparing two things that differ in
        two ways measures neither. Same classification, different wind.
      */
      const descs = Object.keys(W.items);
      let calm = null, gale = null;
      for (const kind of [1, 2, 4, 8]) {
        const same = descs.filter(function (d) { return (W.items[d].k & 15) === kind; });
        const low = same.filter(function (d) { return W.items[d].w <= W.mid; })[0];
        const high = same.slice().sort(function (a, b) { return W.items[b].w - W.items[a].w; })[0];
        if (low && high && W.items[high].w > W.items[low].w) { calm = low; gale = high; break; }
      }
      yes('the table has a calm and a windy weather of the same kind to compare',
          !!calm && !!gale);

      function tempIn(opts) {
        const api = rig();
        api.view(20);
        const id = opts.sky ? api.idOf(opts.sky).toString(16) : '-';
        api.place(20, opts.place || 'outdoors', id,
                  opts.night ? '1' : '0', opts.roof ? '1' : '0',
                  String(opts.high || 0));
        api.minutes(60);
        return api.view(20).temp;
      }

      if (calm && gale) {
        yes('a gale is colder than a calm day in the same place',
            tempIn({ sky: gale }) < tempIn({ sky: calm }));
        /*
          AND A ROOF STOPS ALL OF IT. This is the check that says the whole
          exposure term is gated where it says it is: same gale, same night,
          same mountain, one of them indoors.
        */
        const outside = tempIn({ sky: gale, night: true, high: 20000 });
        const inside = tempIn({ sky: gale, night: true, high: 20000, roof: true,
                                place: 'indoors' });
        yes('and none of it reaches somebody under a roof', inside > outside + 10);
      }

      yes('night is colder than day', tempIn({ night: true }) < tempIn({ night: false }));
      yes('a mountain top is colder than the tundra',
          tempIn({ high: 25000 }) < tempIn({ high: 0 }));
      yes('and a hill is not', Math.abs(tempIn({ high: 3000 }) - tempIn({ high: 0 })) < 0.01);

      // A campfire in a blizzard is still a campfire, but it is not an inn.
      if (gale) {
        const fireOut = tempIn({ place: 'fire', sky: gale, night: true });
        const fireIn = tempIn({ place: 'fire', roof: true });
        yes('a fire in the open beats nothing but loses to a fire indoors',
            fireOut > 50 && fireOut < fireIn);
      }

      // A client that knows none of this still works.
      {
        const api = rig();
        api.view(21);
        api.place(21, 'snow');
        api.minutes(60);
        yes('a client that sends the word alone still gets a temperature',
            api.view(21).temp < 30);
      }
    }
  }

  // ---------------------------------------------------------- water types
  {
    let wet = null;
    try { wet = JSON.parse(fs.readFileSync(path.join(__dirname, 'waters.json'), 'utf8')); }
    catch (e) { wet = null; }
    yes('the water table has been built', !!wet && !!wet.waters);
    yes('and is installed in the gamemode', !!wetLine);

    if (wet) {
      yes('it found the classes Patrick named, including ice and shallow water',
          wet.byClass.ice > 0 && wet.byClass.puddle > 0 &&
          wet.byClass.lava > 0 && wet.byClass.marsh > 0);
      /*
        THE UNLIT FIRE OF THIS TABLE: a class that matched nothing would mean
        the rule is wrong rather than that Skyrim has no such water, and a
        class the gamemode has no number for is a silent zero.
      */
      const priced = Object.keys(NEEDS.water);
      const classes = Object.keys(wet.byClass);
      const unpriced = classes.filter(function (c) { return priced.indexOf(c) === -1; });
      yes('and the gamemode has a number for every class it produced' +
          (unpriced.length ? ' (missing ' + unpriced.join(', ') + ')' : ''),
          unpriced.length === 0);
    }

    // Two people in the same weather, one in a river and one in Frostreach.
    {
      const icy = Object.keys(WATERS.items).filter(function (d) { return WATERS.items[d] === 'ice'; })[0];
      const warm = Object.keys(WATERS.items).filter(function (d) { return WATERS.items[d] === 'still'; })[0];
      yes('the installed table has an icy place and a warm one', !!icy && !!warm);
      function swimIn(desc, place) {
        const api = rig();
        api.view(30);
        if (desc) { api.cellOf(30, desc); }
        api.place(30, place || 'water', '-', '0', '1', '0');
        api.minutes(60);
        return api.view(30).temp;
      }
      if (icy && warm) {
        yes('swimming in ice is colder than swimming in a warm indoor pool',
            swimIn(icy) < swimIn(warm));
        yes('and an unlisted lake is somewhere in between',
            swimIn('nowhere:X.esm') < swimIn(warm) && swimIn('nowhere:X.esm') > swimIn(icy));
      }
      // Wading is not swimming. Patrick asked for shallow by name.
      yes('wading is warmer than swimming',
          swimIn('nowhere:X.esm', 'shallow') > swimIn('nowhere:X.esm', 'water'));
      yes('the client has a word for wading',
          /wading = /.test(FRONT) && /kind = 'shallow'/.test(FRONT));
      // And the water class only ever applies to somebody in the water.
      {
        const icy2 = Object.keys(WATERS.items).filter(function (d) { return WATERS.items[d] === 'ice'; })[0];
        const api = rig();
        api.view(31);
        if (icy2) { api.cellOf(31, icy2); }
        api.place(31, 'indoors', '-', '0', '1', '0');
        api.minutes(60);
        yes('but standing beside icy water is not standing in it',
            api.view(31).temp === NEEDS.place.indoors);
      }
    }
  }

  // --------------------------------------------- fire spreading to people
  {
    yes('the client tells the server it is on fire',
        /tellServer\('\/burn 1'\)/.test(FRONT) && /tellServer\('\/burn 0'\)/.test(FRONT));
    yes('and the server answers that command', /word === '\/burn'/.test(src));
    yes('and there is a property to tell somebody else they caught it',
        /thornswoodBurn/.test(src) && /function burnScript/.test(src));
    yes('which the plugin picks up', /thornswoodCatchFire/.test(FRONT) &&
        /thornswoodCatchFire/.test(src));

    const api = rig();
    api.view(40); api.view(41); api.view(42);
    api.putAt(40, [0, 0, 0]);
    api.putAt(41, [100, 0, 0]);                 // next to them
    api.putAt(42, [5000, 0, 0]);                // across the field
    api.setBurning(40, true);
    api.burnTick();
    yes('somebody standing next to a burning person catches fire',
        api.caught(41).length === 1);
    yes('and somebody across the field does not', api.caught(42).length === 0);

    // A different cell is a different room, whatever the coordinates say.
    {
      const b = rig();
      b.view(50); b.view(51);
      b.putAt(50, [0, 0, 0]);
      b.putAt(51, [100, 0, 0]);
      b.cellOf(51, 'somewhere-else:X.esm');
      b.setBurning(50, true);
      b.burnTick();
      yes('but not through a wall into another cell', b.caught(51).length === 0);
    }

    // A client that stops reporting stops being a fire.
    {
      const c = rig();
      c.view(60); c.view(61);
      c.putAt(60, [0, 0, 0]);
      c.putAt(61, [100, 0, 0]);
      c.setBurning(60, true);
      c.minutes(1);
      c.burnTick();
      yes('a client that stops saying it is alight stops setting people alight',
          c.caught(61).length === 0);
    }
  }

  // ------------------------------------------------------- catching on fire
  {
    yes('standing IN a fire burns you', /damageActorValue\('Health'/.test(FRONT));
    yes('and you are visibly on fire while it happens',
        /EffectShader\.from/.test(FRONT) && /shader\.play\(/.test(FRONT));
    yes('it stops when you step out', /shader\.stop\(/.test(FRONT));
    const inside = /const FIRE_INSIDE = (\d+)/.exec(FRONT);
    const reach = /const FIRE_REACH = (\d+)/.exec(FRONT);
    yes('being near a fire is not the same as being in one',
        !!inside && !!reach && Number(inside[1]) < Number(reach[1]));
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
