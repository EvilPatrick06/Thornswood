// test-5196-bot-pass.js
//
//     node .\tests\test-5196-bot-pass.js
//
// #5196. scripts/bot/Bot-Pass.js, the pass a dev deploy waits on, against a
// stand-in server: a process that prints what the engine prints as it loads
// a gamemode, and a stand-in for the engine's createBotClient that answers as
// the fork and the gamemode do (a new character with the race menu open;
// after a face, the race menu closed, the plain clothes, and the character
// written to the world; after a restart, the character as the world holds
// it). Then the same with each part broken, one at a time, and the pass has
// to FAIL on that step and name it:
//
//  - the gamemode does not load, or a different one loads;
//  - the server holds logins for a join pass (not a bot pass copy);
//  - the character is not new; the race menu does not close; no clothes;
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
  const blob = botPass.gitBlob(path.join(root, 'gamemode.js'));
  const formFile = path.join(root, 'world', 'changeForms', '1.json');

  function spawn() {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    state.runs++;
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
      const settings = JSON.parse(fs.readFileSync(path.join(root, 'server-settings.json'), 'utf8'));
      if (!state.up) { out.push({ type: 'connectionFailed' }); }
      else if (password !== settings.password) { out.push({ type: 'connectionDenied', error: 'Invalid password' }); }
      else { out.push({ type: 'connectionAccepted' }); }
      return {
        tick() { return out.splice(0); },
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
              actor = { t: 33, idx: 4, isMe: true, transform: { pos: SPAWN.slice(), rot: [0, 0, 0], worldOrCell: 0x3c },
                        props: break_ === 'not new' ? {} : { isRaceMenuOpen: true } };
            }
            out.push({ type: 'message', message: actor });
            return;
          }
          if (m.t === 4 && actor && open && m.idx === actor.idx) {
            open = false;
            if (break_ !== 'menu stays') { out.push({ type: 'message', message: { t: 29, open: false } }); }
            if (break_ !== 'no clothes') { out.push({ type: 'message', message: { t: 28, inventory: { entries: [{ baseId: 0x12eb7, count: 1 }] } } }); }
            if (break_ !== 'not saved') {
              fs.writeFileSync(formFile, JSON.stringify({ profileId: actor ? lastPid(m) : 0, position: SPAWN.map((x) => x + 0.25),
                                                          appearanceDump: JSON.stringify(m.data) }));
            }
          }
        }
      };
    }
  };
  // The profile is in the name the bot sends ("Bot Pass <id>").
  function lastPid(m) { return Number(String(m.data.name).replace('Bot Pass ', '')); }
  return { spawn, addon, state };
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
  const stays = await run('stays', 'menu stays');
  yes('the race menu does not close: FAIL on face, saying what it waited for',
    failedAt(stays.r, 'face') && /race menu closing/.test(stays.r.lines.find((l) => !l.ok).detail));
  yes('no clothes: FAIL on face', failedAt((await run('noclothes', 'no clothes')).r, 'face'));
  const unsaved = await run('unsaved', 'not saved');
  yes('nothing written to the world: FAIL on saved', failedAt(unsaved.r, 'saved') && /holds no character/.test(unsaved.r.lines.find((l) => !l.ok).detail));
  const moved = await run('moved', 'moved');
  yes('back somewhere else: FAIL on loads back, with both places', failedAt(moved.r, 'loads back') && /stands at/.test(moved.r.lines.find((l) => !l.ok).detail));
  const nameless = await run('nameless', 'nameless');
  yes('back with no name: FAIL on loads back', failedAt(nameless.r, 'loads back') && /its name is/.test(nameless.r.lines.find((l) => !l.ok).detail));
  yes('a failed pass still stops its server', [other, held, stays, unsaved, moved, nameless].every((x) => x.s.state.up === false));

  // ---------------------------------------- the world folder is the engine's
  const w = folder('worldname', { databaseName: 'saves' });
  fs.mkdirSync(path.join(w, 'saves', 'changeForms'), { recursive: true });
  fs.writeFileSync(path.join(w, 'saves', 'changeForms', '7.json'), JSON.stringify({ profileId: 77, position: [1, 2, 3] }));
  yes('Bot-Pass reads the world where databaseName says', !!botPass.formOf(w, { databaseName: 'saves' }, 77));
  yes('character.js reads it there too (not a worldDir setting the engine does not have)',
    character.characters(w, { databaseName: 'saves' }).some((c) => c.profileId === 77));

  done();
})().catch((err) => { console.log('FAIL  ' + (err && err.stack || err)); fail++; done(); });
