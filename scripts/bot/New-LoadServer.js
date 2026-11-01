#!/usr/bin/env node
// scripts/bot/New-LoadServer.js
//
// #4623. Lays out the load test's server on GitHub's runner, from three
// things and nothing else:
//   the engine   the server build records\server-build.json names, as the
//                signed build-<date>.<run> Release carries it for the deploy
//                agent (the server-<commit>-<hash>.zip, unpacked, as the
//                workflow downloads it), every file the record names held to
//                its sha256, so the server measured is the one dev runs. The
//                fork's own artifact of the commit is not used: after the
//                history rewrite the fork built that commit again (run
//                41340857541), and a rebuild is never the same bytes
//                (engine\README.md), so its scam_native.node is not the one
//                the record holds;
//   the game     game\gamemode.js and game\content\Thornswood-Content.esp
//                from this checkout;
//   the masters  Skyrim.esm, Update.esm, Dawnguard.esm, HearthFires.esm and
//                Dragonborn.esm, downloaded from the copy the fork's own
//                build downloads (cmake\download_skyrim_data.cmake in the
//                fork) and held to the same sha256 (THIRD-PARTY.md). They
//                stay on the runner and go with it.
// The collection's plugins are not here: they are other people's, and only
// Thornswood-Content.esp of ours needs nothing but the five masters. So the
// world is the vanilla one with Thornswood's content on it.
//
// The settings are a load copy's: offline, seats for every bot, the dev
// server's name for itself, the join pass held as on main, and where new
// characters are put. The gamemode ends every session that has no valid join
// pass three minutes in, whatever thornswoodRequirePass says (#937; measured
// on run 41353332627, where every bot was ended at 180 s), so the load copy
// has a pass key of its own: 32 random bytes made here, in private\door.json,
// that no site or real server has. load-bots.js signs each bot's pass with
// it, as the site signs a person's, and answers the login challenge with it.
// Where new characters are put:
//   crowd   everybody at one spot outside Whiterun (the engine's own start
//           point), so everybody is near everybody: the most the server
//           sends;
//   spread  36 spots on a grid over Tamriel, 60,000 units apart, so a bot
//           has few or nobody near it.
// Creation is off (thornswoodChargen false): a person's time on the server
// is in the world, and the load copy has no hall to stand in, which is in
// the collection.
//
//     node New-LoadServer.js --build <unpacked server zip> --masters <folder>
//         --out <server folder> [--shape crowd|spread] [--seats 100]
//         [--download yes]
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const SE_DATA = 'https://gitlab.com/pospelov/se-data/-/raw/main/';
const MASTERS = {
  'Skyrim.esm': '9ec6b3818bbd002487bdc4104add07f814cc067e70c79ea2d164108a6c960f04',
  'Update.esm': '8502f3975a84fc4fd62c9781e867df5bb661972887c93f017db0857b20dc90f2',
  'Dawnguard.esm': '501bbcf0c61c8f28396a13a2ca877f904803ef9c0002b329edde7fb741119023',
  'HearthFires.esm': '30d319a8e439dbd1c5dec03860a60aaec9142642f2c9168419b424c897f592d1',
  'Dragonborn.esm': '4f2fe839956db8807e07b1a0feb805130487899ce337e60ad43f15ed9f8cb988'
};
// The engine's own start point (skymp5-server/ts/settings.ts): outside
// Whiterun, in Tamriel.
const WHITERUN = { pos: [133857, -61130, 14662], worldOrCell: '0x3c', angleZ: 72 };

function sha256(file) {
  const h = crypto.createHash('sha256');
  const fd = fs.openSync(file, 'r');
  const buf = Buffer.alloc(1 << 20);
  try {
    for (;;) { const n = fs.readSync(fd, buf, 0, buf.length, null); if (!n) { break; } h.update(buf.subarray(0, n)); }
  } finally { fs.closeSync(fd); }
  return h.digest('hex');
}

function readJson(file) {
  return JSON.parse(String(fs.readFileSync(file, 'utf8')).replace(/^﻿/, ''));
}

// One https GET into file, following redirects.
function download(url, file, hops) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && (hops || 0) < 5) {
        res.resume();
        resolve(download(new URL(res.headers.location, url).toString(), file, (hops || 0) + 1));
        return;
      }
      if (res.statusCode !== 200) { res.resume(); reject(new Error(url + ' answered HTTP ' + res.statusCode)); return; }
      const out = fs.createWriteStream(file);
      res.pipe(out);
      out.on('finish', () => out.close(() => resolve()));
      out.on('error', reject);
      res.on('error', reject);
    }).on('error', reject);
  });
}

// Throws unless file is the master the fork's build holds name to.
function checkMaster(file, name) {
  if (!MASTERS[name]) { throw new Error(name + ' is not one of the five masters'); }
  if (!fs.existsSync(file)) { throw new Error('there is no ' + file + ' (pass --download yes to fetch the five masters)'); }
  const got = sha256(file);
  if (got !== MASTERS[name]) { throw new Error(name + ' is sha256 ' + got + ', not the ' + MASTERS[name] + ' the fork\'s build holds it to. Nothing was started.'); }
}

function startPoints(shape) {
  if (shape === 'crowd') { return [WHITERUN]; }
  const pts = [];
  for (let i = 0; i < 6; i++) {
    for (let j = 0; j < 6; j++) {
      pts.push({ pos: [-150000 + i * 60000, -150000 + j * 60000, 0], worldOrCell: '0x3c', angleZ: 0 });
    }
  }
  return pts;
}

function copyTree(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const e of fs.readdirSync(from, { withFileTypes: true })) {
    const a = path.join(from, e.name); const b = path.join(to, e.name);
    if (e.isDirectory()) { copyTree(a, b); } else { fs.copyFileSync(a, b); }
  }
}

async function build(o) {
  const shape = o.shape || 'crowd';
  if (!['crowd', 'spread'].includes(shape)) { throw new Error('--shape is crowd or spread, not ' + shape); }
  const seats = Number(o.seats) || 100;
  const record = readJson(path.join(REPO, 'records', 'server-build.json'));
  const commit = String(record.source && record.source.commit || '');
  const dist = path.resolve(o.build);
  const theirs = readJson(path.join(dist, 'server-build.json'));
  if (String(theirs.sha256) !== String(record.sha256)) { throw new Error('the build in ' + dist + ' records scam_native.node as sha256 ' + theirs.sha256 + ', and records\\server-build.json holds ' + record.sha256); }
  const out = path.resolve(o.out);
  if (fs.existsSync(out)) { throw new Error(out + ' is there already'); }
  copyTree(dist, out);
  for (const rel of Object.keys(record.files || {})) {
    const f = path.join(out, rel);
    if (!fs.existsSync(f)) { throw new Error('the build has no ' + rel + ', which records\\server-build.json names'); }
    const got = sha256(f);
    if (got !== record.files[rel].sha256) { throw new Error(rel + ' in the build is sha256 ' + got + ', not the ' + record.files[rel].sha256 + ' records\\server-build.json holds'); }
  }
  fs.copyFileSync(path.join(REPO, 'records', 'server-build.json'), path.join(out, 'server-build.json'));
  fs.copyFileSync(path.join(REPO, 'game', 'gamemode.js'), path.join(out, 'gamemode.js'));

  const masters = path.resolve(o.masters);
  fs.mkdirSync(masters, { recursive: true });
  const order = [];
  for (const name of Object.keys(MASTERS)) {
    const f = path.join(masters, name);
    if (!fs.existsSync(f) && o.download === 'yes') {
      console.log('downloading ' + name + ' from ' + SE_DATA);
      await download(SE_DATA + name, f + '.part');
      fs.renameSync(f + '.part', f);
    }
    checkMaster(f, name);
    order.push(f.replace(/\\/g, '/'));
  }
  const content = path.join(masters, 'Thornswood-Content.esp');
  fs.copyFileSync(path.join(REPO, 'game', 'content', 'Thornswood-Content.esp'), content);
  order.push(content.replace(/\\/g, '/'));

  const settings = {
    dataDir: 'data',
    loadOrder: order,
    master: '',
    name: 'Thornswood load test',
    offlineMode: true,
    port: Number(o.port) || 7777,
    maxPlayers: seats,
    npcEnabled: false,
    npcSettings: {},
    startPoints: startPoints(shape),
    thornswoodServer: 'dev',
    thornswoodRequirePass: true,
    thornswoodChargen: false
  };
  fs.writeFileSync(path.join(out, 'server-settings.json'), JSON.stringify(settings, null, 2) + '\n');
  fs.mkdirSync(path.join(out, 'private'), { recursive: true });
  fs.writeFileSync(path.join(out, 'private', 'door.json'), JSON.stringify({ passKey: crypto.randomBytes(32).toString('hex') }) + '\n');
  console.log('the load server is in ' + out + ': fork ' + commit + ', ' + shape + ', ' + seats + ' seats, ' + order.length + ' plugins');
  return { out, commit, settings };
}

async function main() {
  const o = {};
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 2) { o[String(argv[i]).replace(/^--/, '')] = argv[i + 1]; }
  if (!o.build || !o.masters || !o.out) {
    console.log('node New-LoadServer.js --build <unpacked server zip> --masters <folder> --out <server folder> [--shape crowd|spread] [--seats 100] [--download yes]');
    return 2;
  }
  await build(o);
  return 0;
}

if (require.main === module) {
  main().then((c) => process.exit(c), (e) => { console.log('NEW LOAD SERVER FAILED: ' + (e && e.message || e)); process.exit(1); });
}

module.exports = { build, startPoints, checkMaster, MASTERS, WHITERUN };
