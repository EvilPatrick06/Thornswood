/*
  The downloads folder: the installer's payload and the files listed for
  download.
*/

'use strict';

// Its functions, given before it loads any other module, so a module that
// needs this one back finds them (a function is there from the top of its
// file).
module.exports = { downloadServed, listFiles, payloadZip };

const fs     = require('fs');
const path   = require('path');
const { FILES } = require('./base');
const { jsonFile } = require('./store');

// ------------------------------------------------------------- downloads --
// The payload zip the two file setup program fetches through /api/payload:
// the stable name Publish-Installer sends, or a stamped one an older publish
// left.
function payloadZip(name) {
  return /^Thornswood-Setup(?:-\d{8}-\d{4})?\.zip$/i.test(name);
}

// What /file/ serves, which is also all the Downloads list may show (#3798).
// files.json is the list of what is published, so a name is served only when
// it is listed there and not hidden, or is a listed payload zip, which is
// hidden from people because the setup program fetches it itself. files.json
// is served too: Ship's installer gate reads it at /file/files.json
// (Read-SiteDownloads). Anything else in the folder is not published, and
// answers 404. Until this the route served whatever sat in the folder, and a
// read only diagnostic put there by hand on the box (a script naming a
// staff member and the game server's address) went to anyone who asked for it
// by name, while the Downloads page only hid it.
function downloadServed(name, meta) {
  if (name === 'files.json') return true;
  const m = Object.prototype.hasOwnProperty.call(meta, name) ? meta[name] : null;
  if (!m || typeof m !== 'object') return false;
  return !m.hidden || payloadZip(name);
}

function listFiles() {
  const meta = jsonFile(path.join(FILES, 'files.json'), {});
  const out = [];
  let names = [];
  // No downloads folder is no downloads. One that is there and cannot be
  // listed is said (#2736), since the page then offers nothing and the log
  // is the only place that says it is the folder and not the build.
  if (fs.existsSync(FILES)) {
    try { names = fs.readdirSync(FILES); }
    catch (e) { console.error('[thornswood-docs] could not list the downloads in ' + FILES + ' (' + (e.code || e.message) + ')'); }
  }
  for (const name of names) {
    // Only what /file/ serves, so the page never offers a name that answers
    // 404, and nothing files.json does not publish is listed at all.
    if (name === 'files.json' || !downloadServed(name, meta)) continue;
    let st;
    try { st = fs.statSync(path.join(FILES, name)); } catch (e) { continue; }
    if (!st.isFile()) continue;
    const m = meta[name];
    // hidden has to survive the trip. The payload zip is marked hidden by
    // Publish-Installer because the setup program fetches it itself, and the
    // page hides it on that flag. Dropping it here put the old two file
    // instructions back on the downloads page and a 527 MB button next to
    // them that does nothing on its own.
    // The installer's SHA-256, which Publish-Installer writes, so the Downloads
    // page can print it beside the size and date (To Do entry 176). Only a well
    // formed hash goes out, in lower case because Get-FileHash writes upper and
    // the page builds an address from it.
    const sha256 = String(m.sha256 || '').toLowerCase();
    const hash = /^[0-9a-f]{64}$/.test(sha256) ? sha256 : '';
    // Who the installer is signed by, as Publish-Installer's sign gate held it
    // (#5275): the name Windows shows as the publisher. An entry from before
    // that has none, and the page then names nobody rather than a wrong name.
    out.push({ name, size: st.size, at: st.mtimeMs, hidden: !!m.hidden,
      label: m.label || name, version: m.version || '', note: m.note || '',
      sha256: hash, publisher: typeof m.publisher === 'string' ? m.publisher.trim() : '' });
  }
  out.sort((a, b) => b.at - a.at);
  return out;
}
