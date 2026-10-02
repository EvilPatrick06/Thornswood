// test-putback-flora.js
//
// #382 leftovers: refused fish / hanging game presses must put the FLOR back,
// and a successful plant pick must NOT put the plant back.
//
// Measured on the clone (27 Sep MT): plants called putBack on every non-ALLOW
// toast, including "You pick the ...", so a real gather was un-picked at once.
// Fish and hanging game never called putBack, so a non-Fisher pressing a clam
// left it stripped for everybody.
//
// Read only against game/gamemode.js.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function liftFn(name) {
  const a = src.indexOf('\nfunction ' + name + '(');
  if (a < 0) { return null; }
  const open = src.indexOf('{', a);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') { depth++; }
    else if (src[i] === '}') { depth--; if (!depth) { return src.slice(a + 1, i + 1); } }
  }
  return null;
}

function cut(from, end) {
  const a = src.indexOf(from);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a);
  return b < 0 ? null : src.slice(a, b + end.length);
}

const floraSrc = liftFn('floraHanded');
yes('floraHanded() is in the gamemode', !!floraSrc);
const floraHanded = floraSrc ? new Function('return (' + floraSrc + ')')() : function () { return false; };

const ALLOW = { thornswoodAllow: true };
yes('floraHanded is true for a pick toast', floraHanded('You pick the Lavender.'));
yes('floraHanded is true for a pick toast with rank line',
    floraHanded('You pick the Lavender. You are now Advanced Gatherer.'));
yes('floraHanded is true for a take toast',
    floraHanded('You take 1 Clam Meat out of the Clam.'));
yes('floraHanded is true for hanging game take',
    floraHanded('You take 1 Pheasant Breast off the Pheasant.'));
yes('floraHanded is false for a fisher refusal',
    !floraHanded('Only a fisher can fish. Ask one.'));
yes('floraHanded is false for a gatherer refusal',
    !floraHanded('Only a gatherer can pull that out of the ground. Ask one.'));
yes('floraHanded is false for a hunter refusal',
    !floraHanded('Only a hunter can take anything off a carcass. Ask one.'));
yes('floraHanded is false for fished-out wait',
    !floraHanded('This water is fished out for now. 9 minutes to go.'));
yes('floraHanded is false for ALLOW', !floraHanded(ALLOW));
yes('floraHanded is false for empty or null', !floraHanded('') && !floraHanded(null));

function wouldPutBack(message) {
  return !!(message && message !== ALLOW && !floraHanded(message));
}
yes('a refusal would put back', wouldPutBack('Only a fisher can fish. Ask one.'));
yes('a successful pick would NOT put back', !wouldPutBack('You pick the Lavender.'));
yes('a successful take would NOT put back', !wouldPutBack('You take 1 Clam Meat out of the Clam.'));
yes('ALLOW would NOT put back', !wouldPutBack(ALLOW));
yes('null would NOT put back', !wouldPutBack(null));

const handler = cut("mp.onActivate = guard('onActivate', function (refrId, casterRefrId) {", '\n});\n');
yes('onActivate is in the gamemode', !!handler);

if (handler) {
  const fishBranch = handler.indexOf('else if (isFish(baseDesc))');
  const gameBranch = handler.indexOf('else if (isGame(baseDesc))');
  const plantBranch = handler.indexOf('else if (isPlant(baseDesc))');
  const churnBranch = handler.indexOf('else if (isChurn(baseDesc))');
  yes('fish, game, plant and churn branches are present',
      fishBranch >= 0 && gameBranch >= 0 && plantBranch >= 0 && churnBranch >= 0);

  function branchSlice(start, nextMarks) {
    let end = handler.length;
    for (const m of nextMarks) {
      const i = handler.indexOf(m, start + 1);
      if (i >= 0 && i < end) { end = i; }
    }
    return handler.slice(start, end);
  }

  const fishText = branchSlice(fishBranch, ['else if (isGame(baseDesc))', 'else if (isChurn(baseDesc))']);
  const gameText = branchSlice(gameBranch, ['else if (isChurn(baseDesc))', 'else if (isPlant(baseDesc))']);
  const plantText = branchSlice(plantBranch, ['else if (isVein(baseDesc))', 'else {']);
  const churnText = branchSlice(churnBranch, ['else if (isPlant(baseDesc))', 'else if (isVein(baseDesc))']);

  yes('fish branch calls putBack gated by floraHanded',
      /putBack\(casterRefrId, refrId\)/.test(fishText) &&
      /!floraHanded\(message\)/.test(fishText));
  yes('game branch calls putBack gated by floraHanded',
      /putBack\(casterRefrId, refrId\)/.test(gameText) &&
      /!floraHanded\(message\)/.test(gameText));
  yes('plant branch calls putBack gated by floraHanded',
      /putBack\(casterRefrId, refrId\)/.test(plantText) &&
      /!floraHanded\(message\)/.test(plantText));
  yes('churn still puts back on every non-ALLOW answer (Butter and refusals)',
      /putBack\(casterRefrId, refrId\)/.test(churnText) &&
      /message && message !== ALLOW/.test(churnText) &&
      !/floraHanded/.test(churnText));

  // Old bug shape: plant putBack without floraHanded.
  yes('plant branch is not the old un-gated putBack',
      !/if \(message && message !== ALLOW\) \{ putBack\(casterRefrId, refrId\); \}/.test(plantText));
}

// Real fish() / harvest() toast shapes against the compiled verbs.
{
  const fishFn = liftFn('fish');
  const harvestFn = liftFn('harvest');
  const gameFn = liftFn('game');
  yes('fish, harvest and game lift', !!fishFn && !!harvestFn && !!gameFn);

  const fishTable = cut('// ==== FISH_BY_BASE, generated ====', '// ==== end FISH_BY_BASE ====');
  const gameTable = cut('// ==== GAME_BY_BASE, generated ====', '// ==== end GAME_BY_BASE ====');
  yes('fish and game tables cut', !!fishTable && !!gameTable);

  const FISH_BY_BASE = new Function(fishTable + '\nreturn FISH_BY_BASE;')();
  const GAME_BY_BASE = new Function(gameTable + '\nreturn GAME_BY_BASE;')();
  const fishBase = Object.keys(FISH_BY_BASE).find(k => FISH_BY_BASE[k].rank === 'novice');
  const gameBase = Object.keys(GAME_BY_BASE).find(k => GAME_BY_BASE[k].rank === 'novice');
  yes('novice fish and game rows exist', !!fishBase && !!gameBase);

  const given = [];
  const FISH_NO = 'Only a fisher can fish. Ask one.';
  const GATH_NO = 'Only a gatherer can pull that out of the ground. Ask one.';
  const HUNT_NO = 'Only a hunter can take anything off a carcass. Ask one.';

  function makeFish(gateWho) {
    return new Function(
      'classGate', 'rankStep', 'rankWord', 'RANK_LADDER', 'addItem', 'creditWork',
      'cooldownLeft', 'stampCooldown', 'waitWord', 'randInt', 'FISH_BY_BASE', 'FISH_TUNING',
      'isFish',
      fishFn + '\nreturn fish;'
    )(
      function (actorId, verb) {
        if (verb === 'fish' && actorId !== 1) { return FISH_NO; }
        return null;
      },
      function () { return 0; },
      function (r) { return r; },
      ['novice', 'advanced', 'expert', 'master'],
      function (a, d, n) { given.push([a, d, n]); return true; },
      function () { return null; },
      function () { return 0; },
      function () { },
      function () { return '1 minute'; },
      function (a) { return a; },
      FISH_BY_BASE,
      { cooldownMs: { novice: 1, advanced: 1, expert: 1, master: 1 }, yieldByStep: { 0: [1, 1] } },
      function (d) { return Object.prototype.hasOwnProperty.call(FISH_BY_BASE, d); }
    );
  }

  given.length = 0;
  const fish = makeFish();
  const refused = fish(2, 0x10, fishBase);
  yes('fish() refuses a non-fisher with the class line', refused === FISH_NO);
  yes('and gives nothing', given.length === 0);
  yes('and that refusal is a putBack case', wouldPutBack(refused));

  const ok = fish(1, 0x10, fishBase);
  yes('fish() hands a fisher a You take toast', /^You take /.test(ok || ''));
  yes('and that success is NOT a putBack case', !wouldPutBack(ok));
  yes('and produce was given', given.length === 1);

  function makeGame() {
    return new Function(
      'classGate', 'rankStep', 'rankWord', 'RANK_LADDER', 'addItem', 'creditWork',
      'cooldownLeft', 'stampCooldown', 'waitWord', 'randInt', 'GAME_BY_BASE', 'GAME_TUNING',
      'isGame',
      gameFn + '\nreturn game;'
    )(
      function (actorId, verb) {
        if (verb === 'loot' && actorId !== 1) { return HUNT_NO; }
        return null;
      },
      function () { return 0; },
      function (r) { return r; },
      ['novice', 'advanced', 'expert', 'master'],
      function (a, d, n) { given.push([a, d, n]); return true; },
      function () { return null; },
      function () { return 0; },
      function () { },
      function () { return '1 minute'; },
      function (a) { return a; },
      GAME_BY_BASE,
      { cooldownMs: { novice: 1, advanced: 1, expert: 1, master: 1 }, yieldByStep: { 0: [1, 1] } },
      function (d) { return Object.prototype.hasOwnProperty.call(GAME_BY_BASE, d); }
    );
  }

  given.length = 0;
  const game = makeGame();
  const gNo = game(2, 0x11, gameBase);
  yes('game() refuses a non-hunter', gNo === HUNT_NO && wouldPutBack(gNo));
  const gOk = game(1, 0x11, gameBase);
  yes('game() hands a hunter a You take toast that stays empty',
      /^You take /.test(gOk || '') && !wouldPutBack(gOk) && given.length === 1);

  // harvest: need plantAt + isCrop
  const plant = {
    produce: '57f91:Skyrim.esm',
    name: 'Hanging Moss',
    rank: 'novice'
  };
  function makeHarvest(whoOk) {
    return new Function(
      'classGate', 'rankStep', 'rankWord', 'RANK_LADDER', 'addItem', 'creditWork',
      'HARVEST_COOLDOWN_MS', 'isCrop', 'plantAt', 'lastUse', 'stampCooldown',
      harvestFn + '\nreturn harvest;'
    )(
      function (actorId, verb) {
        if (verb === 'harvest' && actorId !== whoOk) { return GATH_NO; }
        return null;
      },
      function () { return 0; },
      function (r) { return r; },
      ['novice', 'advanced', 'expert', 'master'],
      function (a, d, n) { given.push([a, d, n]); return true; },
      function () { return null; },
      10 * 60 * 1000,
      function () { return false; },
      function () { return plant; },
      new Map(),
      function (a, r) { /* stamp */ }
    );
  }

  given.length = 0;
  const harvestOk = makeHarvest(1);
  const hOk = harvestOk(1, 0x12, 'bb94f:Skyrim.esm');
  yes('harvest() hands a gatherer a You pick toast', /^You pick /.test(hOk || ''));
  yes('and that success is NOT a putBack case (#382)', !wouldPutBack(hOk));
  yes('and produce was given', given.length === 1);

  given.length = 0;
  const harvestNo = makeHarvest(1);
  const hNo = harvestNo(2, 0x12, 'bb94f:Skyrim.esm');
  yes('harvest() refuses a non-gatherer', hNo === GATH_NO);
  yes('and that refusal IS a putBack case', wouldPutBack(hNo) && given.length === 0);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
