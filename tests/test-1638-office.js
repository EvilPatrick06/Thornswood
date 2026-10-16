// test-1638-office.js
//
// #1638. A Jarl and a steward are people in the world, not staff, so their
// powers are buttons (Patrick, 4 Oct: no commands for things people do).
// They live on an Office page of the K panel: for a steward, evict and set or
// clear the rent at the door just opened, make the container just opened a
// hold's box, and move their hold's board to where they stand. Each button
// sends the line the command was, which the server still answers; none is
// named to anybody.
//
// #2551, Patrick, 15 Oct: every office is a Discord role. A Jarl's hold is
// their "Jarl of <Hold>" role, nobody takes an office or picks a hold in the
// game, and the Jarl names and removes their own hold's Court, Steward and
// Guards on the page: Name and Remove send /office, the server asks the site,
// the bot's account sets the role, and the page is written again once the
// game has read it back. Two accounts holding one hold's Jarl role act as
// neither.
//
// The server half is lifted out of the property block and run together over
// a small world, with the roles as a table the door would hand over and the
// site as a stand-in that sets them. The page half is the real
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

/* One function out of the property block, by name, once, to the brace that closes it. */
function fn(name) {
  if (!prop) { return null; }
  const head = '\n  function ' + name + '(';
  const a = prop.indexOf(head);
  if (a < 0 || prop.indexOf(head, a + 1) >= 0) { return null; }
  const b = prop.indexOf('{', a);
  let d = 0;
  for (let i = b; i < prop.length; i++) {
    if (prop[i] === '{') { d++; }
    else if (prop[i] === '}') { d--; if (d === 0) { return prop.slice(a + 1, i + 1); } }
  }
  return null;
}
/* One var line out of the property block. */
function line(re) {
  const m = prop ? re.exec(prop) : null;
  return m ? m[0] : null;
}

const NAMES = ['officeView', 'officeHolders', 'officeRedraw', 'officeCmd', 'officeRole', 'officeDoes',
               'officesOfProfile', 'holdsOffice', 'isJarlOf', 'jarlHoldsOf', 'isJarl', 'isCourtOf',
               'isStewardOf', 'stewardHoldsOf', 'isSteward', 'isGuard', 'guardHoldsOf', 'jarlClashOf', 'officeOf',
               'evict', 'rentCmd', 'boxCmd', 'moveBoard', 'board', 'command', 'holderOf', 'here', 'buildingOf',
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
  line(/  var OFFICE_KINDS = \[[^\]]*\];/),
  line(/  var OFFICE_GIVEN = \{[^}]*\};/),
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

/*
  A server: the property block's office pieces over a world of people, the
  Discord roles as a table by profile (what the door hands over), and a site
  that checks nothing the game did not and sets the role it is asked to.
*/
function server() {
  const people = {};       // actor -> { pid, name, cell, pos, door, box }
  const online = [];
  const writes = [];       // [actor, redraw]
  const roles = {};        // pid -> { jarl, court, steward, guard }
  const account = {};      // pid -> account, for the holders' rows
  const clash = {};        // pid -> [holds whose Jarl role another account holds too]
  const site = { asked: [], answer: null, reads: 0 };
  const reg = { saves: 0, pushes: 0 };
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
  const blank = function () { return { jarl: [], court: [], steward: [], guard: [] }; };
  const g = {
    __thornswoodOffices: function (pid) { return JSON.parse(JSON.stringify(roles[pid] || blank())); },
    __thornswoodOfficeHolders: function (office, hold) {
      const rows = {};
      const out = [];
      Object.keys(roles).forEach(function (k) {
        if ((roles[k][office] || []).indexOf(hold) === -1) { return; }
        const acct = account[k] || ('p:' + k);
        if (!rows[acct]) { rows[acct] = { account: acct, profiles: [] }; out.push(rows[acct]); }
        rows[acct].profiles.push(Number(k));
      });
      return out;
    },
    __thornswoodJarlClash: function (pid) { return (clash[pid] || []).slice(); },
    __thornswoodAskSite: function (route, body, done) {
      site.asked.push([route, JSON.parse(JSON.stringify(body))]);
      if (site.answer) { done(site.answer.why || '', site.answer.doc || null); return; }
      const role = body.office === 'court' ? 'the Court' : body.office;
      const o = roles[body.who] || (roles[body.who] = blank());
      const has = o[body.office].indexOf(body.hold) !== -1;
      if (body.give === has) {
        done('', { ok: false, said: body.whoName + (has ? ' already holds ' : ' does not hold ') + role + '.' });
        return;
      }
      if (body.give) { o[body.office].push(body.hold); }
      else { o[body.office] = o[body.office].filter(function (h) { return h !== body.hold; }); }
      done('', { ok: true, said: body.whoName + (body.give ? ' holds ' : ' no longer holds ') + role + ' now.' });
    },
    __thornswoodDoorReadNow: function (done) { site.reads++; done(true); },
    __thornswoodCharacter: {
      stateOf: function () { return {}; },
      writeState: function (aid, s, redraw) { writes.push([aid, !!redraw]); return s; }
    }
  };
  const boards = {};
  HOLDS10.forEach(function (h, i) {
    boards[h] = { cell: TAMRIEL, pos: [i * 10000, 0, 0],
                  where: h === 'ravenrock' ? 'Raven Rock' : h.charAt(0).toUpperCase() + h.slice(1) };
  });
  const body = [
    'var claims = {}; var boxes = {}; var funds = {}; var notices = {};',
    'var BUILDING_BY_DOOR = {}; BUILDING_BY_DOOR[' + JSON.stringify(DOOR) + '] = ' + JSON.stringify(HOUSE) + ';',
    'var BUILDING_NAME = { breezehome: "Breezehome" };',
    'function lapseDays() { return 14; }',
    'function save() { reg.saves++; }',
    'function pushAll() { reg.pushes++; }',
    'function plog() { }',
    ['deeds', 'setLock', 'mold', 'moldHere', 'cutKey', 'claim', 'sleepHere', 'post', 'take', 'jobs',
     'dropJob', 'unpin', 'postLetter', 'deliver', 'haulCmd', 'haulText', 'dropboxCmd', 'jobDone', 'claimAway',
     'doorLine', 'doorOfId',
     // The server stands the board where a steward moves it (#2516): test-2516-server-boards.js.
     'standBoard']
      .map(function (n) { return 'function ' + n + '() { return true; }'; }).join('\n')
  ].concat(VARS, NAMES.map(function (n) { return lifted[n]; }));
  body.push('return { command: command, officeView: officeView, officeOf: officeOf, isSteward: isSteward, ' +
            'isStewardOf: isStewardOf, isJarlOf: isJarlOf, claims: claims, boxes: boxes, boards: boards, ' +
            'OFFICE_AT_DOOR: OFFICE_AT_DOOR };');
  const make = new Function('mp', 'g', 'boards', 'reg', body.join('\n'));
  const api = make(mp, g, boards, reg);
  api.people = people; api.writes = writes; api.roles = roles; api.account = account; api.clash = clash;
  api.site = site; api.reg = reg;
  api.give = function (pid, office, hold) {
    const o = roles[pid] || (roles[pid] = blank());
    if (o[office].indexOf(hold) === -1) { o[office].push(hold); }
  };
  api.add = function (actor, pid, name) {
    people[actor] = { pid: pid, name: name, cell: TAMRIEL, pos: [500, 500, 0] };
    online.push(actor);
  };
  api.view = function (actor) { return api.officeView(actor, people[actor].pid); };
  api.say = function (actor, text) {
    const parts = text.trim().split(/\s+/);
    const told = [];
    const answered = api.command(parts[0], parts, actor, people[actor].pid, function (pid, m) { told.push([pid, m]); });
    return { answered: answered, told: told.filter(function (t) { return t[0] === people[actor].pid; })
                                           .map(function (t) { return t[1]; }).join('\n'),
             all: told };
  };
  api.atDoor = function (actor, ago) { people[actor].door = { door: DOOR, at: Date.now() - (ago || 0) }; };
  api.atBox = function (actor, ago) { people[actor].box = { refr: CHEST, at: Date.now() - (ago || 0) }; };
  api.writesFor = function (actor) { return writes.filter(function (w) { return w[0] === actor; }).length; };
  return api;
}

const JARL = 0xff000201, STEW = 0xff000202, ALICE = 0xff000203, ALICE2 = 0xff000204, NOBODY = 0xff000205,
      ADMIN = 0xff000206, RJARL = 0xff000207;
const P_JARL = 11, P_STEW = 12, P_ALICE = 13, P_ALICE2 = 14, P_NOBODY = 15, P_ADMIN = 16, P_RJARL = 17;

function world() {
  const srv = server();
  srv.add(JARL, P_JARL, 'Balgruuf');
  srv.add(STEW, P_STEW, 'Proventus');
  srv.add(ALICE, P_ALICE, 'Alice');
  srv.add(ALICE2, P_ALICE2, 'Alice');
  srv.add(NOBODY, P_NOBODY, 'Nobody');
  srv.add(ADMIN, P_ADMIN, 'Staff');
  srv.add(RJARL, P_RJARL, 'Laila');
  srv.give(P_JARL, 'jarl', 'whiterun');
  srv.give(P_RJARL, 'jarl', 'riften');
  return srv;
}

if (missing.length === 0 && VARS.every(function (v) { return !!v; })) {
  // ------------------------------------------------------ A. who gets the page
  {
    const srv = world();
    yes('A1 somebody with no office gets no Office page', srv.view(NOBODY) === null);
    yes('A2 nor does an admin with no role: staff hold no office by being staff', srv.view(ADMIN) === null);
    const v = srv.view(JARL);
    yes('A3 the Jarl of Whiterun, by the role, gets the page with Whiterun and its three offices, and nothing to take or pick',
        !!v && v.jarls.length === 1 && v.jarls[0].hold === 'whiterun' && v.jarls[0].where === 'Whiterun' &&
        Object.keys(v.jarls[0].offices).join() === 'court,steward,guard' &&
        !('may' in v) && !('holds' in v) && !('giveUp' in v));
    yes('A4 each office names its role, nobody holds it yet, and everybody in the world may be named, the Jarl too',
        v.jarls[0].offices.court.role === 'Whiterun Court' && v.jarls[0].offices.steward.role === 'Steward of Whiterun' &&
        v.jarls[0].offices.guard.role === 'Guard of Whiterun' &&
        ['court', 'steward', 'guard'].every(function (k) {
          return v.jarls[0].offices[k].holders.length === 0 && v.jarls[0].offices[k].people.length === 7;
        }));
    yes('A5 the Jarl keeps their hold as its steward: the door, the box and their own board',
        v.steward === true && v.boards.map(function (b) { return b.hold; }).join() === 'whiterun');
  }

  // ------------------------- B. the page agrees with the readers, and reads no character
  {
    let agree = true;
    const cases = [];
    ['jarl', 'court', 'steward', 'guard', ''].forEach(function (office) {
      const srv = world();
      if (office) { srv.give(P_ALICE, office, 'markarth'); }
      const v = srv.view(ALICE);
      const st = srv.isSteward(P_ALICE);
      const ok = office === '' ? v === null
        : (!!v && v.steward === st && (v.jarls.length === 1) === (office === 'jarl') &&
           (v.courtOf.length === 1) === (office === 'court') && (v.stewardOf.length === 1) === (office === 'steward') &&
           (v.guardOf.length === 1) === (office === 'guard'));
      if (!ok) { agree = false; cases.push(office || 'none'); }
    });
    yes('B1 for each office, and none, the page shows exactly the office the role gives, and is a steward exactly when isSteward says' +
        (cases.length ? ' (wrong: ' + cases.join(', ') + ')' : ''), agree);
    const ov = strip(lifted.officeView);
    yes('B2 the page never reads the character itself: writeState is where it is asked from, and stateOf there would ask for itself',
        !/stateOf/.test(ov));
    const ws = slice(charBlock, '  function writeState(actorId, s, redraw) {', '\n  }\n');
    yes('B3 the character block puts the page on the K panel view, with the actor and the profile',
        !!ws && /W\.officeView\(actorId, pid\)/.test(ws) && /view\.officePage = desk;/.test(ws) &&
        /if \(view && !view\.creating\)/.test(ws));
  }

  // ------------------------------------------- C. the Jarl names and removes
  {
    const srv = world();
    const v = srv.view(JARL);
    const names = v.jarls[0].offices.steward.people.map(function (p) { return p.name + ':' + p.pid; });
    yes('C1 the Jarl picks from the people in the world, by name with the id (' + names.join(', ') + ')',
        names.join(',') === ['Alice:' + P_ALICE, 'Alice:' + P_ALICE2, 'Balgruuf:' + P_JARL, 'Laila:' + P_RJARL,
                             'Nobody:' + P_NOBODY, 'Proventus:' + P_STEW, 'Staff:' + P_ADMIN].join(','));
    srv.writes.length = 0;
    const r = srv.say(JARL, '/office steward whiterun ' + P_ALICE2);
    yes('C2 Name beside the second Alice asks the site to give that Alice, and not the first, the Steward of Whiterun role',
        srv.site.asked.length === 1 && srv.site.asked[0][0] === '/api/office' && srv.site.asked[0][1].who === P_ALICE2 &&
        srv.site.asked[0][1].office === 'steward' && srv.site.asked[0][1].hold === 'whiterun' &&
        srv.site.asked[0][1].give === true && srv.site.asked[0][1].by === P_JARL);
    yes('C2 and the Jarl is told what the site said (' + r.told + ')', /Alice holds steward now\./.test(r.told));
    yes('C2 and once the game has read the roles back, the cells are pushed and both pages are written again',
        srv.site.reads === 1 && srv.reg.pushes === 1 && srv.writesFor(JARL) === 1 && srv.writesFor(ALICE2) === 1);
    yes('C2 and she is told what the office lets her do',
        r.all.some(function (t) { return t[0] === P_ALICE2 && /gives you the Steward of Whiterun office\. You end claims/.test(t[1]); }));
    const v2 = srv.view(JARL);
    yes('C3 she is listed as its Steward by name, and is no longer offered',
        v2.jarls[0].offices.steward.holders.length === 1 && v2.jarls[0].offices.steward.holders[0].pid === P_ALICE2 &&
        v2.jarls[0].offices.steward.holders[0].name === 'Alice' &&
        v2.jarls[0].offices.steward.people.every(function (p) { return p.pid !== P_ALICE2; }));
    const hers = srv.view(ALICE2);
    yes('C4 her own page appears, as the Steward of Whiterun, who names nobody',
        !!hers && hers.stewardOf.length === 1 && hers.stewardOf[0].hold === 'whiterun' && hers.jarls.length === 0 &&
        hers.steward === true && hers.boards.map(function (b) { return b.hold; }).join() === 'whiterun');
    const no = srv.say(ALICE2, '/office guard whiterun ' + P_NOBODY);
    yes('C5 a steward who is not the Jarl names nobody, and the site is not asked (' + no.told + ')',
        no.told === 'Only the Jarl of Whiterun gives its offices.' && srv.site.asked.length === 1);
    const riften = srv.say(JARL, '/office guard riften ' + P_NOBODY);
    yes('C6 the Jarl of Whiterun names nobody in Riften: their own hold only', srv.site.asked.length === 1 &&
        riften.told === 'Only the Jarl of Riften gives its offices.');
    srv.writes.length = 0;
    srv.say(JARL, '/office steward whiterun -' + P_ALICE2);
    yes('C7 Remove asks the site to take it back, and both pages are written again',
        srv.site.asked.length === 2 && srv.site.asked[1][1].give === false && srv.writesFor(JARL) === 1 &&
        srv.writesFor(ALICE2) === 1 && srv.view(ALICE2) === null);
    srv.give(99, 'guard', 'whiterun');
    srv.account[99] = 'acct-99';
    const off = srv.view(JARL).jarls[0].offices.guard.holders.filter(function (w) { return w.pid === 99; })[0];
    yes('C8 a guard who is not in the world is listed by profile, with no name to show', !!off && off.name === '');
    srv.give(P_ALICE, 'court', 'whiterun');
    srv.account[P_ALICE] = 'acct-alice'; srv.account[P_ALICE2] = 'acct-alice';
    srv.give(P_ALICE2, 'court', 'whiterun');
    const court = srv.view(JARL).jarls[0].offices.court;
    yes('C9 one account is one row, by its character in the world, and neither of its characters is offered',
        court.holders.length === 1 && court.people.every(function (p) { return p.pid !== P_ALICE && p.pid !== P_ALICE2; }));
    srv.site.answer = { why: '', doc: { ok: false, said: 'Discord could not be asked just now. Try again in a minute.' } };
    srv.writes.length = 0;
    const refused = srv.say(JARL, '/office guard whiterun ' + P_NOBODY);
    yes('C10 a change the site refuses is said to the Jarl in its words, and nothing is pushed or redrawn',
        refused.told === 'Discord could not be asked just now. Try again in a minute.' && srv.writes.length === 0);
    srv.site.answer = { why: 'the site could not be reached', doc: null };
    const down = srv.say(JARL, '/office guard whiterun ' + P_NOBODY);
    yes('C11 a site that does not answer is said too, and nothing is retried',
        down.told === 'The office did not change: the site could not be reached.' && srv.site.asked.length === 4);
    srv.site.answer = null;
    const bad = srv.say(JARL, '/office jarl whiterun ' + P_NOBODY);
    yes('C12 a Jarl gives no Jarl office, and a hold that is not one of the ten is nothing',
        /Court, a Steward and Guards/.test(bad.told) &&
        /Court, a Steward and Guards/.test(srv.say(JARL, '/office guard narnia ' + P_NOBODY).told) &&
        /Pick somebody/.test(srv.say(JARL, '/office guard whiterun Alice').told) && srv.site.asked.length === 4);
  }

  // ------------------------------- D. a Jarl role two accounts hold (#2551)
  {
    const srv = world();
    srv.roles[P_JARL].jarl = [];
    srv.clash[P_JARL] = ['whiterun'];
    const v = srv.view(JARL);
    yes('D1 the page says the role is held twice, and gives no Jarl powers',
        !!v && v.jarls.length === 0 && v.clash.length === 1 && v.clash[0].where === 'Whiterun' && v.steward === false);
    const r = srv.say(JARL, '/office guard whiterun ' + P_NOBODY);
    yes('D2 and a line sent anyway is refused, saying why and that staff know, and the site is not asked (' + r.told + ')',
        srv.site.asked.length === 0 && /Two Discord accounts hold the Jarl of Whiterun role, so neither acts as Jarl/.test(r.told) &&
        /Staff have been told/.test(r.told));
  }

  // ------------------------------------------- E. at the door: evict, rent
  {
    const srv = world();
    srv.give(P_STEW, 'steward', 'whiterun');
    const lost = srv.say(STEW, '/evict');
    yes('E1 away from a door the steward is told to open one and use the page, not to say anything (' + lost.told + ')',
        lost.told === srv.OFFICE_AT_DOOR && !/\/|say that again/.test(lost.told));
    yes('E1 and the page says there is no door', srv.view(STEW).door === null);
    srv.claims[HOUSE] = { by: P_ALICE, name: 'Alice', at: Date.now(), touched: Date.now(), locked: false };
    srv.atDoor(STEW);
    const d = srv.view(STEW).door;
    yes('E2 at the door the page names the building, who holds it, and that there is no rent',
        !!d && d.name === 'Breezehome' && d.by === 'Alice' && d.rent === null);
    srv.writes.length = 0;
    const set = srv.say(STEW, '/rent 50');
    const d2 = srv.view(STEW).door;
    yes('E3 Set rent sends /rent 50: 50 gold every 7 days, nothing owed yet, and the page is written again (' + set.told + ')',
        srv.claims[HOUSE].rent.amount === 50 && d2.rent.amount === 50 && d2.rent.every === 7 && d2.rent.owed === 0 &&
        srv.writesFor(STEW) === 1);
    srv.claims[HOUSE].rent.since = Date.now() - 15 * 86400000;
    yes('E4 two weeks on, the page shows 100 owed, counted the way the ledger counts it',
        srv.view(STEW).door.rent.owed === 100);
    srv.atDoor(NOBODY);
    yes('E5 at the door anybody reads what is owed', srv.say(NOBODY, '/rent').told === 'Breezehome: 50 gold every 7 days, 100 owed.');
    yes('E6 somebody who is not a steward cannot set it', srv.say(NOBODY, '/rent 5').told === 'Only a steward sets rent.' &&
        srv.claims[HOUSE].rent.amount === 50);
    srv.atDoor(ADMIN);
    yes('E6 nor can an admin with no role', srv.say(ADMIN, '/rent 5').told === 'Only a steward sets rent.');
    yes('E7 a rent that is not a number of gold is refused in words that type nothing',
        srv.say(STEW, '/rent lots').told === 'The rent is a number of gold above 0.' && srv.claims[HOUSE].rent.amount === 50);
    srv.say(STEW, '/rent -');
    yes('E8 No rent sends /rent -, and the page says there is none', !srv.claims[HOUSE].rent && srv.view(STEW).door.rent === null);
    srv.atDoor(STEW, 61000);
    yes('E9 a door opened more than a minute ago is not the door, on the page or for the line',
        srv.view(STEW).door === null && srv.say(STEW, '/evict').told === srv.OFFICE_AT_DOOR && !!srv.claims[HOUSE]);
    srv.atDoor(STEW);
    srv.writes.length = 0;
    srv.say(STEW, '/evict');
    yes('E10 Evict ends the claim and the page is written again, now saying nobody holds it',
        !srv.claims[HOUSE] && srv.writesFor(STEW) === 1 && srv.view(STEW).door.by === null);
    srv.claims[HOUSE] = { by: P_ALICE, name: 'Alice', at: Date.now(), touched: Date.now(), locked: false };
    srv.atDoor(JARL);
    srv.say(JARL, '/rent 20');
    const jev = srv.say(JARL, '/evict');
    yes('E11 the Jarl, who keeps their hold, sets the rent and evicts (' + jev.told + ')',
        !srv.claims[HOUSE] && /^You end Alice's claim/.test(jev.told));
  }

  // ----------------------------------------------------------- F. the box
  {
    const srv = world();
    srv.give(P_STEW, 'steward', 'whiterun');
    yes('F1 with no container opened, the page has none', srv.view(STEW).box === null);
    srv.atBox(STEW);
    yes('F2 the container just opened is nobody\'s box yet', JSON.stringify(srv.view(STEW).box) === '{"hold":null}');
    srv.writes.length = 0;
    const r = srv.say(STEW, '/box riften');
    yes('F3 pressing Riften makes it Riften\'s box, and the page says so (' + r.told + ')',
        srv.boxes.riften === CHEST && srv.view(STEW).box.hold === 'riften' && srv.writesFor(STEW) === 1);
    srv.atBox(NOBODY);
    yes('F4 somebody who is not a steward cannot', srv.say(NOBODY, '/box whiterun').told === 'Only a steward sets a hold\'s box.' &&
        !srv.boxes.whiterun);
  }

  // -------------------------------------------------------- G. the boards
  {
    const srv = world();
    srv.give(P_STEW, 'steward', 'riften');
    const v = srv.view(STEW);
    yes('G1 the Steward of Riften\'s page lists Riften\'s board and no other', v.boards.map(function (b) { return b.hold; }).join() === 'riften');
    srv.people[STEW].pos = [123, 456, 7];
    const r = srv.say(STEW, '/board move riften');
    yes('G2 /board move riften, which Riften on the page sends, puts the board where the steward stands (' + r.told + ')',
        srv.boards.riften.pos.join() === '123,456,7' && srv.boards.riften.where === 'Riften');
    const other = srv.say(STEW, '/board move whiterun');
    yes('G3 the Steward of Riften does not move Whiterun\'s board (' + other.told + ')',
        srv.boards.whiterun.pos[0] === 0 && /Whiterun's board\. Its Steward or its Jarl moves it\./.test(other.told));
    const no = srv.say(NOBODY, '/board move whiterun');
    yes('G4 somebody who is not a steward cannot', no.told === 'Only a steward moves a board.' && srv.boards.whiterun.pos[0] === 0);
    srv.people[JARL].pos = [9, 9, 9];
    srv.say(JARL, '/board move whiterun');
    yes('G5 the Jarl of Whiterun moves Whiterun\'s', srv.boards.whiterun.pos.join() === '9,9,9');
    srv.people[NOBODY].pos = [-5e6, 0, 0];
    yes('G6 the lines with nothing after them say what to do without naming one to type',
        !/\//.test(srv.say(STEW, '/board move').told) && !/\//.test(srv.say(NOBODY, '/board here').told));
  }

  // --------------------------------- O. every office, read in one place
  {
    const srv = world();
    srv.give(P_STEW, 'steward', 'whiterun');
    srv.give(P_ALICE, 'court', 'whiterun');
    srv.give(P_NOBODY, 'guard', 'riften');
    const j = srv.officeOf(P_JARL), s = srv.officeOf(P_STEW), c = srv.officeOf(P_ALICE), gd = srv.officeOf(P_NOBODY);
    yes('O1 officeOf names every office by its holds: the Jarl, the Steward, the Court and a guard',
        j.jarl && j.jarlOf.join() === 'whiterun' && j.stewardOf.join() === 'whiterun' &&
        s.steward && s.stewardOf.join() === 'whiterun' && !s.jarl &&
        c.courtOf.join() === 'whiterun' && !c.steward && gd.guardOf.join() === 'riften' && !gd.steward);
    yes('O2 and an admin with no role holds nothing', (function () {
      const a = srv.officeOf(P_ADMIN);
      return !a.jarl && !a.steward && !a.jarlOf.length && !a.courtOf.length && !a.guardOf.length;
    }()));
  }
}

// -------------------------------------------------- N. nobody is told to type
{
  const arrayOf = function (name) {
    const m = new RegExp('const ' + name + ' = (\\[[\\s\\S]*?\\]);').exec(gm);
    if (!m) { return null; }
    try { return new Function('return ' + strip(m[1]))(); } catch (e) { return null; }
  };
  const WORDS = arrayOf('WORDS');
  const PLAYER = arrayOf('PLAYER_WORDS');
  const four = ['/office', '/evict', '/box', '/rent'];
  yes('N1 the server still answers the lines the page sends, and no longer /jarl, /steward or /guard',
      !!WORDS && four.every(function (w) { return WORDS.indexOf(w) !== -1; }) && WORDS.indexOf('/board') !== -1 &&
      ['/jarl', '/steward', '/guard'].every(function (w) { return WORDS.indexOf(w) === -1; }));
  yes('N2 and none of them is in the list named to everybody, which /help and the unknown command reply read',
      !!PLAYER && four.every(function (w) { return PLAYER.indexOf(w) === -1; }));
  // The help is a panel since #1633: its Land topic, as a fresh install reads it.
  const help = helpTopic('land');
  yes('N3 the help panel\'s Land names no office line, and says where the office is',
      !!help && !/\/rent|\/office|\/evict|\/box|\/jarl|\/guard|\/steward|board move|board here/.test(help) &&
      /Office page on K/.test(help));
  // What the server says, in the functions the buttons reach: no line to type.
  const said = [];
  ['officeCmd', 'officeDoes', 'evict', 'rentCmd', 'boxCmd', 'moveBoard', 'board'].forEach(function (n) {
    const code = strip(lifted[n]);
    const re = /'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(code)) !== null) {
      if (/\/(office|jarl|steward|guard|evict|rent|box)\b|board move|board here|say that again|then say/.test(m[1]) &&
          m[1] !== '/api/office') { said.push(n + ': ' + m[1]); }
    }
  });
  const atDoor = (/  var OFFICE_AT_DOOR = '([^\n]*)';/.exec(gm) || [])[1] || '';
  yes('N4 no answer in them names a line to type' + (said.length ? ' (' + said.join(' | ') + ')' : ''),
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
    const rowWith = function (re, button) {
      const r = all(body).filter(function (n) { return /guest/.test(n.className) && re.test(n.textContent) && button.test(n.textContent); });
      return r;
    };
    const base = { 'class': 'hunter', profession: 'smith', half: 'edgewright', ranks: {}, tree: {}, points: 0 };
    const show = function (view) {
      api.setData(null, { panel: Object.assign({}, base, view ? { officePage: view } : {}) });
    };
    api.open();
    show(null);
    yes('H1 with no office there is no Office page (' + navNames().join(', ') + ')', navNames().indexOf('Office') === -1);

    const srv = world();
    srv.give(P_STEW, 'steward', 'whiterun');
    show(srv.view(JARL));
    const row = goOffice();
    yes('H2 the Jarl of Whiterun has an Office page that says so (' + navNames().join(', ') + ')',
        !!row && /Jarl of Whiterun/.test(row.textContent));
    yes('H2 and no Confirm on it', confirmBtn.style.display === 'none');
    yes('H3 the page has the Jarl\'s card, the three offices and nothing to take or pick a hold with',
        /Jarl of Whiterun/.test(body.textContent) && /Whiterun Court/.test(body.textContent) &&
        /Steward of Whiterun/.test(body.textContent) && /Guard of Whiterun/.test(body.textContent) &&
        buttons('Falkreath').length === 0 && buttons('Take the office').length === 0 &&
        buttons('Give up the office').length === 0);
    lines.length = 0;
    const second = rowWith(/profile 14/, /Name/).filter(function (n) { return /Name/.test(n.textContent); })[1];
    const pick = second ? second.children.filter(function (c) { return c.className === 'stop'; })[0] : null;
    if (pick) { pick.onclick({}); }
    yes('H4 Name beside the second Alice, under the Steward, sends her profile id for that office (' + lines.join(' | ') + ')',
        lines.join() === '/office steward whiterun 14');
    yes('H4 and the page says the answer is in the chat', /chat/.test(status.textContent));
    lines.length = 0;
    const holder = rowWith(/Proventus/, /Remove/)[0];
    const rm = holder ? holder.children.filter(function (c) { return c.className === 'stop'; })[0] : null;
    if (rm) { rm.onclick({}); }
    yes('H5 Remove beside the Steward asks first, because it takes the role in Discord',
        lines.length === 0 && !!rm && rm.textContent === 'Press again to take Steward of Whiterun back');
    if (rm) { rm.onclick({}); }
    yes('H5 and the second press sends /office steward whiterun -<id> (' + lines.join(' | ') + ')',
        lines.join() === '/office steward whiterun -' + P_STEW);

    srv.claims[HOUSE] = { by: P_ALICE, name: 'Alice', at: Date.now(), touched: Date.now(), locked: false,
                          rent: { amount: 30, everyDays: 7, owed: 0, since: Date.now() } };
    srv.atDoor(STEW);
    srv.atBox(STEW);
    show(srv.view(STEW));
    const srow = goOffice();
    yes('H6 the Steward of Whiterun\'s page names their office (' + (srow ? srow.textContent : '') + ')',
        !!srow && /Steward of Whiterun/.test(srow.textContent) && /Steward of Whiterun/.test(body.textContent));
    yes('H7 and reads the door just opened: who holds it and the rent (' + body.textContent.slice(0, 300) + ')',
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
    const whiterun = buttons('Whiterun');
    yes('H11 the box offers the hold\'s own board, and the boards card only Whiterun\'s', whiterun.length === 2 &&
        buttons('Riften').length === 0);
    if (whiterun.length === 2) { whiterun[0].onclick({}); }
    yes('H11 a town under the container sends /box whiterun at once (' + lines.join(' | ') + ')', lines.join() === '/box whiterun');
    lines.length = 0;
    if (whiterun.length === 2) { whiterun[1].onclick({}); }
    yes('H12 a town under the boards asks first', lines.length === 0 && whiterun[1].textContent === 'Press again to move Whiterun\'s board here');
    if (whiterun.length === 2) { whiterun[1].onclick({}); }
    yes('H12 and the second press sends /board move whiterun', lines.join() === '/board move whiterun');
    srv.roles[P_STEW].steward = [];
    show(srv.view(STEW));
    yes('H13 a steward whose role is taken loses the page', navNames().indexOf('Office') === -1);

    // A guard and the Court (#502, #2551).
    srv.give(P_ALICE, 'guard', 'whiterun');
    show(srv.view(ALICE));
    const grow = goOffice();
    yes('H14 a guard has an Office page naming their hold and their jail, with nothing to press (' +
        (grow ? grow.textContent : '') + ')',
        !!grow && /Guard of Whiterun/.test(grow.textContent) && /Guard of Whiterun/.test(body.textContent) &&
        /Dragonsreach Dungeon/.test(body.textContent) && /drop box/.test(body.textContent) &&
        all(body).every(function (n) { return n.className !== 'stop'; }));
    srv.roles[P_ALICE].guard = [];
    srv.give(P_ALICE, 'court', 'whiterun');
    show(srv.view(ALICE));
    const crow = goOffice();
    yes('H15 somebody on the Court has a page naming it and the drop box, with nothing to press',
        !!crow && /Whiterun Court/.test(crow.textContent) && /Whiterun Court/.test(body.textContent) &&
        /drop box/.test(body.textContent) && all(body).every(function (n) { return n.className !== 'stop'; }));

    // A Jarl role held twice (#2551).
    srv.roles[P_JARL].jarl = [];
    srv.clash[P_JARL] = ['whiterun'];
    show(srv.view(JARL));
    const jrow = goOffice();
    yes('H16 a Jarl whose role another account holds sees why they do not act, and nothing to press',
        !!jrow && /held twice/.test(jrow.textContent) && /neither\s+of you acts as Jarl until staff/.test(body.textContent) &&
        all(body).every(function (n) { return n.className !== 'stop'; }));
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
