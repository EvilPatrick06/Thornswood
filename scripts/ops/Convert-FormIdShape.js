'use strict';
/*
  Convert-FormIdShape.js

      node scripts\ops\Convert-FormIdShape.js --server <folder> --server-stopped

  Once per game server, with that server stopped, when the build with #2870 is
  first put on it. <folder> is the one its server-settings.json is in.

  WHAT IT IS FOR. Issue #2870. A deleted character's form id was kept two ways:
  the release list (private\deleted-characters.json) and the merchant ledger
  kept the local hex of a change form's formDesc ("a01" as 2561), while the
  embassy rolls, the dungeon chests and the ship manifests keep the runtime
  form id the server hands out (0xff000a01, 4278192641). So a part of the
  release list compared one number with the other and never matched. From
  #2870 every register keeps the runtime form id, 0xff000000 | the local hex
  (game\form-id.js), and a reader refuses the old shape: the gamemode will not
  load a version 1 merchant ledger, and the release list readers and writers
  stop on a list with an old shape actor. This turns the files a server
  already has into the one shape. There is no converter at server start.

  WHAT IT CHANGES, in the server's privDir:
    merchant-ledger.json   version 1 to version 2. A supply wait keyed
                           [formDesc, profile, item] becomes
                           [form id, profile, item]; a commission owner
                           [local, '', profile] becomes [form id, '', profile],
                           in the held and cooling keys and in each held
                           promise's owner. A placed form's owner
                           [local, plugin, profile] and an old supply wait
                           keyed by the item alone stay as they are. The
                           sha256 is worked out again.
    deleted-characters.json  each actor 1..0xffffff becomes its form id.
                           When one did, the parts that compare actors
                           (embassy, dungeon, cargo, merchants) lose their
                           done mark, so the next start runs them again with
                           the number they can match. The others keep theirs.
  It only reads embassy.json, dungeon-rewards-ledger.json and
  trade-cargo.json: those already keep the form id, and it stops if one does
  not.

  IT STOPS, and changes nothing, on: a file it cannot read or parse; a
  merchant ledger whose sha256 does not match, or of a version it does not
  know; a pending trade in the merchant ledger (start the old build once and
  let it settle, then stop it and run this again); a record it cannot place
  in either shape; two records that would become one (a collision).

  BEFORE ANY WRITE it copies each file it is about to change into
  <privDir>\backup-2870-<UTC time>\ with a SHA256SUMS list, reads the copies
  back against the list, and checks the files have not changed since they
  were read. Each file is then written whole (a .tmp beside it, flushed to
  disk, renamed over it) and read back. The merchant ledger goes first and
  the release list last, so a run cut short is finished by running it again.

  RUN IT AGAIN and it changes nothing and takes no backup: a version 2 ledger
  and a list of form ids are already done.

  WITH IT, scripts\ops\Verify-FormIdShape.js reads the same files and counts
  each register by shape. Run it before (to a file) and after (with
  --before that file): it fails on a record lost or an old shape left.

  Prints one JSON report. Exit 0 done (or nothing to do), 2 stopped.
*/
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// One shape for a character's form id (#2870); game\form-id.js is the
// original and tests\test-2870-form-id-shape.js keeps this copy the same.
function formIdOf(desc) {
  if (typeof desc !== 'string' || !/^[0-9a-f]{1,6}$/i.test(desc)) return 0;
  var local = parseInt(desc, 16);
  return local > 0 ? 0xff000000 + local : 0;
}
function isFormId(n) {
  return Number.isSafeInteger(n) && n > 0xff000000 && n <= 0xffffffff;
}

const LOCAL = (n) => Number.isSafeInteger(n) && n > 0 && n <= 0xffffff;
const RERUN = ['embassy', 'dungeon', 'cargo', 'merchants'];
const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const ledgerSum = (version, entries) => sha(JSON.stringify([version, entries]));

class Stop extends Error {}
function stop(why) { throw new Stop(why); }

function parseJson(bytes, name) {
  try { return JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, '')); }
  catch (e) { return stop(name + ' cannot be parsed (' + e.message + ')'); }
}
function readFile(file) {
  try { return fs.readFileSync(file); }
  catch (e) {
    if (e && e.code === 'ENOENT') return null;
    return stop(path.basename(file) + ' cannot be read (' + ((e && e.code) || e) + ')');
  }
}
function parseArray(text, length) {
  if (typeof text !== 'string' || text[0] !== '[') return null;
  try {
    const row = JSON.parse(text);
    return Array.isArray(row) && row.length === length ? row : null;
  } catch (e) { return null; }
}

function folders(server) {
  const settingsFile = path.join(server, 'server-settings.json');
  const bytes = readFile(settingsFile);
  if (bytes === null) stop(settingsFile + ' is not there');
  const settings = parseJson(bytes, 'server-settings.json');
  if (!isObj(settings)) stop('server-settings.json is not a settings object');
  return path.resolve(server, settings.privDir ? String(settings.privDir) : 'private');
}

/* The release list: each old shape actor becomes its form id. */
function planList(doc) {
  if (!isObj(doc) || !Array.isArray(doc.profiles) || (doc.actors !== undefined && !Array.isArray(doc.actors)) ||
      (doc.done !== undefined && !isObj(doc.done))) stop('deleted-characters.json is not a release list');
  const actors = doc.actors || [];
  const seen = new Set();
  let changed = 0;
  const next = actors.map((n, i) => {
    let id;
    if (isFormId(n)) id = n;
    else if (LOCAL(n)) { id = 0xff000000 + n; changed++; }
    else stop('deleted-characters.json actor ' + i + ' (' + JSON.stringify(n) + ') is neither a form id nor an old shape local id');
    if (seen.has(id)) stop('deleted-characters.json names form id ' + id + ' twice once converted (a collision)');
    seen.add(id);
    return id;
  });
  if (!changed) return { changes: 0, cleared: [] };
  const out = {};
  const cleared = [];
  for (const k of Object.keys(doc)) {
    if (k === 'actors') out.actors = next;
    else if (k === 'done') {
      out.done = {};
      for (const part of Object.keys(doc.done)) {
        if (RERUN.includes(part)) cleared.push(part);
        else out.done[part] = doc.done[part];
      }
    } else out[k] = doc[k];
  }
  return { changes: changed, cleared, next: out };
}

/* One commission key, [owner, job], in the new shape; null when it stays. */
function convertKey(name, where) {
  const parts = parseArray(name, 2);
  if (!parts || typeof parts[0] !== 'string' || typeof parts[1] !== 'string') stop(where + ' has a key that cannot be read: ' + name);
  const owner = parseArray(parts[0], 3);
  if (!owner || typeof owner[1] !== 'string' || !Number.isSafeInteger(owner[2]) || owner[2] < 1)
    stop(where + ' has an owner that cannot be read: ' + parts[0]);
  if (owner[1]) {
    if (!LOCAL(owner[0])) stop(where + ' has a placed form owner that cannot be read: ' + parts[0]);
    return { owner: parts[0], name, placed: true };
  }
  if (!LOCAL(owner[0])) stop(where + ' has an owner in neither shape: ' + parts[0]);
  const next = JSON.stringify([0xff000000 + owner[0], '', owner[2]]);
  return { from: parts[0], owner: next, name: JSON.stringify([next, parts[1]]) };
}

/* The merchant ledger, version 1 to 2. */
function planLedger(doc) {
  if (!isObj(doc) || !isObj(doc.entries) || typeof doc.sha256 !== 'string') stop('merchant-ledger.json is not a merchant ledger');
  if (doc.version === 2) return { changes: 0, version: 2 };
  if (doc.version !== 1) stop('merchant-ledger.json is version ' + JSON.stringify(doc.version) + ', which this does not know');
  if (doc.sha256 !== ledgerSum(doc.version, doc.entries)) stop('merchant-ledger.json does not match its sha256');
  const entries = JSON.parse(JSON.stringify(doc.entries));
  const c = { supplyKeys: 0, itemOnlySupply: 0, ownerKeys: 0, heldOwners: 0, placedOwners: 0 };
  for (const ref of Object.keys(entries)) {
    const state = entries[ref];
    if (state === null) continue;
    if (!isObj(state)) stop('merchant-ledger.json entry ' + ref + ' cannot be read');
    if (state.pending !== undefined && state.pending !== null)
      stop('merchant-ledger.json has a pending trade at ' + ref + '; start the old build once to settle it, stop it, and run this again');
    if (state.supply !== undefined) {
      if (!isObj(state.supply)) stop('merchant-ledger.json entry ' + ref + ' has supply that cannot be read');
      const next = {};
      for (const key of Object.keys(state.supply)) {
        let to = key;
        if (key[0] === '[') {
          const row = parseArray(key, 3);
          if (!row || typeof row[0] !== 'string' || !Number.isSafeInteger(row[1]) || row[1] < 1 || typeof row[2] !== 'string')
            stop('merchant-ledger.json entry ' + ref + ' has a supply wait that cannot be read: ' + key);
          const id = formIdOf(row[0]);
          if (!id) stop('merchant-ledger.json entry ' + ref + ' has a supply wait not keyed by a runtime character: ' + key);
          to = JSON.stringify([id, row[1], row[2]]);
          c.supplyKeys++;
        } else c.itemOnlySupply++;
        if (has(next, to)) stop('merchant-ledger.json entry ' + ref + ' has two supply waits that become ' + to + ' (a collision)');
        next[to] = state.supply[key];
      }
      state.supply = next;
    }
    if (state.commissions !== undefined) {
      const k = state.commissions;
      if (!isObj(k) || !isObj(k.held) || !isObj(k.cool)) stop('merchant-ledger.json entry ' + ref + ' has commissions that cannot be read');
      const held = {}, cool = {};
      for (const name of Object.keys(k.held)) {
        const row = k.held[name];
        const to = convertKey(name, 'merchant-ledger.json entry ' + ref);
        if (!isObj(row) || row.owner !== (to.from || to.owner))
          stop('merchant-ledger.json entry ' + ref + ' has a promise whose owner is not its key\'s: ' + name);
        if (has(held, to.name)) stop('merchant-ledger.json entry ' + ref + ' has two promises that become ' + to.name + ' (a collision)');
        if (to.placed) c.placedOwners++;
        else { row.owner = to.owner; c.ownerKeys++; c.heldOwners++; }
        held[to.name] = row;
      }
      for (const name of Object.keys(k.cool)) {
        const to = convertKey(name, 'merchant-ledger.json entry ' + ref);
        if (has(cool, to.name) || has(held, to.name))
          stop('merchant-ledger.json entry ' + ref + ' has two commission records that become ' + to.name + ' (a collision)');
        if (to.placed) c.placedOwners++;
        else c.ownerKeys++;
        cool[to.name] = k.cool[name];
      }
      k.held = held;
      k.cool = cool;
    }
  }
  const next = { version: 2, entries, sha256: ledgerSum(2, entries) };
  // A version change is a change even with nothing in the old shape.
  return Object.assign({ changes: 1 + c.supplyKeys + c.ownerKeys + c.heldOwners, version: 1, next }, c);
}

/* The registers that already keep form ids, read only. */
function checkKept(priv) {
  const out = {};
  const embassy = readFile(path.join(priv, 'embassy.json'));
  if (embassy !== null) {
    const doc = parseJson(embassy, 'embassy.json');
    if (!isObj(doc)) stop('embassy.json is not the embassy rolls');
    let n = 0;
    for (const roll of ['embassy', 'remnant']) {
      if (doc[roll] === undefined) continue;
      if (!Array.isArray(doc[roll])) stop('embassy.json ' + roll + ' is not a roll');
      doc[roll].forEach((r, i) => {
        if (!isObj(r) || !isFormId(r.actor)) stop('embassy.json ' + roll + ' row ' + i + ' does not name a form id');
        n++;
      });
    }
    out.embassy = n;
  }
  const dungeon = readFile(path.join(priv, 'dungeon-rewards-ledger.json'));
  if (dungeon !== null) {
    const doc = parseJson(dungeon, 'dungeon-rewards-ledger.json');
    if (!isObj(doc) || !isObj(doc.entries)) stop('dungeon-rewards-ledger.json is not a ledger');
    let n = 0;
    for (const k of Object.keys(doc.entries)) {
      const e = doc.entries[k];
      if (!isObj(e) || e.kind === 'body' || e.actor === undefined) continue;
      if (e.actor !== 0 && !isFormId(e.actor)) stop('dungeon-rewards-ledger.json ' + k + ' does not name a form id');
      n++;
    }
    out.dungeon = n;
  }
  const cargo = readFile(path.join(priv, 'trade-cargo.json'));
  if (cargo !== null) {
    const doc = parseJson(cargo, 'trade-cargo.json');
    if (!isObj(doc) || !isObj(doc.cargo) || !isObj(doc.cargo.holds)) stop('trade-cargo.json is not a ship register');
    let n = 0;
    const party = (p, where) => {
      if (p === null || p === undefined) return;
      if (!isObj(p) || !isFormId(p.actor)) stop('trade-cargo.json ' + where + ' does not name a form id');
      n++;
    };
    for (const id of Object.keys(doc.cargo.holds)) {
      const h = doc.cargo.holds[id];
      if (!isObj(h) || !isObj(h.lines) || !Array.isArray(h.outs)) stop('trade-cargo.json hold ' + id + ' cannot be read');
      for (const k of Object.keys(h.lines)) {
        party(h.lines[k] && h.lines[k].by, 'hold ' + id + ' line ' + k + ' loader');
        party(h.lines[k] && h.lines[k].for, 'hold ' + id + ' line ' + k + ' recipient');
      }
      h.outs.forEach((o, i) => party(o && o.who, 'hold ' + id + ' out ' + i));
    }
    out.cargo = n;
  }
  return out;
}

function stamp(now) {
  return new Date(now).toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
}
function writeWhole(file, text) {
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, text);
  const fd = fs.openSync(tmp, 'r+');
  try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, file);
  if (fs.readFileSync(file, 'utf8') !== text) stop(path.basename(file) + ' did not read back as written; the backup holds what it was');
}
// A JSON file back the shape it came in: indented if it was, its last line ending kept.
function textLike(was, value) {
  const indent = /^\uFEFF?[\[{]\s*\r?\n/.test(was) ? 2 : undefined;
  return JSON.stringify(value, null, indent) + (/\n$/.test(was) ? '\n' : '');
}

function convert(server, options) {
  const now = options && options.now !== undefined ? options.now : Date.now();
  const priv = folders(server);
  const report = { server: path.resolve(server), privDir: priv, kept: {}, merchants: null, list: null, backup: null, written: [] };
  const files = { ledger: path.join(priv, 'merchant-ledger.json'), list: path.join(priv, 'deleted-characters.json') };
  const bytes = { ledger: readFile(files.ledger), list: readFile(files.list) };
  const plans = {};
  if (bytes.ledger !== null) {
    plans.ledger = planLedger(parseJson(bytes.ledger, 'merchant-ledger.json'));
    report.merchants = Object.assign({}, plans.ledger);
    delete report.merchants.next;
  }
  if (bytes.list !== null) {
    plans.list = planList(parseJson(bytes.list, 'deleted-characters.json'));
    report.list = { changes: plans.list.changes, cleared: plans.list.cleared };
  }
  report.kept = checkKept(priv);
  const order = ['ledger', 'list'].filter((k) => plans[k] && plans[k].changes);
  report.changes = order.reduce((sum, k) => sum + plans[k].changes, 0);
  if (!order.length) return report;

  // The backup, read back against its sums before anything is written.
  const dir = path.join(priv, 'backup-2870-' + stamp(now));
  if (fs.existsSync(dir)) stop(dir + ' is there already; nothing was changed');
  fs.mkdirSync(dir);
  const sums = order.map((k) => sha(bytes[k]) + '  ' + path.basename(files[k]));
  for (const k of order) fs.copyFileSync(files[k], path.join(dir, path.basename(files[k])));
  fs.writeFileSync(path.join(dir, 'SHA256SUMS'), sums.join('\n') + '\n');
  for (const k of order) {
    const name = path.basename(files[k]);
    if (sha(fs.readFileSync(path.join(dir, name))) !== sha(bytes[k])) stop('the backup of ' + name + ' does not match; nothing was changed');
    const now2 = readFile(files[k]);
    if (now2 === null || sha(now2) !== sha(bytes[k])) stop(name + ' changed while this ran; is the server stopped? Nothing was changed');
  }
  report.backup = dir;
  for (const k of order) {
    const text = k === 'ledger' ? JSON.stringify(plans.ledger.next) : textLike(bytes.list.toString('utf8'), plans.list.next);
    writeWhole(files[k], text);
    report.written.push(path.basename(files[k]));
  }
  return report;
}

module.exports = { formIdOf, isFormId, convert, planLedger, planList, Stop };

if (require.main === module) {
  const args = process.argv.slice(2);
  const at = args.indexOf('--server');
  const server = at >= 0 ? args[at + 1] : '';
  if (!server || !args.includes('--server-stopped') || args.length !== 3) {
    console.error('Usage: node scripts\\ops\\Convert-FormIdShape.js --server <folder> --server-stopped');
    console.error('Stop that game server first; --server-stopped says it is.');
    process.exit(2);
  }
  try {
    const report = convert(server);
    report.result = report.changes ? 'converted' : 'nothing to change';
    console.log(JSON.stringify(report, null, 2));
  } catch (e) {
    if (!(e instanceof Stop)) throw e;
    console.log(JSON.stringify({ server: path.resolve(server), result: 'stopped', why: e.message }, null, 2));
    process.exit(2);
  }
}
