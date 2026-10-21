// nexus-collection.js
//
// The collection.json half of a new collection revision (#2914), run by
// New-NexusRevision.ps1:
//
//   node scripts/release/nexus-collection.js <collection.json> <swaps.json> <out collection.json> <out payload.json>
//
// It reads the collection.json of the revision that is published now, as
// Vortex wrote it, changes the entries swaps.json names to their new Nexus
// file and nothing else, writes the new collection.json the way Vortex
// writes it, and writes the collection_data the v3 API takes with it.
//
// WHY IN NODE. Vortex writes collection.json with JSON.stringify(info,
// undefined, 2) (collectionExport.ts, writeCollectionToFile). Read on 20 October:
// revision 2's collection.json, 1,069,730 bytes, comes back byte for byte from
// JSON.parse and that same JSON.stringify. PowerShell's ConvertTo-Json writes
// a different layout and, in Windows PowerShell 5.1, escapes characters
// differently, so the file is read and written here.
//
// THE PAYLOAD is Vortex's own mapping, ported line for line from
// Nexus-Mods/Vortex src/renderer/src/extensions/nexus_integration/util_v3/
// manifestMapping.ts (toV3CollectionPayload, read at 2e29b16d on 20 October)
// after collectionExport.ts's filterInfo, which is what submitCollectionV3.ts
// sends to POST /collections/{id}/revisions. One thing in it reads oddly and
// is kept as Vortex has it: filterInfo drops each source's fileSize before the
// mapping reads it, so every file_size goes as null. The size is still in
// collection.json inside the archive, where Vortex reads it on install.
//
// WHAT IT REFUSES. A swap changes an entry's file, version, md5, size and
// file name. That is the whole of what Vortex records for a mod only when the
// entry carries nothing worked out from the archive's contents. So it refuses
// an entry that has hashes (the files Vortex checks after install), choices
// (an installer's answers), patches (binary patches made against the old
// archive's files, which would not apply to the new one) or fileOverrides,
// and an entry any mod rule names, because those rules name the old archive
// by its md5. Those need Vortex on One, where the collection is built from
// what is installed (docs\COLLECTION-REVISION-2.md). Every refusal exits 1
// with the reason on stderr and writes nothing.
//
// swaps.json: [{ "modId": "192762", "fileId": "812345", "version": "1.0.1",
//                "md5": "<32 hex>", "fileSize": 148896610,
//                "logicalFilename": "Thornswood Client Runtime" }]
// On stdout, one line per field changed: <entry name>\t<field>\t<was>\t<now>.
//
// ADDING A MOD (#2969). An entry with "add": true is a mod the revision does
// not carry yet, written the way Vortex writes a mod it installed with its
// basic installer (no installer answers, no file hashes, no patches):
//   { "add": true, "modId": "1932", "fileId": "8662", "version": "1.3",
//     "md5": "<32 hex>", "fileSize": 52221104,
//     "logicalFilename": "KS Hairdos Lite SE NoNPCs",
//     "name": "KS Hairdos Lite SE - KS Hairdos Lite SE NoNPCs",
//     "author": "...", "category": "Body, Face, and Hair",
//     "plugins": [{ "name": "KS_Hairdo's_Lite_NoNPCs.esp", "after": ["Playable Rieklings.esp"] }] }
// Each plugin goes on the end of the plugin list, switched on, and its
// "after" becomes a plugin rule, lower case as Vortex keeps them, so Vortex
// and LOOT put it where the list does. Every "after" has to be a plugin the
// list already has, or one added before it. It refuses a file the revision
// already carries and a plugin the list already names. The tag Vortex gives
// an installed mod is made the way shortid makes one, unless "tag" is given.
// On stdout: <entry name>\tadded\t\tfile <id>, and <plugin>\tplugin\t\tafter <names>.
//
// A PATCH (#2979). An entry with "patch": true gives the entry that installs
// Nexus file fileId a binary patch for one of its files, the way Vortex
// records one it made: the file's path in the mod and the CRC-32 of the
// archive's own copy, which Vortex checks before it applies
// patches\<entry name>\<path>.diff (New-NexusRevision.ps1 packs that file):
//   { "patch": true, "fileId": "743640", "path": "RaceMenu.esp", "crc": "1A2B3C4D" }
// It refuses a file the entry already patches. "patches" goes after the
// installer answers and file hashes, where Vortex writes it.
// On stdout: <entry name>\tpatch\t\t<path> CRC-32 <crc>.

'use strict';
const fs = require('fs');

function stop(msg) {
  process.stderr.write(msg + '\n');
  process.exit(1);
}

// ------------------------------------------- Vortex's mapping, as it is ---
function omit(obj, keys) {
  const res = {};
  for (const k of Object.keys(obj)) { if (keys.indexOf(k) < 0) res[k] = obj[k]; }
  return res;
}
function filterInfoModSource(source) { return omit(source, ['instructions', 'fileSize', 'tag']); }
function filterInfoMod(mod) {
  const res = omit(mod, ['hashes', 'choices', 'patches', 'details', 'instructions', 'phase', 'fileOverrides']);
  res.source = filterInfoModSource(res.source);
  return res;
}
function filterInfo(input) {
  return { info: omit(input.info, ['installInstructions']), mods: input.mods.map(filterInfoMod) };
}
function str(v) { return (v === undefined || v === null) ? undefined : v.toString(); }
function nn(v) { return (v === undefined || v === null) ? null : v; }
function toV3ManifestModSource(source) {
  return {
    type: source.type,
    mod_id: str(source.modId),
    file_id: str(source.fileId),
    md5: nn(source.md5),
    file_size: nn(source.fileSize),
    update_policy: source.updatePolicy,
    logical_filename: nn(source.logicalFilename),
    file_expression: nn(source.fileExpression),
    url: nn(source.url),
    adult_content: nn(source.adultContent),
  };
}
function toV3ManifestMod(mod) {
  return {
    name: mod.name,
    version: mod.version,
    optional: mod.optional,
    domain_name: mod.domainName,
    source: toV3ManifestModSource(mod.source),
    author: nn(mod.author),
  };
}
function toV3Manifest(manifest) {
  return {
    info: {
      author: manifest.info.author,
      author_url: manifest.info.authorUrl || null,
      name: manifest.info.name,
      description: manifest.info.description || null,
      summary: manifest.info.summary || null,
      domain_name: manifest.info.domainName,
      game_versions: nn(manifest.info.gameVersions),
    },
    mods: manifest.mods.map(toV3ManifestMod),
  };
}
function toV3CollectionPayload(manifest, adultContent) {
  return {
    adult_content: adultContent === undefined ? false : adultContent,
    collection_manifest: toV3Manifest(manifest),
    collection_schema_id: 1,
  };
}

// The collectionExport.ts step is filterInfo first, then the mapping; the
// mapping reads only what filterInfo leaves, so the order is kept.
function payloadOf(collection) { return toV3CollectionPayload(filterInfo(collection)); }

// --------------------------------------------------------------- swaps ---
function named(rule, entry) {
  const s = entry.source;
  for (const side of [rule.source, rule.reference]) {
    if (!side) continue;
    if (s.md5 && side.fileMD5 === s.md5) return true;
    if (s.logicalFilename && side.logicalFileName === s.logicalFilename) return true;
    if (s.tag && side.tag === s.tag) return true;
  }
  return false;
}

function applySwaps(collection, swaps) {
  const lines = [];
  if (!Array.isArray(collection.mods)) stop('collection.json has no mods list, so it is not a collection Vortex wrote.');
  for (const sw of swaps) {
    if (sw.add === true) { applyAdd(collection, sw, lines); continue; }
    if (sw.patch === true) { applyPatch(collection, sw, lines); continue; }
    for (const k of ['modId', 'fileId', 'version', 'md5', 'fileSize', 'logicalFilename']) {
      if (sw[k] === undefined || sw[k] === null || sw[k] === '') stop('A swap has no ' + k + '.');
    }
    if (!/^[0-9a-f]{32}$/.test(String(sw.md5))) stop('The md5 for mod ' + sw.modId + ' is not 32 lower case hex characters.');
    const hits = collection.mods.filter(m => m.source && m.source.type === 'nexus' && String(m.source.modId) === String(sw.modId));
    if (hits.length !== 1) stop('The revision has ' + hits.length + ' entries for Nexus mod ' + sw.modId + ', so there is no one entry to change.');
    const e = hits[0];
    const carried = ['hashes', 'choices', 'patches', 'fileOverrides'].filter(k => {
      const v = e[k];
      if (v === undefined || v === null) return false;
      if (Array.isArray(v)) return v.length > 0;
      if (typeof v === 'object') return Object.keys(v).length > 0;
      return true;
    });
    if (carried.length) {
      stop(e.name + ' carries ' + carried.join(' and ') + ' worked out from the archive it has now, which would not fit the new one. A new file for it is a revision made in Vortex on One.');
    }
    const rules = (collection.modRules || []).filter(r => named(r, e));
    if (rules.length) {
      stop(rules.length + ' of the collection\'s mod rules name ' + e.name + ' by the archive it has now, so they would not find the new one. A new file for it is a revision made in Vortex on One.');
    }
    if (String(e.source.fileId) === String(sw.fileId)) stop(e.name + ' is already file ' + sw.fileId + ' in this revision.');
    const set = (obj, key, val, label) => {
      const was = obj[key];
      if (String(was) === String(val)) return;
      obj[key] = val;
      lines.push([e.name, label, String(was), String(val)].join('\t'));
    };
    set(e, 'version', String(sw.version), 'version');
    set(e.source, 'fileId', Number(sw.fileId), 'source.fileId');
    set(e.source, 'md5', String(sw.md5), 'source.md5');
    set(e.source, 'fileSize', Number(sw.fileSize), 'source.fileSize');
    set(e.source, 'logicalFilename', String(sw.logicalFilename), 'source.logicalFilename');
  }
  return lines;
}

// shortid's alphabet, which Vortex's reference tags are drawn from.
const TAG_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_-';
function newTag() {
  const bytes = require('crypto').randomBytes(10);
  let t = '';
  for (const b of bytes) t += TAG_CHARS[b % TAG_CHARS.length];
  return t;
}

function applyAdd(collection, add, lines) {
  for (const k of ['modId', 'fileId', 'version', 'md5', 'fileSize', 'logicalFilename', 'name', 'author', 'category']) {
    if (add[k] === undefined || add[k] === null || add[k] === '') stop('A mod to add has no ' + k + '.');
  }
  if (!/^\d+$/.test(String(add.modId)) || !/^\d+$/.test(String(add.fileId))) stop('A mod to add has a mod number or file id that is not a number.');
  if (!/^[0-9a-f]{32}$/.test(String(add.md5))) stop('The md5 for mod ' + add.modId + ' is not 32 lower case hex characters.');
  const plugins = Array.isArray(add.plugins) ? add.plugins : [];
  const same = collection.mods.find(m => m.source && m.source.type === 'nexus' && String(m.source.fileId) === String(add.fileId));
  if (same) stop(same.name + ' is already file ' + add.fileId + ' in this revision, so it is not added again.');
  if (!Array.isArray(collection.plugins)) collection.plugins = [];
  if (!collection.pluginRules || typeof collection.pluginRules !== 'object') collection.pluginRules = { plugins: [], groups: [] };
  if (!Array.isArray(collection.pluginRules.plugins)) collection.pluginRules.plugins = [];
  const known = new Set(collection.plugins.map(p => String(p.name).toLowerCase()));
  for (const m of ['skyrim.esm', 'update.esm', 'dawnguard.esm', 'hearthfires.esm', 'dragonborn.esm']) known.add(m);
  for (const p of plugins) {
    if (!p || !p.name || !/\.es[mpl]$/i.test(p.name)) stop('A plugin of ' + add.name + ' has no plugin name (.esm, .esp or .esl).');
    const low = String(p.name).toLowerCase();
    if (collection.plugins.some(q => String(q.name).toLowerCase() === low)) stop('The plugin list already names ' + p.name + ', so ' + add.name + ' would put a second one in Data.');
    const after = Array.isArray(p.after) ? p.after : [];
    if (!after.length) stop(p.name + ' says nothing to load after, so Vortex and LOOT would place it where they liked.');
    for (const a of after) if (!known.has(String(a).toLowerCase())) stop(p.name + ' is to load after ' + a + ', which the plugin list does not name.');
    known.add(low);
  }
  collection.mods.push({
    name: String(add.name),
    version: String(add.version),
    optional: false,
    domainName: (collection.info && collection.info.domainName) || 'skyrimspecialedition',
    source: {
      type: 'nexus',
      modId: Number(add.modId),
      fileId: Number(add.fileId),
      md5: String(add.md5),
      fileSize: Number(add.fileSize),
      logicalFilename: String(add.logicalFilename),
      updatePolicy: 'exact',
      tag: add.tag ? String(add.tag) : newTag(),
    },
    author: String(add.author),
    details: { category: String(add.category), type: '' },
    phase: 0,
  });
  lines.push([String(add.name), 'added', '', 'file ' + add.fileId].join('\t'));
  for (const p of plugins) {
    collection.plugins.push({ name: String(p.name), enabled: true });
    collection.pluginRules.plugins.push({ name: String(p.name).toLowerCase(), after: p.after.map(a => String(a).toLowerCase()) });
    lines.push([String(p.name), 'plugin', '', 'after ' + p.after.join(', ')].join('\t'));
  }
}

function applyPatch(collection, pt, lines) {
  for (const k of ['fileId', 'path', 'crc']) {
    if (pt[k] === undefined || pt[k] === null || pt[k] === '') stop('A patch has no ' + k + '.');
  }
  if (!/^[0-9A-F]{8}$/.test(String(pt.crc))) stop('The CRC-32 for ' + pt.path + ' is not 8 upper case hex characters.');
  const hits = collection.mods.filter(m => m.source && m.source.type === 'nexus' && String(m.source.fileId) === String(pt.fileId));
  if (hits.length !== 1) stop('The revision has ' + hits.length + ' entries for Nexus file ' + pt.fileId + ', so there is no one entry to patch.');
  const i = collection.mods.indexOf(hits[0]);
  const e = hits[0];
  const low = String(pt.path).toLowerCase();
  if (e.patches && Object.keys(e.patches).some(k => k.toLowerCase() === low)) stop(e.name + ' already patches ' + pt.path + '.');
  if (e.patches) { e.patches[String(pt.path)] = String(pt.crc); }
  else {
    const at = ['choices', 'hashes', 'source'].find(k => Object.prototype.hasOwnProperty.call(e, k));
    const next = {};
    for (const k of Object.keys(e)) {
      next[k] = e[k];
      if (k === at) next.patches = { [String(pt.path)]: String(pt.crc) };
    }
    collection.mods[i] = next;
  }
  lines.push([String(e.name), 'patch', '', String(pt.path) + ' CRC-32 ' + String(pt.crc)].join('\t'));
}

function main(argv) {
  if (argv.length !== 4) stop('usage: node nexus-collection.js <collection.json> <swaps.json> <out collection.json> <out payload.json>');
  const [inPath, swapsPath, outPath, payloadPath] = argv;
  let collection, swaps;
  try { collection = JSON.parse(fs.readFileSync(inPath, 'utf8')); }
  catch (e) { stop(inPath + ' is not JSON this can read: ' + e.message); }
  try { swaps = JSON.parse(fs.readFileSync(swapsPath, 'utf8').replace(/^﻿/, '')); }
  catch (e) { stop(swapsPath + ' is not JSON this can read: ' + e.message); }
  if (!Array.isArray(swaps)) swaps = [swaps];
  if (!swaps.length) stop('There are no swaps, so the revision would be the same as the one published.');
  const lines = applySwaps(collection, swaps);
  fs.writeFileSync(outPath, JSON.stringify(collection, undefined, 2));
  fs.writeFileSync(payloadPath, JSON.stringify(payloadOf(collection)));
  process.stdout.write(lines.join('\n') + (lines.length ? '\n' : ''));
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { payloadOf, applySwaps, applyAdd, applyPatch, filterInfo, toV3CollectionPayload };
