/*
  test-staff-commands.js

  Issue #412, "A moderator has no powers in the game at all". Done when a
  harness over handle() shows a person who is not staff getting "That one is
  not yours to run." while a staff profile reaches the action, and in the
  world each command answers through the person's chat.

  PART A runs the REAL command block of game/gamemode.js (WORDS through the
  end of the chat commands, so the real poll(), dispatch() and handle()) and
  the REAL staff block, over a pretend world. Commands go in the way they do on
  the server: the voice service's GET /commands answer, collected by poll() on
  the command timer. Every answer is read back from the POST /say it makes,
  which is how a line reaches somebody's chat.

  PART B spawns the REAL voice service in a temp folder and checks the two
  things it does for this: a queued command says whether its connection was
  proven by a join token, and somebody on the /silenced list reaches nobody.

  PART C checks the bot: moderation_text through python (bot/test-moderation.py
  is the full check of the watcher).

  Read only apart from its own temp folder and one loopback port.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const { spawn } = require('child_process');

const ROOT = path.join(__dirname, '..');
const GM = process.env.GM || path.join(ROOT, 'game', 'gamemode.js');
const VOICE = process.env.VOICE || path.join(ROOT, 'voice', 'voice-server.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(GM, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const REFUSED = 'That one is not yours to run.';

// ------------------------------------------------------------------ A --
function slice(from, to) {
  const a = src.indexOf(from);
  const b = a < 0 ? -1 : src.indexOf(to, a);
  return (a < 0 || b < 0) ? null : src.slice(a, b + to.length);
}
const COMMANDS = slice('const WORDS = [', '// ==== end thornswood chat commands ====');
const STAFF = slice('// ==== thornswood staff ====', '// ==== end thornswood staff ====');
yes('the chat command block is in gamemode.js', !!COMMANDS);
yes('the staff block is in gamemode.js', !!STAFF);
yes('handle() hands staff words to the staff block with isStaff',
    !!COMMANDS && /staffCmd\.command\(cmd, word, parts, profileId, actorId, isStaff\)/.test(COMMANDS));
yes('isStaff is the dev tier, which carries the staff roles',
    !!COMMANDS && /function isStaff\(profileId\) \{\s*return isDev\(profileId\);/.test(COMMANDS));

const STAFFER = 1001, BJORN = 2002, NOBODY = 3003, SERA = 4004;
const A_STAFF = 0xff000001, A_BJORN = 0xff000002, A_NOBODY = 0xff000003, A_SERA = 0xff000004;

function world() {
  const w = {
    online: [A_STAFF, A_BJORN, A_NOBODY, A_SERA],
    pid: { [A_STAFF]: STAFFER, [A_BJORN]: BJORN, [A_NOBODY]: NOBODY, [A_SERA]: SERA },
    name: { [A_STAFF]: 'Aela', [A_BJORN]: 'Bjorn Iron-Hand', [A_NOBODY]: 'Nobody Special', [A_SERA]: 'Sera' },
    where: {
      [A_STAFF]: { desc: 'Whiterun:1', pos: [100, 200, 300], rot: [0, 0, 90] },
      [A_BJORN]: { desc: 'Riften:2', pos: [5000, 6000, 700], rot: [0, 0, 10] },
      [A_NOBODY]: { desc: 'Solitude:3', pos: [1, 2, 3], rot: [0, 0, 0] },
      [A_SERA]: { desc: 'Markarth:4', pos: [9, 9, 9], rot: [0, 0, 0] }
    },
    staff: {}, kicked: [], set: [], said: [], silencedPosts: [], logged: [], records: [],
    queue: [], timers: [], timeouts: []
  };
  w.staff[STAFFER] = true;
  return w;
}

function load(w) {
  const mp = {
    get: function (id, key) {
      if (id === 0 && key === 'onlinePlayers') { return w.online.slice(); }
      if (key === 'profileId') { return w.pid[id]; }
      if (key === 'appearance') { return { name: w.name[id] }; }
      if (key === 'worldOrCellDesc') { return (w.where[id] || {}).desc; }
      if (key === 'pos') { return (w.where[id] || {}).pos; }
      if (key === 'angle') { return (w.where[id] || {}).rot; }
      return undefined;
    },
    set: function (id, key, v) {
      w.set.push({ id: id, key: key, v: v });
      if (key === 'locationalData') {
        w.where[id] = { desc: v.cellOrWorldDesc, pos: v.pos.slice(), rot: v.rot.slice() };
      }
    },
    getServerSettings: function () { return { privDir: 'private' }; },
    getUserByActor: function (a) { return w.online.indexOf(a) >= 0 ? 70 + w.online.indexOf(a) : -1; },
    kick: function (u) { w.kicked.push(u); },
    makeProperty: function () { },
    callPapyrusFunction: function () { }
  };
  const http = {
    request: function (opts, cb) {
      const req = {
        on: function () { return req; },
        destroy: function () { },
        end: function (body) {
          if (opts.method === 'GET' && String(opts.path).indexOf('/commands') === 0) {
            const out = JSON.stringify({ commands: w.queue.splice(0, w.queue.length) });
            const h = {};
            const res = { on: function (ev, fn) { h[ev] = fn; return res; }, resume: function () { } };
            cb(res);
            if (h.data) { h.data(out); }
            if (h.end) { h.end(); }
            return;
          }
          let doc = null;
          try { doc = JSON.parse(body); } catch (e) { doc = body; }
          if (opts.path === '/say') { w.said.push({ to: doc.profileId, text: doc.text }); }
          if (opts.path === '/silenced') { w.silencedPosts.push(doc); }
          if (cb) { cb({ resume: function () { }, on: function () { } }); }
        }
      };
      return req;
    }
  };
  const fakeFs = {
    readFileSync: function () { throw new Error('not here'); },
    existsSync: function () { return false; },
    appendFileSync: function (p, text) { w.records.push({ path: p, text: text }); },
    writeFileSync: function () { }, unlinkSync: function () { }
  };
  const box = {
    mp: mp,
    require: function (n) { return n === 'http' ? http : n === 'fs' ? fakeFs : n === 'path' ? path : require(n); },
    console: { log: function () { }, error: function () { } },
    Buffer: Buffer,
    log: function () { w.logged.push(Array.prototype.join.call(arguments, ' ')); },
    voicePort: function () { return 7778; },
    guard: function (name, fn) { return fn; },
    setInterval: function (fn, ms) { w.timers.push({ fn: fn, ms: ms }); return w.timers.length; },
    clearInterval: function () { },
    setTimeout: function (fn, ms) { w.timeouts.push({ fn: fn, ms: ms }); return w.timeouts.length; },
    clearTimeout: function () { }
  };
  vm.createContext(box);
  box.__thornswoodIsDev = function (p) { return !!w.staff[p]; };
  box.__thornswoodIsAdmin = function () { return false; };
  box.__thornswoodIsAllowed = function () { return true; };
  box.__thornswoodPassSeen = { passes: {}, online: {}, said: {} };
  box.__thornswoodSocial = {
    findPerson: function (want) {
      const low = String(want).toLowerCase();
      const hit = w.online.filter(function (a) { return String(w.name[a]).toLowerCase().indexOf(low) === 0; });
      if (hit.length === 1) { return { actorId: hit[0], why: '' }; }
      return { actorId: 0, why: hit.length ? 'More than one person here answers to that.' : 'Nobody here by that name.' };
    }
  };
  vm.runInContext(COMMANDS.split('const WORDS').join('var WORDS').split('const PLAYER_WORDS').join('var PLAYER_WORDS') +
                  '\n' + STAFF, box, { filename: 'gamemode.js (commands and staff)' });
  w.box = box;
  w.tick = w.timers.filter(function (t) { return t.ms === 1500; })[0];
  w.freeze = w.timers.filter(function (t) { return t.ms === 1000; })[0];
  return w;
}

let nextId = 1;
function run(w, pid, text, proven) {
  const before = w.said.length;
  w.queue.push({ id: 't:' + (nextId++), profileId: pid, name: '', text: text, at: Date.now(),
                 proven: proven !== false });
  w.tick.fn();
  return w.said.slice(before);
}
function to(lines, pid) { return lines.filter(function (l) { return l.to === pid; }).map(function (l) { return l.text; }); }
function pass10(w, pid) { w.box.__thornswoodPassSeen.passes[pid] = { at: Date.now(), x: Date.now() + 600000, v: '1.1.102' }; }

if (COMMANDS && STAFF) {
  const w = load(world());
  yes('the blocks load and arm the command and freeze timers', !!w.tick && !!w.freeze);
  yes('the staff block is on globalThis', !!w.box.__thornswoodStaff);
  pass10(w, STAFFER);
  pass10(w, NOBODY);

  console.log('\nsomebody who is not staff:');
  const words = ['/kick Bjorn', '/freeze Bjorn', '/unfreeze Bjorn', '/bring Bjorn',
                 '/silence Bjorn', '/unsilence Bjorn', '/warn Bjorn rude'];
  for (const line of words) {
    const got = to(run(w, NOBODY, line), NOBODY);
    yes(line + ' answers exactly "' + REFUSED + '" in their chat',
        got.length === 1 && got[0] === REFUSED);
  }
  yes('and nothing happened to Bjorn: not moved, not kicked, told nothing',
      w.set.length === 0 && w.kicked.length === 0 && to(w.said, BJORN).length === 0);
  yes('nothing was recorded for the staff channel', w.records.length === 0);
  yes('each refusal is in the log', w.logged.filter(function (l) { return /staff: \/\w+ refused profile 3003, who is not staff/.test(l); }).length === words.length);
  const gotoNon = to(run(w, NOBODY, '/goto Bjorn'), NOBODY);
  yes('/goto from somebody not staff is left to the place teleport, not refused as staff',
      gotoNon.every(function (t) { return t !== REFUSED; }));

  console.log('\nstaff, proven, with a join pass:');
  let got = run(w, STAFFER, '/warn Bjorn spamming the market');
  yes('/warn tells the moderator in their chat', to(got, STAFFER)[0] === 'Warned Bjorn Iron-Hand.');
  yes('and tells Bjorn what for, in his', /^A warning from staff: spamming the market\./.test(to(got, BJORN)[0] || ''));
  const rec = w.records.map(function (r) { return JSON.parse(r.text); });
  yes('one line in moderation.log, under privDir', w.records.length === 1 &&
      w.records[0].path === path.join('private', 'moderation.log'));
  yes('which says who did what to whom and why', rec[0] && rec[0].did === 'warn' && rec[0].by === STAFFER &&
      rec[0].who === BJORN && rec[0].whoName === 'Bjorn Iron-Hand' && rec[0].why === 'spamming the market' &&
      rec[0].server === 'main');
  yes('and one line in thornswood.log', w.logged.some(function (l) {
    return l === 'staff: Aela (profile 1001) warn Bjorn Iron-Hand (profile 2002): spamming the market'; }));
  got = run(w, STAFFER, '/warn Bjorn');
  yes('/warn with no reason asks for one', /Warn them about what/.test(to(got, STAFFER)[0] || '') && w.records.length === 1);

  got = run(w, STAFFER, '/freeze Bjorn');
  yes('/freeze answers the moderator', /^Froze Bjorn Iron-Hand\./.test(to(got, STAFFER)[0] || ''));
  yes('and tells Bjorn', /Staff have frozen you in place/.test(to(got, BJORN)[0] || ''));
  w.where[A_BJORN] = { desc: 'Riften:2', pos: [5400, 6000, 700], rot: [0, 0, 10] };
  const setsBefore = w.set.length;
  w.freeze.fn();
  yes('a frozen person who walks off is put back where they were frozen',
      w.set.length === setsBefore + 1 && w.set[w.set.length - 1].id === A_BJORN &&
      JSON.stringify(w.where[A_BJORN].pos) === '[5000,6000,700]');
  w.where[A_BJORN].pos = [5010, 6000, 700];
  w.freeze.fn();
  yes('a step inside the slack is left alone', w.set.length === setsBefore + 1);
  got = run(w, STAFFER, '/unfreeze Bjorn');
  yes('/unfreeze lets him go and says so to both', /can move again/.test(to(got, STAFFER)[0] || '') &&
      /You can move again/.test(to(got, BJORN)[0] || ''));
  w.where[A_BJORN].pos = [9000, 6000, 700];
  const s2 = w.set.length;
  w.freeze.fn();
  yes('and after that he is not put back', w.set.length === s2);

  got = run(w, STAFFER, '/bring bjorn');
  yes('/bring moves Bjorn to the moderator', w.where[A_BJORN].desc === 'Whiterun:1' &&
      JSON.stringify(w.where[A_BJORN].pos) === '[100,200,300]');
  yes('and answers both', to(got, STAFFER)[0] === 'Brought Bjorn Iron-Hand to you.' &&
      to(got, BJORN)[0] === 'Staff brought you to them.');

  got = run(w, STAFFER, '/goto Sera');
  yes('/goto <person> moves the moderator to them', w.where[A_STAFF].desc === 'Markarth:4' &&
      to(got, STAFFER)[0] === 'Sent to Sera.');
  yes('/goto <place> is not taken by the staff block',
      w.box.__thornswoodStaff.command({ proven: true }, '/goto', ['/goto', 'whiterun'], STAFFER, A_STAFF,
                                      function () { return true; }) === false);

  got = run(w, STAFFER, '/silence Bjorn 10 shouting slurs');
  const last = w.silencedPosts[w.silencedPosts.length - 1] || {};
  yes('/silence tells the voice service who, and until when', !!last.profiles &&
      Object.keys(last.profiles).join() === String(BJORN) &&
      Math.abs(last.profiles[BJORN] - (Date.now() + 600000)) < 5000);
  yes('and answers both', /^Silenced Bjorn Iron-Hand for 10 minutes/.test(to(got, STAFFER)[0] || '') &&
      /silenced you for 10 minutes: shouting slurs\./.test(to(got, BJORN)[0] || ''));
  got = run(w, BJORN, '/ooc can anybody hear me');
  yes('/ooc from somebody silenced reaches nobody and says why',
      got.length === 1 && got[0].to === BJORN && /silenced you for another 10 minutes/.test(got[0].text));
  got = run(w, BJORN, '/roll 20');
  yes('nor does /roll', got.length === 1 && /silenced/.test(got[0].text));
  got = run(w, STAFFER, '/unsilence Bjorn');
  yes('/unsilence clears it at the voice service too',
      JSON.stringify((w.silencedPosts[w.silencedPosts.length - 1] || {}).profiles) === '{}' &&
      /can speak again/.test(to(got, STAFFER)[0] || ''));

  got = run(w, STAFFER, '/kick Bjorn');
  yes('/kick tells Bjorn first and the moderator', /Staff have ended your session/.test(to(got, BJORN)[0] || '') &&
      /^Removing Bjorn Iron-Hand/.test(to(got, STAFFER)[0] || ''));
  yes('and nobody is kicked until the line has had time to show', w.kicked.length === 0);
  const t = w.timeouts[w.timeouts.length - 1];
  t.fn();
  yes('then his connection is ended', w.kicked.length === 1 && w.kicked[0] === 70 + w.online.indexOf(A_BJORN));
  got = run(w, STAFFER, '/kick Aela');
  yes('staff cannot kick themselves by accident', to(got, STAFFER)[0] === 'That is you.');

  const dids = w.records.map(function (r) { return JSON.parse(r.text).did; }).join(',');
  yes('every action wrote one line for the staff channel: ' + dids,
      dids === 'warn,freeze,unfreeze,bring,goto,silence,unsilence,kick');

  console.log('\nstaff whose identity is not proven:');
  const recs = w.records.length;
  got = run(w, STAFFER, '/kick Bjorn', false);
  yes('an unproven connection is refused, with a sentence saying so',
      /proved who you are/.test(to(got, STAFFER)[0] || '') && w.records.length === recs);
  delete w.box.__thornswoodPassSeen.passes[STAFFER];
  got = run(w, STAFFER, '/freeze Bjorn');
  yes('no join pass on hand is refused', /launcher's pass/.test(to(got, STAFFER)[0] || '') && w.records.length === recs);
  w.box.__thornswoodPassSeen.passes[STAFFER] = { at: Date.now() - 700000, x: Date.now() - 1 };
  got = run(w, STAFFER, '/freeze Bjorn');
  yes('an expired pass is refused', /launcher's pass/.test(to(got, STAFFER)[0] || '') && w.records.length === recs);
  yes('and the log says which', w.logged.some(function (l) { return /refused profile 1001, no join pass on hand/.test(l); }) &&
      w.logged.some(function (l) { return /refused profile 1001, the voice service did not prove/.test(l); }));

  console.log('\nthe words:');
  const all = w.said.map(function (s) { return s.text; }).join('\n') + STAFF;
  yes('nothing said uses the word the house rules forbid', !/player/i.test(w.said.map(function (s) { return s.text; }).join('\n')));
  yes('no em dash in anything said or in the block', all.indexOf(String.fromCharCode(0x2014)) < 0);
  yes('the staff words are not offered to everybody in /help',
      ['/kick', '/freeze', '/silence', '/warn', '/bring'].every(function (x) { return w.box.PLAYER_WORDS.indexOf(x) < 0; }));
}

// ------------------------------------------------------------------ B --
const PORT = 7931;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-staff-'));
const KEY = crypto.randomBytes(32).toString('hex');
fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
const srv = spawn(process.execPath, ['voice-server.js'], {
  cwd: dir,
  env: Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_AUTH: 'log', THORNSWOOD_SITE: '',
    THORNSWOOD_CHAT_DIR: path.join(dir, 'chat'), THORNSWOOD_CHAT_RANGE: 'off'
  })
});
let srvLog = '';
srv.stdout.on('data', (d) => { srvLog += d; });
srv.stderr.on('data', (d) => { srvLog += d; });
const base = 'http://127.0.0.1:' + PORT;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(cond, ms) {
  const end = Date.now() + (ms || 3000);
  while (Date.now() < end) { if (await cond()) { return true; } await wait(25); }
  return false;
}
function token(pid) {
  const until = Date.now() + 3600000;
  const body = String(pid) + '.' + String(until);
  const mac = crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return 'v1.' + body + '.' + mac;
}
const sockets = [];
function join(pid, name, tok) {
  return new Promise((done, bad) => {
    const ws = new WebSocket('ws://127.0.0.1:' + PORT + '/');
    const heard = [];
    sockets.push(ws);
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', profileId: pid, name: name, token: tok || '' }));
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (m.t === 'welcome') { done({ heard: heard, say: (text) => ws.send(JSON.stringify({ t: 'chat', text: text })) }); }
      if (m.t === 'chat') { heard.push(m); }
    };
    ws.onerror = () => bad(new Error('could not join'));
    setTimeout(() => bad(new Error('no welcome')), 4000);
  });
}
async function commands() {
  const r = await fetch(base + '/commands');
  try { return (await r.json()).commands || []; } catch (e) { return []; }
}
async function health() {
  try { const r = await fetch(base + '/health'); if (r.ok) { return await r.json(); } } catch (e) { }
  return null;
}

function python(args) {
  const { spawnSync } = require('child_process');
  // The first one that has discord.py, which bot.py needs to load at all.
  let had = null;
  for (const exe of ['py', 'python', 'python3']) {
    const r = spawnSync(exe, args, { encoding: 'utf8', cwd: path.join(ROOT, 'bot'),
      env: Object.assign({}, process.env, { DISCORD_TOKEN: 'not-a-real-token', PYTHONIOENCODING: 'utf-8' }) });
    if (r.error) { continue; }
    if (/No module named 'discord'/.test(String(r.stderr || ''))) { had = had || r; continue; }
    return r;
  }
  return had;
}

(async () => {
  let h = null;
  for (let i = 0; i < 60 && !h; i++) { h = await health(); if (!h) { await wait(150); } }
  if (!h) { yes('the voice service came up', false); console.log(srvLog); return; }
  console.log('\nthe voice service:');
  const aela = await join(STAFFER, 'Aela', token(STAFFER));
  const liar = await join(STAFFER, 'Not Aela', '');
  const bjorn = await join(BJORN, 'Bjorn', token(BJORN));
  const sera = await join(SERA, 'Sera', token(SERA));

  aela.say('/kick Bjorn');
  await until(async () => (h = await health()) && h.queuedCommands === 1);
  liar.say('/kick Bjorn');
  await until(async () => (h = await health()) && h.queuedCommands === 2);
  const got = await commands();
  yes('a command from a connection with a good token is queued as proven',
      got.length === 2 && got[0].proven === true && got[0].profileId === STAFFER);
  yes('the same profile number with no token is queued as not proven',
      got.length === 2 && got[1].proven === false && got[1].profileId === STAFFER);

  const r = await fetch(base + '/silenced', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ profiles: { [BJORN]: Date.now() + 120000 } }) });
  yes('POST /silenced from loopback is taken', r.ok && (await r.json()).silenced === 1);
  const seraBefore = sera.heard.length;
  bjorn.say('hello everybody');
  yes('a line from somebody silenced is answered to them alone',
      await until(() => bjorn.heard.some((m) => /silenced you for another 2 minutes/.test(m.text)), 3000));
  sera.say('I am here');
  await until(() => sera.heard.length > seraBefore, 3000);
  yes('and reaches nobody else', !sera.heard.some((m) => m.text === 'hello everybody'));
  bjorn.say('/me waves');
  await wait(300);
  yes('nor does /me', !sera.heard.some((m) => /waves/.test(m.text)));
  bjorn.say('/help');
  yes('their slash commands still go to the game server',
      await until(async () => (await commands()).some((c) => c.text === '/help' && c.profileId === BJORN), 3000));
  await fetch(base + '/silenced', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ profiles: {} }) });
  const before = sera.heard.length;
  bjorn.say('back again');
  yes('an empty list lets them speak again',
      await until(() => sera.heard.slice(before).some((m) => m.text === 'back again'), 3000));

  // ---------------------------------------------------------------- C --
  console.log('\nthe bot:');
  const py = python(['-c',
    'import bot, json\n' +
    'print(bot.moderation_text("live", {"did":"kick","by":1001,"byName":"Aela","who":2002,"whoName":"@everyone","why":"**spam**"}))\n' +
    'print(bot.moderation_text("dev", {"did":"silence","by":1,"byName":"A","who":2,"whoName":"B","minutes":10}))\n' +
    'print(bot.moderation_text("dev", {"did":"nonsense"}))\n' +
    'print("watch_moderation()" in __import__("inspect").getsource(bot.on_ready))']);
  if (!py) { yes('python is here to check the bot', false); }
  else {
    const out = String(py.stdout || '').split(/\r?\n/);
    yes('the bot says a kick in the staff channel with both names and profiles',
        /^\*\*Staff on the live server:\*\* Aela \(profile 1001\) removed @.everyone \(profile 2002\) from the world: \\\*\\\*spam\\\*\\\*$/.test(out[0] || ''));
    yes('a silence says for how long', out[1] === '**Staff on the dev server:** A (profile 1) silenced B (profile 2) for 10 minutes.');
    yes('a line that is not an action says nothing', out[2] === 'None');
    yes('on_ready starts the watcher', out[3] === 'True');
    if (py.status !== 0) { console.log(py.stderr); }
  }
})().catch((e) => { fail++; console.log('FAIL  the harness threw: ' + (e && e.stack ? e.stack : e)); })
  .then(() => {
    for (const s of sockets) { try { s.close(); } catch (e) { } }
    try { srv.kill(); } catch (e) { }
    setTimeout(() => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { } }, 300).unref();
    console.log('');
    console.log(pass + ' passed, ' + fail + ' failed');
    process.exitCode = fail ? 1 : 0;
    setTimeout(() => process.exit(process.exitCode), 1500).unref();
  });
