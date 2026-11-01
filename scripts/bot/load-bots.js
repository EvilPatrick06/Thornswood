// scripts/bot/load-bots.js
//
// #4623. One of the load test's bot processes. Load-Test.js starts a few of
// these (child_process.fork) so the bots' own work is spread over the
// runner's cores, and tells each one how many bots to add. Every bot is the
// engine's own client (createBotClient in the server's scam_native.node,
// bot.js), so it connects, logs in and moves the way a game does:
//   1. connect over the game's port with the server's password (through
//      load-proxy.js, which counts the bytes);
//   2. log in as a profile nobody has, with a join pass the bot signs with
//      the load copy's own pass key (bot.js mintPass, the site's makePass;
//      a Discord id of its own, so no two bots are one account), answer the
//      login challenge with it as the launcher's game does, and wait for its
//      character (createActor with isMe);
//   3. send a face (UpdateAppearance), which closes the race menu the engine
//      opens for a new character;
//   4. walk: an UpdateMovement every 130 ms, unreliable, the rate and the
//      reliability skymp5-client's SendInputsService.sendMovement uses, in a
//      slow circle around where it was put, at a walk. A teleport the server
//      sends (Teleport, Teleport2) is carried out and its teleportSeq echoed,
//      as the game's RemoteServer does. Moves keep to their 130 ms beat
//      (the next is due 130 ms after the last was due), so Windows' timer
//      steps of about 15.6 ms do not slow a bot below the game's rate.
// Every message the server sends is read and counted, by type; none is kept.
//
// Messages from Load-Test.js:
//   { add: [profileId, ...] }   bots to start
//   { report: true }            answered with { report: {...} }
//   { stop: true }              closes every bot and ends
'use strict';
const os = require('os');
const fs = require('fs');
const path = require('path');
const { Bot, MSG, loadAddon, mintPass, passLoginKey } = require('./bot.js');
const { face } = require('./Bot-Pass.js');

const MOVE_MS = 130;           // SendInputsService.sendMovement's sendMovementRateMs
const STEP_MS = 60000;         // how long each login step may take
const WALK = 100;              // units a second, a walk
const TELEPORT = 20;
const TELEPORT2 = 31;

// A bot that reads what it is sent without keeping it: Bot.pump keeps every
// message, which a load test cannot (a crowd of 60 is sent tens of
// thousands a second).
class LoadBot extends Bot {
  constructor(addon, opts) {
    super(addon, opts);
    this.counts = {};          // message type -> how many, since the last report
    this.all = 0;              // every message, since it connected
    this.step = 'new';         // new, connecting, login, face, moving, failed
    this.why = '';
    this.deadline = 0;
    this.seq = 0;              // the newest teleportSeq carried out
    this.center = null;        // [x, y, z] it walks around
    this.cell = 0;
    this.angle = Math.random() * Math.PI * 2;
    this.radius = 200 + Math.random() * 300;
    this.lastMove = 0;
    this.teleports = 0;
  }

  pump() {
    if (!this.client) { return; }
    for (const e of this.client.tick()) {
      if (e.type === 'connectionAccepted') { this.state = 'connected'; continue; }
      if (e.type === 'connectionDenied' || e.type === 'connectionFailed') { this.state = 'refused'; this.refusal = e.type + (e.error ? ': ' + e.error : ''); continue; }
      if (e.type === 'disconnect') { this.state = 'closed'; continue; }
      if (e.type !== 'message') { continue; }
      const m = e.message;
      this.all++;
      const t = m && typeof m.t === 'number' ? m.t : 'raw';
      this.counts[t] = (this.counts[t] || 0) + 1;
      if (!m) { continue; }
      if (m.t === MSG.CreateActor && m.isMe && !this.character) { this.character = m; }
      if (m.t === MSG.CustomPacket && typeof m.contentJsonDump === 'string' && m.contentJsonDump.indexOf('thornswoodLoginChallenge') >= 0) {
        let c = null;
        try { c = JSON.parse(m.contentJsonDump); } catch (err) { this.fail('a login challenge that does not read as JSON'); return; }
        this.onCustom(c);
      }
      if ((m.t === TELEPORT && this.character && m.idx === this.character.idx) || m.t === TELEPORT2) {
        if (Array.isArray(m.pos) && m.pos.length === 3) { this.center = m.pos.map(Number); }
        if (typeof m.worldOrCell === 'number') { this.cell = m.worldOrCell; }
        if (typeof m.teleportSeq === 'number') { this.seq = m.teleportSeq; }
        this.teleports++;
      }
    }
  }

  fail(why) { this.step = 'failed'; this.why = why; try { this.close(); } catch (e) { this.why += ' (and closing it said ' + e.message + ')'; } }

  // One pass of this bot's steps; now is Date.now().
  advance(now) {
    if (this.step === 'failed') { return; }
    if (this.state === 'refused') { this.fail('refused: ' + this.refusal); return; }
    if (this.state === 'closed' && this.step !== 'new') { this.fail('the server closed the connection at step ' + this.step); return; }
    if (this.step !== 'moving' && this.deadline && now > this.deadline) { this.fail('no answer at step ' + this.step + ' in ' + STEP_MS / 1000 + ' s'); return; }
    if (this.step === 'connecting' && this.state === 'connected') {
      if (this.passKey) {
        const at = Date.now();
        const pass = mintPass(this.passKey, { p: Number(this.profileId), s: this.server, v: 'load-test', d: 'load-' + this.profileId, i: at, x: at + 4 * 3600000 });
        this.pass = { pass, loginKey: passLoginKey(this.passKey, pass) };
      }
      this.sendCustom({ customPacketType: 'loginWithSkympIo', gameData: { profileId: Number(this.profileId) } });
      this.step = 'login'; this.deadline = now + STEP_MS;
      return;
    }
    if (this.step === 'login' && this.character) {
      const tr = this.character.transform || {};
      this.center = Array.isArray(tr.pos) ? tr.pos.map(Number) : [0, 0, 0];
      this.cell = Number(tr.worldOrCell) || 0;
      if ((this.character.props || {}).isRaceMenuOpen === true) {
        this.send({ t: 4, idx: this.character.idx, data: face('Load ' + this.profileId) }, true);
      }
      this.step = 'moving'; this.deadline = 0; this.lastMove = now - Math.random() * MOVE_MS;
      return;
    }
    if (this.step === 'moving' && now - this.lastMove >= MOVE_MS) {
      const dt = MOVE_MS / 1000;
      // On the beat, unless the bot fell a whole beat behind, which starts
      // the beat again from now rather than sending the missed ones at once.
      this.lastMove = now - this.lastMove >= 2 * MOVE_MS ? now : this.lastMove + MOVE_MS;
      this.angle += (WALK * dt) / this.radius;
      const c = this.center;
      const pos = [c[0] + Math.cos(this.angle) * this.radius, c[1] + Math.sin(this.angle) * this.radius, c[2]];
      const heading = ((this.angle * 180 / Math.PI) + 90) % 360;
      this.send({ t: MSG.UpdateMovement, idx: this.character.idx, data: {
        worldOrCell: this.cell, pos, rot: [0, 0, heading], direction: 0, healthPercentage: 1, speed: WALK,
        runMode: 'Walking', isInJumpState: false, isSneaking: false, isBlocking: false, isWeapDrawn: false, isDead: false,
        teleportSeq: this.seq
      } }, false);
    }
  }
}

// The load copy's own pass key and the name its passes carry: door.json in
// its privDir, and thornswoodServer ("main" when unset, as the gamemode reads
// it).
function passKeyOf(root) {
  const settings = JSON.parse(String(fs.readFileSync(path.join(root, 'server-settings.json'), 'utf8')).replace(/^\uFEFF/, ''));
  const door = JSON.parse(String(fs.readFileSync(path.join(root, String(settings.privDir || 'private'), 'door.json'), 'utf8')).replace(/^\uFEFF/, ''));
  if (!door.passKey) { throw new Error('door.json in ' + root + ' has no passKey, so no bot can hold a join pass there'); }
  return { passKey: String(door.passKey), server: String(settings.thornswoodServer || '').trim().toLowerCase() || 'main' };
}

function args(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i += 2) { o[String(argv[i]).replace(/^--/, '')] = argv[i + 1]; }
  return o;
}

function main() {
  const a = args(process.argv.slice(2));
  if (!a.root || !a.port || !process.send) {
    console.log('node load-bots.js --root <server folder> --port <proxy port> [--password <p>], started by Load-Test.js with IPC');
    process.exit(2);
  }
  const addon = loadAddon(a.root);
  const { passKey, server } = passKeyOf(a.root);
  const bots = [];
  let cpu0 = process.cpuUsage();
  let at0 = Date.now();
  process.on('message', (msg) => {
    if (msg && Array.isArray(msg.add)) {
      for (const id of msg.add) {
        const b = new LoadBot(addon, { host: '127.0.0.1', port: Number(a.port), password: a.password || '', name: 'load ' + id });
        b.profileId = id; b.passKey = passKey; b.server = server;
        try {
          b.client = addon.createBotClient(b.host, b.port, b.password, b.timeoutMs);
          b.state = 'connecting'; b.step = 'connecting'; b.deadline = Date.now() + STEP_MS;
        } catch (e) { b.fail('createBotClient: ' + e.message); }
        bots.push(b);
      }
    }
    if (msg && msg.report) {
      const now = Date.now();
      const cpu = process.cpuUsage(cpu0);
      const steps = {};
      const counts = {};
      const failed = [];
      let teleports = 0;
      let all = 0;
      const perBot = [];
      for (const b of bots) {
        steps[b.step] = (steps[b.step] || 0) + 1;
        if (b.step === 'failed') { failed.push({ profileId: b.profileId, why: b.why }); }
        for (const k of Object.keys(b.counts)) { counts[k] = (counts[k] || 0) + b.counts[k]; }
        if (b.step === 'moving') { perBot.push(b.counts[MSG.UpdateMovement] || 0); }
        b.counts = {};
        teleports += b.teleports; all += b.all;
      }
      process.send({ report: { ms: now - at0, cpuMs: (cpu.user + cpu.system) / 1000, steps, counts, failed, teleports, all, movesReadPerBot: perBot, cores: os.cpus().length } });
      cpu0 = process.cpuUsage(); at0 = now;
    }
    if (msg && msg.stop) {
      for (const b of bots) { if (b.client) { b.close(); } }
      process.exit(0);
    }
  });
  process.on('disconnect', () => process.exit(0));
  const loop = () => {
    const now = Date.now();
    for (const b of bots) {
      if (b.step === 'failed') { continue; }
      try { b.pump(); b.advance(now); } catch (e) { b.fail(e.message); }
    }
    setTimeout(loop, 5);
  };
  loop();
}

if (require.main === module) { main(); }

module.exports = { LoadBot, MOVE_MS, passKeyOf };
