<#
  Delete-Person.ps1

  Carries out a deletion request (issue #2351). Finds one person's records in
  every store on the box by their Discord id, shows how many there are, deletes
  them only when told to, and writes the request down so that a restore
  reapplies it. Runs ON the VPS, as Administrator, sent there by Remote.ps1:

      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId 123456789012345678'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId 123456789012345678 -Delete -By Patrick'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-Reapply'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-Reapply -Delete'

  WHY. site\data\site\privacy.md promises that somebody who asks in the
  Discord has their Discord link, session records, chat and character
  deleted, by a person, and that staff reapply completed requests before an
  older backup goes back into service. Until this there was no list of where a
  person's records are, no way to remove them but by hand, and no record of
  what had been done. Patrick decided on 12 October 2026 (option A on #2351): a
  staff script that finds, shows counts, deletes with a dry run first, and
  records each request so a restore reapplies it. "Deletion requests" in
  docs\WEBSITE-OPERATIONS.md is the procedure around it.

  A DRY RUN IS THE DEFAULT. Without -Delete nothing is changed, stopped or
  written. It prints, for every store, how many of the person's records are
  there and whether a real run removes them or leaves them. Counts only,
  never what a record says and never an address.

  WHO. Their Discord id, and their characters: the profile ids linked.json
  holds for them, which the site checked were theirs when they played, and on
  a reapply also the ids the record wrote down. A profile id that another
  account also holds is not theirs to delete and is left, and said.

  WHAT A REAL RUN REMOVES, the person's own records, in every copy on the box
  (the live folder and the copies a restore, a wipe, an install or a character
  reset sets aside beside it):
    site            their Discord link (linked.json), their answer to the
                    rules (rules-accepted.json), their sign-in rows
                    (signins.json, which hold an address), their session rows
                    (sessions.json) with the launcher logs sent with them
                    (session-logs) and the failed-session alerts about them
                    (for-bot\trouble.json), their characters' rows in
                    roster.json, the tickets, applications and calls for help
                    they sent (for-bot\inbox.json), and their gallery
                    pictures, waiting or approved, with the file
    game servers    each character's change form (world\changeForms, and the
                    world-before-* and _discarded-* copies), its card
                    (private\characters.json and the characters-before-*
                    copies), its mod menu choices (private\mod-settings.json),
                    its take counts (private\take-limit.json) and when it last
                    left (private\last-left.json, and data\last-left.json in a
                    folder set aside before #2582 moved it), live and dev
    voice           every chat line their characters wrote, out of each day's
                    file, live and dev, except the lines said inside a
                    session staff marked kept (#2166), which stay with it.
                    The voice service never edits a day
                    (voice\voice-server.js); these are the only edits, and the
                    record keeps each file's line count before and after, so
                    an edited day says so
    the bot         their join number (joins.json; the last number given out
                    stays, so nobody is handed theirs again) and their open
                    ticket (open-tickets.json)

  WHAT IT LEAVES, counted and said:
    - staff's records about them: bans, PKs and notes (bans.json, pk.json,
      notes.json), the staff logs' lines naming them (moderation.log on the
      site and on each game server, the game server's door.log), reports they
      made and reports made about them (inbox.json, gallery-reports.json), and
      a session staff marked kept, with its launcher logs, alerts, the copy
      of its chat and the chat lines in the day files inside its window. The
      privacy page: "What cannot be undone is something you said that
      somebody else has already quoted in a report, because that now belongs
      to the report."
    - the game's registers that it does not let go (below): the old copies a
      game server kept in data: counted, never changed.
    - a gallery picture with an open report against it, or taken down after
      one and still held, which is staff's while they look into it (#2352);
      and one approved before the site kept the sending account in its
      uploads note (16 Oct 2026, #2351), which nothing ties to them, so staff
      remove theirs in the hub by name.
    - logs, which age by their own rule (server.log 30 days, #2349; the
      site's, the gamemode's, voice's and the bot's by size), and the
      encrypted backups, which expire on their schedule and are why the
      record exists.

  WHAT THE GAME SERVER LETS GO AT ITS NEXT START (Patrick, 16 October, option
  A on #2351: "Delete-Person.ps1 writes a list, and the gamemode releases
  those entries at its next start"). The game's registers in a server's
  private folder name a character: a house and its master key in
  property.json, with the notice boards' posts and the drop box and its
  record; a farm in farm-claims.json; an office in law.json; a bed's guests
  and takings in beds.json; the embassy and remnant rolls in embassy.json; a
  dungeon chest's reservation in dungeon-rewards-ledger.json; a faction or
  business book's members, chat and owner in books.json. This script never
  edits those: what happens to a house or a post held by somebody who is gone
  is each register's own rule, and that rule is in the gamemode. So it counts
  them ("release" in what it prints) and, for every server that holds
  something of theirs, writes private\deleted-characters.json beside them:
  their profile ids and the form ids of the characters it found there. The
  game server's release block reads it at its start, lets go of every entry
  through the register's own code, logs counts only and deletes the list. A
  faction or business book they own is disbanded then, so the procedure says
  to have staff hand it on in the game first when the group wants to keep it.

  A REAL RUN STOPS WHAT WRITES THOSE STORES, and only those. The site, a game
  server, a voice service and the bot each write their files while they run,
  so a file changed underneath one is written straight back over (the same
  reason docs\RESTORING.md stops the game server to put one character back).
  So for each one whose files hold something to remove: the watchdog is
  disabled first so it starts nothing again, the service is stopped and any
  process still running from its folder is ended, the files are changed, and
  the service is started again, then the watchdog. A game server with anybody
  online is refused unless -Now: they would be dropped. A game server with an
  unfinished save (.pending-batch in changeForms) is refused: the engine
  replays it at its next start and could write a deleted character back.
  Every file is read and checked before any is written, and each JSON file is
  written to a file beside it and swapped in, the way the site writes its own.

  THE RECORD. Each completed request is one line in
  C:\Thornswood-Deletions\requests.jsonl: the Discord id, the profile ids,
  when, who ran it, and the counts it removed. Nothing else about the person.
  The folder is SYSTEM's and Administrators' only, locked when this makes it.
  The nightly backup takes it (deletions\requests.jsonl), so it leaves the box
  with every backup.

  -Reapply reads that record and removes every request in it again: after a
  backup is put back and before anything starts (Restore-Box.ps1 runs it, and
  docs\RESTORING.md says when by hand). -Merge names other copies of the
  record (the one in the backup being put back, or one from a newer backup);
  lines the box's record does not have are added to it first. -Reapply never
  stops anything: it refuses while a service it would write under is running,
  and never adds a line of its own.

  WHAT IT REFUSES, with nothing changed:
    - anywhere with C:\Thornswood\Game\SkyrimSE.exe, which is a gaming PC
    - a Discord id that is not 17 to 20 digits
    - -Delete without -By, the person running it
    - a JSON file, or a line of the record, that is there and will not parse
    - no node on the PATH (the JSON is edited by node, as the site writes it)

  tests\test-2351-delete-person.ps1 runs it against stand-ins of every store.

.PARAMETER DiscordId
  The Discord id of the person who asked, 17 to 20 digits.
.PARAMETER Delete
  Change things. Without it this is a dry run that changes nothing.
.PARAMETER By
  Who is running the request, written into the record. Required with -Delete.
.PARAMETER Reapply
  Remove every request in the record again, after a restore.
.PARAMETER Merge
  With -Reapply: other copies of the record to add to the box's first.
.PARAMETER Now
  Stop a game server even with people online.
.PARAMETER SiteRoot
  The site's folder.
.PARAMETER GameRoot
  The live game server's folder.
.PARAMETER DevGameRoot
  The dev game server's folder.
.PARAMETER VoiceRoot
  The live voice service's folder.
.PARAMETER DevVoiceRoot
  The dev voice service's folder.
.PARAMETER BotRoot
  The bot's folder.
.PARAMETER RecordRoot
  Where the record of completed requests is kept.
.PARAMETER NoServices
  Neither stop nor check any service: for stand-in folders nothing runs from.
  Only the tests pass it.
.PARAMETER AllowGamingPc
  Run on a machine with the game on it. Only the tests pass it.
#>
[CmdletBinding()]
param(
    [string]$DiscordId = '',
    [switch]$Delete,
    [string]$By = '',
    [switch]$Reapply,
    [string[]]$Merge = @(),
    [switch]$Now,
    [string]$SiteRoot     = 'C:\Thornswood-Docs',
    [string]$GameRoot     = 'C:\Thornswood-Server',
    [string]$DevGameRoot  = 'C:\Thornswood-Server-Dev',
    [string]$VoiceRoot    = 'C:\Thornswood-Voice',
    [string]$DevVoiceRoot = 'C:\Thornswood-Voice-Dev',
    [string]$BotRoot      = 'C:\Thornswood-Bot',
    [string]$RecordRoot   = 'C:\Thornswood-Deletions',
    [switch]$NoServices,
    [switch]$AllowGamingPc
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Say([string]$m) { Write-Output $m }
function Refuse([string]$m) { Write-Output ('REFUSED: ' + $m); exit 1 }

if (-not $AllowGamingPc -and (Test-Path -LiteralPath 'C:\Thornswood\Game\SkyrimSE.exe')) {
    Refuse 'C:\Thornswood\Game\SkyrimSE.exe is here, so this is a gaming PC, not the VPS. Nothing was changed.'
}
# powershell -File hands a list over as one word with commas in it.
$Merge = @($Merge | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Reapply -and $DiscordId) { Refuse '-Reapply takes every request in the record; leave -DiscordId off. Nothing was changed.' }
if ($Merge.Count -and -not $Reapply) { Refuse '-Merge goes with -Reapply. Nothing was changed.' }
if (-not $Reapply) {
    if ($DiscordId -notmatch '^\d{17,20}$') { Refuse '-DiscordId takes a Discord id, 17 to 20 digits. Nothing was changed.' }
    if ($Delete -and -not $By.Trim()) { Refuse '-Delete needs -By, the person running the request, for the record. Nothing was changed.' }
}
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) { Refuse 'node is not on the PATH. Nothing was changed.' }
$node = $nodeCmd.Source
$record = Join-Path $RecordRoot 'requests.jsonl'
$utf8 = New-Object Text.UTF8Encoding($false)

# ---------------------------------------------------------------- record ---
# The folder: SYSTEM, Administrators and the account running this, nothing
# inherited and no Users rule, the rule Lock-Folder.ps1 -Only applies. Only
# the access rules are written back, never the audit part (#1120).
function Lock-RecordFolder([string]$Path) {
    $tree = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $keepers = @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
        if ($keepers -notcontains $r.IdentityReference.Value) { [void]$acl.RemoveAccessRuleSpecific($r) }
    }
    foreach ($s in $keepers) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', $tree, 'None', 'Allow')))
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($PSVersionTable.PSEdition -eq 'Core') {
        [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$acl)
    } else { $item.SetAccessControl($acl) }
}
function Ensure-RecordFolder {
    if (Test-Path -LiteralPath $RecordRoot) { return }
    $null = New-Item -ItemType Directory -Path $RecordRoot -Force
    Lock-RecordFolder $RecordRoot
    Say ('locked    ' + $RecordRoot + ', SYSTEM and Administrators only')
}
# Every line of a record, each with its Discord id and profile ids. A line
# that will not parse, or names no Discord id, refuses the run: a record that
# cannot be read in full cannot be reapplied in full.
function Read-Record([string]$file) {
    $rows = @()
    if (-not (Test-Path -LiteralPath $file)) { return ,$rows }
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $n++
        if (-not $line.Trim()) { continue }
        $o = $null
        try { $o = $line | ConvertFrom-Json } catch { Refuse ("line $n of $file will not parse. Nothing was changed.") }
        if ("$($o.discordId)" -notmatch '^\d{17,20}$') { Refuse ("line $n of $file names no Discord id. Nothing was changed.") }
        $rows += ,@{ line = $line.Trim(); discordId = "$($o.discordId)"; profiles = @(@($o.profiles) | Where-Object { "$_" -match '^\d{1,12}$' } | ForEach-Object { [long]$_ } | Where-Object { $_ -gt 0 }) }
    }
    return ,$rows
}

# ------------------------------------------------------------------- who ---
$people = @()
if ($Reapply) {
    foreach ($m in $Merge) { if (-not (Test-Path -LiteralPath $m)) { Refuse "-Merge names $m, which is not there. Nothing was changed." } }
    $have = Read-Record $record
    $adds = @()
    foreach ($m in $Merge) {
        foreach ($r in (Read-Record $m)) {
            if (@($have | Where-Object { $_.line -eq $r.line }).Count -or @($adds | Where-Object { $_.line -eq $r.line }).Count) { continue }
            $adds += ,$r
        }
    }
    $byId = [ordered]@{}
    foreach ($r in @($have) + @($adds)) {
        if (-not $byId.Contains($r.discordId)) { $byId[$r.discordId] = @() }
        $byId[$r.discordId] = @($byId[$r.discordId]) + @($r.profiles)
    }
    foreach ($k in $byId.Keys) { $people += ,@{ discordId = $k; profiles = @($byId[$k] | Sort-Object -Unique) } }
    Say ('record    ' + @($have).Count + ' completed request(s) in ' + $record + $(if ($adds.Count) { ', and ' + $adds.Count + ' more in ' + ($Merge -join ', ') } else { '' }))
    if (-not $people.Count) { Say 'NOTHING TO REAPPLY: no record names a request.'; exit 0 }
} else {
    $people = @(@{ discordId = $DiscordId; profiles = @() })
}

# ------------------------------------------------------------------ node ---
# The JSON is read and written by node, as the site, the voice service and
# the game server write their own, so a file goes back the shape it came in.
# It prints lines: WRITER|<service> for each service whose files it would
# change, PERSON|<json> for each person, STOP|<why> when nothing may be done,
# FAILED|<file> for a change that did not take, and DONE|<mode> at the end.
$core = @'
'use strict';
const fs = require('fs');
const path = require('path');
const a = JSON.parse(fs.readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, ''));
const say = (s) => process.stdout.write(s + '\n');
function stop(m) { say('STOP|' + m); process.exit(2); }
const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

// What is in a folder, [] when it is not there. Anything else stops.
function names(dir) {
  try { return fs.readdirSync(dir); }
  catch (e) {
    if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return [];
    stop(dir + ' cannot be listed (' + e.code + '), so nothing was changed');
  }
}
function isDir(p) { try { return fs.statSync(p).isDirectory(); } catch (e) { return false; } }

// Every JSON file this run reads, once. A file that is there and cannot be
// read or parsed stops the run before anything is written.
const files = new Map();
function json(p, writer) {
  if (files.has(p)) return files.get(p);
  let t = null;
  try { t = fs.readFileSync(p, 'utf8'); }
  catch (e) { if (e.code !== 'ENOENT') stop(p + ' cannot be read (' + e.code + '), so nothing was changed'); }
  let f;
  if (t === null) f = { p, value: undefined, missing: true, writer, dirty: false };
  else {
    t = t.replace(/^\uFEFF/, '');
    let v;
    try { v = JSON.parse(t); } catch (e) { stop(p + ' will not parse, so nothing was changed'); }
    f = { p, value: v, missing: false, indent: /^[\[{]\s*\r?\n/.test(t) ? 2 : 0, eol: /\n$/.test(t), writer, dirty: false };
  }
  files.set(p, f);
  return f;
}
function want(f, kind) {
  if (f.missing) return false;
  const ok = kind === 'array' ? Array.isArray(f.value) : isObj(f.value);
  if (!ok) stop(f.p + ' is not the shape it should be (' + kind + '), so nothing was changed');
  return true;
}
const texts = new Map();    // path -> { lines, writer, dirty }
const unlinks = new Map();  // path -> writer
function text(p, writer) {
  if (texts.has(p)) return texts.get(p);
  let raw = '';
  try { raw = fs.readFileSync(p, 'utf8'); }
  catch (e) { if (e.code === 'ENOENT') return null; stop(p + ' cannot be read (' + e.code + '), so nothing was changed'); }
  const lines = raw.split('\n');
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  const t = { lines, writer, dirty: false };
  texts.set(p, t);
  return t;
}
function lines(p) {
  try { return fs.readFileSync(p, 'utf8').split(/\r?\n/); }
  catch (e) { if (e.code === 'ENOENT') return []; stop(p + ' cannot be read (' + e.code + '), so nothing was changed'); }
}

// The copies a restore, a wipe or an install leaves beside a folder.
const ASIDE_SITE = /^data-before-restore-\d{8}-\d{6}(-\d+)?$/;
function siteSets(root) {
  const out = [{ tag: 'site', data: path.join(root, 'data'), uploads: path.join(root, 'uploads'), writer: 'site' }];
  for (const n of names(root).sort()) {
    if (!ASIDE_SITE.test(n) || !isDir(path.join(root, n))) continue;
    const up = path.join(root, n.replace(/^data-/, 'uploads-'));
    out.push({ tag: 'site, set aside as ' + n, data: path.join(root, n), uploads: isDir(up) ? up : null, writer: null });
  }
  return out;
}
function serverSets(s) {
  const out = [{ tag: s.tag + ' game server', root: s.root, writer: 'server:' + s.tag }];
  const parent = path.dirname(s.root), leaf = path.basename(s.root).toLowerCase();
  for (const n of names(parent).sort()) {
    const l = n.toLowerCase();
    if (l.indexOf(leaf + '.') !== 0 || !/^\.(prev|undone|failed)-\d{8}-\d{6}$/.test(l.slice(leaf.length))) continue;
    if (isDir(path.join(parent, n))) out.push({ tag: s.tag + ' game server, set aside as ' + n, root: path.join(parent, n), writer: null });
  }
  return out;
}

/*
  How many places in a register name one of these characters or this account:
  an object with a key that is the profile id, or with an owner-like field
  holding it, or an array of numbers holding it. A count for the person
  running this to read, never a reason to change anything.
*/
const REF_KEY = /^(pid|profile|profileid|owner|ownerpid|holder|who|by|byid|account|discordid|member|guard|tenant|guest|claimant|leader|taken|owedto|deliveredto|downby|doneby|for)$/i;
function refs(v, P, id, A) {
  let n = 0;
  const hit = (x) => (typeof x === 'number' || (typeof x === 'string' && /^\d{1,20}$/.test(x))) && (P.has(Number(x)) || String(x) === id);
  // A character's form id, kept as `actor` by the embassy rolls and the dungeon chests' record.
  const hitActor = (k, x) => !!A && /^actor$/i.test(k) && typeof x === 'number' && A.has(x);
  (function walk(x, depth) {
    if (depth > 40 || x === null || typeof x !== 'object') return;
    if (Array.isArray(x)) {
      if (x.some(hit)) n++;
      for (const y of x) walk(y, depth + 1);
      return;
    }
    let mine = false;
    for (const k of Object.keys(x)) {
      // The merchant ledger keys a supply wait by [form id, profile, what].
      let inKey = false;
      if (k[0] === '[') { try { const ks = JSON.parse(k); inKey = Array.isArray(ks) && ks.some(hit); } catch (e) { inKey = false; } }
      if (hit(k) || inKey) mine = true;
      else if (REF_KEY.test(k) && hit(x[k])) mine = true;
      else if (hitActor(k, x[k])) mine = true;
    }
    if (mine) n++;
    for (const k of Object.keys(x)) walk(x[k], depth + 1);
  })(v, 0);
  return n;
}
function logLinesNaming(p, P, id) {
  let n = 0;
  for (const line of lines(p)) {
    if (!line.trim()) continue;
    let o = null;
    try { o = JSON.parse(line); } catch (e) { o = null; }
    if (o !== null && typeof o === 'object') { if (refs(o, P, id)) n++; continue; }
    if (line.indexOf(id) >= 0 || Array.from(P).some((pid) => new RegExp('\\b' + pid + '\\b').test(line))) n++;
  }
  return n;
}

const people = a.people.map((x) => ({ discordId: String(x.discordId), profiles: (x.profiles || []).map(Number).filter((n) => n > 0) }));
const linked = json(path.join(a.site, 'data', 'linked.json'), 'site');
want(linked, 'object');
const results = [];

for (const person of people) {
  const id = person.discordId;
  const r = { discordId: id, profiles: [], skipped: [], removed: {}, held: {}, left: {}, release: {}, chat: [], notes: [] };
  const removed = (k, n) => { if (n) r.removed[k] = (r.removed[k] || 0) + n; };
  const releases = (k, n) => { if (n) r.release[k] = (r.release[k] || 0) + n; };
  const held = (k, n) => { if (n) r.held[k] = (r.held[k] || 0) + n; };
  const left = (k, n) => { if (n) r.left[k] = (r.left[k] || 0) + n; };

  // Their characters. An id another account holds is not theirs.
  const P = new Set(person.profiles);
  const L = linked.value || {};
  if (isObj(L[id]) && Array.isArray(L[id].profiles)) for (const n of L[id].profiles) if (Number(n) > 0) P.add(Number(n));
  for (const other of Object.keys(L)) {
    if (other === id || !isObj(L[other]) || !Array.isArray(L[other].profiles)) continue;
    for (const n of L[other].profiles) if (P.has(Number(n))) { P.delete(Number(n)); r.skipped.push(Number(n)); }
  }
  r.profiles = Array.from(P).sort((x, y) => x - y);
  const hasP = (v) => P.has(Number(v));
  // The windows of their sessions staff marked kept, from every copy of the
  // site, so the chat said in them stays (#2166). The same window the site's
  // /api/session-logs reads: a minute either side of start and end, and to
  // now for one still open.
  const keptWindows = [];

  // ---- the site, and each copy of its data a restore set aside
  for (const s of siteSets(a.site)) {
    const D = s.data, FB = path.join(D, 'for-bot'), T = s.tag;
    const lk = json(path.join(D, 'linked.json'), s.writer);
    if (want(lk, 'object') && has(lk.value, id)) { delete lk.value[id]; lk.dirty = true; removed(T + ': Discord link', 1); }
    const rules = json(path.join(D, 'rules-accepted.json'), s.writer);
    if (want(rules, 'object') && has(rules.value, id)) { delete rules.value[id]; rules.dirty = true; removed(T + ': answer to the rules', 1); }
    const signins = json(path.join(D, 'signins.json'), s.writer);
    if (want(signins, 'array')) {
      const keep = signins.value.filter((x) => !(isObj(x) && String(x.id) === id));
      if (keep.length !== signins.value.length) { removed(T + ': sign-in rows', signins.value.length - keep.length); signins.value = keep; signins.dirty = true; }
    }
    const kept = new Set(), gone = new Set();
    const sessions = json(path.join(D, 'sessions.json'), s.writer);
    if (want(sessions, 'array')) {
      const keep = [];
      for (const x of sessions.value) {
        if (isObj(x) && String(x.who) === id) {
          if (x.keep) {
            keep.push(x); kept.add(String(x.session)); held(T + ': session rows staff marked kept', 1);
            // A row with neither a start nor an end has no window to keep.
            if (Number(x.start) || Number(x.end)) {
              keptWindows.push({ voice: x.channel === 'dev' ? 'dev' : 'live', profile: Number(x.profile) || 0,
                                 from: (Number(x.start) || Number(x.end)) - 60000,
                                 to: (Number(x.end) || Number(a.now) || Date.now()) + 60000 });
            }
          }
          else { gone.add(String(x.session)); removed(T + ': session rows', 1); }
        } else keep.push(x);
      }
      if (keep.length !== sessions.value.length) { sessions.value = keep; sessions.dirty = true; }
    }
    const slogs = path.join(D, 'session-logs');
    for (const f of names(slogs).sort()) {
      if (!/\.json$/i.test(f)) continue;
      const p = path.join(slogs, f);
      // Read and let go, not kept with the files this run may write: there
      // can be a year of them, up to a megabyte each.
      let set = null;
      try { set = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, '')); }
      catch (e) { left(T + ': launcher logs that would not parse, so were not read', 1); continue; }
      if (!isObj(set)) continue;
      if (String(set.who) !== id && !gone.has(String(set.session))) continue;
      if (kept.has(String(set.session))) held(T + ': launcher logs of kept sessions', 1);
      else { unlinks.set(p, s.writer); removed(T + ': launcher logs', 1); }
    }
    const trouble = json(path.join(FB, 'trouble.json'), s.writer);
    if (want(trouble, 'array')) {
      const keep = [];
      for (const x of trouble.value) {
        const theirs = isObj(x) && (String(x.who) === id || hasP(x.profile) || gone.has(String(x.session)));
        if (theirs && !kept.has(String(x.session))) { removed(T + ': failed-session alerts', 1); continue; }
        if (theirs) held(T + ': failed-session alerts of kept sessions', 1);
        keep.push(x);
      }
      if (keep.length !== trouble.value.length) { trouble.value = keep; trouble.dirty = true; }
    }
    const roster = json(path.join(D, 'roster.json'), s.writer);
    if (want(roster, 'object')) {
      if (isObj(roster.value.who)) {
        for (const k of Object.keys(roster.value.who)) if (hasP(k)) { delete roster.value.who[k]; roster.dirty = true; removed(T + ': roster rows', 1); }
      }
      if (isObj(roster.value.servers)) {
        for (const sv of Object.values(roster.value.servers)) {
          if (!isObj(sv)) continue;
          for (const k of ['checked', 'held']) {
            if (!Array.isArray(sv[k])) continue;
            const keep = sv[k].filter((n) => !hasP(n));
            if (keep.length !== sv[k].length) { sv[k] = keep; roster.dirty = true; }
          }
        }
      }
    }
    const inbox = json(path.join(FB, 'inbox.json'), s.writer);
    if (want(inbox, 'array')) {
      const keep = [];
      for (const x of inbox.value) {
        if (!isObj(x)) { keep.push(x); continue; }
        const sent = String(x.discordId || '') === id || hasP(x.profileId);
        const report = x.kind === 'report' || x.ticket === 'report';
        if (sent && !report) { removed(T + ': tickets, applications and calls for help they sent', 1); continue; }
        keep.push(x);
        if (sent) held(T + ': reports they made', 1);
        else if (hasP(x.aboutProfileId)) held(T + ': reports about them', 1);
      }
      if (keep.length !== inbox.value.length) { inbox.value = keep; inbox.dirty = true; }
    }
    const pending = json(path.join(D, 'gallery-pending.json'), s.writer);
    if (want(pending, 'array')) {
      const keep = [];
      const meta = s.uploads ? json(path.join(s.uploads, 'uploads.json'), s.writer) : null;
      if (meta) want(meta, 'object');
      for (const x of pending.value) {
        if (!(isObj(x) && String(x.discordId || '') === id)) { keep.push(x); continue; }
        removed(T + ': gallery submissions waiting for staff', 1);
        const name = String(x.name || '');
        if (s.uploads && /^[A-Za-z0-9._ -]+$/.test(name) && name !== 'uploads.json') {
          const fp = path.join(s.uploads, name);
          if (fs.existsSync(fp)) unlinks.set(fp, s.writer);
          if (meta && !meta.missing && has(meta.value, name)) { delete meta.value[name]; meta.dirty = true; }
        }
      }
      if (keep.length !== pending.value.length) { pending.value = keep; pending.dirty = true; }
    }
    const greports = json(path.join(D, 'gallery-reports.json'), s.writer);
    const hasReports = want(greports, 'array');
    if (hasReports) held(T + ': reports they made about a gallery picture', greports.value.filter((x) => isObj(x) && String(x.discordId || '') === id).length);
    /*
      Their approved pictures. gallery.json keeps no account, because the site
      hands it out; the uploads note the site writes at submission does
      (site/server.js, #2351). One with an open report against it, or taken
      down after one and still held, is staff's while they look into it, the
      site's own rule (#2352), and is left. A picture approved before the
      note carried the account cannot be found here: Show says so.
    */
    const gallery = json(path.join(D, 'gallery.json'), s.writer);
    const umeta = s.uploads ? json(path.join(s.uploads, 'uploads.json'), s.writer) : null;
    if (want(gallery, 'array') && umeta && want(umeta, 'object')) {
      const reported = new Set(hasReports ? greports.value.filter(isObj).map((x) => String(x.name)) : []);
      for (const name of Object.keys(umeta.value)) {
        const m = umeta.value[name];
        if (!isObj(m) || String(m.discordId || '') !== id || !/^[A-Za-z0-9._ -]+$/.test(name) || name === 'uploads.json') continue;
        const onGallery = gallery.value.some((g) => isObj(g) && String(g.name) === name);
        if (reported.has(name) || (m.removed && Number(m.heldUntil) > a.now)) { held(T + ': gallery pictures held while a report about them is looked into', 1); continue; }
        if (onGallery) {
          gallery.value = gallery.value.filter((g) => !(isObj(g) && String(g.name) === name));
          gallery.dirty = true;
          removed(T + ': approved gallery pictures', 1);
        } else removed(T + ': other gallery files they sent', 1);
        const fp = path.join(s.uploads, name);
        if (fs.existsSync(fp)) unlinks.set(fp, s.writer);
        delete umeta.value[name];
        umeta.dirty = true;
      }
    }
    const bans = json(path.join(D, 'bans.json'), s.writer);
    const notes = json(path.join(D, 'notes.json'), s.writer);
    const pk = json(path.join(D, 'pk.json'), s.writer);
    const hasBans = want(bans, 'object'), hasNotes = want(notes, 'object'), hasPk = want(pk, 'object');
    for (const k of [id].concat(r.profiles.map((n) => 'p:' + n))) {
      if (hasBans && has(bans.value, k)) held(T + ': bans', 1);
      if (hasNotes && Array.isArray(notes.value[k])) held(T + ': staff notes', notes.value[k].length);
    }
    if (hasPk) for (const n of r.profiles) if (has(pk.value, String(n))) held(T + ': PK records', 1);
    held(T + ': staff log lines naming them', logLinesNaming(path.join(FB, 'moderation.log'), P, id));
  }

  // ---- the game servers, and each copy set aside beside them
  for (const s of a.servers) {
    for (const g of serverSets(s)) {
      const R = g.root, T = g.tag;
      if (!isDir(R)) continue;
      // The form ids of their characters found here, for the release list.
      const A = new Set();
      const worlds = names(R).filter((n) => /^world(-before-.+)?$/i.test(n)).sort();
      for (const w of worlds) {
        const forms = path.join(R, w, 'changeForms');
        const dirs = [forms].concat(names(forms).filter((n) => /^_discarded-/.test(n)).map((n) => path.join(forms, n)));
        for (const dir of dirs) {
          const fl = names(dir);
          if (P.size && fl.indexOf('.pending-batch') >= 0) {
            stop(path.join(dir, '.pending-batch') + ' is an unfinished save, which the server replays at its next start and which could write a character back. ' +
                 'Start that server once and stop it, then run this again. Nothing was changed');
          }
          for (const f of fl) {
            if (!/\.json$/i.test(f) || f[0] === '.') continue;
            const p = path.join(dir, f);
            if (!P.size) continue;
            let o = null;
            try { o = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { left(T + ': change forms that would not parse, so were not read', 1); continue; }
            if (isObj(o) && Number(o.profileId) > 0 && hasP(o.profileId) && !unlinks.has(p)) {
              unlinks.set(p, g.writer);
              removed(T + ': characters' + (w === 'world' && dir === forms ? '' : ' in ' + path.relative(R, dir)), 1);
              // A character made in the world has a form id of its own, no plugin (FormDesc::ToString).
              if (/^[0-9a-f]{1,8}$/i.test(String(o.formDesc || ''))) A.add(parseInt(o.formDesc, 16));
            }
          }
        }
      }
      const priv = path.join(R, 'private'), data = path.join(R, 'data');
      const handled = new Set();
      for (const f of names(priv)) {
        if (!/^characters(-before-.+)?\.json$/i.test(f) && f.toLowerCase() !== 'mod-settings.json') continue;
        const b = json(path.join(priv, f), g.writer);
        handled.add(path.join(priv, f).toLowerCase());
        if (!want(b, 'object') || !isObj(b.value.who)) continue;
        const label = f.toLowerCase() === 'mod-settings.json' ? 'mod menu choices' : 'character cards' + (f.toLowerCase() === 'characters.json' ? '' : ' in ' + f);
        for (const k of Object.keys(b.value.who)) if (hasP(k)) { delete b.value.who[k]; b.dirty = true; removed(T + ': ' + label, 1); }
      }
      const take = json(path.join(priv, 'take-limit.json'), g.writer);
      handled.add(path.join(priv, 'take-limit.json').toLowerCase());
      if (want(take, 'object') && isObj(take.value.counts)) {
        for (const k of Object.keys(take.value.counts)) if (hasP(k.split('|')[0])) { delete take.value.counts[k]; take.dirty = true; removed(T + ': take counts', 1); }
      }
      // The gamemode keeps it in private since #2582; a server folder set aside
      // before that still has it in data, and is the person's record all the same.
      for (const dir of [priv, data]) {
        const lastLeft = json(path.join(dir, 'last-left.json'), g.writer);
        handled.add(path.join(dir, 'last-left.json').toLowerCase());
        if (want(lastLeft, 'object')) {
          for (const k of Object.keys(lastLeft.value)) if (hasP(k)) { delete lastLeft.value[k]; lastLeft.dirty = true; removed(T + ': when they last left', 1); }
        }
      }
      /*
        The game's registers (#2351, Patrick's A of 16 October): the ones the
        gamemode keeps in private are let go by the game server itself, at
        its next start, through each register's own rule, from the list this
        writes beside them (private\deleted-characters.json, the release
        block in game\gamemode.js). So here they are counted, never edited.
        A server that holds something of theirs gets the list: their profile
        ids and the form ids of their characters found here, merged into a
        list still waiting there, with what was already done cleared so every
        part runs for the new ids too. It is written like any other file of
        that server's, so a real run stops the server, writes it and starts
        it again, and the start lets go of it then. A copy set aside gets one
        too, which nothing runs from until it is put back. Every other file
        is counted and left: the old copies in data. The merchant ledger is
        released like the rest, by the purse service at NPC startup (#2652).
      */
      const LIST = 'deleted-characters.json';
      const RELEASED = /^(property|law|beds|farm-claims|embassy|books|dungeon-rewards-ledger|merchant-ledger)\.json$/i;
      handled.add(path.join(priv, LIST).toLowerCase());
      let theirs = 0;
      if (P.size) {
        for (const dir of [priv, data]) {
          for (const f of names(dir).sort()) {
            const p = path.join(dir, f);
            if (!/\.json$/i.test(f) || f[0] === '.' || handled.has(p.toLowerCase())) continue;
            let st; try { st = fs.statSync(p); } catch (e) { continue; }
            if (!st.isFile() || st.size > 64 * 1024 * 1024) continue;
            let v;
            try { v = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); }
            catch (e) { left(T + ': ' + path.relative(R, p) + ' would not parse, so was not read', 1); continue; }
            const n = refs(v, P, id, A);
            if (dir === priv && RELEASED.test(f)) {
              releases(T + ': places in ' + path.relative(R, p) + ' naming their character', n);
              theirs += n;
              if (f.toLowerCase() === 'books.json' && isObj(v) && Array.isArray(v.books)) {
                releases(T + ': faction and business books they own, disbanded unless staff hand them on first',
                         v.books.filter((b) => isObj(b) && hasP(b.owner)).length);
              }
            } else left(T + ': places in ' + path.relative(R, p) + ' naming their character', n);
          }
        }
      }
      if (P.size && (theirs || A.size)) {
        const lf = json(path.join(priv, LIST), g.writer);
        if (!lf.missing && !(isObj(lf.value) && Array.isArray(lf.value.profiles))) {
          stop(lf.p + ' is not a list of deleted characters, so nothing was changed');
        }
        const was = lf.missing ? {} : lf.value;
        const ids = (xs) => (Array.isArray(xs) ? xs : []).map(Number).filter((x) => Number.isSafeInteger(x) && x > 0);
        const profiles = Array.from(new Set(ids(was.profiles).concat(Array.from(P)))).sort((x, y) => x - y);
        const actors = Array.from(new Set(ids(was.actors).concat(Array.from(A)))).sort((x, y) => x - y);
        lf.value = { profiles, actors };
        lf.dirty = true;
        releases(T + ': ' + path.relative(R, lf.p) + ', the list the game server lets go of at its next start', 1);
      }
      for (const lg of [path.join(priv, 'moderation.log'), path.join(R, 'for-bot', 'moderation.log'), path.join(priv, 'door.log')]) {
        held(T + ': staff log lines naming them (' + path.relative(R, lg) + ')', logLinesNaming(lg, P, id));
      }
    }
  }

  // ---- chat, one day file at a time
  for (const v of a.voices) {
    if (!P.size) break;
    const dir = path.join(v.root, 'chat');
    for (const f of names(dir).sort()) {
      if (!/^\d{4}-\d{2}-\d{2}\.jsonl$/.test(f)) continue;
      const p = path.join(dir, f);
      const t = text(p, 'voice:' + v.tag);
      if (!t) continue;
      let inKept = 0;
      const keep = t.lines.filter((line) => {
        let o = null;
        try { o = JSON.parse(line); } catch (e) { return true; }
        if (!(isObj(o) && hasP(o.profileId))) return true;
        const at = Number(o.at) || 0;
        if (keptWindows.some((w) => w.voice === v.tag && w.profile === Number(o.profileId) && at >= w.from && at <= w.to)) { inKept++; return true; }
        return false;
      });
      held(v.tag + ' voice: chat lines in sessions staff marked kept', inKept);
      if (keep.length !== t.lines.length) {
        r.chat.push({ voice: v.tag, file: f, before: t.lines.length, after: keep.length });
        removed(v.tag + ' voice: chat lines', t.lines.length - keep.length);
        t.lines = keep;
        t.dirty = true;
      }
    }
  }

  // ---- the bot: its data folder since #1104, beside the code before that
  const bd = isDir(path.join(a.bot, 'data')) ? path.join(a.bot, 'data') : a.bot;
  const joins = json(path.join(bd, 'joins.json'), 'bot');
  if (want(joins, 'object')) {
    for (const gv of Object.values(joins.value)) {
      if (isObj(gv) && isObj(gv.members) && has(gv.members, id)) { delete gv.members[id]; joins.dirty = true; removed('bot: join number', 1); }
    }
  }
  const tickets = json(path.join(bd, 'open-tickets.json'), 'bot');
  if (want(tickets, 'object')) {
    for (const k of Object.keys(tickets.value)) if (k.split(':').pop() === id) { delete tickets.value[k]; tickets.dirty = true; removed('bot: open ticket', 1); }
  }
  results.push(r);
}

const writers = new Set();
for (const f of files.values()) if (f.dirty && f.writer) writers.add(f.writer);
for (const w of unlinks.values()) if (w) writers.add(w);
for (const t of texts.values()) if (t.dirty && t.writer) writers.add(t.writer);
for (const w of writers) say('WRITER|' + w);
for (const r of results) say('PERSON|' + JSON.stringify(r));

if (a.mode !== 'apply') { say('DONE|plan'); process.exit(0); }

// Each file to a file beside it, then swapped in, so a write that fails half
// way leaves the old file whole. A change that does not take is named.
const failed = [];
function swap(p, body) {
  const tmp = path.join(path.dirname(p), '.' + path.basename(p) + '.delete-person.tmp');
  try { fs.writeFileSync(tmp, body, 'utf8'); fs.renameSync(tmp, p); }
  catch (e) {
    failed.push(p + ' (' + (e.code || e.message) + ')');
    try { fs.unlinkSync(tmp); } catch (e2) { }
  }
}
for (const f of files.values()) {
  if (!f.dirty) continue;
  swap(f.p, JSON.stringify(f.value, null, f.indent || undefined) + (f.eol ? '\n' : ''));
}
for (const [p, t] of texts) {
  if (!t.dirty) continue;
  swap(p, t.lines.length ? t.lines.join('\n') + '\n' : '');
}
for (const p of unlinks.keys()) {
  try { fs.unlinkSync(p); }
  catch (e) { if (e.code !== 'ENOENT') failed.push(p + ' (' + e.code + ')'); }
}
for (const f of failed) say('FAILED|' + f);
say(failed.length ? 'DONE|failed' : 'DONE|apply');
'@

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-delete-person-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work -Force
function Run-Core([string]$mode) {
    $plan = @{
        mode    = $mode
        now     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        people  = @($people | ForEach-Object { @{ discordId = $_.discordId; profiles = @($_.profiles) } })
        site    = $SiteRoot
        servers = @(@{ tag = 'live'; root = $GameRoot }, @{ tag = 'dev'; root = $DevGameRoot })
        voices  = @(@{ tag = 'live'; root = $VoiceRoot }, @{ tag = 'dev'; root = $DevVoiceRoot })
        bot     = $BotRoot
    }
    $af = Join-Path $work ($mode + '.json')
    [IO.File]::WriteAllText($af, (ConvertTo-Json -InputObject $plan -Depth 6), $utf8)
    $cf = Join-Path $work 'core.js'
    [IO.File]::WriteAllText($cf, $core, $utf8)
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $lines = @(& $node $cf $af 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $eap }
    return ,$lines
}
function Show([string[]]$lines, [string]$verb) {
    foreach ($l in $lines) {
        if ($l -notlike 'PERSON|*') { continue }
        $r = $l.Substring(7) | ConvertFrom-Json
        Say ''
        Say ('Discord id ' + $r.discordId + ': ' + @($r.profiles).Count + ' character(s)')
        foreach ($n in @($r.skipped)) { if ($n) { Say ('  left       profile ' + $n + ': another account holds it too, so it is not theirs to delete') } }
        $any = $false
        foreach ($p in $r.removed.PSObject.Properties) { $any = $true; Say ('  {0,-10} {1,6}  {2}' -f $verb, $p.Value, $p.Name) }
        # The game's registers, let go by the game server at its next start (#2351).
        foreach ($p in $r.release.PSObject.Properties) { $any = $true; Say ('  {0,-10} {1,6}  {2}' -f 'release', $p.Value, $p.Name) }
        foreach ($p in $r.held.PSObject.Properties) { $any = $true; Say ('  {0,-10} {1,6}  {2}' -f 'kept', $p.Value, $p.Name) }
        foreach ($p in $r.left.PSObject.Properties) { $any = $true; Say ('  {0,-10} {1,6}  {2}' -f 'left', $p.Value, $p.Name) }
        foreach ($c in @($r.chat)) { if ($c) { Say ('  chat       {0} {1}: {2} lines before, {3} after' -f $c.voice, $c.file, $c.before, $c.after) } }
        if (-not $any) { Say '  nothing of theirs on this box' }
    }
    Say ''
    Say '  Not on this box, so not done here: their Discord tickets (staff delete those in the Discord),'
    Say '  gallery pictures approved before the site kept the sending account (remove theirs in the hub by name),'
    Say '  and the encrypted backups (they expire on their schedule; the record reapplies this after a restore).'
}
# Where a game server was given the list of characters to let go (#2351):
# it does that as it starts, so what to read afterwards, and where.
function Say-Release([string[]]$lines) {
    $at = @()
    foreach ($l in $lines) {
        if ($l -notlike 'PERSON|*') { continue }
        foreach ($p in ($l.Substring(7) | ConvertFrom-Json).release.PSObject.Properties) {
            # A copy set aside starts nowhere until it is put back, and then a restore reapplies the record.
            if ($p.Name -like '*deleted-characters.json*' -and $p.Name -notlike '*set aside*') { $at += ($p.Name -split ':')[0] }
        }
    }
    $at = @($at | Sort-Object -Unique)
    if (-not $at.Count) { return }
    Say ('The game''s registers are let go as each of these starts: ' + ($at -join ', ') + '. Its thornswood.log says release: with the counts, and private\deleted-characters.json is gone once every part is done.')
}
function Stopped([string[]]$lines) {
    $s = @($lines | Where-Object { $_ -like 'STOP|*' } | Select-Object -First 1)
    if ($s.Count) { return $s[0].Substring(5) }
    if (-not @($lines | Where-Object { $_ -like 'DONE|*' }).Count) { return ('node did not finish: ' + (($lines | Select-Object -Last 3) -join ' / ')) }
    return ''
}

# ------------------------------------------------------------- services ---
# What writes each store, by the name the plan uses for it.
$svc = [ordered]@{
    'site'        = @{ Task = 'Thornswood Docs';       Root = $SiteRoot;     Say = 'the site' }
    'server:live' = @{ Task = 'Thornswood Server';     Root = $GameRoot;     Say = 'the live game server'; Online = 3000 }
    'server:dev'  = @{ Task = 'Thornswood Dev Server'; Root = $DevGameRoot;  Say = 'the dev game server';  Online = 7788 }
    'voice:live'  = @{ Task = 'Thornswood Voice';      Root = $VoiceRoot;    Say = 'live voice' }
    'voice:dev'   = @{ Task = 'Thornswood Dev Voice';  Root = $DevVoiceRoot; Say = 'dev voice' }
    'bot'         = @{ Svc  = 'ThornswoodBot';         Root = $BotRoot;      Say = 'the bot' }
}
# The processes running from a folder: node, cmd or python whose command line
# names it, and the node or python each of those started. The trailing
# backslash matters: C:\Thornswood-Server is a prefix of C:\Thornswood-Server-Dev.
function Holders($it) {
    $mark = $it.Root.TrimEnd('\') + '\'
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
    $ids = @()
    foreach ($p in $all) {
        if ($p.Name -match '^(node|cmd|python|pythonw)(\d|\.)*\.exe$' -and $p.CommandLine.IndexOf($mark, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $ids += [int]$p.ProcessId }
    }
    foreach ($p in $all) {
        if ($p.Name -match '^(node|python|pythonw)(\d|\.)*\.exe$' -and $ids -contains [int]$p.ParentProcessId) { $ids += [int]$p.ProcessId }
    }
    return @($ids | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)
}
function Running($it) {
    if ($it.Svc) { $s = Get-Service -Name $it.Svc -ErrorAction SilentlyContinue; if ($s -and $s.Status -ne 'Stopped') { return $true } }
    else { $t = Get-ScheduledTask -TaskName $it.Task -ErrorAction SilentlyContinue; if ($t -and $t.State -eq 'Running') { return $true } }
    return [bool](@(Holders $it).Count)
}

$exit = 0
try {
    $plan = Run-Core 'plan'
    $why = Stopped $plan
    if ($why) { Refuse $why }
    $writers = @($plan | Where-Object { $_ -like 'WRITER|*' } | ForEach-Object { $_.Substring(7) })
    $need = @($svc.Keys | Where-Object { $writers -contains $_ })

    if (-not $Delete) {
        Show $plan 'remove'
        Say ''
        if ($need.Count) { Say ('A real run stops these while it changes their files, then starts them again: ' + (($need | ForEach-Object { $svc[$_].Say }) -join ', ') + '.') }
        Say ('DRY RUN: nothing was changed. Add -Delete' + $(if (-not $Reapply) { ' -By <your name>' } else { '' }) + ' to do it.')
        exit 0
    }

    $stoppedHere = @()
    $watch = 'Thornswood Watch'
    $watchOff = $false
    try {
        if (-not $NoServices -and $need.Count) {
            $busy = @($need | Where-Object { Running $svc[$_] })
            if ($Reapply -and $busy.Count) {
                Refuse ('running: ' + (($busy | ForEach-Object { $svc[$_].Say }) -join ', ') + '. -Reapply is for a restore, before anything starts, and stops nothing. Nothing was changed.')
            }
            foreach ($w in $busy) {
                $it = $svc[$w]
                if (-not $it.Online -or $Now) { continue }
                $n = -1
                try { $n = [int]((Invoke-WebRequest -Uri ('http://127.0.0.1:' + $it.Online + '/online.json') -TimeoutSec 15 -UseBasicParsing).Content | ConvertFrom-Json).now } catch { $n = -1 }
                if ($n -ne 0) {
                    Refuse ($it.Say + ' has ' + $(if ($n -lt 0) { 'an online count that could not be read' } else { "$n online" }) + ', who would be dropped. Run it when nobody is on, or pass -Now. Nothing was changed.')
                }
            }
            if ($busy.Count -and (Get-ScheduledTask -TaskName $watch -ErrorAction SilentlyContinue)) {
                Disable-ScheduledTask -TaskName $watch | Out-Null
                $watchOff = $true
                Say ('disabled  ' + $watch + ', so it starts nothing again while this runs')
            }
            foreach ($w in $busy) {
                $it = $svc[$w]
                if ($it.Svc) { Stop-Service -Name $it.Svc -Force -ErrorAction SilentlyContinue }
                else { Stop-ScheduledTask -TaskName $it.Task -ErrorAction SilentlyContinue }
                # A stopped task does not always take its child with it
                # (vps-freeze.ps1), so whatever still runs from its folder goes too.
                foreach ($id in @(Holders $it)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
                $stoppedHere += $w
                Say ('stopped   ' + $it.Say)
            }
            # Waiting for processes that were ended to be gone, ten seconds at
            # most, then refusing rather than writing under one.
            for ($i = 0; $i -lt 20 -and @($busy | Where-Object { Running $svc[$_] }).Count; $i++) { Start-Sleep -Milliseconds 500 }
            $still = @($busy | Where-Object { Running $svc[$_] })
            if ($still.Count) { Refuse ('still running after being stopped: ' + (($still | ForEach-Object { $svc[$_].Say }) -join ', ') + '. Nothing was changed.') }
        }

        $done = Run-Core 'apply'
        $why = Stopped $done
        if ($why) { Refuse $why }
        Show $done 'removed'
        $failed = @($done | Where-Object { $_ -like 'FAILED|*' } | ForEach-Object { $_.Substring(7) })
        if ($failed.Count) {
            Say ''
            foreach ($f in $failed) { Say ('COULD NOT CHANGE ' + $f) }
            Say 'NOT FINISHED: the files above were not changed and the request is not in the record. Run it again; what is already gone stays gone.'
            $exit = 1
        } elseif ($Reapply) {
            if ($adds.Count) {
                Ensure-RecordFolder
                foreach ($r in $adds) { [IO.File]::AppendAllText($record, $r.line + "`n", $utf8) }
                Say ('merged    ' + $adds.Count + ' request(s) into ' + $record)
            }
            Say ''
            Say ('REAPPLIED: every request in ' + $record + ' is removed again.')
            Say-Release $done
        } else {
            $r = ((@($done | Where-Object { $_ -like 'PERSON|*' }))[0]).Substring(7) | ConvertFrom-Json
            $row = [ordered]@{
                at        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                discordId = $DiscordId
                profiles  = @($r.profiles)
                by        = $By.Trim()
                removed   = $r.removed
                chat      = @($r.chat)
            }
            Ensure-RecordFolder
            [IO.File]::AppendAllText($record, (ConvertTo-Json -InputObject $row -Depth 6 -Compress) + "`n", $utf8)
            Say ''
            Say ('DELETED, and written down in ' + $record + ' so a restore reapplies it. The nightly backup takes the record from tonight.')
            Say-Release $done
        }
    } finally {
        foreach ($w in $stoppedHere) {
            $it = $svc[$w]
            try {
                if ($it.Svc) { Start-Service -Name $it.Svc } else { Start-ScheduledTask -TaskName $it.Task }
                Say ('started   ' + $it.Say)
            } catch { Say ('COULD NOT START ' + $it.Say + ': ' + $_.Exception.Message); $exit = 1 }
        }
        if ($watchOff) {
            try { Enable-ScheduledTask -TaskName $watch | Out-Null; Say ('enabled   ' + $watch) }
            catch { Say ('COULD NOT ENABLE ' + $watch + ': ' + $_.Exception.Message); $exit = 1 }
        }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit $exit
