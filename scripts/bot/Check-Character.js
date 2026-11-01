#!/usr/bin/env node
// scripts/bot/Check-Character.js
//
// #5196. The restore rehearsal's in-game step (#1046, #5020), done by a bot:
// on a running server made by Restore-Server.ps1 -Rehearse, log in as one
// character and check the server sends back the character the backup holds.
//
//     node scripts/bot/Check-Character.js --root <server folder> --profile <id>
//          [--host 127.0.0.1] [--port <game port>] [--out <result.json>]
//
// --root is the rehearsal's folder: its scam_native.node is the bot's
// connection, its server-settings.json gives the port and password, and its
// world is what the character is checked against, read before the bot logs
// in (the server writes the form again once the character is loaded).
// The rehearsal server has no door.json and no join pass hold, so the bot
// logs in with the profile id alone, as the gamemode's watching login allows.
//
// Prints a PASS, FAIL or SKIP line for each thing it compares and exits 1
// when any FAIL, or when the bot could not connect or was sent no
// character. --out writes the same as JSON for the run's record.
'use strict';
const fs = require('fs');
const path = require('path');
const { Bot, loadAddon } = require('./bot.js');
const { expected, compare } = require('./character.js');

function args(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const m = /^--([a-z]+)$/.exec(argv[i]);
    if (!m) { throw new Error('what is "' + argv[i] + '"? Use --root, --profile, --host, --port and --out.'); }
    o[m[1]] = argv[++i];
  }
  return o;
}

async function main() {
  const a = args(process.argv.slice(2));
  if (!a.root || !a.profile) {
    console.log('node scripts/bot/Check-Character.js --root <server folder> --profile <id> [--host 127.0.0.1] [--port <port>] [--out <file>]');
    return 1;
  }
  const root = path.resolve(a.root);
  const result = { at: new Date().toISOString(), root, profile: Number(a.profile), lines: [], error: '' };
  let fails = 0;
  let bot = null;
  try {
    const want = expected(root, a.profile);
    console.log('character ' + want.profileId + ' is ' + want.file + ' in the world, read before the login');
    const addon = loadAddon(root);
    const port = Number(a.port) || want.port;
    bot = new Bot(addon, { host: a.host || '127.0.0.1', port, password: want.password,
                           name: 'bot', log: (m) => console.log('  ' + m) });
    await bot.connect(15000);
    const got = await bot.login(want.profileId, null, 30000);
    for (const l of compare(want, got)) {
      result.lines.push(l);
      const tag = l.ok === null ? 'SKIP' : l.ok ? 'PASS' : 'FAIL';
      if (l.ok === false) { fails++; }
      console.log(tag + '  ' + l.what + (l.ok === null ? '' : '  (backup ' + l.want + ', server ' + l.got + ')'));
    }
  } catch (e) {
    fails++;
    result.error = e.message;
    console.log('FAIL  ' + e.message);
  } finally {
    if (bot) { bot.close(); }
  }
  result.ok = fails === 0;
  if (a.out) { fs.writeFileSync(a.out, JSON.stringify(result, null, 2)); }
  console.log('');
  console.log(fails ? 'CHARACTER CHECK FAILED: ' + fails + ' failed' : 'CHARACTER CHECK OK: the server sent character ' + a.profile + ' as the backup holds it');
  return fails ? 1 : 0;
}

main().then((code) => process.exit(code), (e) => { console.log('FAIL  ' + (e && e.stack || e)); process.exit(1); });
