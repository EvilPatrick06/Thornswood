// test-5196-bot-pass.js
//
//     node .\tests\test-5196-bot-pass.js
//
// #5196. scripts/bot/Bot-Pass.js, the pass a dev deploy waits on, against a
// stand-in server: a process that prints what the engine prints as it loads
// a gamemode, and a stand-in for the engine's createBotClient that answers as
// the fork and the gamemode do. A new character comes with the race menu
// open and creation already open in its first packet (the thornswoodChargen
// property at stage appearance, and the plain clothes in its pack), because
// gamemode.js opens creation before the engine hands the character over
// (spawn.ts, __thornswoodChargen.created). A face then moves creation on to
// choosing, which comes as an UpdateProperty, and the character is written
// to the world. The race menu's close is never sent after a face: the engine
// closes the menu as it takes the face, so the gamemode's closeRaceMenu sends
// nothing (PartOne::SetRaceMenuOpen). After a restart the character comes
// as the world holds it. Then the same with each part broken, one at a
// time, and the pass has to FAIL on that step and name it:
//
//  - the gamemode does not load, or a different one loads;
//  - the server holds logins for a join pass (not a bot pass copy);
//  - the character is not new; creation is not opened for it; the gamemode
//    takes it for a returning one; creation does not move on after a face;
//  - nothing is written to the world;
//  - after the restart the character comes back somewhere else, or nameless.
//
// Read only, apart from a temp folder it deletes. Nothing connects anywhere.
'use strict';
const crypto = require('crypto');
const EventEmitter = require('events');
const fs = require('fs');
const os = require('os');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const botPass = require(path.join(ROOT, 'scripts', 'bot', 'Bot-Pass.js'));
const character = require(path.join(ROOT, 'scripts', 'bot', 'character.js'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-5196p-'));
process.on('exit', () => { fs.rmSync(TMP, { recursive: true, force: true }); });

const SPAWN = [133857, -61130, 14662];

// A server folder: settings, a gamemode, an empty world.
function folder(name, settings) {
  const root = path.join(TMP, name);
  fs.mkdirSync(path.join(root, 'world', 'changeForms'), { recursive: true });
  fs.writeFileSync(path.join(root, 'gamemode.js'), '// the gamemode under test ' + name + '\n');
  fs.writeFileSync(path.join(root, 'server-settings.json'), JSON.stringify(Object.assign({
    port: 7801, password: 'pw-' + name, thornswoodRequirePass: false, databaseName: 'world'
  }, settings || {})));
  return root;
}

// The stand-in. break_ names the one thing it gets wrong.
function standIn(root, break_) {
  const state = { up: false, runs: 0, moved: false };
  // Every message the stand-in sent a bot.
  const sent = [];
  // The running server, so the stand-in engine can print the gamemode's lines.
  let child0 = null;
  const blob = botPass.gitBlob(path.join(root, 'gamemode.js'));
  const formFile = path.join(root, 'world', 'changeForms', '1.json');

  function spawn() {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    state.runs++;
    child0 = child;
    child.kill = () => { setTimeout(() => { state.up = false; child.emit('exit', null, 'SIGTERM'); }, 5); };
    setTimeout(() => {
      child.stdout.emit('data', 'Using data dir \'data\'\n');
      if (break_ === 'no load') { child.stdout.emit('data', '[thornswood] gamemode did not load; the error is above\n'); return; }
      const said = break_ === 'other gamemode' ? 'f'.repeat(40) : blob;
      child.stdout.emit('data', 'gamemode.js is git blob ' + said + ', 40 bytes\r\n[thornswood] gamemode client scripts ab');
      child.stdout.emit('data', 'cd (3), the first load in this process\n');
      state.up = true;
    }, 5);
    return child;
  }

  const addon = {
    createBotClient(host, port, password) {
      const out = [];
      let actor = null;
      let open = true;
      // gamemode.js's chargen stage: 'appearance' from creation, 'choosing'
      // once a face lands in it.
      let stage = '';
      const settings = JSON.parse(fs.readFileSync(path.join(root, 'server-settings.json'), 'utf8'));
      if (!state.up) { out.push({ type: 'connectionFailed' }); }
      else if (password !== settings.password) { out.push({ type: 'connectionDenied', error: 'Invalid password' }); }
      else { out.push({ type: 'connectionAccepted' }); }
      return {
        tick() { const got = out.splice(0); for (const e of got) { if (e.message) { sent.push(e.message); } } return got; },
        isConnected() { return true; },
        destroy() { },
        send(m) {
          if (m.t === 1) {
            const c = JSON.parse(m.contentJsonDump);
            if (c.customPacketType !== 'loginWithSkympIo') { return; }
            const pid = c.gameData.profileId;
            let form = null;
            try { form = JSON.parse(fs.readFileSync(formFile, 'utf8')); } catch (e) { form = null; }
            if (form && form.profileId === pid) {
              let pos = form.position.slice();
              if (break_ === 'moved') { pos[0] += 500; }
              let ap = JSON.parse(form.appearanceDump);
              if (break_ === 'nameless') { ap = null; }
              actor = { t: 33, idx: 5, isMe: true, transform: { pos, rot: [0, 0, 90], worldOrCell: 0x3c },
                        appearance: ap, props: {} };
            } else {
              // spawn.ts: the gamemode's created() runs before the owner gets
              // anything, so the first packet carries creation and the clothes.
              stage = break_ === 'no creation' ? '' : break_ === 'returning' ? 'done' : 'appearance';
              if (break_ === 'no creation') {
                child0.stdout.emit('data', '[thornswood] chargen ff000801 profile 5 already has a character and is carrying nothing, not in the hall, no face, so creation is skipped for them\n');
              }
              const custom = stage ? [{ propName: 'thornswoodChargen', propValueJsonDump: JSON.stringify({ stage, at: 1 }) }] : [];
              actor = { t: 33, idx: 4, isMe: true, transform: { pos: SPAWN.slice(), rot: [0, 0, 0], worldOrCell: 0x3c },
                        props: Object.assign(break_ === 'not new' ? {} : { isRaceMenuOpen: true },
                          { inventory: { entries: [{ baseId: 0x12eb7, count: 1, worn: true }, { baseId: 0xf, count: 40 }] } }),
                        customPropsJsonDumps: custom };
            }
            out.push({ type: 'message', message: actor });
            return;
          }
          // The engine takes one face per race menu, stores it and closes
          // the menu itself; the gamemode moves creation on when the face
          // lands in it. No race menu message is sent either way.
          if (m.t === 4 && actor && open && m.idx === actor.idx) {
            open = false;
            if (break_ !== 'not saved') {
              fs.writeFileSync(formFile, JSON.stringify({ profileId: actor ? lastPid(m) : 0, position: SPAWN.map((x) => x + 0.25),
                                                          appearanceDump: JSON.stringify(m.data) }));
            }
            if (stage !== 'appearance' || break_ === 'stays') { return; }
            stage = 'choosing';
            out.push({ type: 'message', message: { t: 7, idx: actor.idx, refrId: 0xff000801, propName: 'thornswoodChargen',
                                                  dataDump: JSON.stringify({ stage, at: 2 }) } });
          }
        }
      };
    }
  };
  // The profile is in the name the bot sends ("Bot Pass <id>").
  function lastPid(m) { return Number(String(m.data.name).replace('Bot Pass ', '')); }
  return { spawn, addon, state, sent };
}

async function run(name, break_, settings) {
  const root = folder(name, settings);
  const s = standIn(root, break_);
  const said = [];
  const r = await botPass.pass({ root, spawn: s.spawn, addon: s.addon, loadMs: 2000, stepMs: 1500, log: (l) => said.push(l) });
  return { r, s, said, root };
}

function failedAt(r, step) {
  const bad = r.lines.filter((l) => !l.ok);
  return !r.ok && bad.length === 1 && bad[0].step === step;
}

(async () => {
  // ------------------------------------------------------------------ whole
  const good = await run('good');
  yes('a good server passes the whole pass', good.r.ok === true);
  yes('every step is a line: loads, login, new, face, saved, restart, loads back',
    good.r.lines.map((l) => l.step).join(',') === 'loads,login,new,face,saved,restart,loads back');
  yes('the server was started twice (once, then after the restart)', good.s.state.runs === 2);
  yes('the server is stopped at the end', good.s.state.up === false);
  yes('the result names the gamemode\'s git blob', good.r.blob === botPass.gitBlob(path.join(good.root, 'gamemode.js')));
  yes('the server\'s output went to bot-pass-server.log', /gamemode client scripts abcd/.test(fs.readFileSync(path.join(good.root, 'bot-pass-server.log'), 'utf8')));
  yes('a line split across two reads is read whole', good.r.tail.some((l) => l === '[thornswood] gamemode client scripts abcd (3), the first load in this process'));
  yes('the git blob is git\'s (blob <size>\\0<bytes>)',
    botPass.gitBlob(path.join(good.root, 'gamemode.js')) ===
    crypto.createHash('sha1').update('blob ' + fs.statSync(path.join(good.root, 'gamemode.js')).size + '\0' + fs.readFileSync(path.join(good.root, 'gamemode.js'), 'utf8')).digest('hex'));
  yes('the face is a Nord with the engine\'s 19 morphs and 4 presets',
    (() => { const f = botPass.face('X'); return f.raceId === 0x13746 && f.options.length === 19 && f.presets.length === 4 && f.name === 'X'; })());

  // ------------------------------------- where a pass that runs on got to
  // The pass says each step as it starts, before it waits on it, so the
  // last line of bot-pass.log names the wait a pass that never ends is in.
  const order = ['loading the engine', 'the server started; it has 2 s', 'PASS  loads', 'a bot connects to port 7801',
    'PASS  login', 'the bot sends a face', 'PASS  face', 'waiting for the world on disk', 'PASS  saved',
    'the server is stopped', 'the server started again', 'PASS  restart', 'a second bot connects', 'PASS  loads back', 'the pass ends'];
  const at = order.map((o) => good.said.findIndex((l) => l.startsWith(o)));
  yes('the pass says each step as it starts, in order, before its PASS line', at.every((x, i) => x >= 0 && (i === 0 || x > at[i - 1])));
  {
    const cp = require('child_process');
    const root = folder('mainlog', { thornswoodRequirePass: true });
    const out = path.join(TMP, 'mainlog-run', 'result.json');
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const ran = cp.spawnSync(process.execPath, [path.join(ROOT, 'scripts', 'bot', 'Bot-Pass.js'), '--root', root, '--out', out], { encoding: 'utf8' });
    const logAt = path.join(path.dirname(out), 'bot-pass.log');
    const text = fs.existsSync(logAt) ? fs.readFileSync(logAt, 'utf8') : '';
    yes('run as the task runs it, the pass writes bot-pass.log beside its result as it goes, each line timed',
      ran.status === 1 && fs.existsSync(out) && /^\d{4}-\d\d-\d\dT[\d:.]+Z  the bot pass starts in /.test(text) &&
      /FAIL  loads: .*not a bot pass copy/.test(text) && /BOT PASS FAILED\n$/.test(text));
  }

  // ------------------------------------------------------------- broken
  yes('the gamemode does not load: FAIL on loads', failedAt((await run('noload', 'no load')).r, 'loads'));
  const other = await run('other', 'other gamemode');
  yes('another gamemode loads: FAIL on loads, naming both blobs',
    failedAt(other.r, 'loads') && /a different gamemode loaded, git blob f{40}, not [0-9a-f]{40}/.test(other.r.lines[0].detail));
  const held = await run('held', null, { thornswoodRequirePass: true });
  yes('a server that holds logins for a pass is refused before it is started',
    failedAt(held.r, 'loads') && held.s.state.runs === 0 && /not a bot pass copy/.test(held.r.lines[0].detail));
  const unset = await run('unset', null, { thornswoodRequirePass: undefined });
  yes('a server that does not say it holds no pass is refused too', failedAt(unset.r, 'loads') && unset.s.state.runs === 0);
  yes('not new: FAIL on new', failedAt((await run('notnew', 'not new')).r, 'new'));
  const stays = await run('stays', 'stays');
  yes('creation does not move on after the face: FAIL on face, saying what it waited for',
    failedAt(stays.r, 'face') && /creation moving on to choosing/.test(stays.r.lines.find((l) => !l.ok).detail));
  const nocreate = await run('nocreate', 'no creation');
  yes('creation is not opened for it: FAIL on new, saying so',
    failedAt(nocreate.r, 'new') && /no creation stage/.test(nocreate.r.lines.find((l) => !l.ok).detail));
  yes('  and the FAIL carries what the gamemode said about creating it',
    /The gamemode said: \[thornswood\] chargen ff000801 profile 5 .*not in the hall/.test(nocreate.r.lines.find((l) => !l.ok).detail));
  yes('  and a PASS line carries none of it', nocreate.r.lines.filter((l) => l.ok).every((l) => !/gamemode said/.test(l.detail)));
  const returning = await run('returning', 'returning');
  yes('taken for a returning character: FAIL on new, saying so',
    failedAt(returning.r, 'new') && /at stage done, not appearance/.test(returning.r.lines.find((l) => !l.ok).detail));
  yes('  and a FAIL where the gamemode said nothing says that',
    /The gamemode said nothing about creating it/.test(returning.r && returning.r.lines.find((l) => !l.ok).detail || ''));

  const unsaved = await run('unsaved', 'not saved');
  yes('nothing written to the world: FAIL on saved', failedAt(unsaved.r, 'saved') && /holds no character/.test(unsaved.r.lines.find((l) => !l.ok).detail));
  const moved = await run('moved', 'moved');
  yes('back somewhere else: FAIL on loads back, with both places', failedAt(moved.r, 'loads back') && /stands at/.test(moved.r.lines.find((l) => !l.ok).detail));
  const nameless = await run('nameless', 'nameless');
  yes('back with no name: FAIL on loads back', failedAt(nameless.r, 'loads back') && /its name is/.test(nameless.r.lines.find((l) => !l.ok).detail));
  yes('a failed pass still stops its server', [other, held, nocreate, returning, stays, unsaved, moved, nameless].every((x) => x.s.state.up === false));

  // ------------------- what the first two passes on the box waited for
  // Neither comes from the engine and gamemode: no inventory message after
  // the first packet, and no race menu close after a face.
  yes('the good pass got no inventory message and no race menu message, and did not need one',
    good.r.ok && !good.s.sent.some((m) => m.t === 28 || m.t === 29));

  // ---------------------------------------- the world folder is the engine's
  const w = folder('worldname', { databaseName: 'saves' });
  fs.mkdirSync(path.join(w, 'saves', 'changeForms'), { recursive: true });
  fs.writeFileSync(path.join(w, 'saves', 'changeForms', '7.json'), JSON.stringify({ profileId: 77, position: [1, 2, 3] }));
  yes('Bot-Pass reads the world where databaseName says', !!botPass.formOf(w, { databaseName: 'saves' }, 77));
  yes('character.js reads it there too (not a worldDir setting the engine does not have)',
    character.characters(w, { databaseName: 'saves' }).some((c) => c.profileId === 77));

  done();
})().catch((err) => { console.log('FAIL  ' + (err && err.stack || err)); fail++; done(); });
