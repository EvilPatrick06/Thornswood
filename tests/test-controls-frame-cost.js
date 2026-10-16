// test-controls-frame-cost.js
//
// The controls watchdog must not call into the game on every update.
//
// MEASURED 26 September on DevBuild thornswood-front.log (~14:28-14:35 MT):
// controls was #1 in 11/13 heartbeats at 366-736 ms per ~30 s, after
// MENU_CACHE_MS and CONTROLS_CACHE_MS were already 250. The residual was
// getPlayer + notOurs (getPlayer again, isDead, getFurnitureReference) on
// every frame. The fix gates the whole tick at CONTROLS_CACHE_MS and caches
// notOurs at the same rate.
//
// This lifts the real CONTROLS table, caches, notOurs, readControls and
// controlsTick out of the plugin and runs them on a fake clock and fake sp.
// Native counts prove the happy path is four times a second, not thirty, and
// that five seconds of controls-off still turns them back on.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const SRC = process.env.FRONT ||
            path.join(REPO_DIR, 'game', 'plugins', 'thornswood-front.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const START = '  const CONTROLS = [';
const END_MARK = "  sp.on('update', guard('controls', controlsTick));";
const a = src.indexOf(START);
const b = a < 0 ? -1 : src.indexOf(END_MARK, a);
// While bound (#2573) the watchdog leaves fighting off: boundOn and
// controlsBackOn sit just above the extract in the plugin, so they are lifted
// with it, as the plugin has them, nobody bound.
const BOUND_FROM = src.indexOf('  function controlsBackOn() {');
const BOUND_PIECE = BOUND_FROM < 0 ? '' : src.slice(BOUND_FROM, src.indexOf('\n  }\n', BOUND_FROM) + 4);
const block = (a >= 0 && b >= 0 && BOUND_PIECE) ? 'let boundOn = false;\n' + BOUND_PIECE + src.slice(a, b) : null;

yes('the plugin still has its controls watchdog', block !== null);
yes('CONTROLS_CACHE_MS is 250', /const CONTROLS_CACHE_MS = 250;/.test(src));
yes('controlsTick gates on controlsTickAt',
    /if \(now - controlsTickAt < CONTROLS_CACHE_MS\) \{ return; \}/.test(src));
yes('notOurs is cached at CONTROLS_CACHE_MS',
    /if \(now - notOursCachedAt < CONTROLS_CACHE_MS\) \{ return notOursCached; \}/.test(src));

function harness(opts) {
  opts = opts || {};
  const clock = { t: 0 };
  const counts = {
    getPlayer: 0,
    isDead: 0,
    getFurniture: 0,
    isMenuOpen: 0,
    controlReads: 0,
    enable: 0,
    setAI: 0
  };
  const said = [];
  const menus = opts.menus || {};
  const flags = Object.assign({
    isMovementControlsEnabled: true,
    isFightingControlsEnabled: true,
    isCamSwitchControlsEnabled: true,
    isLookingControlsEnabled: true,
    isSneakingControlsEnabled: true,
    isMenuControlsEnabled: true,
    isActivateControlsEnabled: true,
    isJournalControlsEnabled: true
  }, opts.flags || {});
  const player = {
    isDead: function () { counts.isDead++; return !!opts.dead; },
    getFurnitureReference: function () {
      counts.getFurniture++;
      return opts.furniture || null;
    },
    getSitState: function () { return opts.sitState || 0; }
  };
  const sp = {
    Game: {
      getPlayer: function () { counts.getPlayer++; return opts.noPlayer ? null : player; },
      enablePlayerControls: function () { counts.enable++; },
      setPlayerAIDriven: function () { counts.setAI++; }
    },
    Ui: {
      isMenuOpen: function (name) {
        counts.isMenuOpen++;
        return !!menus[name];
      }
    }
  };
  Object.keys(flags).forEach(function (k) {
    sp.Game[k] = function () { counts.controlReads++; return flags[k]; };
  });

  // Minimal busyMenuOpen that matches the plugin's KEYBOARD_MENUS walk.
  const KEYBOARD_MENUS = [
    'Console', 'Crafting Menu', 'ContainerMenu', 'Dialogue Menu', 'FavoritesMenu',
    'GiftMenu', 'InventoryMenu', 'Journal Menu', 'Lockpicking Menu', 'Loading Menu',
    'MagicMenu', 'MapMenu', 'RaceSex Menu', 'StatsMenu', 'TweenMenu', 'Main Menu',
    'MessageBoxMenu', 'Book Menu', 'Sleep/Wait Menu', 'Barter Menu', 'Training Menu',
  ];
  function busyMenuOpen() {
    for (let i = 0; i < KEYBOARD_MENUS.length; i++) {
      if (sp.Ui.isMenuOpen(KEYBOARD_MENUS[i])) { return KEYBOARD_MENUS[i]; }
    }
    return '';
  }
  const say = function (t) { said.push(t); };
  const FakeDate = { now: function () { return clock.t; } };
  const fn = new Function('sp', 'busyMenuOpen', 'say', 'Date',
    block + '\nreturn { tick: controlsTick, off: function () { return controlsOffNow; },' +
    ' since: function () { return controlsSince; }, cacheMs: CONTROLS_CACHE_MS,' +
    ' notOurs: notOurs, readControls: readControls };');
  const api = fn(sp, busyMenuOpen, say, FakeDate);
  api.clock = clock;
  api.counts = counts;
  api.said = said;
  api.at = function (t) { clock.t = t; api.tick(); };
  api.run = function (from, to, step) {
    step = step || 16;
    for (let t = from; t <= to; t += step) { api.at(t); }
  };
  api.setFlag = function (name, on) { flags[name] = on; };
  return api;
}

if (block) {
  // Happy path: ~60 frames a second for 30 seconds should call getPlayer
  // about 4 times a second (CONTROLS_CACHE_MS), not every frame.
  const h = harness();
  // Step at the cache rate so the expected count is exact; a tighter 16ms
  // loop is covered by the stuck / death / menu cases below.
  // Start after 0: controlsTickAt begins at 0, and (now - 0) < 250 would
  // skip a fake clock at t=0 the way a real Date.now() never would.
  h.run(250, 30250, 250);
  const expectedTicks = Math.floor(30000 / h.cacheMs) + 1; // 250..30250 inclusive
  // One getPlayer in controlsTick, one inside notOursNow per tick.
  const expectedPlayers = expectedTicks * 2;
  yes('happy path: getPlayer twice per tick over 30s (got ' +
      h.counts.getPlayer + ', expect ' + expectedPlayers + ')',
      h.counts.getPlayer === expectedPlayers);
  yes('happy path: isDead once per tick (got ' + h.counts.isDead + ', expect ' + expectedTicks + ')',
      h.counts.isDead === expectedTicks);
  // Same wall time at 60fps would be ~3600 frames; prove we are not there.
  const hFrame = harness();
  hFrame.run(250, 30250, 16);
  yes('happy path at 60fps step: still ~4Hz natives (got ' + hFrame.counts.isDead + ' isDead)',
      hFrame.counts.isDead <= expectedTicks &&
      hFrame.counts.isDead >= expectedTicks - 6);
  yes('happy path at 60fps step: far below every-frame getPlayer',
      hFrame.counts.getPlayer < Math.floor(30000 / 16));
  yes('happy path: never enables controls when they are on', h.counts.enable === 0);
  yes('happy path: controlsOffNow stays empty', h.off().length === 0);

  // Cache hit: two notOurs calls 16ms apart only ask the game once.
  const h2 = harness();
  h2.clock.t = 1000;
  h2.notOurs();
  const afterFirst = h2.counts.getPlayer;
  h2.clock.t = 1016;
  h2.notOurs();
  yes('notOurs cache: second call within 250ms does no getPlayer',
      h2.counts.getPlayer === afterFirst);
  h2.clock.t = 1300;
  h2.notOurs();
  yes('notOurs cache: call after 250ms refreshes',
      h2.counts.getPlayer === afterFirst + 1);

  // Stuck: movement off for five seconds turns controls back on once.
  const h3 = harness({ flags: { isMovementControlsEnabled: false } });
  h3.run(0, 6000, 16);
  yes('stuck: enables controls after five seconds off (got enable=' +
      h3.counts.enable + ')', h3.counts.enable === 1);
  yes('stuck: clears AI driven with the enable', h3.counts.setAI === 1);
  yes('stuck: says what it fixed',
      h3.said.length === 1 && /movement/.test(h3.said[0]));

  // Death: never fights the death camera.
  const h4 = harness({
    dead: true,
    flags: { isMovementControlsEnabled: false }
  });
  h4.run(0, 6000, 16);
  yes('dead: does not enable controls', h4.counts.enable === 0);

  // Menu open: does not enable, and isMenuOpen is only asked on tick rate.
  const h5 = harness({
    menus: { InventoryMenu: true },
    flags: { isMovementControlsEnabled: false }
  });
  h5.run(0, 3000, 16);
  yes('menu open: does not enable controls', h5.counts.enable === 0);
  const menuTicks = Math.floor(3000 / h5.cacheMs) + 1;
  yes('menu open: isMenuOpen only on the tick rate, not every frame (got ' +
      h5.counts.isMenuOpen + ')',
      h5.counts.isMenuOpen <= menuTicks * 25); // 21 menus max per tick

  // Furniture (#843): sitting must not be fought by the watchdog.
  const h6 = harness({
    furniture: { id: 1 },
    flags: { isMovementControlsEnabled: false }
  });
  h6.run(0, 6000, 16);
  yes('furniture: does not enable controls while seated', h6.counts.enable === 0);

  const h7 = harness({
    sitState: 3,
    flags: { isMovementControlsEnabled: false }
  });
  h7.run(0, 6000, 16);
  yes('sitState 3 with no furniture ref: does not enable', h7.counts.enable === 0);
}

console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
