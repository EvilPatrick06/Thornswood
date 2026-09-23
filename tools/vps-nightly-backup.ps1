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
    the site's data       linked Discord accounts, the boards, the documents
    the bot's config      bot.env.json, and the voice service's choices.json
    the Caddyfile         whatever is answering on 443 for thornswood.net

  What it leaves: node_modules, the installer under the site's public folder,
  and anything over the size cap. All of those come back from the repo.

  Encrypted, because the point of a backup is that it lives somewhere other
  than the box, and everything above is either somebody's account or a
  password. AES-256-CBC with an HMAC-SHA256 over the ciphertext, the key
  stretched out of a passphrase with PBKDF2. The passphrase lives in a file
  whose location is set below and never appears in this script, in the task
  definition, or in the log.

  Kept: seven daily and four weekly. A weekly is whichever run lands on a
  Sunday. Nothing else is deleted, ever, including anything a person put in
  that folder by hand.

  Restoring one is tools\RESTORING.md, which is also how you check that any of
  this works. A backup nobody has restored is a guess.
#>
[CmdletBinding()]
param(
  [string]$GameRoot   = 'C:\Thornswood-Server',
  [string]$SiteRoot   = 'C:\Thornswood-Docs',
  [string]$BotRoot    = 'C:\Thornswood-Bot',
  [string]$CaddyRoot  = 'C:\Thornswood-Caddy',
  [string]$VoiceRoot  = 'C:\Thornswood-Voice',
  [string]$Out        = 'C:\Thornswood-Backup',
  # The passphrase. Created by Install-Backup.ps1 if it is not already there,
  # and the one thing in all of this that has to be kept somewhere else as
  # well: lose it and the backups are noise.
  [string]$KeyFile    = 'C:\Thornswood-Backup\key.txt',
  [int]$KeepDaily     = 7,
  [int]$KeepWeekly    = 4,
  # Per file. The installer is the only thing that goes near it.
  [int]$MaxFileMB     = 200,
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

if (-not (Test-Path $Out)) { [void](New-Item -ItemType Directory -Path $Out -Force) }
Note "---- nightly backup $stamp ----"

# ---------------------------------------------------------------- gather ----
$stage = Join-Path $env:TEMP ("thornswood-backup-" + $stamp)
[void](New-Item -ItemType Directory -Path $stage -Force)
$cap = $MaxFileMB * 1MB
$took = 0
$skipped = 0

function Grab($from, $to) {
  if (-not (Test-Path -LiteralPath $from)) { Note "  missing   $from"; return }
  $dest = Join-Path $stage $to
  $item = Get-Item -LiteralPath $from
  if (-not $item.PSIsContainer) {
    if ($item.Length -gt $cap) { Note ("  too big   $from"); $script:skipped++; return }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    Copy-Item -LiteralPath $from -Destination $dest -Force
    $script:took++
    return
  }
  $n = 0
  foreach ($f in (Get-ChildItem -LiteralPath $from -Recurse -File -EA SilentlyContinue)) {
    if ($f.FullName -match '\\node_modules\\') { continue }
    if ($f.Length -gt $cap) { $script:skipped++; continue }
    $rel = $f.FullName.Substring($item.FullName.Length).TrimStart('\')
    $d = Join-Path $dest $rel
    $parent = Split-Path -Parent $d
    if (-not (Test-Path $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    # The server writes into world while this runs. A file that moves under us
    # is one character, and stopping the whole backup over it would be worse
    # than missing it, so it is counted and the rest carries on.
    try { Copy-Item -LiteralPath $f.FullName -Destination $d -Force; $n++ }
    catch { $script:skipped++ }
  }
  $script:took += $n
  Note ("  {0,-42} {1} files" -f $to, $n)
}

Grab (Join-Path $GameRoot 'world')                'game\world'
Grab (Join-Path $GameRoot 'private')              'game\private'
Grab (Join-Path $GameRoot 'data')                 'game\data'
Grab (Join-Path $GameRoot 'server-settings.json') 'game\server-settings.json'
Grab (Join-Path $GameRoot 'gamemode.js')          'game\gamemode.js'
Grab (Join-Path $SiteRoot 'data')                 'site\data'
Grab (Join-Path $SiteRoot 'config.json')          'site\config.json'
# bot.env.json, not config.json. The first nightly run reported the bot config
# missing because this asked for a name the bot has never used.
Grab (Join-Path $BotRoot  'bot.env.json')         'bot\bot.env.json'
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
Grab (Join-Path $VoiceRoot 'choices.json')        'voice\choices.json'

# What was running and how, so a restore onto a fresh box is not archaeology.
$notes = @("taken    $stamp", "host     $env:COMPUTERNAME", "windows  $([Environment]::OSVersion.Version)", '', 'scheduled tasks:')
foreach ($t in (Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskName -match 'Thornswood' } | Sort-Object TaskName)) {
  $notes += ("  {0,-30} {1}" -f $t.TaskName, $t.State)
}
$notes += ''
$notes += 'this backup does NOT contain: node_modules, the installer, the'
$notes += 'Skyrim data files. All of those come back from the repo.'
Set-Content -LiteralPath (Join-Path $stage 'NOTES.txt') -Value ($notes -join "`r`n") -Encoding UTF8

Note "  $took files taken, $skipped skipped"
if ($took -eq 0) { Note '  NOTHING WAS TAKEN. Stopping rather than writing an empty backup.'; Remove-Item $stage -Recurse -Force -EA SilentlyContinue; exit 1 }

# ------------------------------------------------------------------ zip ----
$zip = Join-Path $Out ("thornswood-$stamp.zip")
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Remove-Item $stage -Recurse -Force -EA SilentlyContinue
$zipMB = [math]::Round((Get-Item $zip).Length / 1MB, 2)
Note "  zipped    $([IO.Path]::GetFileName($zip))  $zipMB MB"

# -------------------------------------------------------------- encrypt ----
if ($Plain) {
  Note '  NOT ENCRYPTED, -Plain was passed. This does not belong anywhere but here.'
} else {
  if (-not (Test-Path -LiteralPath $KeyFile)) {
    Note "  NO PASSPHRASE AT $KeyFile. The zip is left in the clear; fix this."
  } else {
    $pass = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
    if (-not $pass) { Note '  the passphrase file is empty. The zip is left in the clear.'; }
    else {
      $enc = $zip + '.enc'
      $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
      $salt = New-Object byte[] 16; $rng.GetBytes($salt)
      $iv   = New-Object byte[] 16; $rng.GetBytes($iv)
      # Two keys out of one passphrase: one to encrypt with, one to sign the
      # result with. Never the same bytes for both.
      $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($pass, $salt, 200000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
      $kEnc = $kdf.GetBytes(32)
      $kMac = $kdf.GetBytes(32)
      $aes = [System.Security.Cryptography.Aes]::Create()
      $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
      $aes.Key = $kEnc; $aes.IV = $iv
      # Named $clear rather than $plain, and the stream below $fs rather than
      # $out, because -Plain and -Out are parameters of this script and a
      # parameter keeps its declared type for the whole run. Assigning bytes
      # to $plain is assigning them to a [switch], which fails with a message
      # about SwitchParameter that says nothing about where it came from.
      $clear = [System.IO.File]::ReadAllBytes($zip)
      $cipher = $aes.CreateEncryptor().TransformFinalBlock($clear, 0, $clear.Length)
      # Signed over everything that is not the signature, so a changed salt or
      # IV is caught too, and checked before anything is decrypted.
      $hmac = [System.Security.Cryptography.HMACSHA256]::new($kMac)
      $signed = New-Object byte[] (16 + 16 + $cipher.Length)
      [Array]::Copy($salt, 0, $signed, 0, 16)
      [Array]::Copy($iv, 0, $signed, 16, 16)
      [Array]::Copy($cipher, 0, $signed, 32, $cipher.Length)
      $mac = $hmac.ComputeHash($signed)
      $magic = [Text.Encoding]::ASCII.GetBytes('TSBK1')
      $fs = New-Object System.IO.FileStream($enc, [IO.FileMode]::Create)
      $fs.Write($magic, 0, $magic.Length)
      $fs.Write($signed, 0, $signed.Length)
      $fs.Write($mac, 0, $mac.Length)
      $fs.Close()
      $aes.Dispose(); $kdf.Dispose(); $hmac.Dispose(); $rng.Dispose()
      Remove-Item -LiteralPath $zip -Force
      Note "  encrypted $([IO.Path]::GetFileName($enc))  $([math]::Round((Get-Item $enc).Length / 1MB, 2)) MB"
    }
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
foreach ($f in $drop) {
  Remove-Item -LiteralPath $f.FullName -Force -EA SilentlyContinue
  Note "  dropped   $($f.Name)"
}
Note ("  kept      {0} daily, {1} weekly" -f [Math]::Min($daily.Count, $KeepDaily), [Math]::Min($weekly.Count, $KeepWeekly))
Note '  done. Fetch-Backups.ps1 on the other machine is what gets these off this box.'
