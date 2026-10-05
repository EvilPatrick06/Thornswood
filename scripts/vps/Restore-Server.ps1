<#
  Restore-Server.ps1

  Puts a nightly backup's world back into a game server folder and checks the
  result would start: the load order resolves and the characters are there.

      .\scripts\vps\Restore-Server.ps1 -Backup <file>.zip.enc -Root C:\Thornswood-Restore-Test
      .\scripts\vps\Restore-Server.ps1 -Backup <file>.zip.enc -Root C:\Thornswood-Server-Dev -Which dev
      .\scripts\vps\Restore-Server.ps1 -Backup <file>.zip.enc -Root <folder> -Expect 1234567
      .\scripts\vps\Restore-Server.ps1 -Backup <file>.zip.enc -Root <folder> -Work C:\ThornswoodTemps&Worktrees\temp\restore

  Restore-Backup.ps1 checks the signature and unpacks; this is the step after
  it that docs\RESTORING.md used to leave to hand copying. It takes the
  backup's game (live) or game-dev (dev) half and lays it into -Root:

    world    whole, because the backup is the truth about who exists
    private  whole: characters.json, mod-settings.json, take-limit.json,
             door.json, allowed.json. Nothing in a build ships into it.
    data     only the files the folder does not already have, so a build
             already installed there keeps its own shipped files
    server-settings.json and gamemode.js
             only when the folder has none, for the same reason, EXCEPT the
             keys that say which server this is: port, name,
             thornswoodVoicePort, thornswoodServer and
             thornswoodLoadOrderRefuse come from the backup. The payload on
             the box (C:\thornswood-server.zip) is whichever channel was
             published last, and on the first rehearsal (28 September) it was
             a dev one: a live restore kept port 7787 and the name
             Thornswood Dev, so the live server would have come back as the
             dev one. The join pass switch and the written role lists,
             thornswoodRequirePass, thornswoodDevs and thornswoodPlaytesters,
             come from the backup too (#1845): they are the server's own and
             no build carries them (#1223), so the payload's would be nobody's
             choice. Those three are named and their values never printed.

  Whatever world and private the folder already had is moved aside into
  world-before-restore-<stamp> inside it, never deleted.

  -Root must already hold the server program and its plugins: on a new box,
  Install-ThornswoodServer.ps1 -Zip <payload> -Root <it> -NoTask first. The
  backup does not carry them; they come from the repo.

  THE LOAD ORDER CHECK. server-settings.json names each plugin by its full
  path, C:/Thornswood-Server/plugins/..., so a throwaway folder restored from
  a live backup would "resolve" against the live server's plugins and prove
  nothing. Any entry whose folder is not -Root is pointed at -Root first (the
  same rewrite vps-dev-instance.ps1 does for dev), and then every entry must
  be on disk. One that is not is named and the run ends with exit 1, the same
  refusal Install-ThornswoodServer.ps1 makes.

  THE CHARACTER CHECK. A character is a change form named with a bare number
  in world\changeForms (0.json, 1.json, ...: a slot number, not the profile
  id) whose profileId is set and which is not deleted. A deleted character
  keeps its slot file with profileId -1 and isDeleted true, so counting the
  files counted the dead too: the first real rehearsal, 28 September, found
  18 slot files on live and 11 people in them. No characters is exit 1.
  -Expect <profile id> (the number the launcher and the site show, in
  decimal) also requires that person's character.

  It refuses to touch a folder whose server is running: the server writes
  world while it runs and would write straight back over the restore.

  Prints RESTORE OK and exits 0 only when every check above passed.

  -Work is the folder the decrypted zip and the unpacked backup sit in while
  this runs. Left out, that is %TEMP%. Restore-Backup.ps1 is given the same
  folder, so the zip is not written to %TEMP% either. Both are deleted before
  this exits, including when the run is refused: the unpacked backup holds
  the bot token and the site keys.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Backup,
  [Parameter(Mandatory = $true)][string]$Root,
  [ValidateSet('live', 'dev')][string]$Which = 'live',
  [string]$KeyFile,
  [string]$Expect,
  # Where the decrypted zip and the unpacked backup sit. Left out, %TEMP%.
  [string]$Work,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# $work below is the unpacked backup. PowerShell does not distinguish it from
# -Work, so copy the folder off under another name before that assignment.
if ($Work) { $WorkRoot = $Work } else { $WorkRoot = $env:TEMP }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
$work = $null
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  # The unpacked backup holds the bot token and the site keys. Never left behind.
  if ($script:work -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -EA SilentlyContinue }
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}
# The characters in a world: one entry per living one, with its profile id and
# slot file. $script:deleted counts the slots a deleted character left behind.
$deleted = 0
function People([string]$worldDir) {
  $script:deleted = 0
  $forms = Join-Path $worldDir 'changeForms'
  if (-not (Test-Path -LiteralPath $forms)) { return @() }
  $out = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $forms -File -Filter *.json -EA SilentlyContinue |
                   Where-Object { $_.BaseName -match '^[0-9]+$' } | Sort-Object { [long]$_.BaseName })) {
    $o = $null
    try { $o = [IO.File]::ReadAllText($f.FullName) -replace '^\uFEFF', '' | ConvertFrom-Json } catch { $o = $null }
    $id = 0L
    if ($o -and $null -ne $o.profileId) { try { $id = [long]$o.profileId } catch { $id = 0L } }
    if ($id -le 0 -or ($o -and $o.isDeleted -eq $true)) { $script:deleted++; continue }
    $out += [pscustomobject]@{ Id = $id; File = $f }
  }
  return $out
}

if (-not (Test-Path -LiteralPath $Root)) {
  Die ("There is no server folder at $Root. Put the server program there first " +
       "(Install-ThornswoodServer.ps1 -Zip <payload> -Root $Root -NoTask), then restore into it.")
}
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$rootFwd = $Root -replace '\\', '/'
$tag = if ($Which -eq 'dev') { 'game-dev' } else { 'game' }

Write-Host ''
Write-Host '  THORNSWOOD  -  put a backup back into a server folder' -ForegroundColor White
Say "  backup  $Backup" 'DarkGray'
Say "  into    $Root  ($Which, from $tag in the backup)" 'DarkGray'

# ------------------------------------------------------------ not running ---
Head 'Is its server running'
$settingsPath = Join-Path $Root 'server-settings.json'
# node under this folder, or the cmd the server task wraps it in. Only those:
# the shell this was started from can name the folder too (an ssh command
# line does), and that is not a server.
$running = @()
try {
  $running = @(Get-CimInstance Win32_Process -EA SilentlyContinue |
               Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and
                              $_.CommandLine.IndexOf($Root, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                              ($_.Name -eq 'node.exe' -or $_.CommandLine -match 'skymp5-server') })
} catch { $running = @() }
if ($running.Count) {
  Die ("The server in this folder is running (pid {0}, {1}). Stop it first: it writes world while it runs." -f
       $running[0].ProcessId, $running[0].Name)
}
# node started by hand with a relative path does not name the folder on its
# command line. Whoever holds the game port does, or its parent does. A port
# held by some OTHER server (a throwaway folder whose settings still say 7777
# while live runs) is not this one running, and is only said.
$port = 0
if (Test-Path -LiteralPath $settingsPath) {
  try { $port = [int]((Get-Content -LiteralPath $settingsPath -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json).port } catch { $port = 0 }
}
if ($port -and (Get-Command Get-NetUDPEndpoint -EA SilentlyContinue)) {
  foreach ($ep in @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue)) {
    $p = Get-CimInstance Win32_Process -Filter ("ProcessId = " + [int]$ep.OwningProcess) -EA SilentlyContinue
    $up = $null
    if ($p) { $up = Get-CimInstance Win32_Process -Filter ("ProcessId = " + [int]$p.ParentProcessId) -EA SilentlyContinue }
    $lines = @($p, $up) | Where-Object { $_ -and $_.CommandLine } | ForEach-Object { $_.CommandLine }
    if (@($lines | Where-Object { $_.IndexOf($Root, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) {
      Die "UDP $port is held by this folder's server (pid $($ep.OwningProcess)). Stop it first: it writes world while it runs."
    }
    Say "  UDP $port is held by another server (pid $($ep.OwningProcess)); give this folder its own port before starting it" 'Yellow'
  }
}
Say '  nothing is running from it' 'Green'

# ---------------------------------------------------------------- unpack ---
Head 'Opening the backup'
if (-not $WorkRoot) { Die 'No folder for the unpacked backup: -Work was not passed and %TEMP% is not set.' }
try { [void][IO.Directory]::CreateDirectory($WorkRoot) }
catch { Die ("-Work is not a folder: " + $WorkRoot + " (" + $_.Exception.Message + ")") }
try {
$work = Join-Path $WorkRoot ('thornswood-restore-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$open = @{ Backup = $Backup; To = $work; NoPause = $true; Work = $WorkRoot }
if ($KeyFile) { $open['KeyFile'] = $KeyFile }
$global:LASTEXITCODE = 0
& (Join-Path $Here 'Restore-Backup.ps1') @open
if ($LASTEXITCODE -ne 0) { Die 'The backup did not open, so nothing was put back. The lines above say why.' }

$src = Join-Path $work $tag
$srcWorld = Join-Path $src 'world'
if (-not (Test-Path -LiteralPath $srcWorld)) {
  Die "This backup has no $tag\world. Backups from before issue #401 carry no dev server; use -Which live or a newer one."
}
$had = @(People $srcWorld)
if (-not $had.Count) { Die "The backup's $tag\world holds no characters. Use an older backup: that is what the weeklies are for." }
Say ("  {0} character(s) in the backup's {1}\world" -f $had.Count, $tag) 'Green'

# --------------------------------------------------------------- put back ---
Head 'Putting it back'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$aside = Join-Path $Root ('world-before-restore-' + $stamp)
foreach ($n in 'world', 'private') {
  $d = Join-Path $Root $n
  if ((Test-Path -LiteralPath $d) -and @(Get-ChildItem -LiteralPath $d -Force -EA SilentlyContinue).Count) {
    [void](New-Item -ItemType Directory -Path $aside -Force)
    Move-Item -LiteralPath $d -Destination (Join-Path $aside $n)
    Say "  the $n that was here is kept at $aside\$n" 'Yellow'
  } elseif (Test-Path -LiteralPath $d) {
    Remove-Item -LiteralPath $d -Recurse -Force
  }
}
Copy-Item -LiteralPath $srcWorld -Destination (Join-Path $Root 'world') -Recurse -Force
Say ("  world      {0} file(s)" -f @(Get-ChildItem -LiteralPath (Join-Path $Root 'world') -Recurse -File).Count)

$srcPriv = Join-Path $src 'private'
if (Test-Path -LiteralPath $srcPriv) {
  Copy-Item -LiteralPath $srcPriv -Destination (Join-Path $Root 'private') -Recurse -Force
  $names = @(Get-ChildItem -LiteralPath (Join-Path $Root 'private') -File | ForEach-Object { $_.Name })
  Say ("  private    {0}" -f ($names -join ', '))
} else {
  [void](New-Item -ItemType Directory -Path (Join-Path $Root 'private') -Force)
  Say '  private    NOT IN THE BACKUP. The door and the character cards start empty.' 'Yellow'
}

$srcData = Join-Path $src 'data'
if (Test-Path -LiteralPath $srcData) {
  $kept = 0
  # Each file's path under data, cut off the very string it was listed from.
  # This used to cut Get-ChildItem's FullName by the length of Resolve-Path's
  # answer, and the two disagree when TEMP is a short 8.3 path (C:\Users\
  # ADMINI~1\...), which it is for Administrator on the box: Resolve-Path
  # kept the short form, FullName gave the long one, and data\keep.txt came
  # back as data\game\data\keep.txt. Seen on the build runner, issue #1120.
  foreach ($path in @([IO.Directory]::EnumerateFiles($srcData, '*', [IO.SearchOption]::AllDirectories))) {
    $to = Join-Path (Join-Path $Root 'data') $path.Substring($srcData.Length).TrimStart('\')
    if (Test-Path -LiteralPath $to) { continue }
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force)
    Copy-Item -LiteralPath $path -Destination $to
    $kept++
  }
  Say "  data       $kept file(s) the folder did not already have"
}
foreach ($n in 'server-settings.json', 'gamemode.js') {
  $from = Join-Path $src $n
  if (-not (Test-Path -LiteralPath (Join-Path $Root $n)) -and (Test-Path -LiteralPath $from)) {
    Copy-Item -LiteralPath $from -Destination (Join-Path $Root $n)
    Say "  $n from the backup, because the folder had none" 'Yellow'
  }
}

# ------------------------------------------------------------ load order ---
Head 'Does the load order resolve'
if (-not (Test-Path -LiteralPath $settingsPath)) { Die "There is no server-settings.json in $Root or in the backup." }
$bytes = [IO.File]::ReadAllBytes($settingsPath)
$bom = $false
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  $bytes = [byte[]]($bytes[3..($bytes.Length - 1)])
  $bom = $true
  Say '  took a byte order mark off server-settings.json, node cannot parse one' 'Yellow'
}
$utf8 = New-Object Text.UTF8Encoding($false)
$s = $utf8.GetString($bytes) | ConvertFrom-Json
if (-not $s.loadOrder) { Die 'server-settings.json has no loadOrder.' }

# Which server this is comes from the backup, not from whichever channel's
# payload was unpacked here (see the note at the top). So do the join pass
# switch and the written role lists (#1845), which are said by name only.
$named = 0
$byNameOnly = @('thornswoodRequirePass', 'thornswoodDevs', 'thornswoodPlaytesters')
$srcSettings = Join-Path $src 'server-settings.json'
if (Test-Path -LiteralPath $srcSettings) {
  $b = $null
  try { $b = [IO.File]::ReadAllText($srcSettings) -replace '^\uFEFF', '' | ConvertFrom-Json } catch { $b = $null }
  if ($b) {
    foreach ($k in @('port', 'name', 'thornswoodVoicePort', 'thornswoodServer', 'thornswoodLoadOrderRefuse') + $byNameOnly) {
      $has = $s.PSObject.Properties.Name -contains $k
      $want = $b.PSObject.Properties.Name -contains $k
      $quiet = $byNameOnly -contains $k
      if ($want) {
        if (-not $has) {
          if ($quiet) { Say "  $k from the backup, the folder had none" 'Yellow' }
          else { Say ("  {0}: {1} from the backup, the folder had none" -f $k, (ConvertTo-Json $b.$k -Compress)) 'Yellow' }
          $s | Add-Member -NotePropertyName $k -NotePropertyValue $b.$k; $named++
        }
        elseif ((ConvertTo-Json $s.$k -Compress) -ne (ConvertTo-Json $b.$k -Compress)) {
          if ($quiet) { Say "  $k from the backup, the folder's was different" 'Yellow' }
          else { Say ("  {0}: {1} from the backup, was {2}" -f $k, (ConvertTo-Json $b.$k -Compress), (ConvertTo-Json $s.$k -Compress)) 'Yellow' }
          $s.$k = $b.$k; $named++
        }
      } elseif ($has) {
        Say "  $k taken off: the backup's settings do not have it" 'Yellow'
        $s.PSObject.Properties.Remove($k); $named++
      }
    }
  }
}

$order = @()
$moved = 0
foreach ($p in @($s.loadOrder)) {
  $fwd = ([string]$p) -replace '\\', '/'
  $i = $fwd.ToLowerInvariant().LastIndexOf('/plugins/')
  if ($i -gt 0 -and -not [string]::Equals($fwd.Substring(0, $i), $rootFwd, [StringComparison]::OrdinalIgnoreCase)) {
    $fwd = $rootFwd + $fwd.Substring($i)
    $moved++
  }
  $order += $fwd
}
if ($moved -or $named) {
  $s.loadOrder = $order
  [IO.File]::WriteAllText($settingsPath, ($s | ConvertTo-Json -Depth 20), $utf8)
  if ($moved) { Say "  $moved plugin path(s) named another server's folder; pointed at $rootFwd" 'Yellow' }
} elseif ($bom) {
  [IO.File]::WriteAllBytes($settingsPath, $bytes)
}
$bad = @($order | Where-Object { -not (Test-Path -LiteralPath ($_ -replace '/', '\')) })
if ($bad.Count) {
  Write-Host ''
  Write-Host ("{0} plugin(s) in the load order are not on disk:" -f $bad.Count) -ForegroundColor Red
  foreach ($b in $bad) { Write-Host "    $b" -ForegroundColor Red }
  Die ('load order does not resolve. The world is back, but this server would refuse to start. ' +
       'Put the server program and plugins here with Install-ThornswoodServer.ps1, then run this again.')
}
Say ("  load order: all {0} plugins present" -f $order.Count) 'Green'

# ------------------------------------------------------------ characters ---
Head 'Are the characters there'
$now = @(People (Join-Path $Root 'world'))
if (-not $now.Count) { Die 'world\changeForms holds no characters after the restore.' }
Say ("  {0} character(s), profile ids {1}{2}" -f $now.Count, (($now | Select-Object -First 5 | ForEach-Object { $_.Id }) -join ', '),
     $(if ($now.Count -gt 5) { ', ...' } else { '' })) 'Green'
if ($deleted) { Say "  and $deleted slot(s) a deleted character left behind, not counted" 'DarkGray' }
if ($Expect) {
  $hit = @($now | Where-Object { [string]$_.Id -eq $Expect.Trim() })
  if (-not $hit.Count) {
    Die "Character $Expect is not in the restored world (no living character has that profile id)."
  }
  Say ("  character {0} is there, in {1}" -f $Expect, $hit[0].File.Name) 'Green'
}
$book = Join-Path $Root 'private\characters.json'
if (Test-Path -LiteralPath $book) {
  try {
    $who = (Get-Content -LiteralPath $book -Raw -Encoding UTF8 | ConvertFrom-Json).who
    $cards = @($who.PSObject.Properties).Count
    Say "  characters.json names $cards on the launcher's cards" 'DarkGray'
  } catch { Say '  characters.json is there but does not parse' 'Yellow' }
}
if (-not (Test-Path -LiteralPath (Join-Path $Root 'dist_back\skymp5-server.js'))) {
  Say '  there is no dist_back\skymp5-server.js here, so this folder has the world but not the server program yet' 'Yellow'
}

Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
Write-Host ''
Say ("RESTORE OK: {0} character(s), all {1} plugins on disk, in {2}" -f $now.Count, $order.Count, $Root) 'Green'
Say '  Start it with its scheduled task, or: Set-Location <root>; node dist_back/skymp5-server.js' 'DarkGray'
Say '  and watch thornswood.log until a character connects. docs\RESTORING.md has the rest.' 'DarkGray'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0

} finally {
  if ($script:work -and (Test-Path -LiteralPath $script:work)) {
    Remove-Item -LiteralPath $script:work -Recurse -Force -EA SilentlyContinue
  }
}
