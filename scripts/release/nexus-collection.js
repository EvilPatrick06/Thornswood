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
module.exports = { payloadOf, applySwaps, filterInfo, toV3CollectionPayload };
