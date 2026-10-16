<#
  vps-nightly-backup.ps1

  Runs on the VPS, once a night, as the scheduled task that Install-Backup.ps1
  puts there. Not meant to be run from this machine; Install-Backup.ps1 sends
  it up and Fetch-Backups.ps1 brings the results down.

  What it takes, and why each one:
    world                 the characters. Every person who plays here is a
                          change form in that folder and nowhere else. It is
                          about 2 MB. This is the only thing here that people
                          would grieve over.
    private               the door list, who is allowed in, the door log
    data                  the door's own records and the online count
    server-settings.json  the port, the name, the load order
    gamemode.js           so a restore is a working server and not a puzzle
    the site's uploads    the gallery's pictures and what staff put up;
                          every upload, including larger recordings
    the feed's store      each channel's version.json, published.json,
                          launchers.txt, releases.txt and history, not assets
    the site's data       linked Discord accounts, the boards, the documents
    the bot's config      bot.env.json
    the bot's join record joins.json, which arrival each person was
    the deletion record   requests.jsonl, every deletion request carried out
                          (Delete-Person.ps1, #2351), so a restore reapplies
                          them before anything starts
    the Caddyfile         whatever is answering on 443 for thornswood.net

    the dev server        its world, private, data, server-settings.json and
                          gamemode.js, under game-dev. Since issue #401: dev
                          is where new work is tested before it goes live, so
                          the characters there are somebody's afternoon too,
                          and it is a few MB.

  What it leaves: node_modules, the installer under the site's public folder,
  the dev voice service, and anything over the size cap. All of those come
  back from the repo. Uploads are always taken in full.

  The server writes world while this runs, so a file can be caught half
  written. Every .json taken from a world folder is read back, and one that
  does not parse is copied again a moment later; one that still does not is
  counted as torn in the log and in NOTES.txt, so a backup that caught the
  server mid-save says so instead of looking whole.

  Encrypted, because the point of a backup is that it lives somewhere other
  than the box, and everything above is either somebody's account or a
  password. AES-256-CBC with an HMAC-SHA256 over the ciphertext, the key
  stretched out of a passphrase with PBKDF2. The passphrase lives in a file
  whose location is set below and never appears in this script, in the task
  definition, or in the log.

  Kept: seven daily and four weekly. A weekly is whichever run lands on a
  Sunday. Nothing else is deleted, ever, including anything a person put in
  that folder by hand.

  Restoring one is docs\RESTORING.md, which is also how you check that any of
  this works. A backup nobody has restored is a guess.
#>
[CmdletBinding()]
param(
  [string]$GameRoot   = 'C:\Thornswood-Server',
  [string]$DevGameRoot = 'C:\Thornswood-Server-Dev',
  [string]$SiteRoot  = 'C:\Thornswood-Docs',
  [string]$BotRoot    = 'C:\Thornswood-Bot',
  [string]$CaddyRoot  = 'C:\Thornswood-Caddy',
  [string]$VoiceRoot  = 'C:\Thornswood-Voice',
  # The record of completed deletion requests (Delete-Person.ps1, #2351).
  [string]$DeletionRoot = 'C:\Thornswood-Deletions',
  [string]$Out        = 'C:\Thornswood-Backup',
  # The passphrase. Created by Install-Backup.ps1 if it is not already there,
  # and the one thing in all of this that has to be kept somewhere else as
  # well: lose it and the backups are noise.
  [string]$KeyFile    = 'C:\Thornswood-Backup\key.txt',
  [int]$KeepDaily     = 7,
  [int]$KeepWeekly    = 4,
  # Per file. The installer is the only thing that goes near it.
  [int]$MaxFileMB     = 200,
  # Warn at this total size, but always take every upload. Kept as an option
  # for existing tasks; it no longer discards larger recordings.
  [int]$MaxUploadsMB  = 300,
  # Take the copy but do not encrypt it. For working out what is wrong, never
  # for a backup that is kept.
  [switch]$Plain
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log   = Join-Path $Out 'backup.log'

function Note($m) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
  Write-Host $line
  try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
}

$pass = $null
if (-not $Plain) {
  if (-not (Test-Path -LiteralPath $KeyFile)) { throw 'No backup passphrase file. No archive was created.' }
  # "$()": an empty file reads as $null (even through [string](...)), and a method on $null throws. Without it the
  # line below, which says the file is empty, was never reached.
  $pass = ("$(Get-Content -LiteralPath $KeyFile -Raw)").Trim()
  if (-not $pass) { throw 'The backup passphrase file is empty. No archive was created.' }
}

if (-not (Test-Path $Out)) { [void](New-Item -ItemType Directory -Path $Out -Force) }
Note "---- nightly backup $stamp ----"

# ---------------------------------------------------------------- gather ----
$ownedStage = Join-Path $env:TEMP ("thornswood-backup-" + $stamp + "-" + [Guid]::NewGuid().ToString("N"))
$ownedStage = [IO.Path]::GetFullPath($ownedStage)
$stageRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd("\") + "\"
if (-not $ownedStage.StartsWith($stageRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Backup stage is outside TEMP." }
$stage = Join-Path $ownedStage 'payload'
$zip = Join-Path $ownedStage 'archive.zip'
$archive = Join-Path $Out ("thornswood-$stamp.zip")
$stageOwned = $false
$cap = $MaxFileMB * 1MB
$took = 0
$skipped = 0

try {
  [void](New-Item -ItemType Directory -Path $ownedStage)
  $stageOwned = $true
  # The temporary copies include credentials. Restrict access before copying
  # any data; descendants inherit this ACL even when TEMP is shared.
  $acl = [Security.AccessControl.DirectorySecurity]::new()
  $acl.SetAccessRuleProtection($true, $false)
  $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  foreach ($sid in @($currentSid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    [void]$acl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $ownedStage -AclObject $acl
  [void](New-Item -ItemType Directory -Path $stage)
function Grab($from, $to, [switch]$Complete) {
  if (-not (Test-Path -LiteralPath $from)) { Note "  missing   $from"; return }
  $dest = Join-Path $stage $to
  $item = Get-Item -LiteralPath $from
  if (-not $item.PSIsContainer) {
    if (-not $Complete -and $item.Length -gt $cap) { Note ("  too big   $from"); $script:skipped++; return }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    Copy-Item -LiteralPath $from -Destination $dest -Force
    $script:took++
    return
  }
  $n = 0
  # Listed from the long path. $from may be the short 8.3 form, and
  # FullName is not: cutting by the short length takes the wrong relative
  # path (issue #1156).
  $listedFrom = $item.FullName
  foreach ($f in (Get-ChildItem -LiteralPath $listedFrom -Recurse -File -EA $(if ($Complete) { "Stop" } else { "SilentlyContinue" }))) {
    if ($f.FullName -match '\\node_modules\\') { continue }
    if (-not $Complete -and $f.Length -gt $cap) { $script:skipped++; continue }
    $rel = $f.FullName.Substring($listedFrom.Length).TrimStart('\')
    $d = Join-Path $dest $rel
    $parent = Split-Path -Parent $d
    if (-not (Test-Path $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    # The server writes into world while this runs. A file that moves under us
    # is one character, and stopping the whole backup over it would be worse
    # than missing it, so it is counted and the rest carries on.
    try {
      if ($Complete) {
        # Hold the source against concurrent writing for this copy. A busy or
        # unreadable upload fails the run instead of making a partial archive.
        $inputFile = $null; $outputFile = $null
        try {
          $inputFile = [IO.File]::Open($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
          $outputFile = [IO.File]::Create($d)
          $inputFile.CopyTo($outputFile)
          if ($outputFile.Length -ne $inputFile.Length) { throw 'Incomplete upload copy.' }
        } finally {
          if ($null -ne $outputFile) { $outputFile.Dispose() }
          if ($null -ne $inputFile) { $inputFile.Dispose() }
        }
      } else { Copy-Item -LiteralPath $f.FullName -Destination $d -Force }
      $n++
    }
    catch { if ($Complete) { throw }; $script:skipped++ }
  }
  $script:took += $n
  Note ("  {0,-42} {1} files" -f $to, $n)
}

# A world file the server was halfway through writing when it was copied.
# Read back every .json taken from a world folder; one that does not parse
# is copied again after a moment, and one that still does not is counted.
$torn = @{}
function Mend($from, $to) {
  $dest = Join-Path $stage $to
  if (-not (Test-Path -LiteralPath $dest)) { return }
  $bad = 0
  # $dest is under TEMP. TEMP is often the short 8.3 form, and the
  # file's FullName is the long one. Cut off that long path, the string
  # the files were listed from (issue #1156).
  $destListed = (Get-Item -LiteralPath $dest).FullName
  foreach ($f in (Get-ChildItem -LiteralPath $destListed -Recurse -File -Filter *.json -EA SilentlyContinue)) {
    $ok = $false
    for ($try = 0; $try -lt 3 -and -not $ok; $try++) {
      try { [void]((Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8) | ConvertFrom-Json); $ok = $true }
      catch {
        Start-Sleep -Milliseconds 400
        $src = Join-Path $from $f.FullName.Substring($destListed.Length).TrimStart('\')
        try { Copy-Item -LiteralPath $src -Destination $f.FullName -Force } catch { }
      }
    }
    if (-not $ok) { $bad++ }
  }
  $script:torn[$to] = $bad
  if ($bad) { Note ("  TORN      {0}: {1} file(s) would not parse after three copies" -f $to, $bad) }
}

# How many people a world folder holds: the change forms named with a bare
# number are character slots (scripts\ops\Reset-Character.ps1 reads them the
# same way), everything else in there describes the world. A deleted
# character keeps its slot with profileId -1 and isDeleted true, so only a
# slot with a profile id that is not deleted is a person (#401: the first
# rehearsal found 18 slots on live and 11 people).
function People($to) {
  $forms = Join-Path $stage ($to + '\changeForms')
  if (-not (Test-Path -LiteralPath $forms)) { return 0 }
  $n = 0
  foreach ($f in @(Get-ChildItem -LiteralPath $forms -File -Filter *.json -EA SilentlyContinue |
                   Where-Object { $_.BaseName -match '^[0-9]+$' })) {
    try { $o = [IO.File]::ReadAllText($f.FullName) -replace '^\uFEFF', '' | ConvertFrom-Json } catch { continue }
    if ($null -ne $o.profileId -and [long]$o.profileId -gt 0 -and $o.isDeleted -ne $true) { $n++ }
  }
  return $n
}

# The live server, then the dev one, the same five things from each.
$servers = @(@{ Root = $GameRoot; Tag = 'game' }, @{ Root = $DevGameRoot; Tag = 'game-dev' })
foreach ($sv in $servers) {
  Grab (Join-Path $sv.Root 'world')                ($sv.Tag + '\world')
  Mend (Join-Path $sv.Root 'world')                ($sv.Tag + '\world')
  Grab (Join-Path $sv.Root 'private')              ($sv.Tag + '\private')
  Grab (Join-Path $sv.Root 'data')                 ($sv.Tag + '\data')
  Grab (Join-Path $sv.Root 'server-settings.json') ($sv.Tag + '\server-settings.json')
  Grab (Join-Path $sv.Root 'gamemode.js')          ($sv.Tag + '\gamemode.js')
}
Grab (Join-Path $SiteRoot 'data')                 'site\data'
Grab (Join-Path $SiteRoot 'config.json')          'site\config.json'
# Issue #454: a restore onto a new box came back without these. uploads is
# the gallery's pictures and everything staff put up through the site, which
# gallery.json in data only names. The feed's store is each channel's
# version.json, the baseline the next Ship compares against, the launcher and
# release lists and their history (#907), which live nowhere else since the
# releases repository went. Not the feed's assets: they are every release's
# downloads, and Remirror-Site-Feed.ps1 sends them again from the machine that
# shipped them.
# The old budget omitted larger recordings. Encryption now streams, so size
# is an advisory warning rather than permission to lose gallery media.
$up = Join-Path $SiteRoot 'uploads'
$upBytes = 0
if (Test-Path -LiteralPath $up) {
  $upBytes = (Get-ChildItem -LiteralPath $up -Recurse -File -EA Stop | Measure-Object Length -Sum).Sum
}
if ($upBytes -gt ([long]$MaxUploadsMB * 1MB)) {
  Note ('  uploads exceed the advisory threshold of ' + $MaxUploadsMB + ' MB; every file will be taken')
}
Grab $up 'site\uploads' -Complete
foreach ($feed in 'feed', 'feed-dev') {
  foreach ($n in 'version.json', 'published.json', 'launchers.txt', 'releases.txt', 'history') {
    Grab (Join-Path $SiteRoot "$feed\$n")         "site\$feed\$n"
  }
}
# bot.env.json, not config.json. The first nightly run reported the bot config
# missing because this asked for a name the bot has never used.
Grab (Join-Path $BotRoot  'bot.env.json')         'bot\bot.env.json'
# joins.json is which arrival each person was, written by the bot on every
# join since the join card fix (#318). Without it a restored bot has no
# numbers to go on: the next card is numbered from the member count, which is
# how two cards came to say "The 28th to walk in", and anybody coming back is
# given a new number. Only Backup-Server.ps1, which takes the whole bot
# folder, had it until 24 September. A bot that has seen no join since that
# fix has none yet, and that is a "missing" line, not a failure. In the
# bot's data folder since #1104; beside the code on a box whose bot install
# is older. The name in the backup stays bot\joins.json either way.
$joins = Join-Path $BotRoot 'data\joins.json'
if (-not (Test-Path -LiteralPath $joins) -and (Test-Path -LiteralPath (Join-Path $BotRoot 'joins.json'))) { $joins = Join-Path $BotRoot 'joins.json' }
Grab $joins                                       'bot\joins.json'
# Every deletion request carried out (#2351). A backup put back holds the
# people who asked before it was taken; this line is how a restore knows to
# remove them again, and the copy here is the one that survives the box.
# A box where nobody has asked yet has none, and that is a "missing" line.
Grab (Join-Path $DeletionRoot 'requests.jsonl')  'deletions\requests.jsonl'
# THE CHARACTER REGISTER IS GONE, 23 September, and so are the two files this
# used to fetch for it: secret.txt, the shared secret it checked against, and
# owners.json, the register itself. Nothing reads either any more, so backing
# them up would be backing up a secret with no reader, which is worse than
# having neither.
#
# token-key.txt is still deliberately not here, for its own reason: it makes
# itself on first run and losing it only expires join tokens that were good
# for an hour anyway.
# Whatever is terminating TLS. RESTORING.md needs it on a fresh box.
Grab (Join-Path $CaddyRoot 'Caddyfile')           'web\Caddyfile'
# What was running and how, so a restore onto a fresh box is not archaeology.
$notes = @("taken    $stamp", "host     $env:COMPUTERNAME", "windows  $([Environment]::OSVersion.Version)", '', 'scheduled tasks:')
foreach ($t in (Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskName -match 'Thornswood' } | Sort-Object TaskName)) {
  $notes += ("  {0,-30} {1}" -f $t.TaskName, $t.State)
}
# What is in it, said where Restore-Backup.ps1 prints it. The private files
# are named one by one because each is a different thing lost: the character
# cards, the mod menu choices, the take limits, and the door and its list.
$notes += ''
foreach ($sv in $servers) {
  $n = People ($sv.Tag + '\world')
  $t = 0; if ($torn.ContainsKey($sv.Tag + '\world')) { $t = $torn[$sv.Tag + '\world'] }
  $notes += ("{0,-9}{1} character(s), {2} torn world file(s), from {3}" -f $sv.Tag, $n, $t, $sv.Root)
  Note ("  {0,-42} {1} character(s)" -f ($sv.Tag + '\world'), $n)
  $have = @(); $lack = @()
  foreach ($p in 'characters.json', 'mod-settings.json', 'take-limit.json', 'door.json', 'allowed.json') {
    if (Test-Path -LiteralPath (Join-Path $stage ($sv.Tag + '\private\' + $p))) { $have += $p } else { $lack += $p }
  }
  $notes += ('         private has: ' + $(if ($have.Count) { $have -join ', ' } else { 'none of them' }))
  if ($lack.Count) { $notes += ('         private lacks: ' + ($lack -join ', ')) }
}
$notes += ''
$notes += 'this backup does NOT contain: node_modules, the installer, the'
$notes += 'Skyrim data files. All of those come back from the repo.'
Set-Content -LiteralPath (Join-Path $stage 'NOTES.txt') -Value ($notes -join "`r`n") -Encoding UTF8

Note "  $took files taken, $skipped skipped"
if ($took -eq 0) { Note '  NOTHING WAS TAKEN. Stopping rather than writing an empty backup.'; Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue; exit 1 }

# ------------------------------------------------------------------ zip ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Remove-Item -LiteralPath $stage -Recurse -Force
$zipMB = [math]::Round((Get-Item $zip).Length / 1MB, 2)
Note "  zipped    $([IO.Path]::GetFileName($zip))  $zipMB MB"

# -------------------------------------------------------------- encrypt ----
if ($Plain) {
  # File.Move refuses an existing destination. Never overwrite an earlier run
  # or let failure cleanup remove an archive that this run did not create.
  [IO.File]::Move($zip, $archive)
  Note '  NOT ENCRYPTED, -Plain was passed. This does not belong anywhere but here.'
} else {
  $enc = $archive + '.enc'
  $partial = $enc + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
  $rng = $null; $kdf = $null; $aes = $null; $hmac = $null
  $inputFile = $null; $outputFile = $null; $cryptoStream = $null; $encryptor = $null
  $partialOwned = $false; $operationFailure = $null
  try {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16; $rng.GetBytes($salt)
    $iv = New-Object byte[] 16; $rng.GetBytes($iv)
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($pass, $salt, 200000, [Security.Cryptography.HashAlgorithmName]::SHA256)
    $kEnc = $kdf.GetBytes(32); $kMac = $kdf.GetBytes(32)
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $kEnc; $aes.IV = $iv
    $outputFile = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $partialOwned = $true
    $magic = [Text.Encoding]::ASCII.GetBytes('TSBK1')
    $outputFile.Write($magic, 0, 5); $outputFile.Write($salt, 0, 16); $outputFile.Write($iv, 0, 16)
    $encryptor = $aes.CreateEncryptor()
    $cryptoStream = [Security.Cryptography.CryptoStream]::new($outputFile, $encryptor, [Security.Cryptography.CryptoStreamMode]::Write, $true)
    $inputFile = [IO.File]::OpenRead($zip)
    $inputFile.CopyTo($cryptoStream); $cryptoStream.FlushFinalBlock()
    $cryptoStream.Dispose(); $cryptoStream = $null
    $inputFile.Dispose(); $inputFile = $null
    # Same TSBK1 signature as existing archives: salt, IV and ciphertext.
    # A second bounded pass authenticates the ciphertext, never the plaintext.
    $hmac = [Security.Cryptography.HMACSHA256]::new($kMac)
    $outputFile.Position = 5
    $left = $outputFile.Length - 5
    $chunk = New-Object byte[] 1MB
    while ($left -gt 0) {
      $n = $outputFile.Read($chunk, 0, [int][Math]::Min([long]$chunk.Length, [long]$left))
      if ($n -eq 0) { throw 'Encrypted archive ended before its signature was complete.' }
      [void]$hmac.TransformBlock($chunk, 0, $n, $chunk, 0); $left -= $n
    }
    [void]$hmac.TransformFinalBlock([byte[]]@(), 0, 0)
    $mac = $hmac.Hash; $outputFile.Write($mac, 0, $mac.Length)
    $outputFile.Flush($true); $outputFile.Dispose(); $outputFile = $null
    [IO.File]::Move($partial, $enc)
    Note "  encrypted $([IO.Path]::GetFileName($enc))  $([math]::Round((Get-Item $enc).Length / 1MB, 2)) MB"
  } catch { $operationFailure = $_; throw } finally {
    $cleanupFailure = $null
    foreach ($resource in @($cryptoStream, $encryptor, $inputFile, $outputFile, $hmac, $aes, $kdf, $rng)) {
      if ($null -ne $resource) {
        try { $resource.Dispose() } catch { if (-not $cleanupFailure) { $cleanupFailure = $_ } }
      }
    }
    if ($partialOwned -and (Test-Path -LiteralPath $partial)) {
      try { Remove-Item -LiteralPath $partial -Force } catch { if (-not $cleanupFailure) { $cleanupFailure = $_ } }
    }
    if ($cleanupFailure -and -not $operationFailure) { throw $cleanupFailure }
  }
}

# ------------------------------------------------------------ retention ----
# A weekly is a run that landed on a Sunday. Everything is matched by name, so
# nothing anybody put in this folder by hand is ever considered.
$all = Get-ChildItem -LiteralPath $Out -File |
       Where-Object { $_.Name -match '^thornswood-(\d{8})-(\d{6})\.zip(\.enc)?$' } |
       Sort-Object Name -Descending
$weekly = @(); $daily = @()
foreach ($f in $all) {
  $d = [datetime]::ParseExact($f.Name.Substring(11, 8), 'yyyyMMdd', $null)
  if ($d.DayOfWeek -eq 'Sunday') { $weekly += $f } else { $daily += $f }
}
$drop = @()
if ($daily.Count  -gt $KeepDaily)  { $drop += $daily[$KeepDaily..($daily.Count - 1)] }
if ($weekly.Count -gt $KeepWeekly) { $drop += $weekly[$KeepWeekly..($weekly.Count - 1)] }
# A copy that will not delete is said, by name and the kind of error, never
# logged as dropped (#2354). It used to be Remove-Item -EA SilentlyContinue
# and then "dropped" whatever happened, so a copy past the seven daily and
# four weekly that site/data/site/privacy.md promises could stay with the log
# saying it went. The names that would not go are written to
# retention-failed.txt beside the backups, which Watch-Services.ps1 reads and
# says, and the task ends non-zero so its last result says so too. The file
# goes again on the first run where every drop went.
$stuck = @()
foreach ($f in $drop) {
  try {
    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $f.FullName) { throw [IO.IOException]::new('still there after the delete') }
    Note "  dropped   $($f.Name)"
  } catch {
    $ex = $_.Exception
    $kind = $ex.GetType().Name
    if ($ex.HResult) { $kind += (' 0x{0:X8}' -f $ex.HResult) }
    $stuck += ($f.Name + '|' + $kind)
    Note "  NOT DROPPED $($f.Name): $kind. It is past the seven daily and four weekly kept and is still here."
  }
}
$failedList = Join-Path $Out 'retention-failed.txt'
if ($stuck.Count) {
  Set-Content -LiteralPath $failedList -Value ($stuck -join "`r`n") -Encoding UTF8
} elseif (Test-Path -LiteralPath $failedList) {
  Remove-Item -LiteralPath $failedList -Force -ErrorAction Stop
  Note '  every copy past retention went this time, so retention-failed.txt is gone'
}
Note ("  kept      {0} daily, {1} weekly" -f [Math]::Min($daily.Count, $KeepDaily), [Math]::Min($weekly.Count, $KeepWeekly))
if ($stuck.Count) {
  throw ("Retention failed: {0} backup(s) past the seven daily and four weekly would not delete (listed in {1}). Tonight's backup itself was made." -f $stuck.Count, $failedList)
}
Note '  done. Fetch-Backups.ps1 on the other machine is what gets these off this box.'

} finally {
  if ($stageOwned -and (Test-Path -LiteralPath $ownedStage)) { Remove-Item -LiteralPath $ownedStage -Recurse -Force }
}
