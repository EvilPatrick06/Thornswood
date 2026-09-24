// ---------------------------------------------------------------------------
// Thornswood: mark this spot.
//
// The arrival coordinates for the nine starting inns were first written by
// hand, each one the inn's front door moved 110 units along the door's own
// heading, and seven of those eight were not in the room. 1.1.41 walked five;
// Solitude, Falkreath and Dawnstar now use the spot the game puts you on when
// you walk in the front door (the comment above CHARGEN in gamemode.js says
// how). The old Morthal and Dawnstar points only looked like one spot because
// the two inns share a layout: interior coordinates belong to their own cell.
//
// So a spot gets measured rather than typed. Stand where somebody should arrive, face the
// way they should face, press the key. This writes the cell, the position and
// the angle out of the running game, and Mark-Spot.ps1 turns the file into the
// line the content table wants.
//
// Nothing here touches anything. It reads three values and appends a line.
// ---------------------------------------------------------------------------

(function () {
'use strict';

// ------------------------------------------------------------ whose game ----
// Skyrim Platform loads every plugin in Data/Platform/Plugins, whichever server
// skymp5-client is about to join. Somebody who also plays another server starts
// it from this same Skyrim, so on 2026-09-16 Thornswood's voice indicator sat
// on top of that server's menu. Whichever launcher ran last wrote
// skymp5-client-settings.txt, and its server-ip says whose game this is. Not
// ours: this file does nothing at all. Unreadable: carry on, as before.
//
// Ours is the address in Thornswood.ini's ServerAddress line when there is
// one, so a server move is an ini edit, and the fixed address below when
// there is not.
if (!thornswoodGame()) { return; }
function thornswoodGame() {
  const ours = ['192.135.112.23'];
  let ip = '';
  try {
    const fs = require('fs');
    try {
      const m = fs.readFileSync('Data/SKSE/Plugins/Thornswood.ini', 'utf8')
        .match(/^\s*ServerAddress\s*=\s*([^\s;]+)/m);
      if (m) { ours.push(m[1]); }
    } catch (e) { }
    let raw = fs.readFileSync('Data/Platform/Plugins/skymp5-client-settings.txt', 'utf8');
    if (raw.charCodeAt(0) === 0xFEFF) { raw = raw.slice(1); }
    ip = String((JSON.parse(raw) || {})['server-ip'] || '').trim();
  } catch (e) { return true; }
  if (ip && ours.indexOf(ip) < 0) {
    try { skyrimPlatform.printConsole('[thornswood] the client points at ' + ip + ', not this server. Plugin idle.'); } catch (e) { }
    return false;
  }
  // The client can point at us and this still not be our session: another
  // server's launcher that never rewrites the client settings leaves our
  // address in them. So the launcher leaves a note when it starts the game
  // and takes it away when the game closes. No fresh note, not our session.
  try {
    const note = String(require('fs').readFileSync('Data/Platform/thornswood-session.txt', 'utf8')).trim();
    const first = note.split(/\s+/)[0];
    let when = Number(first);         // unix milliseconds from the launcher
    if (!isFinite(when) || when < 1e12) { when = Date.parse(first); }
    if (isFinite(when) && Math.abs(Date.now() - when) < 24 * 3600 * 1000) { return true; }
    try { skyrimPlatform.printConsole('[thornswood] the launcher\'s session note is stale, so this is another server\'s session. Plugin idle.'); } catch (e) { }
  } catch (e) {
    try { skyrimPlatform.printConsole('[thornswood] the launcher left no session note, so this is another server\'s session. Plugin idle.'); } catch (e2) { }
  }
  return false;
}

const sp = skyrimPlatform;

const OUT = 'Data/Platform/thornswood-spots.txt';
const INI = 'Data/SKSE/Plugins/Thornswood.ini';

let markKey = 66;   // F8
try {
  const text = require('fs').readFileSync(INI, 'utf8');
  const m = text.match(/^\s*MarkKey\s*=\s*(\d+)/m);
  if (m) { markKey = Number(m[1]) || markKey; }
} catch (e) { }

function log() {
  try { sp.printConsole('[mark] ' + Array.prototype.slice.call(arguments).join(' ')); } catch (e) { }
}

function guard(name, fn) {
  return function () {
    try { return fn.apply(null, arguments); }
    catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
  };
}

function say(text) {
  // On screen, because the console is not open while somebody is walking round
  // an inn deciding where the door is.
  try { sp.Debug.notification(text); } catch (e) { }
  log(text);
}

/*
  AND ONLY FOR SOMEBODY THE SITE CALLS A DEV.

  This is internal tooling. It writes coordinates out of the world so the
  arrival points and the notice boards can be measured rather than typed, and
  it has been shipping to every customer bound to an unmodified F8 since it was
  written. Nothing it does is dangerous, but a retail client should not carry a
  developer tool on a function key, and the next one like it might not be
  harmless.

  THE FLAG ALREADY EXISTS AND IS NOT THIS FILE'S TO INVENT. The launcher asks
  the site whether this person may use the dev build, and Discord.cs writes
  Profile\dev-allowed.txt when the answer is yes and DELETES it when the answer
  is no. So the file being there is the site's answer, kept on disk, and it is
  the same answer the dev build itself is gated on.

  Relative to the game folder, because that is where the process stands: the
  paths above are Data/Platform/... for the same reason, and Profile sits
  beside Game rather than inside it. Relative also means the dev build reads
  its own Profile rather than the play install's.

  THE FILE STILL SHIPS, deliberately. Ship refuses a release when the plugin
  folder and the source differ by a byte, and a half done removal stops every
  release, which is what the entry's own trap says. MarkKey stays in the ini
  for the same reason: the ini is not packed, so taking it out would change
  nothing for anybody who already has one. The guard is the fix; the key is
  simply never bound for anybody the site has not named.
*/
let markAllowed = false;
try {
  require('fs').readFileSync('../Profile/dev-allowed.txt', 'utf8');
  markAllowed = true;
} catch (e) {
  markAllowed = false;
}

sp.on('buttonEvent', guard('mark', (e) => {
  if (!markAllowed) { return; }
  if (!e.isDown || e.isUp || e.code !== markKey) { return; }

  let pc = null;
  try { pc = sp.Game.getPlayer(); } catch (e2) { pc = null; }
  if (!pc) { return; }

  let cell = null;
  try { cell = pc.getParentCell(); } catch (e2) { cell = null; }
  if (!cell) { say('Nothing to mark, no cell.'); return; }

  let name = '';
  let id = 0;
  try { name = cell.getName() || ''; } catch (e2) { name = ''; }
  try { id = cell.getFormID() || 0; } catch (e2) { id = 0; }

  // The editor id is what the content table names cells by, and getName gives
  // the one people see. Both go in: the id is what actually resolves, the name
  // is what makes the file readable when you come back to it.
  let editorId = '';
  try { editorId = sp.Utility.getFormEditorID ? sp.Utility.getFormEditorID(id) : ''; } catch (e2) { editorId = ''; }
  const label = (editorId || name || ('cell_' + id.toString(16))).replace(/\s+/g, '');

  let x = 0, y = 0, z = 0, rot = 0;
  try {
    x = pc.getPositionX();
    y = pc.getPositionY();
    z = pc.getPositionZ();
    rot = pc.getAngleZ();
  } catch (e2) {
    say('Could not read your position.');
    return;
  }

  const round = (v) => Math.round(v * 10) / 10;
  const line = [label, id.toString(16), round(x), round(y), round(z), round(rot)].join('\t');

  try {
    const fs = require('fs');
    if (!fs.existsSync(OUT)) {
      fs.writeFileSync(OUT,
        '# Thornswood marked spots\n' +
        '# cell\tformId\tx\ty\tz\tangleZ\n' +
        '# The last mark of a cell wins, so walk back and press it again to correct one.\n');
    }
    fs.appendFileSync(OUT, line + '\n');
  } catch (e2) {
    say('Could not write the spot file.');
    return;
  }

  say('Marked ' + label + ' at ' + round(x) + ', ' + round(y) + ', ' + round(z));
}));

log(markAllowed
  ? ('loaded, mark key is scan code ' + markKey)
  : 'loaded and idle: this build is not a dev one, so the mark key is not bound');

})();
