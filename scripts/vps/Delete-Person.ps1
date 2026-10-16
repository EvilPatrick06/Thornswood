<#
  Delete-Person.ps1

  Carries out a deletion request: finds one person's records in every store on the box by their Discord id, shows the counts, and deletes them only when told to, then writes the request down so a restore reapplies it (issue #2351). Runs ON the VPS, as Administrator, through Remote.ps1.

      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId 123456789012345678'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId 123456789012345678 -Delete -By Patrick'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-Reapply'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-Reapply -Delete'

  WHY. privacy.md promises that a person who asks in the Discord has their
  Discord link, session records, chat and character deleted, by a person,
  and that staff reapply completed requests before an older backup goes back
  into service. Until 12 October nothing did either: no script, no list of
  the stores, and no record of what had been done. Patrick decided on 12
  October (option A on #2351): a staff script that finds, shows counts,
  deletes with a dry run first, and records each request so a restore
  reapplies it.

  A DRY RUN IS THE DEFAULT. Without -Delete nothing is changed, nothing is
  stopped and nothing is written: it prints, for every store, how many of the
  person's records are there and whether a real run removes them or leaves
  them. Counts only, never what a record says and never an address.

  WHAT A REAL RUN REMOVES, the person's own records:
    site data      their Discord link (linked.json), their answer to the
                   rules (rules-accepted.json), their sign-in rows
                   (signins.json, which hold an address), their session rows
                   (sessions.json) and the launcher logs sent with them
                   (session-logs), their characters' rows in roster.json, and
                   the tickets, applications, calls for help, bugs and ideas
                   they sent (for-bot\inbox.json)
    game servers   each character's change form (world\changeForms, live and
                   dev), its card (private\characters.json) and its mod menu
                   choices (private\mod-settings.json)
    voice          every chat line their characters wrote, out of each day's
                   file on live and dev. The voice service never edits a day
                   (voice-server.js): these are the only edits, and the
                   record keeps each file's line count before and after, so
                   an edited day says so
    the bot        their join number (joins.json). The last number given out
                   stays, so nobody is handed theirs again
  Their characters are the profile ids linked.json holds for them, which the
  site checked were theirs. A profile id another account also holds is left
  alone and said.

  WHAT IT LEAVES, counted and said, because each belongs to staff or to
  somebody else (the page: "What cannot be undone is something you said that
  somebody else has already quoted in a report"):
    bans, PKs and staff notes about them (bans.json, pk.json, notes.json),
    the staff logs' lines naming them (moderation.log on the site and on
    each game server), reports they made about somebody else and reports
    made about them (inbox.json), and a session staff marked kept as
    evidence, with its launcher logs. Their gallery submissions are counted
    and removed from the hub, one at a time, which deletes the file.
  Logs that are aged by their own rule (the game servers' server.log, the
  site's) are not edited here.

  A REAL RUN STOPS WHAT WRITES THOSE STORES, and only those. The site, a
  game server, a voice service or the bot each writes its files while it
  runs, so a file changed underneath one is written straight back over (the
  same reason RESTORING.md stops the game server to put one character back).
  So, for each one whose files hold a record to remove: the watchdog is
  disabled first so it starts nothing again, the service is stopped and any
  process still holding its port is ended, the files are changed, and the
  service is started again, then the watchdog. A game server with anybody
  online is refused unless -Now: they would be dropped. A game server with an
  unfinished save (.pending-batch in changeForms) is refused: the engine
  replays it at its next start and could write a deleted character back.
  Every JSON file is read and checked before any is written, and each is
  written to a file beside it and swapped in, the way the site writes its
  own.

  THE RECORD. Each completed request is one line in
  C:\Thornswood-Deletions\requests.jsonl: the Discord id, the profile ids,
  when, who ran it, and the counts it removed. Nothing else about the person.
  The folder is SYSTEM's and Administrators' only, locked when this makes it.
  The nightly backup takes it (deletions\requests.jsonl), so it goes off the
  box with every backup.

  -Reapply reads that record and removes every request in it again: run after
  a backup is put back and before anything starts (Restore-Box.ps1 does, and
  docs\RESTORING.md says when by hand). -Merge names other copies of the
  record (one from a newer backup, or the one inside the backup being put
  back); lines the box's record does not have are added to it first. -Reapply
  never stops anything: it refuses while a service it would write under is
  running, and never adds a line of its own.

  WHAT IT REFUSES.
    - anywhere with SkyrimSE.exe on it, which is the gaming PC, not the VPS
    - a Discord id that is not 17 to 20 digits
    - -Delete without -By, the person running it
    - a JSON file that is there and will not parse: nothing is changed
    - no node on the PATH (the JSON is edited by node, as the site writes it)

  tests\test-2351-delete-person.ps1 runs it against scratch copies of every
  store.

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
  Neither stop nor check any service. Only the tests pass it.
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
function Refuse([string]$m) { Say ('REFUSED: ' + $m); exit 1 }

if (-not $AllowGamingPc -and (Test-Path 'C:\Thornswood\Game\SkyrimSE.exe')) {
    Refuse 'SkyrimSE.exe is here, so this is the gaming PC, not the VPS. Nothing was changed.'
}
# Passed as one word with commas when it comes through powershell -File.
$Merge = @($Merge | ForEach-Object { "$_" -split ',' } | Where-Object { $_ })
if ($Reapply -and $DiscordId) { Refuse '-Reapply takes every request in the record; leave -DiscordId off.' }
if (-not $Reapply) {
    if ($DiscordId -notmatch '^\d{17,20}$') { Refuse '-DiscordId takes a Discord id, 17 to 20 digits. Nothing was changed.' }
    if ($Delete -and -not $By.Trim()) { Refuse '-Delete needs -By, the person running the request, for the record. Nothing was changed.' }
}
if ($Merge.Count -and -not $Reapply) { Refuse '-Merge goes with -Reapply.' }
$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) { Refuse 'node is not on the PATH. Nothing was changed.' }
$node = $node.Source
$record = Join-Path $RecordRoot 'requests.jsonl'
$utf8 = New-Object Text.UTF8Encoding($false)

# The record folder: SYSTEM, Administrators and the account running this,
# nothing inherited and no Users rule, the rule Lock-Folder.ps1 -Only applies.
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
    # Only the access rules are written back, never the audit part (#1120).
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
function Read-Record([string]$file) {
    $rows = @()
    if (-not (Test-Path -LiteralPath $file)) { return ,$rows }
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $n++
        if (-not $line.Trim()) { continue }
        try { $o = $line | ConvertFrom-Json } catch { Refuse ("line $n of $file will not parse. Nothing was changed.") }
        if ("$($o.discordId)" -notmatch '^\d{17,20}$') { Refuse ("line $n of $file has no Discord id. Nothing was changed.") }
        $rows += ,@{ line = $line.Trim(); discordId = "$($o.discordId)"; profiles = @($o.profiles | ForEach-Object { [long]$_ } | Where-Object { $_ -gt 0 }) }
    }
    return ,$rows
}

# ------------------------------------------------------------------ who ---
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
    if ($adds.Count) {
        if ($Delete) {
            Ensure-RecordFolder
            foreach ($r in $adds) { [IO.File]::AppendAllText($record, $r.line + "`n", $utf8) }
            Say ('merged    ' + $adds.Count + ' request(s) the record did not have, into ' + $record)
        } else {
            Say ('merge     ' + $adds.Count + ' request(s) the record does not have would be added to ' + $record)
        }
    }
    $byId = [ordered]@{}
    foreach ($r in @($have) + @($adds)) {
        if (-not $byId.Contains($r.discordId)) { $byId[$r.discordId] = @() }
        $byId[$r.discordId] = @($byId[$r.discordId]) + @($r.profiles)
    }
    foreach ($k in $byId.Keys) { $people += ,@{ discordId = $k; profiles = @($byId[$k] | Sort-Object -Unique) } }
    Say ('record    ' + $people.Count + ' completed request(s) in ' + $record)
    if (-not $people.Count) { Say 'NOTHING TO REAPPLY: the record holds no request.'; exit 0 }
} else {
    $people = @(@{ discordId = $DiscordId; profiles = @() })
}

# ----------------------------------------------------------------- node ---
# The JSON is read and written by node, as the site, the voice service and
# the game server write their own, so a file comes back the shape it went in.
$core = @'
'use strict';
const fs = require('fs'), path = require('path');
const a = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const say = (s) => process.stdout.write(s + '\n');
function stop(m) { say('STOP|' + m); process.exit(2); }

const files = new Map();
function readJson(p, fallback, writer) {
  if (files.has(p)) return files.get(p);
  let t = null;
  try { t = fs.readFileSync(p, 'utf8'); }
  catch (e) {
    if (e.code !== 'ENOENT') stop(p + ' cannot be read (' + e.code + '), so nothing was changed');
  }
  let f;
  if (t === null) f = { p, value: fallback, missing: true, indent: 2, writer, dirty: false };
  else {
    t = t.replace(/^\uFEFF/, '');
    let v;
    try { v = JSON.parse(t); } catch (e) { stop(p + ' will not parse, so nothing was changed'); }
    f = { p, value: v, missing: false, indent: /^[\[{]\s*\r?\n/.test(t) ? 2 : 0, writer, dirty: false };
  }
  files.set(p, f);
  return f;
}
const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
function want(f, kind) {
  const ok = kind === 'array' ? Array.isArray(f.value) : isObj(f.value);
  if (!ok) stop(f.p + ' is not the shape it should be (' + kind + '), so nothing was changed');
}
const texts = new Map();   // path -> { lines, before, after, writer, voice }
const unlinks = [];        // { p, writer }
const writers = new Set();

const people = a.people.map((x) => ({ discordId: String(x.discordId), profiles: (x.profiles || []).map(Number).filter((n) => n > 0) }));
const results = [];

const D = path.join(a.site, 'data');
const FB = path.join(D, 'for-bot');
const linked = readJson(path.join(D, 'linked.json'), {}, 'site'); want(linked, 'object');

for (const person of people) {
  const id = person.discordId;
  const r = { discordId: id, profiles: [], removed: {}, held: {}, chat: [], skipped: [] };
  const removed = (k, n) => { if (n) r.removed[k] = (r.removed[k] || 0) + n; };
  const held = (k, n) => { if (n) r.held[k] = (r.held[k] || 0) + n; };

  // Their characters: the ids linked.json holds for them, and any the record
  // already named. An id another account also holds is not theirs to delete.
  const P = new Set(person.profiles);
  const mine = isObj(linked.value[id]) && Array.isArray(linked.value[id].profiles) ? linked.value[id].profiles : [];
  for (const n of mine) if (Number(n) > 0) P.add(Number(n));
  for (const other of Object.keys(linked.value)) {
    if (other === id || !isObj(linked.value[other]) || !Array.isArray(linked.value[other].profiles)) continue;
    for (const n of linked.value[other].profiles) {
      if (P.has(Number(n))) { P.delete(Number(n)); r.skipped.push(Number(n)); }
    }
  }
  r.profiles = Array.from(P).sort((x, y) => x - y);
  const hasP = (v) => P.has(Number(v));

  // ---- the site
  if (Object.prototype.hasOwnProperty.call(linked.value, id)) { delete linked.value[id]; linked.dirty = true; removed('site: Discord link', 1); }
  const rules = readJson(path.join(D, 'rules-accepted.json'), {}, 'site'); want(rules, 'object');
  if (Object.prototype.hasOwnProperty.call(rules.value, id)) { delete rules.value[id]; rules.dirty = true; removed('site: rules answer', 1); }
  const signins = readJson(path.join(D, 'signins.json'), [], 'site'); want(signins, 'array');
  { const keep = signins.value.filter((x) => !(isObj(x) && String(x.id) === id));
    if (keep.length !== signins.value.length) { removed('site: sign-in rows', signins.value.length - keep.length); signins.value = keep; signins.dirty = true; } }
  const sessions = readJson(path.join(D, 'sessions.json'), [], 'site'); want(sessions, 'array');
  const keptSessions = new Set();
  { const keep = [];
    for (const x of sessions.value) {
      if (isObj(x) && String(x.who) === id) {
        if (x.keep === true) { keep.push(x); keptSessions.add(String(x.session)); held('site: session rows staff marked kept', 1); }
        else removed('site: session rows', 1);
      } else keep.push(x);
    }
    if (keep.length !== sessions.value.length) { sessions.value = keep; sessions.dirty = true; } }
  const slogs = path.join(D, 'session-logs');
  let names = [];
  try { names = fs.readdirSync(slogs); } catch (e) { }
  for (const f of names) {
    if (!/\.json$/.test(f)) continue;
    const p = path.join(slogs, f);
    let set;
    try { set = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { continue; }
    if (!isObj(set) || String(set.who) !== id) continue;
    if (keptSessions.has(String(set.session))) held('site: launcher logs of kept sessions', 1);
    else if (!unlinks.some((u) => u.p === p)) { unlinks.push({ p, writer: 'site' }); removed('site: launcher logs', 1); }
  }
  const roster = readJson(path.join(D, 'roster.json'), { who: {} }, 'site'); want(roster, 'object');
  if (isObj(roster.value.who)) {
    for (const k of Object.keys(roster.value.who)) if (hasP(k)) { delete roster.value.who[k]; roster.dirty = true; removed('site: roster rows', 1); }
  }
  if (isObj(roster.value.servers)) {
    for (const s of Object.keys(roster.value.servers)) {
      const sv = roster.value.servers[s];
      if (!isObj(sv)) continue;
      for (const k of ['checked', 'held']) {
        if (!Array.isArray(sv[k])) continue;
        const keep = sv[k].filter((n) => !hasP(n));
        if (keep.length !== sv[k].length) { sv[k] = keep; roster.dirty = true; }
      }
    }
  }
  const inbox = readJson(path.join(FB, 'inbox.json'), [], 'site'); want(inbox, 'array');
  { const keep = [];
    for (const x of inbox.value) {
      if (!isObj(x)) { keep.push(x); continue; }
      const sent = String(x.discordId || '') === id || hasP(x.profileId);
      const report = x.kind === 'report' || x.ticket === 'report';
      if (sent && !report) { removed('site: tickets, applications and calls for help they sent', 1); continue; }
      keep.push(x);
      if (sent) held('site: reports they made about somebody', 1);
      else if (hasP(x.aboutProfileId)) held('site: reports about them', 1);
    }
    if (keep.length !== inbox.value.length) { inbox.value = keep; inbox.dirty = true; } }
  const bans = readJson(path.join(D, 'bans.json'), {}, 'site'); want(bans, 'object');
  const pk = readJson(path.join(D, 'pk.json'), {}, 'site'); want(pk, 'object');
  const notes = readJson(path.join(D, 'notes.json'), {}, 'site'); want(notes, 'object');
  const keys = [id].concat(r.profiles.map((n) => 'p:' + n));
  for (const k of keys) {
    if (Object.prototype.hasOwnProperty.call(bans.value, k)) held('site: bans', 1);
    if (Array.isArray(notes.value[k])) held('site: staff notes', notes.value[k].length);
  }
  for (const n of r.profiles) if (Object.prototype.hasOwnProperty.call(pk.value, String(n))) held('site: PK records', 1);
  for (const g of ['gallery.json', 'gallery-pending.json']) {
    const gal = readJson(path.join(D, g), [], 'site');
    if (!Array.isArray(gal.value)) continue;
    held('site: gallery submissions (remove each in the hub)', gal.value.filter((x) => isObj(x) && String(x.discordId || '') === id).length);
  }
  // The staff logs, read here and never written.
  const modlogs = [path.join(FB, 'moderation.log')];
  for (const s of a.servers) modlogs.push(path.join(s.root, 'for-bot', 'moderation.log'), path.join(s.root, 'private', 'moderation.log'));
  const nameKeys = ['by', 'who', 'profileId', 'pid', 'profile', 'aboutProfileId'];
  for (const m of modlogs) {
    let t = '';
    try { t = fs.readFileSync(m, 'utf8'); } catch (e) { continue; }
    let n = 0;
    for (const line of t.split(/\r?\n/)) {
      if (!line.trim()) continue;
      let o; try { o = JSON.parse(line); } catch (e) { continue; }
      if (!isObj(o)) continue;
      if (Object.keys(o).some((k) => String(o[k]) === id || (nameKeys.indexOf(k) >= 0 && hasP(o[k])))) n++;
    }
    held('staff logs: lines naming them', n);
  }

  // ---- the game servers
  for (const s of a.servers) {
    const forms = path.join(s.root, 'world', 'changeForms');
    let fl = [];
    try { fl = fs.readdirSync(forms); } catch (e) { }
    if (r.profiles.length && fl.indexOf('.pending-batch') >= 0) {
      stop('the ' + s.tag + ' game server has an unfinished save (' + path.join(forms, '.pending-batch') +
           '), which it replays at its next start and which could write a character back. Start it once and stop it, then run this again. Nothing was changed');
    }
    for (const f of fl) {
      if (!/^\d+\.json$/.test(f)) continue;
      const p = path.join(forms, f);
      let o;
      try { o = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { continue; }
      if (isObj(o) && hasP(o.profileId) && o.isDeleted !== true && !unlinks.some((u) => u.p === p)) {
        unlinks.push({ p, writer: 'server:' + s.tag });
        removed(s.tag + ' game server: characters', 1);
      }
    }
    for (const [file, label] of [['characters.json', 'character cards'], ['mod-settings.json', 'mod menu choices']]) {
      const b = readJson(path.join(s.root, 'private', file), { who: {} }, 'server:' + s.tag); want(b, 'object');
      if (!isObj(b.value.who)) continue;
      for (const k of Object.keys(b.value.who)) if (hasP(k)) { delete b.value.who[k]; b.dirty = true; removed(s.tag + ' game server: ' + label, 1); }
    }
  }

  // ---- chat, one day file at a time
  for (const v of a.voices) {
    const dir = path.join(v.root, 'chat');
    let fl = [];
    try { fl = fs.readdirSync(dir); } catch (e) { }
    for (const f of fl.sort()) {
      if (!/^\d{4}-\d{2}-\d{2}\.jsonl$/.test(f)) continue;
      const p = path.join(dir, f);
      let t = texts.get(p);
      if (!t) {
        const raw = fs.readFileSync(p, 'utf8');
        const lines = raw.split('\n');
        if (lines.length && lines[lines.length - 1] === '') lines.pop();
        t = { lines, before: lines.length, writer: 'voice:' + v.tag, voice: v.tag, file: f };
        texts.set(p, t);
      }
      const keep = t.lines.filter((line) => {
        let o; try { o = JSON.parse(line); } catch (e) { return true; }
        return !(isObj(o) && hasP(o.profileId));
      });
      if (keep.length !== t.lines.length) {
        const gone = t.lines.length - keep.length;
        r.chat.push({ voice: v.tag, file: f, before: t.lines.length, after: keep.length });
        removed(v.tag + ' voice: chat lines', gone);
        t.lines = keep;
        t.dirty = true;
      }
    }
  }

  // ---- the bot's join numbers
  const jp = fs.existsSync(path.join(a.bot, 'data', 'joins.json')) || !fs.existsSync(path.join(a.bot, 'joins.json'))
    ? path.join(a.bot, 'data', 'joins.json') : path.join(a.bot, 'joins.json');
  const joins = readJson(jp, {}, 'bot'); want(joins, 'object');
  for (const g of Object.keys(joins.value)) {
    const gv = joins.value[g];
    if (isObj(gv) && isObj(gv.members) && Object.prototype.hasOwnProperty.call(gv.members, id)) {
      delete gv.members[id]; joins.dirty = true; removed('bot: join number', 1);
    }
  }
  results.push(r);
}

for (const f of files.values()) if (f.dirty) writers.add(f.writer);
for (const u of unlinks) writers.add(u.writer);
for (const t of texts.values()) if (t.dirty) writers.add(t.writer);
for (const w of writers) say('WRITER|' + w);
for (const r of results) say('PERSON|' + JSON.stringify(r));

if (a.mode === 'apply') {
  const swap = (p, body) => {
    const tmp = path.join(path.dirname(p), '.' + path.basename(p) + '.delete-person.tmp');
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(tmp, body, 'utf8');
    fs.renameSync(tmp, p);
  };
  let done = 0;
  try {
    for (const f of files.values()) {
      if (!f.dirty) continue;
      swap(f.p, JSON.stringify(f.value, null, f.indent || undefined)); done++;
    }
    for (const t of texts.values()) {
      if (!t.dirty) continue;
      swap(t.p || '', '');
    }
  } catch (e) { }
  done = 0;
}
'@
# The block above ends early on purpose so a mistake shows; the real apply is
# below, kept apart so the plan half reads on its own.
$core = $core.Substring(0, $core.IndexOf("if (a.mode === 'apply') {")) + @'
if (a.mode === 'apply') {
  const swap = (p, body) => {
    const tmp = path.join(path.dirname(p), '.' + path.basename(p) + '.delete-person.tmp');
    fs.writeFileSync(tmp, body, 'utf8');
    fs.renameSync(tmp, p);
  };
  const failed = [];
  for (const f of files.values()) {
    if (!f.dirty) continue;
    try { swap(f.p, JSON.stringify(f.value, null, f.indent || undefined) + (f.indent ? '\n' : '')); }
    catch (e) { failed.push(f.p + ' (' + (e.code || e.message) + ')'); }
  }
  for (const [p, t] of texts) {
    if (!t.dirty) continue;
    try { swap(p, t.lines.length ? t.lines.join('\n') + '\n' : ''); }
    catch (e) { failed.push(p + ' (' + (e.code || e.message) + ')'); }
  }
  for (const u of unlinks) {
    try { fs.unlinkSync(u.p); }
    catch (e) { if (e.code !== 'ENOENT') failed.push(u.p + ' (' + e.code + ')'); }
  }
  for (const f of failed) say('FAILED|' + f);
  say(failed.length ? 'DONE|failed' : 'DONE|apply');
} else {
  say('DONE|plan');
}
'@

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-delete-person-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work -Force
function Run-Core([string]$mode) {
    $args = @{
        mode    = $mode
        people  = @($people | ForEach-Object { @{ discordId = $_.discordId; profiles = @($_.profiles) } })
        site    = $SiteRoot
        servers = @(@{ tag = 'live'; root = $GameRoot }, @{ tag = 'dev'; root = $DevGameRoot })
        voices  = @(@{ tag = 'live'; root = $VoiceRoot }, @{ tag = 'dev'; root = $DevVoiceRoot })
        bot     = $BotRoot
    }
    $af = Join-Path $work ($mode + '.json')
    [IO.File]::WriteAllText($af, (ConvertTo-Json -InputObject $args -Depth 6), $utf8)
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
        Say ('Discord id ' + $r.discordId + ': ' + @($r.profiles).Count + ' character(s) linked')
        foreach ($n in @($r.skipped)) { if ($n) { Say ('  left      profile ' + $n + ': another account holds it too, so it is not theirs to delete') } }
        $any = $false
        foreach ($p in $r.removed.PSObject.Properties) { $any = $true; Say ('  {0,-9} {1,6}  {2}' -f $verb, $p.Value, $p.Name) }
        foreach ($p in $r.held.PSObject.Properties) { $any = $true; Say ('  {0,-9} {1,6}  {2}' -f 'left', $p.Value, $p.Name) }
        foreach ($c in @($r.chat)) { if ($c) { Say ('  chat      {0} {1}: {2} lines before, {3} after' -f $c.voice, $c.file, $c.before, $c.after) } }
        if (-not $any) { Say '  nothing of theirs on this box' }
    }
}
function Stopped([string[]]$lines) {
    $s = @($lines | Where-Object { $_ -like 'STOP|*' } | Select-Object -First 1)
    if ($s.Count) { return $s[0].Substring(5) }
    if (-not @($lines | Where-Object { $_ -like 'DONE|*' }).Count) { return ('node did not finish: ' + (($lines | Select-Object -Last 3) -join ' / ')) }
    return ''
}

# ------------------------------------------------------------- services ---
$svc = [ordered]@{
    'site'        = @{ Task = 'Thornswood Docs';       Tcp = 3001; Say = 'the site' }
    'server:live' = @{ Task = 'Thornswood Server';     Root = $GameRoot; Online = 3000; Say = 'the live game server' }
    'server:dev'  = @{ Task = 'Thornswood Dev Server'; Root = $DevGameRoot; Online = 7788; Say = 'the dev game server' }
    'voice:live'  = @{ Task = 'Thornswood Voice';      Tcp = 7778; Say = 'live voice' }
    'voice:dev'   = @{ Task = 'Thornswood Dev Voice';  Tcp = 7789; Say = 'dev voice' }
    'bot'         = @{ Svc = 'ThornswoodBot';          Say = 'the bot' }
}
function Holders($it) {
    $ids = @()
    if ($it.Tcp) { $ids += @(Get-NetTCPConnection -LocalPort $it.Tcp -State Listen -EA SilentlyContinue | ForEach-Object { $_.OwningProcess }) }
    if ($it.Root) {
        try {
            $port = [int]((Get-Content -LiteralPath (Join-Path $it.Root 'server-settings.json') -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json).port
            if ($port -gt 0) { $ids += @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue | ForEach-Object { $_.OwningProcess }) }
        } catch { }
    }
    if ($it.Svc) {
        foreach ($p in @(Get-CimInstance Win32_Process -EA SilentlyContinue)) {
            if ($p.CommandLine -and $p.CommandLine -like ('*' + $BotRoot + '*') -and $p.Name -like 'python*') { $ids += $p.ProcessId }
        }
    }
    return @($ids | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)
}
function Running($it) {
    if ($it.Svc) { $s = Get-Service -Name $it.Svc -EA SilentlyContinue; if ($s -and $s.Status -ne 'Stopped') { return $true } }
    else { $t = Get-ScheduledTask -TaskName $it.Task -EA SilentlyContinue; if ($t -and $t.State -eq 'Running') { return $true } }
    return [bool](@(Holders $it).Count)
}

$exit = 0
try {
    $plan = Run-Core 'plan'
    $why = Stopped $plan
    if ($why) { Refuse $why }
    $need = @($plan | Where-Object { $_ -like 'WRITER|*' } | ForEach-Object { $_.Substring(7) })

    if (-not $Delete) {
        Show $plan 'remove'
        Say ''
        if ($need.Count) { Say ('A real run would stop and start again: ' + (($need | ForEach-Object { $svc[$_].Say }) -join ', ') + '.') }
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
                try { $n = [int]((Invoke-WebRequest -Uri ('http://127.0.0.1:' + $it.Online + '/online.json') -TimeoutSec 15 -UseBasicParsing).Content | ConvertFrom-Json).now } catch { }
                if ($n -ne 0) {
                    Refuse ($it.Say + ' has ' + $(if ($n -lt 0) { 'an online count it could not read' } else { "$n online" }) + ', who would be dropped. Run it when nobody is on, or pass -Now. Nothing was changed.')
                }
            }
            if ($busy.Count -and (Get-ScheduledTask -TaskName $watch -EA SilentlyContinue)) {
                Disable-ScheduledTask -TaskName $watch | Out-Null
                Stop-ScheduledTask -TaskName $watch -EA SilentlyContinue
                $watchOff = $true
                Say ('disabled  ' + $watch + ', so it starts nothing again while this runs')
            }
            foreach ($w in $busy) {
                $it = $svc[$w]
                if ($it.Svc) { Stop-Service -Name $it.Svc -Force -EA SilentlyContinue } else { Stop-ScheduledTask -TaskName $it.Task -EA SilentlyContinue }
                # A stopped task does not always take its child with it
                # (vps-freeze.ps1): the process on its port goes too.
                foreach ($id in @(Holders $it)) { Stop-Process -Id $id -Force -EA SilentlyContinue }
                $stoppedHere += $w
                Say ('stopped   ' + $it.Say)
            }
            # Waiting for a process that was ended to be gone, not for a race.
            for ($i = 0; $i -lt 20 -and @($busy | Where-Object { Running $svc[$_] }).Count; $i++) { Start-Sleep -Milliseconds 500 }
            $left = @($busy | Where-Object { Running $svc[$_] })
            if ($left.Count) { Refuse ('still running after being stopped: ' + (($left | ForEach-Object { $svc[$_].Say }) -join ', ') + '. Nothing was changed.') }
        }

        $done = Run-Core 'apply'
        $why = Stopped $done
        if ($why) { Refuse $why }
        Show $done $(if ($Reapply) { 'removed' } else { 'removed' })
        $failed = @($done | Where-Object { $_ -like 'FAILED|*' } | ForEach-Object { $_.Substring(7) })
        if ($failed.Count) {
            Say ''
            foreach ($f in $failed) { Say ('COULD NOT CHANGE ' + $f) }
            Say 'NOT FINISHED: the files above were not changed and the request is not in the record. Run it again; what is already gone stays gone.'
            $exit = 1
        } elseif ($Reapply) {
            Say ''
            Say ('REAPPLIED: every request in ' + $record + ' is removed again.')
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
            Say ('DELETED, and written down in ' + $record + ' so a restore reapplies it.')
        }
    } finally {
        foreach ($w in $stoppedHere) {
            $it = $svc[$w]
            try {
                if ($it.Svc) { Start-Service -Name $it.Svc } else { Start-ScheduledTask -TaskName $it.Task }
                Say ('started   ' + $it.Say)
            } catch { Say ('COULD NOT START ' + $it.Say + ': ' + $_.Exception.Message) }
        }
        if ($watchOff) {
            try { Enable-ScheduledTask -TaskName $watch | Out-Null; Say ('enabled   ' + $watch) }
            catch { Say ('COULD NOT ENABLE ' + $watch + ': ' + $_.Exception.Message) }
        }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}
exit $exit
