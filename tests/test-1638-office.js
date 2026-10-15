// test-1638-office.js
//
// #1638. A Jarl and a steward are people in the world, not staff, so their
// powers are buttons (Patrick, 4 Oct: no commands for things people do).
// They live on an Office page of the K panel for the character that holds an
// office or may take one: Take the office; name a steward by picking a person
// in the world, and remove one; and for a steward, evict and set or clear the
// rent at the door just opened, make the container just opened a hold's box,
// and move a board to where they stand. Each button sends the line the
// command was, which the server still answers; none is named to anybody.
//
// #502, Patrick, 12 Oct: guards are named by the Jarl of that hold, and
// taking the Jarl office asks for a hold. So the office is taken by pressing
// its hold (twice), the hold is chosen once, and the Jarl of a hold names and
// removes that hold's guards alone (section I, and H14 to H17 on the page).
//
// The server half is lifted out of the property block and run together over
// a small world: the page's view (officeView), and the lines the buttons
// send, through the property block's own command. The page half is the real
// game/ui/thornswood-skills.js in a stand-in document, the way
// tests/test-1387-college.js runs it, with its buttons pressed.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(process.env.GM || path.join(REPO_DIR, 'game', 'gamemode.js'), 'utf8').split(CR).join('');
/*
  One topic of the help panel (#1633), as a fresh install reads it: /help's
  topics moved out of the gamemode into game/ui/thornswood-help.js, each a
  list of paragraphs made from the key names.
*/
function helpTopic(id) {
  const page = fs.readFileSync(path.join(REPO_DIR, 'game', 'ui', 'thornswood-help.js'), 'utf8')
    .split(String.fromCharCode(13)).join('');
  const a = page.indexOf('  var TOPICS = [');
  const b = a < 0 ? -1 : page.indexOf('\n  ];\n', a);
  const k = /var keys = (\{[\s\S]*?\});/.exec(page);
  if (a < 0 || b < 0 || !k) { return ''; }
  try {
    const topics = new Function('return ' + page.slice(page.indexOf('[', a), b + 4))();
    const t = topics.filter(function (x) { return x.id === id; })[0];
    return t ? t.text(new Function('return ' + k[1])()).join(' ') : '';
  } catch (e) { return ''; }
}
const ui = fs.readFileSync(path.join(REPO_DIR, 'game', 'ui', 'thornswood-skills.js'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function slice(src, start, end) {
  if (src === null) { return null; }
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}
function strip(s) {
  return String(s || '').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
}

const prop = slice(gm, '// ==== thornswood property ====', '// ==== end thornswood property ====');
const charBlock = slice(gm, '// ==== thornswood character ====', '// ==== end thornswood character ====');
yes('the property and character blocks are in the gamemode', prop !== null && charBlock !== null);

/* One function out of the property block, by name, once. */
function fn(name) {
  if (!prop) { return null; }
  const head = '\n  function ' + name + '(';
  const a = prop.indexOf(head);
  if (a < 0 || prop.indexOf(head, a + 1) >= 0) { return null; }
  const b = prop.indexOf('\n  }\n', a + 1);
  return b < 0 ? null : prop.slice(a + 1, b + 4);
}
/* One var line out of the property block. */
function line(re) {
  const m = prop ? re.exec(prop) : null;
  return m ? m[0] : null;
}

const NAMES = ['officeView', 'officeRedraw', 'stewardCmd', 'jarlCmd', 'guardCmd', 'officeHoldOf', 'jarlHoldOf',
               'seatOf', 'seatHeldBy', 'giveUpJarl', 'officeOf',
               'guardHoldOf', 'evict', 'rentCmd', 'boxCmd',
               'moveBoard', 'board', 'command', 'isJarl', 'isSteward', 'holderOf', 'here', 'buildingOf',
               'boxAt', 'holdOfBox', 'rentDue', 'nameOf', 'profileOf', 'onlineActorOf', 'redrawPanel', 'personName',
               'boardHere'];
const lifted = {};
const missing = [];
NAMES.forEach(function (n) { lifted[n] = fn(n); if (!lifted[n]) { missing.push(n); } });
yes('every piece of the offices is in the property block, once' +
    (missing.length ? ' (missing: ' + missing.join(', ') + ')' : ''), missing.length === 0);
const VARS = [
  line(/  var LEDGER_HOLDS = \[[^\]]*\];/),
  line(/  var OFFICE_AT_DOOR = '[^\n]*';/),
  line(/  var OFFICE_PEOPLE_MAX = \d+;/),
  line(/  var DOOR_MEMORY_MS = \d+;/),
  line(/  var DOOR_PROPERTY = '[^']*';/),
  line(/  var BOX_PROPERTY = '[^']*';/),
  line(/  var BOARD_REACH = \d+;/),
  line(/  var HOLD_TOWN = \{[^}]*\};/),
  line(/  var JAIL_NAME = \{[^\n]*\};/)
];
yes('and the numbers and names they read', VARS.every(function (v) { return !!v; }));

const TAMRIEL = '3c:Skyrim.esm';
const DOOR = '1a2b3:Skyrim.esm';
const HOUSE = 'breezehome';
const CHEST = 0x0004cafe;
const HOLDS10 = ['whiterun', 'solitude', 'riften', 'markarth', 'windhelm',
                 'falkreath', 'morthal', 'dawnstar', 'winterhold', 'ravenrock'];

/* A server: the property block's office pieces over a world of people. */
function server() {
  const people = {};       // actor -> { pid, name, cell, pos, door, box }
  const online = [];
  const states = {};       // actor -> character state
  const writes = [];       // [actor, redraw]
  const roles = { admin: {}, jarl: {} };
  const reg = { saves: 0, pushes: 0, lawSaves: 0 };
  const mp = {
    get: function (id, key) {
      if (id === 0 && key === 'onlinePlayers') { return online.slice(); }
      const p = people[id];
      if (!p) { return undefined; }
      if (key === 'profileId') { return p.pid; }
      if (key === 'appearance') { return p.name ? { name: p.name } : {}; }
      if (key === 'worldOrCellDesc') { return p.cell; }
      if (key === 'pos') { return p.pos.slice(); }
      if (key === 'thornswoodDoor') { return p.door || undefined; }
      if (key === 'thornswoodBoxAt') { return p.box || undefined; }
      return undefined;
    },
    set: function () { }
  };
  const g = {
    __thornswoodIsAdmin: function (pid) { return !!roles.admin[pid]; },
    __thornswoodIsJarl: function (pid) { return !!roles.jarl[pid]; },
    __thornswoodCharacter: {
      stateOf: function (aid) { return states[aid] || null; },
      writeState: function (aid, s, redraw) { states[aid] = s; writes.push([aid, !!redraw]); return s; }
    }
  };
  const boards = {};
  HOLDS10.forEach(function (h, i) {
    boards[h] = { cell: TAMRIEL, pos: [i * 10000, 0, 0],
                  where: h === 'ravenrock' ? 'Raven Rock' : h.charAt(0).toUpperCase() + h.slice(1) };
  });
  const body = [
    'var claims = {}; var stewards = []; var boxes = {}; var funds = {}; var notices = {};',
    'var BUILDING_BY_DOOR = {}; BUILDING_BY_DOOR[' + JSON.stringify(DOOR) + '] = ' + JSON.stringify(HOUSE) + ';',
    'var BUILDING_NAME = { breezehome: "Breezehome" };',
    'function lapseDays() { return 14; }',
    'function save() { reg.saves++; }',
    'function pushAll() { reg.pushes++; }',
    'var law = { guards: {}, cells: {}, jarls: {} };',
    'function jailOfBuilding(b) { return b === "dungeon" ? "whiterun" : null; }',
    'function saveLaw() { reg.lawSaves++; }',
    'function plog() { }',
    ['deeds', 'setLock', 'mold', 'moldHere', 'cutKey', 'claim', 'sleepHere', 'post', 'take', 'jobs',
     'dropJob', 'unpin', 'postLetter', 'deliver', 'haulCmd', 'haulText']
      .map(function (n) { return 'function ' + n + '() { return true; }'; }).join('\n')
  ].concat(VARS, NAMES.map(function (n) { return lifted[n]; }));
  body.push('return { command: command, officeView: officeView, isJarl: isJarl, isSteward: isSteward, officeOf: officeOf, ' +
            'claims: claims, stewards: stewards, boxes: boxes, boards: boards, law: law, ' +
            'OFFICE_AT_DOOR: OFFICE_AT_DOOR };');
  const make = new Function('mp', 'g', 'boards', 'reg', body.join('\n'));
  const api = make(mp, g, boards, reg);
  api.people = people; api.states = states; api.writes = writes; api.roles = roles; api.reg = reg;
  api.add = function (actor, pid, name) {
    people[actor] = { pid: pid, name: name, cell: TAMRIEL, pos: [500, 500, 0] };
    online.push(actor);
    states[actor] = { office: null };
  };
  api.view = function (actor) { return api.officeView(actor, people[actor].pid, states[actor]); };
  api.say = function (actor, text) {
    const parts = text.trim().split(/\s+/);
    const told = [];
    const answered = api.command(parts[0], parts, actor, people[actor].pid, function (pid, m) { told.push(m); });
    return { answered: answered, told: told.join('\n') };
  };
  api.atDoor = function (actor, ago) { people[actor].door = { door: DOOR, at: Date.now() - (ago || 0) }; };
  api.atBox = function (actor, ago) { people[actor].box = { refr: CHEST, at: Date.now() - (ago || 0) }; };
  api.writesFor = function (actor) { return writes.filter(function (w) { return w[0] === actor; }).length; };
  return api;
}

const JARL = 0xff000201, STEW = 0xff000202, ALICE = 0xff000203, ALICE2 = 0xff000204, NOBODY = 0xff000205, ADMIN = 0xff000206;
const P_JARL = 11, P_STEW = 12, P_ALICE = 13, P_ALICE2 = 14, P_NOBODY = 15, P_ADMIN = 16;

function world() {
  const srv = server();
  srv.add(JARL, P_JARL, 'Balgruuf');
  srv.add(STEW, P_STEW, 'Proventus');
  srv.add(ALICE, P_ALICE, 'Alice');
  srv.add(ALICE2, P_ALICE2, 'Alice');
  srv.add(NOBODY, P_NOBODY, 'Nobody');
  srv.add(ADMIN, P_ADMIN, 'Staff');
  srv.roles.jarl[P_JARL] = true;
  srv.roles.admin[P_ADMIN] = true;
  return srv;
}

if (missing.length === 0 && VARS.every(function (v) { return !!v; })) {
  // ------------------------------------------------------ A. who gets the page
  {
    const srv = world();
    yes('A1 somebody with no office and no Jarl role gets no Office page', srv.view(NOBODY) === null);
    const v = srv.view(JARL);
    yes('A2 a Jarl-role character that has not taken the office gets the page with Take the office and nothing else',
        !!v && v.may === true && v.jarl === false && v.name === false && v.steward === false &&
        v.people.length === 0 && v.door === null && v.boards.length === 0);
    const bare = srv.say(JARL, '/jarl');
    yes('A3 the office is of one hold: /jarl with none seats nothing and says where to press (' + bare.told + ')',
        srv.states[JARL].office === null && /one hold/.test(bare.told) && /Office page of K/.test(bare.told));
    const r = srv.say(JARL, '/jarl whiterun');
    const v2 = srv.view(JARL);
    yes('A3 Take the office sends /jarl, the character holds it, and its page is written again (' + r.told + ')',
        r.answered && srv.states[JARL].office === 'jarl' && srv.states[JARL].officeHold === 'whiterun' &&
        srv.writes.length === 1 && srv.writes[0][1] === true &&
        v2.jarl === true && v2.may === false && v2.name === true && v2.steward === true);
    const a = srv.view(ADMIN);
    yes('A4 an admin may take the office, and names and acts as a steward without it, as isJarl says',
        !!a && a.may === true && a.name === true && a.steward === true);
  }

  // ------------------------- B. the page agrees with isJarl and isSteward
  {
    let agree = true;
    const cases = [];
    [false, true].forEach(function (admin) {
      [false, true].forEach(function (role) {
        [false, true].forEach(function (holds) {
          [false, true].forEach(function (named) {
            const srv = world();
            srv.roles.admin = {}; srv.roles.jarl = {};
            if (admin) { srv.roles.admin[P_ALICE] = true; }
            if (role) { srv.roles.jarl[P_ALICE] = true; }
            srv.states[ALICE].office = holds ? 'jarl' : null;
            if (named) { srv.stewards.push(P_ALICE); }
            const v = srv.view(ALICE);
            const j = srv.isJarl(P_ALICE, ALICE), st = srv.isSteward(P_ALICE, ALICE);
            const ok = v === null ? (!admin && !role && !st) : (v.name === j && v.steward === st);
            if (!ok) { agree = false; cases.push([admin, role, holds, named].join('/')); }
          });
        });
      });
    });
    yes('B1 in all sixteen cases the page names stewards exactly when isJarl says, and is a steward exactly when isSteward says' +
        (cases.length ? ' (wrong: ' + cases.join(', ') + ')' : ''), agree);
    const ov = strip(lifted.officeView);
    yes('B2 the page never reads the character itself: writeState hands it the state, and stateOf there would ask for itself',
        !/stateOf/.test(ov) && !/isJarl\(/.test(ov) && !/isSteward\(/.test(ov));
    const ws = slice(charBlock, '  function writeState(actorId, s, redraw) {', '\n  }\n');
    yes('B3 the character block puts the page on the K panel view, handing it the state in hand',
        !!ws && /W\.officeView\(actorId, pid, s\)/.test(ws) && /view\.officePage = desk;/.test(ws) &&
        /if \(view && !view\.creating\)/.test(ws));
  }

  // ------------------------------------------------ C. naming a steward
  {
    const srv = world();
    srv.say(JARL, '/jarl whiterun');
    const v = srv.view(JARL);
    const names = v.people.map(function (p) { return p.name + ':' + p.pid; });
    yes('C1 the Jarl picks from the people in the world, by name with the id, never themselves (' + names.join(', ') + ')',
        names.join(',') === ['Alice:' + P_ALICE, 'Alice:' + P_ALICE2, 'Nobody:' + P_NOBODY,
                             'Proventus:' + P_STEW, 'Staff:' + P_ADMIN].join(','));
    srv.writes.length = 0;
    const r = srv.say(JARL, '/steward ' + P_ALICE2);
    yes('C2 Name steward beside the second Alice names that Alice and not the first, by name (' + r.told + ')',
        srv.stewards.length === 1 && srv.stewards[0] === P_ALICE2 && r.told === 'Alice is a steward now.');
    yes('C2 and both Office pages are written again, the Jarl\'s and hers',
        srv.writesFor(JARL) === 1 && srv.writesFor(ALICE2) === 1);
    const v2 = srv.view(JARL);
    yes('C3 she is listed as a steward by name, and is no longer offered',
        v2.stewards.length === 1 && v2.stewards[0].pid === P_ALICE2 && v2.stewards[0].name === 'Alice' &&
        v2.people.every(function (p) { return p.pid !== P_ALICE2; }));
    const hers = srv.view(ALICE2);
    yes('C4 her own page appears, as a steward who names nobody',
        !!hers && hers.steward === true && hers.name === false && hers.may === false && hers.people.length === 0);
    const no = srv.say(ALICE2, '/steward ' + P_NOBODY);
    yes('C5 a steward who is not a Jarl cannot name one', no.told === 'Only a jarl names a steward.' && srv.stewards.length === 1);
    srv.writes.length = 0;
    srv.say(JARL, '/steward -' + P_ALICE2);
    yes('C6 Remove takes it back, and both pages are written again',
        srv.stewards.length === 0 && srv.writesFor(JARL) === 1 && srv.writesFor(ALICE2) === 1 &&
        srv.view(ALICE2) === null);
    srv.stewards.push(99);
    const off = srv.view(JARL).stewards.filter(function (w) { return w.pid === 99; })[0];
    yes('C7 a steward who is not in the world is listed by profile, with no name to show', !!off && off.name === '');
    const none = srv.say(NOBODY, '/steward');
    yes('C8 the line with no id still says who holds it', /^Stewards: 99\.$/.test(none.told));
  }

  // ------------------------------------------- D. at the door: evict, rent
  {
    const srv = world();
    srv.say(JARL, '/jarl whiterun');
    srv.say(JARL, '/steward ' + P_STEW);
    const lost = srv.say(STEW, '/evict');
    yes('D1 away from a door the steward is told to open one and use the page, not to say anything (' + lost.told + ')',
        lost.told === srv.OFFICE_AT_DOOR && !/\/|say that again/.test(lost.told));
    yes('D1 and the page says there is no door', srv.view(STEW).door === null);
    srv.claims[HOUSE] = { by: P_ALICE, name: 'Alice', at: Date.now(), touched: Date.now(), locked: false };
    srv.atDoor(STEW);
    const d = srv.view(STEW).door;
    yes('D2 at the door the page names the building, who holds it, and that there is no rent',
        !!d && d.name === 'Breezehome' && d.by === 'Alice' && d.rent === null);
    srv.writes.length = 0;
    const set = srv.say(STEW, '/rent 50');
    const d2 = srv.view(STEW).door;
    yes('D3 Set rent sends /rent 50: 50 gold every 7 days, nothing owed yet, and the page is written again (' + set.told + ')',
        srv.claims[HOUSE].rent.amount === 50 && d2.rent.amount === 50 && d2.rent.every === 7 && d2.rent.owed === 0 &&
        srv.writesFor(STEW) === 1);
    srv.claims[HOUSE].rent.since = Date.now() - 15 * 86400000;
    yes('D4 two weeks on, the page shows 100 owed, counted the way the ledger counts it',
        srv.view(STEW).door.rent.owed === 100);
    const reading = srv.say(NOBODY, '/rent');
    yes('D5 the line with no amount still says what is owed (' + reading.told + ')', false === /Only a steward/.test(reading.told) &&
        /Open the door/.test(reading.told));
    srv.atDoor(NOBODY);
    yes('D5 and at the door it does', srv.say(NOBODY, '/rent').told === 'Breezehome: 50 gold every 7 days, 100 owed.');
    yes('D6 somebody who is not a steward cannot set it', srv.say(NOBODY, '/rent 5').told === 'Only a steward sets rent.' &&
        srv.claims[HOUSE].rent.amount === 50);
    yes('D7 a rent that is not a number of gold is refused in words that type nothing',
        srv.say(STEW, '/rent lots').told === 'The rent is a number of gold above 0.' && srv.claims[HOUSE].rent.amount === 50);
    srv.say(STEW, '/rent -');
    yes('D8 No rent sends /rent -, and the page says there is none', !srv.claims[HOUSE].rent && srv.view(STEW).door.rent === null);
    srv.atDoor(STEW, 61000);
    yes('D9 a door opened more than a minute ago is not the door, on the page or for the line',
        srv.view(STEW).door === null && srv.say(STEW, '/evict').told === srv.OFFICE_AT_DOOR && !!srv.claims[HOUSE]);
    srv.atDoor(STEW);
    srv.writes.length = 0;
    const ev = srv.say(STEW, '/evict');
    yes('D10 Evict ends the claim and the page is written again, now saying nobody holds it (' + ev.told + ')',
        !srv.claims[HOUSE] && srv.writesFor(STEW) === 1 && srv.view(STEW).door.by === null);
    // The Jarl is a steward: isSteward says so, and the lines now ask with the character.
    srv.claims[HOUSE] = { by: P_ALICE, name: 'Alice', at: Date.now(), touched: Date.now(), locked: false };
    srv.atDoor(JARL);
    srv.say(JARL, '/rent 20');
    const jev = srv.say(JARL, '/evict');
    yes('D11 a Jarl who is not staff sets the rent and evicts, the steward the page shows them to be (' + jev.told + ')',
        !srv.claims[HOUSE] && /^You end Alice's claim/.test(jev.told));
  }

  // ----------------------------------------------------------- E. the box
  {
    const srv = world();
    srv.stewards.push(P_STEW);
    yes('E1 with no container opened, the page has none', srv.view(STEW).box === null);
    srv.atBox(STEW);
    yes('E2 the container just opened is nobody\'s box yet', JSON.stringify(srv.view(STEW).box) === '{"hold":null}');
    srv.writes.length = 0;
    const r = srv.say(STEW, '/box riften');
    yes('E3 pressing Riften makes it Riften\'s box, and the page says so (' + r.told + ')',
        srv.boxes.riften === CHEST && srv.view(STEW).box.hold === 'riften' && srv.writesFor(STEW) === 1);
    const typo = srv.say(STEW, '/box riftn');
    yes('E4 a hold that is not one of the ten starts no box (' + typo.told + ')',
        !Object.prototype.hasOwnProperty.call(srv.boxes, 'riftn') && /^No hold called riftn\./.test(typo.told));
    srv.atBox(NOBODY);
    yes('E5 somebody who is not a steward cannot', srv.say(NOBODY, '/box whiterun').told === 'Only a steward sets a hold\'s box.' &&
        !srv.boxes.whiterun);
    srv.atBox(STEW, 61000);
    const late = srv.say(STEW, '/box whiterun');
    yes('E6 a container opened more than a minute ago is not the one, and the answer types nothing (' + late.told + ')',
        !srv.boxes.whiterun && !/\/|say that again/.test(late.told));
  }

  // -------------------------------------------------------- F. the boards
  {
    const srv = world();
    srv.stewards.push(P_STEW);
    const v = srv.view(STEW);
    yes('F1 the page lists the ten boards by town, in the ledger\'s order',
        v.boards.map(function (b) { return b.hold; }).join() === HOLDS10.join() && v.boards[9].where === 'Raven Rock');
    srv.people[STEW].pos = [123, 456, 7];
    const r = srv.say(STEW, '/board move riften');
    yes('F2 /board move riften, which Riften on the page sends, puts the board is where the steward stands (' + r.told + ')',
        srv.boards.riften.pos.join() === '123,456,7' && srv.boards.riften.where === 'Riften');
    const no = srv.say(NOBODY, '/board move whiterun');
    yes('F3 somebody who is not a steward cannot', no.told === 'Only a steward moves a board.' && srv.boards.whiterun.pos[0] === 0);
    srv.say(JARL, '/jarl whiterun');
    srv.people[JARL].pos = [9, 9, 9];
    srv.say(JARL, '/board move whiterun');
    yes('F4 a Jarl who is not staff can', srv.boards.whiterun.pos.join() === '9,9,9');
    srv.people[NOBODY].pos = [-5e6, 0, 0];
    yes('F5 the lines with nothing after them say what to do without naming one to type',
        !/\//.test(srv.say(STEW, '/board move').told) && !/\//.test(srv.say(NOBODY, '/board here').told));
  }

  // ------------------------------------- I. the Jarl of a hold names its guards (#502)
  {
    const srv = world();
    srv.roles.jarl[P_ALICE] = true;
    const before = srv.say(JARL, '/guard ' + P_NOBODY);
    yes('I1 a Jarl-role character with no office names no guard (' + before.told + ')',
        before.told === 'Only the Jarl of a hold names its guards.' && Object.keys(srv.law.guards).length === 0);
    srv.say(JARL, '/jarl whiterun');
    srv.say(ALICE, '/jarl riften');
    const again = srv.say(JARL, '/jarl riften');
    yes('I2 the hold is chosen once: a second /jarl changes nothing (' + again.told + ')',
        srv.states[JARL].officeHold === 'whiterun' && /already holds the Jarl office of Whiterun/.test(again.told));
    const odd = srv.say(NOBODY, '/jarl whiterun');
    yes('I3 somebody with no Jarl role cannot take it, hold or no hold', srv.states[NOBODY].office === null &&
        /Only someone with the Jarl role/.test(odd.told));
    const v = srv.view(JARL);
    yes('I4 the Jarl\'s page has the hold, no hold list, no guards yet, and everybody who guards no hold to name, themselves too',
        v.hold === 'whiterun' && v.where === 'Whiterun' && v.holds.length === 0 && v.guards.length === 0 &&
        v.guardPeople.length === 6 && v.guardPeople.some(function (p) { return p.pid === P_JARL; }));
    srv.writes.length = 0; srv.reg.pushes = 0; srv.reg.lawSaves = 0;
    const named = srv.say(JARL, '/guard ' + P_STEW);
    yes('I5 Name guard names a guard of Whiterun, in the register, saved, every door list pushed (' + named.told + ')',
        srv.law.guards[P_STEW] === 'whiterun' && srv.reg.lawSaves === 1 && srv.reg.pushes === 1 &&
        /Proventus is a guard of Whiterun now\./.test(named.told) && /names you a guard of the hold/.test(named.told));
    yes('I5 and both pages are written again, the Jarl\'s and the guard\'s',
        srv.writesFor(JARL) === 1 && srv.writesFor(STEW) === 1);
    const gv = srv.view(STEW);
    yes('I6 the guard gets an Office page that says which hold they guard, and nothing else to press',
        !!gv && gv.guardOf && gv.guardOf.hold === 'whiterun' && gv.guardOf.jail === 'Dragonsreach Dungeon' &&
        gv.name === false && gv.steward === false && gv.may === false && gv.guardPeople.length === 0);
    const v2 = srv.view(JARL);
    yes('I7 the Jarl\'s page lists them as a guard by name and no longer offers them',
        v2.guards.length === 1 && v2.guards[0].pid === P_STEW && v2.guards[0].name === 'Proventus' &&
        v2.guardPeople.every(function (p) { return p.pid !== P_STEW; }));
    const poach = srv.say(ALICE, '/guard ' + P_STEW);
    yes('I8 the Jarl of Riften cannot name Whiterun\'s guard: a guard keeps one hold (' + poach.told + ')',
        srv.law.guards[P_STEW] === 'whiterun' && /is a guard of Whiterun\. A guard keeps one hold/.test(poach.told));
    const steal = srv.say(ALICE, '/guard -' + P_STEW);
    yes('I9 nor take Whiterun\'s guard back (' + steal.told + ')',
        srv.law.guards[P_STEW] === 'whiterun' && /is not a guard of Riften/.test(steal.told));
    const hers = srv.say(ALICE, '/guard ' + P_ALICE2);
    yes('I10 the Jarl of Riften names Riften\'s guards', srv.law.guards[P_ALICE2] === 'riften' && /guard of Riften now/.test(hers.told));
    const riftenView = srv.view(ALICE);
    yes('I11 and each Jarl\'s page lists only their own hold\'s guards',
        riftenView.guards.map(function (g) { return g.pid; }).join() === String(P_ALICE2) &&
        srv.view(JARL).guards.map(function (g) { return g.pid; }).join() === String(P_STEW));
    const steward = srv.say(STEW, '/guard ' + P_NOBODY);
    yes('I12 a guard, or a steward, who is not a Jarl names nobody', !srv.law.guards[P_NOBODY] &&
        steward.told === 'Only the Jarl of a hold names its guards.');
    const adm = srv.say(ADMIN, '/guard ' + P_NOBODY);
    yes('I13 an admin with no seated office has no hold, so names no guard (' + adm.told + ')',
        !srv.law.guards[P_NOBODY] && /no hold yet/.test(adm.told));
    srv.writes.length = 0;
    const back = srv.say(JARL, '/guard -' + P_STEW);
    yes('I14 Remove takes the office back, and both pages are written again (' + back.told + ')',
        !srv.law.guards[P_STEW] && srv.writesFor(JARL) === 1 && srv.writesFor(STEW) === 1 && srv.view(STEW) === null &&
        /no longer a guard of Whiterun/.test(back.told));
    srv.states[JARL].officeHold = undefined;
    delete srv.law.jarls.whiterun;   // seated before there was a hold, so no seat either
    const old = srv.view(JARL);
    yes('I15 a Jarl seated before there was a hold is offered the ten to choose from, and names no guard until then',
        old.jarl === true && old.hold === null && old.holds.length === 10 && old.guardPeople.length === 0 &&
        /no hold yet/.test(srv.say(JARL, '/guard ' + P_NOBODY).told));
    srv.say(JARL, '/jarl markarth');
    yes('I16 and choosing it seats that hold on the same office', srv.states[JARL].office === 'jarl' &&
        srv.states[JARL].officeHold === 'markarth');
    delete srv.law.guards[P_ALICE2];
    srv.roles.jarl[P_ALICE2] = true;
    const bad = srv.say(ALICE2, '/jarl __proto__');
    yes('I17 a hold that is not one of the ten is refused (' + bad.told + ')',
        !srv.states[ALICE2].office && /no hold called __proto__/.test(bad.told));
  }

  // ---------------------- J. one Jarl a hold, and giving the office up (#502)
  {
    const srv = world();
    srv.roles.jarl[P_ALICE] = true;
    srv.say(JARL, '/jarl whiterun');
    const seat = srv.law.jarls.whiterun;
    yes('J1 taking the office seats the character in the law register, by profile, character and name',
        !!seat && seat.pid === P_JARL && seat.actor === JARL && seat.name === 'Balgruuf' && srv.reg.lawSaves === 1);
    const v = srv.view(ALICE);
    const wr = v.holds.filter(function (h) { return h.hold === 'whiterun'; })[0];
    const rf = v.holds.filter(function (h) { return h.hold === 'riften'; })[0];
    yes('J2 another Jarl-role character sees Whiterun held by its Jarl, by name, and Riften free',
        !!wr && wr.by === 'Balgruuf' && !!rf && rf.by === null);
    const second = srv.say(ALICE, '/jarl whiterun');
    yes('J3 and is refused Whiterun, told who holds the seat (' + second.told + ')',
        srv.states[ALICE].office === null && srv.law.jarls.whiterun.actor === JARL &&
        second.told === 'Balgruuf holds the Jarl\'s seat of Whiterun. A hold has one Jarl, and the seat comes free when they give up the office.');
    srv.say(ALICE, '/jarl riften');
    yes('J4 Riften is free, so they take it', srv.states[ALICE].officeHold === 'riften' && srv.law.jarls.riften.actor === ALICE);
    const twice = srv.say(ALICE, '/jarl solitude');
    yes('J5 one character holds one seat', !srv.law.jarls.solitude && /already holds the Jarl office of Riften/.test(twice.told));
    srv.states[ALICE2].office = 'jarl';
    srv.states[ALICE2].officeHold = 'whiterun';
    srv.roles.jarl[P_ALICE2] = true;
    const fake = srv.view(ALICE2);
    yes('J6 a character whose own record says Whiterun, without the seat, is no Jarl of Whiterun',
        fake.hold === null && fake.holds.length === 10 && srv.officeOf(P_ALICE2, ALICE2).jarlOf === '');
    yes('J7 officeOf reads the seat: the Jarl of Whiterun is that, Alice is Riften\'s',
        srv.officeOf(P_JARL, JARL).jarlOf === 'whiterun' && srv.officeOf(P_ALICE, ALICE).jarlOf === 'riften');
    srv.claims.dungeon = { by: P_JARL, name: 'Balgruuf', at: Date.now(), touched: Date.now(), locked: false };
    srv.claims[HOUSE] = { by: P_JARL, name: 'Balgruuf', at: Date.now(), touched: Date.now(), locked: false };
    yes('J8 the Jarl\'s page offers Give up the office', srv.view(JARL).giveUp === true);
    srv.writes.length = 0;
    const gave = srv.say(JARL, '/jarl -');
    yes('J9 Give up the office frees the seat, clears the office on the character, and redraws the page (' + gave.told + ')',
        !srv.law.jarls.whiterun && srv.states[JARL].office === null && srv.states[JARL].officeHold === null &&
        srv.writesFor(JARL) === 1 && /You give up the Jarl office of Whiterun\./.test(gave.told));
    yes('J10 the hold\'s jail goes back to nobody with it, and the Jarl\'s house stays theirs',
        !srv.claims.dungeon && !!srv.claims[HOUSE] && /is the next Jarl's to claim/.test(gave.told));
    const now = srv.say(ALICE2, '/jarl whiterun');
    yes('J11 and the next Jarl-role character takes Whiterun (' + now.told + ')',
        srv.law.jarls.whiterun && srv.law.jarls.whiterun.actor === ALICE2);
    const none = srv.say(NOBODY, '/jarl -');
    yes('J12 somebody with no office has nothing to give up', none.told === 'This character holds no Jarl office.');
    delete srv.roles.jarl[P_ALICE];
    const lost = srv.view(ALICE);
    yes('J13 a Jarl whose role was taken still has the page, to give the office up',
        !!lost && lost.giveUp === true && lost.name === false);
    const adm = srv.view(ADMIN);
    yes('J14 an admin with no seated office has no hold', adm.hold === null && srv.officeOf(P_ADMIN, ADMIN).jarlOf === '');
  }
}

// -------------------------------------------------- G. nobody is told to type
{
  const arrayOf = function (name) {
    const m = new RegExp('const ' + name + ' = (\\[[\\s\\S]*?\\]);').exec(gm);
    if (!m) { return null; }
    try { return new Function('return ' + strip(m[1]))(); } catch (e) { return null; }
  };
  const WORDS = arrayOf('WORDS');
  const PLAYER = arrayOf('PLAYER_WORDS');
  const five = ['/jarl', '/steward', '/guard', '/evict', '/box', '/rent'];
  yes('G1 the server still answers the five lines the page sends',
      !!WORDS && five.every(function (w) { return WORDS.indexOf(w) !== -1; }) && WORDS.indexOf('/board') !== -1);
  yes('G2 and none of them is in the list named to everybody, which /help and the unknown command reply read',
      !!PLAYER && five.every(function (w) { return PLAYER.indexOf(w) === -1; }));
  // The help is a panel since #1633: its Land topic, as a fresh install reads it.
  const help = helpTopic('land');
  yes('G3 the help panel\'s Land names no office line, and says where the office is',
      !!help && !/\/rent|\/steward|\/evict|\/box|\/jarl|\/guard|board move|board here/.test(help) && /Office page on K/.test(help));
  // What the server says, in the functions the buttons reach: no line to type.
  const said = [];
  ['stewardCmd', 'jarlCmd', 'guardCmd', 'evict', 'rentCmd', 'boxCmd', 'moveBoard', 'board'].forEach(function (n) {
    const code = strip(lifted[n]);
    const re = /'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(code)) !== null) {
      if (/\/(jarl|steward|guard|evict|rent|box)\b|board move|board here|say that again|then say/.test(m[1])) { said.push(n + ': ' + m[1]); }
    }
  });
  const atDoor = (/  var OFFICE_AT_DOOR = '([^\n]*)';/.exec(gm) || [])[1] || '';
  yes('G4 no answer in them names a line to type' + (said.length ? ' (' + said.join(' | ') + ')' : ''),
      said.length === 0 && /Office page of K/.test(atDoor));
}

// ------------------------------------------------- H. the K panel's Office page
{
  const sent = [];      // what the page said to the plugin
  const lines = [];     // what the page sent the server through the chat line
  function node(tag) {
    const n = { tag: tag, children: [], style: {}, className: '', _text: '', id: '', onclick: null, title: '' };
    Object.defineProperty(n, 'textContent', {
      get: function () { return n._text + n.children.map(function (c) { return c.textContent; }).join(''); },
      set: function (v) { n._text = String(v); n.children = []; }
    });
    n.appendChild = function (c) { n.children.push(c); return c; };
    n.querySelector = function (sel) { return (n._q && n._q[sel]) || node('div'); };
    return n;
  }
  const docu = {
    head: node('head'), body: node('body'),
    createElement: function (tag) {
      const n = node(tag);
      Object.defineProperty(n, 'innerHTML', { set: function () {
        const close = node('div'); close._q = { span: node('span'), '.key': node('span') };
        n._q = { '.title': node('div'), '.who': node('div'), '.nav': node('div'), '.body': node('div'),
                 '.status': node('div'), '[data-act="confirm"]': node('div'), '[data-act="close"]': close, '.panel': node('div') };
      } });
      return n;
    },
    createTextNode: function (t) { const n = node('#text'); n._text = String(t); return n; }
  };
  const win = { innerWidth: 1920, innerHeight: 1080, addEventListener: function () { },
                skyrimPlatform: { sendMessage: function (to, m) { sent.push(m); } },
                thornswoodNet: { say: function (l) { lines.push(l); } } };
  const box = { window: win, document: docu, setTimeout: function () { }, Date: Date, JSON: JSON, console: console };
  vm.createContext(box);
  let ran = true;
  try { vm.runInContext(ui, box, { filename: 'thornswood-skills.js' }); } catch (e) { ran = false; console.log(e); }
  const api = win.thornswoodSkills;
  yes('H0 the K panel runs in a stand-in document', ran && !!api);
  if (api && missing.length === 0) {
    const root = docu.body.children[0];
    const nav = root._q['.nav'], body = root._q['.body'], confirmBtn = root._q['[data-act="confirm"]'];
    const status = root._q['.status'];
    const navRows = function () { return nav.children.filter(function (r) { return /navrow/.test(r.className); }); };
    const navNames = function () { return navRows().map(function (r) { return r.children[0].textContent; }); };
    const goOffice = function () {
      const r = navRows().filter(function (x) { return x.children[0].textContent === 'Office'; })[0];
      if (r) { r.onclick(); }
      return r;
    };
    const all = function (n, out) {
      out = out || [];
      out.push(n);
      (n.children || []).forEach(function (c) { all(c, out); });
      return out;
    };
    const buttons = function (text) {
      return all(body).filter(function (n) { return n.className === 'stop' && n.textContent === text; });
    };
    const base = { 'class': 'hunter', profession: 'smith', half: 'edgewright', ranks: {}, tree: {}, points: 0 };
    const show = function (view) {
      api.setData(null, { panel: Object.assign({}, base, view ? { officePage: view } : {}) });
    };
    api.open();
    show(null);
    yes('H1 with no office there is no Office page (' + navNames().join(', ') + ')', navNames().indexOf('Office') === -1);

    const srv = world();
    show(srv.view(JARL));
    const row = goOffice();
    yes('H2 a Jarl-role character has an Office page that says it may take the office (' + navNames().join(', ') + ')',
        !!row && /may take the office/.test(row.textContent));
    yes('H2 and no Confirm on it', confirmBtn.style.display === 'none');
    lines.length = 0;
    const take = buttons('Falkreath');
    yes('H3 the office is taken by pressing its hold, one of ten (#502)',
        take.length === 1 && buttons('Raven Rock').length === 1 && buttons('Take the office').length === 0);
    if (take.length) { take[0].onclick({}); }
    yes('H3 the first press sends nothing and says what the second does',
        lines.length === 0 && take.length === 1 && take[0].textContent === 'Press again to be Jarl of Falkreath');
    if (take.length) { take[0].onclick({}); }
    yes('H3 the second sends /jarl falkreath (' + lines.join(' | ') + ')', lines.join() === '/jarl falkreath');
    yes('H3 and the page says the answer is in the chat', /chat/.test(status.textContent));

    srv.say(JARL, '/jarl whiterun');
    srv.say(JARL, '/steward ' + P_STEW);
    show(srv.view(JARL));
    goOffice();
    const named = buttons('Name steward');
    yes('H4 the Jarl\'s page lists the people in the world with Name steward, and both Alices by their profile (' +
        body.textContent.slice(0, 160) + ')',
        named.length === 4 && /profile 13/.test(body.textContent) && /profile 14/.test(body.textContent));
    lines.length = 0;
    const second = all(body).filter(function (n) {
      return /guest/.test(n.className) && /profile 14/.test(n.textContent) && /Name steward/.test(n.textContent);
    })[0];
    const pick = second ? second.children.filter(function (c) { return c.className === 'stop'; })[0] : null;
    if (pick) { pick.onclick({}); }
    yes('H5 Name steward beside the second Alice sends her profile id (' + lines.join(' | ') + ')', lines.join() === '/steward 14');
    lines.length = 0;
    const remove = buttons('Remove');
    if (remove.length) { remove[0].onclick({}); }
    yes('H6 Remove beside a steward sends /steward -<id> (' + lines.join(' | ') + ')', lines.join() === '/steward -' + P_STEW);

    srv.claims[HOUSE] = { by: P_ALICE, name: 'Alice', at: Date.now(), touched: Date.now(), locked: false,
                          rent: { amount: 30, everyDays: 7, owed: 0, since: Date.now() } };
    srv.atDoor(STEW);
    srv.atBox(STEW);
    show(srv.view(STEW));
    goOffice();
    yes('H7 a steward\'s page reads the door just opened: who holds it and the rent (' + body.textContent.slice(0, 400) + ')',
        /Breezehome/.test(body.textContent) && /Held by Alice\. Rent 30 gold every 7 days, 0 owed\./.test(body.textContent));
    lines.length = 0;
    const evict = buttons('Evict');
    if (evict.length) { evict[0].onclick({}); }
    yes('H8 the first press of Evict sends nothing and says what the second does',
        lines.length === 0 && evict.length === 1 && evict[0].textContent === 'Press again to end Alice\'s claim');
    if (evict.length) { evict[0].onclick({}); }
    yes('H8 and the second sends /evict', lines.join() === '/evict');
    const input = all(body).filter(function (n) { return n.tag === 'input'; })[0];
    const setRent = buttons('Set rent')[0];
    lines.length = 0;
    if (input && setRent) { input.value = 'lots'; setRent.onclick({}); }
    yes('H9 a rent that is not a whole number of gold is not sent, and the page says why (' + status.textContent + ')',
        lines.length === 0 && /whole number of gold/.test(status.textContent));
    if (input && setRent) { input.value = '45'; input.onkeydown({ key: 'Enter' }); }
    yes('H9 Enter in the box, or Set rent, sends /rent 45 (' + lines.join(' | ') + ')', lines.join() === '/rent 45');
    lines.length = 0;
    const noRent = buttons('No rent');
    if (noRent.length) { noRent[0].onclick({}); }
    yes('H10 No rent sends /rent -', lines.join() === '/rent -');
    lines.length = 0;
    const riften = buttons('Riften');
    yes('H11 the box and the boards each offer the ten towns', riften.length === 2 && buttons('Raven Rock').length === 2);
    if (riften.length === 2) { riften[0].onclick({}); }
    yes('H11 a town under the container sends /box riften at once (' + lines.join(' | ') + ')', lines.join() === '/box riften');
    lines.length = 0;
    if (riften.length === 2) { riften[1].onclick({}); }
    yes('H12 a town under the boards asks first', lines.length === 0 && riften[1].textContent === 'Press again to move Riften\'s board here');
    if (riften.length === 2) { riften[1].onclick({}); }
    yes('H12 and the second press sends /board move riften', lines.join() === '/board move riften');
    srv.stewards.length = 0;
    show(srv.view(STEW));
    yes('H13 a steward who is removed loses the page', navNames().indexOf('Office') === -1);

    // The guards on the page (#502).
    srv.say(JARL, '/guard ' + P_ALICE);
    show(srv.view(JARL));
    goOffice();
    yes('H14 the Jarl\'s page is the Jarl of Whiterun, with a Guards of Whiterun card (' + body.textContent.slice(0, 200) + ')',
        /Jarl of Whiterun/.test(body.textContent) && /Guards of Whiterun/.test(body.textContent));
    lines.length = 0;
    const nameGuard = buttons('Name guard');
    const pickNobody = all(body).filter(function (n) {
      return /guest/.test(n.className) && /profile 15/.test(n.textContent) && /Name guard/.test(n.textContent);
    })[0];
    const ng = pickNobody ? pickNobody.children.filter(function (c) { return c.className === 'stop'; })[0] : null;
    if (ng) { ng.onclick({}); }
    yes('H15 Name guard beside a person sends /guard <their id> (' + lines.join(' | ') + ')',
        nameGuard.length >= 1 && lines.join() === '/guard ' + P_NOBODY);
    lines.length = 0;
    const guardRow = all(body).filter(function (n) {
      return /guest/.test(n.className) && /profile 13/.test(n.textContent) && /Remove/.test(n.textContent);
    })[0];
    const rm = guardRow ? guardRow.children.filter(function (c) { return c.className === 'stop'; })[0] : null;
    if (rm) { rm.onclick({}); }
    yes('H16 Remove beside a guard sends /guard -<their id> (' + lines.join(' | ') + ')', lines.join() === '/guard -' + P_ALICE);
    show(srv.view(ALICE));
    const grow = goOffice();
    yes('H17 the guard has an Office page naming their hold and their jail, with nothing to press (' +
        (grow ? grow.textContent : '') + ')',
        !!grow && /guard of Whiterun/.test(grow.textContent) && /Guard of Whiterun/.test(body.textContent) &&
        /Dragonsreach Dungeon/.test(body.textContent) && all(body).every(function (n) { return n.className !== 'stop'; }));

    // One Jarl a hold, and Give up the office (#502).
    srv.roles.jarl[P_ALICE2] = true;
    show(srv.view(ALICE2));
    goOffice();
    yes('H18 another Jarl-role character is not offered Whiterun, and is told who holds it (' +
        body.textContent.slice(0, 200) + ')',
        buttons('Whiterun').length === 0 && buttons('Riften').length === 1 &&
        /Held by their Jarl: Whiterun \(Balgruuf\)\./.test(body.textContent));
    show(srv.view(JARL));
    goOffice();
    lines.length = 0;
    const give = buttons('Give up the office');
    if (give.length) { give[0].onclick({}); }
    yes('H19 Give up the office asks first', give.length === 1 && lines.length === 0 &&
        give[0].textContent === 'Press again to give up the office of Whiterun');
    if (give.length) { give[0].onclick({}); }
    yes('H19 and the second press sends /jarl - (' + lines.join(' | ') + ')', lines.join() === '/jarl -');
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
