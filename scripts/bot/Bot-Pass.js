#!/usr/bin/env node
// scripts/bot/Bot-Pass.js
//
// #5196. The bot pass a dev deploy waits on. The box deploy agent (#5180)
// makes a throwaway copy of the dev server with the gamemode it is about to
// put on dev (tools/DeployAgent/BotPass.cs), and starts this in that copy as
// a task of its own with no rights outside it. This starts that server,
// plays the parts of the game a bot can reach over the game port, stops it,
// and writes what happened. A FAIL in it fails the Deployment and the
// gamemode does not go on dev.
//
//     node Bot-Pass.js --root <server folder> --out <result.json> [--id <run id>]
//
// What it checks, each a line in the result:
//   loads      the server starts, says this folder's gamemode.js loaded (the
//              git blob it names is this file's), and takes a connection;
//   login      a bot logs in as a profile nobody has, the way the game does,
//              and is sent its character (createActor with isMe);
//   new        that character is new: the race menu is open, and the
//              gamemode starts creation, which the bot sees as the plain
//              clothes arriving (gamemode.js beginAppearance and giveShift);
//   face       only then the bot sends a face (UpdateAppearance), and the
//              gamemode moves it on: the race menu closes (gamemode.js
//              onUpdateAppearanceAttempt, beginChoosing, closeRaceMenu);
//   saved      the world on disk holds the character with that name;
//   restart    the server is stopped and started again and loads again;
//   loads back a second bot logs in as the same profile and is sent the same
//              character: its name, where it stood, and no race menu.
// The server's own output goes to bot-pass-server.log beside it, and the
// last lines of it into the result, so a FAIL says what the server said.
//
// The waits are on things the server says or writes, each with a time
// limit: nothing is sent twice, and nothing is put right after the fact.
'use strict';
const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Bot, MSG, loadAddon } = require('./bot.js');

const LOADED = '[thornswood] gamemode client scripts ';
const NOT_LOADED = ['[thornswood] gamemode did not load', 'Bad syntax, ignoring'];
const BLOB = /gamemode\.js is git blob ([0-9a-f]{40})/;
// gamemode.js's creation lines (log('chargen', ...)), and the steps whose
// FAIL carries them.
const CHARGEN = '[thornswood] chargen ';
const CHARGEN_STEPS = ['new', 'face', 'saved'];
// A Nord, the race the game's own race menu opens on (NordRace,
// 0x13746:Skyrim.esm), with the shape unit/TestUtils.hpp sends.
const NORD = 0x13746;
// Gold (0xf:Skyrim.esm). The gamemode counts what a character carries apart
// from gold to tell a new character (nothing) from a returning one.
const GOLD = 0xf;

function readJson(file) {
  return JSON.parse(String(fs.readFileSync(file, 'utf8')).replace(/^﻿/, ''));
}

// git's id for a file's bytes, which the gamemode logs as it loads.
function gitBlob(file) {
  const b = fs.readFileSync(file);
  return crypto.createHash('sha1').update('blob ' + b.length + '\0').update(b).digest('hex');
}

function face(name) {
  return {
    isFemale: false, raceId: NORD, weight: 50, skinColor: -1, hairColor: -1,
    headpartIds: [], headTextureSetId: 0, tints: [], name,
    options: new Array(19).fill(0), presets: new Array(4).fill(0)
  };
}

// The character with this profile id in the world folder, or null. The
// engine's own setting names the folder (databaseName, "world" when unset,
// DatabaseFactory.cpp).
function formOf(root, settings, profileId) {
  const dir = path.join(root, String(settings.databaseName || 'world'), 'changeForms');
  let names = [];
  try { names = fs.readdirSync(dir); } catch (e) { return null; }
  for (const n of names) {
    if (!/^\d+\.json$/.test(n)) { continue; }
    let o = null;
    try { o = readJson(path.join(dir, n)); } catch (e) { continue; }
    if (o && Number(o.profileId) === profileId && !o.isDeleted) { return o; }
  }
  return null;
}

function nameIn(form) {
  if (!form || !form.appearanceDump) { return ''; }
  try {
    const a = typeof form.appearanceDump === 'string' ? JSON.parse(form.appearanceDump) : form.appearanceDump;
    return a && typeof a.name === 'string' ? a.name : '';
  } catch (e) { return ''; }
}

// One run of the server in root: node dist_back/skymp5-server.js, as the
// server's task starts it, its output kept and read line by line.
class ServerRun {
  constructor(root, spawn, logFile) {
    this.root = root;
    this.spawn = spawn;
    this.logFile = logFile;
    this.child = null;
    this.lines = [];
    this.tail = [];
    this.exited = null;
    this.partial = '';
  }

  start() {
    this.lines = [];
    this.exited = null;
    this.partial = '';
    this.child = this.spawn(this.root);
    const take = (chunk) => {
      const text = this.partial + String(chunk);
      const parts = text.split(/\r?\n/);
      this.partial = parts.pop();
      for (const l of parts) {
        this.lines.push(l);
        this.tail.push(l);
        if (this.tail.length > 60) { this.tail.shift(); }
        try { fs.appendFileSync(this.logFile, l + '\n'); } catch (e) { /* the result still holds the tail */ }
      }
    };
    this.child.stdout.on('data', take);
    this.child.stderr.on('data', take);
    this.child.on('exit', (code, signal) => { this.exited = { code, signal }; });
  }

  // Until the server says how the gamemode load went: '' when the gamemode
  // with this blob loaded, else why not.
  async awaitLoad(blob, ms) {
    const end = Date.now() + ms;
    let seen = 0;
    let said = '';
    for (;;) {
      for (; seen < this.lines.length; seen++) {
        const l = this.lines[seen];
        const m = BLOB.exec(l);
        if (m) { said = m[1]; continue; }
        if (l.indexOf(LOADED) >= 0) {
          if (said === blob) { return ''; }
          return said ? 'a different gamemode loaded, git blob ' + said + ', not ' + blob
            : 'a gamemode loaded without saying which it is';
        }
        if (NOT_LOADED.some((x) => l.indexOf(x) >= 0)) { return 'the gamemode did not load: ' + l.trim(); }
      }
      if (this.exited) { return 'the server ended (' + JSON.stringify(this.exited) + ') before the gamemode loaded'; }
      if (Date.now() > end) { return 'the server said nothing about the gamemode loading within ' + Math.round(ms / 1000) + ' s'; }
      await new Promise((r) => setTimeout(r, 50));
    }
  }

  async stop(ms) {
    if (!this.child || this.exited) { return true; }
    this.child.kill();
    const end = Date.now() + ms;
    while (!this.exited && Date.now() < end) { await new Promise((r) => setTimeout(r, 50)); }
    return !!this.exited;
  }
}

function spawnNode(root) {
  return childProcess.spawn(process.execPath, ['dist_back/skymp5-server.js'], {
    cwd: root, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true
  });
}

// The pass. opts: { root, id, loadMs, stepMs, spawn, addon, profileId, log }.
// Returns { ok, lines: [{ step, ok, detail }], blob, tail }.
async function pass(opts) {
  const root = path.resolve(opts.root);
  const log = opts.log || (() => {});
  const loadMs = opts.loadMs || 600000;
  const stepMs = opts.stepMs || 60000;
  const lines = [];
  // A FAIL from the character on says what the gamemode's creation said
  // about it (the copy has nobody else on it), so the Deployment's log holds
  // the reason and nobody has to fetch the server's log off the box.
  const said = (step) => {
    if (!CHARGEN_STEPS.includes(step)) { return ''; }
    const c = server.lines.filter((l) => l.indexOf(CHARGEN) >= 0).slice(-3).map((l) => l.trim().slice(0, 300));
    return c.length ? '. The gamemode said: ' + c.join(' | ') : '. The gamemode said nothing about creating it';
  };
  const say = (step, ok, detail) => {
    if (!ok) { detail += said(step); }
    lines.push({ step, ok, detail }); log((ok ? 'PASS  ' : 'FAIL  ') + step + ': ' + detail); return ok;
  };
  const settings = readJson(path.join(root, 'server-settings.json'));
  const port = Number(settings.port);
  const password = settings.password === undefined ? '' : String(settings.password);
  const blob = gitBlob(path.join(root, 'gamemode.js'));
  // A profile no real character has: the agent's throwaway world starts
  // empty, and the number says it was a bot.
  const profileId = opts.profileId || 1900000000 + crypto.randomInt(0, 90000000);
  const name = 'Bot Pass ' + profileId;
  const server = new ServerRun(root, opts.spawn || spawnNode, path.join(root, 'bot-pass-server.log'));
  const result = () => ({ ok: lines.length > 0 && lines.every((l) => l.ok), lines, blob, profileId, tail: server.tail.slice() });
  const bots = [];
  try {
    if (!(port > 0)) { say('loads', false, 'server-settings.json names no port'); return result(); }
    if (settings.thornswoodRequirePass !== false) {
      say('loads', false, 'this server holds every login for a join pass (thornswoodRequirePass is not false), so it is not a bot pass copy');
      return result();
    }
    const addon = opts.addon || loadAddon(root);

    server.start();
    let why = await server.awaitLoad(blob, loadMs);
    if (!say('loads', why === '', why || 'gamemode.js, git blob ' + blob.slice(0, 12) + ', loaded')) { return result(); }

    const first = new Bot(addon, { port, password, name: 'bot', log });
    bots.push(first);
    try {
      await first.connect(stepMs);
      const me = await first.login(profileId, null, stepMs);
      say('login', me.isMe === true, 'profile ' + profileId + ' was sent its character, idx ' + me.idx);
    } catch (e) { say('login', false, e.message); return result(); }
    const me = first.character;
    const props = me.props || {};
    if (props.isRaceMenuOpen !== true) {
      say('new', false, 'the character was sent with the race menu ' + (props.isRaceMenuOpen === undefined ? 'not named' : 'closed') + ', so it was not made new');
      return result();
    }
    // The face waits for creation to start. The engine takes one face per
    // race menu (ActionListener::OnUpdateAppearance closes it on the first),
    // and the gamemode starts creation only once a new arrival has settled
    // (SETTLE_MS): it records the face the character stands in as the one
    // to tell the made face from, and moves the character on when a face
    // arrives while creation is open. A face sent before that is recorded
    // as the starting face, and the race menu never closes: the first real
    // pass, Deployment 7475814060, failed at face that way. What says
    // creation has started is the plain clothes (giveShift runs once the
    // stage is saved), the first thing but gold in the character's pack.
    const clothed = (m) => m.t === MSG.SetInventory && m.inventory && Array.isArray(m.inventory.entries) &&
      m.inventory.entries.some((e) => e && Number(e.baseId) !== GOLD);
    const closed = (m) => m.t === MSG.SetRaceMenuOpen && m.open === false;
    let started = null;
    try {
      started = await first.until(() => {
        for (const x of first.inbox) {
          if (!x.message) { continue; }
          if (clothed(x.message)) { return 'clothes'; }
          if (closed(x.message)) { return 'closed'; }
        }
        return null;
      }, stepMs, 'creation starting (the plain clothes) for the new character');
    } catch (e) { say('new', false, e.message); return result(); }
    if (!say('new', started === 'clothes', started === 'clothes'
      ? 'a new character: the race menu is open and creation started with the plain clothes'
      : 'the race menu closed before creation started, so the gamemode took the character for a returning one')) {
      return result();
    }

    const sentAt = first.inbox.length;
    first.send({ t: 4, idx: me.idx, data: face(name) }, true);
    try {
      await first.until(() => first.inbox.slice(sentAt).some((x) => x.message && closed(x.message)), stepMs, 'the race menu closing after the face was sent');
      say('face', true, 'the face was taken and the race menu closed');
    } catch (e) { say('face', false, e.message); return result(); }

    let form = null;
    const end = Date.now() + stepMs;
    while (Date.now() < end) {
      form = formOf(root, settings, profileId);
      if (form && nameIn(form) === name) { break; }
      await new Promise((r) => setTimeout(r, 200));
    }
    if (!say('saved', !!form && nameIn(form) === name, form
      ? (nameIn(form) === name ? 'the world holds ' + name : 'the world holds the character as "' + nameIn(form) + '", not ' + name)
      : 'the world holds no character for profile ' + profileId + ' after ' + Math.round(stepMs / 1000) + ' s')) {
      return result();
    }
    first.close();

    if (!await server.stop(stepMs)) { say('restart', false, 'the server did not end within ' + Math.round(stepMs / 1000) + ' s of being stopped'); return result(); }
    // What it was saved as, read once it has ended and written its last.
    form = formOf(root, settings, profileId) || form;
    server.start();
    why = await server.awaitLoad(blob, loadMs);
    if (!say('restart', why === '', why || 'stopped, started again, and the gamemode loaded again')) { return result(); }

    const second = new Bot(addon, { port, password, name: 'bot again', log });
    bots.push(second);
    try {
      await second.connect(stepMs);
      const again = await second.login(profileId, null, stepMs);
      const p = again.props || {};
      const got = again.appearance || p.appearance;
      const pos = (again.transform || {}).pos || [];
      const want = form.position || [];
      const near = want.length === 3 && pos.length === 3 && want.every((x, i) => Math.abs(Number(x) - Number(pos[i])) <= 1);
      const wrong = [];
      if (!got || got.name !== name) { wrong.push('its name is ' + JSON.stringify(got ? got.name : undefined) + ', not ' + name); }
      if (!near) { wrong.push('it stands at ' + JSON.stringify(pos) + ', and the world saved ' + JSON.stringify(want)); }
      if (p.isRaceMenuOpen === true) { wrong.push('the race menu is open again'); }
      say('loads back', wrong.length === 0, wrong.length ? wrong.join('; ') : name + ' came back where it was saved, with no race menu');
    } catch (e) { say('loads back', false, e.message); }
    return result();
  } catch (e) {
    say('pass', false, 'the pass itself failed: ' + (e && e.stack || e));
    return result();
  } finally {
    for (const b of bots) { try { b.close(); } catch (e) { /* closing a closed bot */ } }
    await server.stop(stepMs);
  }
}

function args(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const m = /^--([a-z]+)$/.exec(argv[i]);
    if (!m || i + 1 >= argv.length) { throw new Error('what is "' + argv[i] + '"? Use --root, --out and --id.'); }
    o[m[1]] = argv[++i];
  }
  return o;
}

async function main() {
  const a = args(process.argv.slice(2));
  if (!a.root || !a.out) {
    console.log('node Bot-Pass.js --root <server folder> --out <result.json> [--id <run id>]');
    return 2;
  }
  const started = new Date().toISOString();
  const r = await pass({ root: a.root, log: (s) => console.log(s) });
  const doc = Object.assign({ schema: 1, id: a.id || '', started, ended: new Date().toISOString() }, r);
  // Whole or not at all: the agent reads this file once the task has ended.
  const tmp = a.out + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(doc, null, 2));
  fs.renameSync(tmp, a.out);
  console.log(r.ok ? 'BOT PASS OK' : 'BOT PASS FAILED');
  return r.ok ? 0 : 1;
}

if (require.main === module) {
  main().then((code) => process.exit(code), (e) => { console.log('BOT PASS FAILED: ' + (e && e.stack || e)); process.exit(1); });
}

module.exports = { pass, gitBlob, face, formOf, nameIn, ServerRun };
