<#
  Publish-Installer.ps1

  Puts the current installer on the docs site so friends always have the newest
  one without anybody sending files around.

  The installer is a pair: a small exe and a payload zip of about a gigabyte.
  The exe finds the zip beside itself, so both have to land in the same folder
  and neither is any use alone. They are published together and the page says
  so, because "I downloaded the installer and it did nothing" is what happens
  when somebody takes only the exe.

  Called by Package-Thornswood.ps1 at the end, so a rebuilt installer publishes
  itself. Can be run on its own if a push failed.

    .\Publish-Installer.ps1
    .\Publish-Installer.ps1 -OutDir .\out\dist\Thornswood\_dist
    .\Publish-Installer.ps1 -KeepOld     ignored (stable name; stamped leftovers always pruned)

  Only the current pair is kept by default. At a gigabyte each, three
  generations is several gigabytes of VPS disk for something nobody has ever
  rolled back to.

#>
[CmdletBinding()]
param(
  <#
    WHERE PACKAGE-THORNSWOOD ACTUALLY PUTS IT.

    This defaulted to C:\Thornswood\_dist, which stopped existing when
    releases were moved out of the folder Patrick plays from. Package builds
    into out\dist\Thornswood\_dist in the repository (Where.ps1 Package) and
    has done since; running this on its own, which is what Package's own recovery line
    tells you to do when publishing fails, threw "not built" and named a folder
    nobody has.

    Found 23 September, and it is the same shape as the eleven scripts that
    were still reading the old build folder: a default that points at a machine
    nobody has any more, waiting for the one day somebody needs it.
  #>
  [string]$OutDir = (& (Join-Path $PSScriptRoot 'Where.ps1') Package),
  [string]$Version,
  [string]$Note,
  [string]$Vps  = '',
  [string]$User = '',
  [string]$Root = 'C:/Thornswood-Docs',
  [switch]$KeepOld,
  # The payload is inside the exe, so there is one file to publish and the
  # downloads page has one button. Package-Thornswood -OneFile passes this
  # through. Without it the pair is published the old way.
  [switch]$OneFile,
    # Go ahead from a checkout that is not exactly origin/main and clean (#2118). Loud.
    [switch]$AllowStaleCheckout
)

$ErrorActionPreference = 'Stop'   # before any file loads, so one that is missing stops here (#3006)
# A stale or dirty checkout sends old or unlanded code; refuse it (#2118).
# The installer is a live release, so the branch rule is Ship's for a main
# release, Test-FreshAnyBranch -Channel main (#2436): main, or a clean
# hotfix/ branch that matches its own origin branch. Until 12 October this
# asked for origin/main only, and the 1.2.4 hotfix's installer needed
# -AllowStaleCheckout to go out.
. (Join-Path $PSScriptRoot '..\deploy\Fresh-Checkout.ps1')
$freshRepo = Join-Path $PSScriptRoot '..\..'
Assert-FreshCheckout -RepoDir $freshRepo -What 'Publish-Installer' -Target $Vps -AnyBranch:(Test-FreshAnyBranch -RepoDir $freshRepo -Channel main) -AllowStale:$AllowStaleCheckout

$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$rootWin = $Root.Replace('/','\')

function Remote($script) {
  # Send-Script.ps1 (issue #1070): a long script goes by scp and its run takes
  # it off the box before it runs, and the far side's exit code comes back.
  return Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Script $script
}

$exe = Join-Path $OutDir 'Thornswood-Setup.exe'
$zip = Join-Path $OutDir 'Thornswood-Setup.zip'
if (-not (Test-Path -LiteralPath $exe)) {
  throw "not built: $exe  (run Package-Thornswood.ps1 first, or pass -OutDir)"
}
$exeItem = Get-Item -LiteralPath $exe
# The SHA-256 of the exact file people download. The Downloads page prints it
# beside the size and date so somebody can check what they got. VirusTotal is
# no longer part of publish: code signing covers trust, and a manual send is
# scripts\release\Publish-VirusTotal.ps1 when somebody wants a report.
$exeSha = (Get-FileHash -LiteralPath $exeItem.FullName -Algorithm SHA256).Hash

# Which release this installer carries, from the note Package-Thornswood.ps1
# left beside the exe it built, checked against the exe's own sha256 (#3043).
# It goes into the exe's entry in files.json, and Ship's installer gate counts
# the releases after it there. Read before anything is sent: an installer whose
# release is not known would leave every main Ship unable to tell how far
# behind it is, so it is not published.
. (Join-Path $Here 'Release-Name.ps1')
$installerRelease = Read-InstallerReleaseNote $OutDir $exeSha
Write-Host ("  carries release {0}" -f $installerRelease)

# Publish sign gate: the tip on the site must be Authenticode Valid under
# ExpectedSigner. Package -NoPublish may leave an unsigned Setup for local use;
# this script is the site path and refuses that soft skip.
. (Join-Path $Here 'Assert-PublishSigned.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $Here)
try {
  $expectWho = Get-ExpectedSignerFragment -RepoRoot $repoRoot
} catch {
  throw $_.Exception.Message
}
$signWhy = Get-PublishSignRefusal -Path $exeItem.FullName -ExpectedSigner $expectWho
if ($signWhy) { throw $signWhy }
Write-Host ("  publish sign gate: {0} Authenticode Valid, ExpectedSigner {1}" -f $exeItem.Name, $expectWho) -ForegroundColor Green

# A one file build is decided by the exe rather than by the switch, because the
# switch is easy to forget on a rerun and the file on disk is not. Anything
# over 64 MB is carrying the payload: the plain stub is under half a megabyte.
$single = $OneFile -or ($exeItem.Length -gt 64MB)
$zipItem = $null
if (-not $single) {
  if (-not (Test-Path -LiteralPath $zip)) {
    throw "not built: $zip  (run Package-Thornswood.ps1 first, or pass -OutDir)"
  }
  $zipItem = Get-Item -LiteralPath $zip
  # The setup program downloads this and runs the Setup.bat inside it, and
  # until now it checked nothing but the length. The hash goes into files.json
  # beside the name, /api/payload hands it over, and Bootstrap.cs deletes a
  # download that does not match instead of unpacking it (To Do entry 173).
  # Lower case, the same shape Publish-Update writes for every pack and for
  # launcherSha256. Measured here, beside the exe's, so the $meta block below
  # only names what was measured.
  $zipSha = (Get-FileHash -LiteralPath $zipItem.FullName -Algorithm SHA256).Hash.ToLower()
}

# Date and time, not just the date. Two builds in one day are normal here
# and a bare date cannot tell them apart, which is how somebody ends up
# testing this morning's installer and reporting a bug fixed at lunch.
# Shown under the download button, so it is read the way a clock is read
# rather than the way a log line is. The site reformats an older 24 hour
# Update the tip entry already sitting in files.json.
if (-not $Version) { $Version = $exeItem.LastWriteTime.ToString('M-d-yyyy h:mm tt') }

# Stable download name (Gavin 2026-09-27): no date stamp in the filename.
# Version and SHA-256 stay in files.json / the Downloads page.
$exeOut = 'Thornswood-Setup.exe'
$zipOut = 'Thornswood-Setup.zip'

'{0,-26} {1:N0} bytes' -f 'Thornswood-Setup.exe', $exeItem.Length | Write-Host
if (-not $single) { '{0,-26} {1:N0} bytes' -f 'Thornswood-Setup.zip', $zipItem.Length | Write-Host }

# files.json on the site lists every download with its hash, and the installer
# is listed in it after it lands (below). It is read first (#2711): one that
# does not read stops here, before the installer replaces the one people
# download, so the site is never left with a new installer and a list that
# cannot name it. Until 18 Oct a list that did not read became an empty one in
# a try with an empty catch, and was written back naming the installer alone.
$listCheck = @(Remote @"
`$f = '$rootWin\files\files.json'
if (-not (Test-Path -LiteralPath `$f)) { 'FILESJSON|none'; exit 0 }
try { `$null = Get-Content -LiteralPath `$f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop; 'FILESJSON|reads'; exit 0 }
catch { 'FILESJSON|' + (`$_.Exception.Message -replace '[\r\n]+', ' '); exit 1 }
"@)
$listCode = $LASTEXITCODE
$listSaid = @($listCheck | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'FILESJSON|*' } | Select-Object -First 1)
if ($listCode -ne 0 -or -not $listSaid.Count -or ($listSaid[0] -ne 'FILESJSON|none' -and $listSaid[0] -ne 'FILESJSON|reads')) {
  $why = $(if ($listSaid.Count) { $listSaid[0].Substring(10) } else { (($listCheck | ForEach-Object { [string]$_ }) -join ' ').Trim() })
  throw ("files.json on the site ($Root/files/files.json) does not read, exit $listCode" + $(if ($why) { ": $why" } else { '' }) +
         ". Nothing was sent. It lists every download and its hash, and the Downloads page reads it too; fix it on the box, then run this again.")
}

Write-Host ''
Write-Host '  Sending. This is about a gigabyte, so it takes a few minutes.'
Write-Host ''

$send = @(, @($exeItem.FullName, $exeOut))
if (-not $single) { $send += , @($zipItem.FullName, $zipOut) }
foreach ($pair in $send) {
  Invoke-ThornswoodNative { & scp @ssh $pair[0] "$User@${Vps}:$Root/files/$($pair[1])" }
  if ($LASTEXITCODE -ne 0) { throw "scp failed: $($pair[1])" }
  Write-Host "  $($pair[1])"
}

if ($single) {
  $meta = @{
    $exeOut = @{
      label   = 'Thornswood installer'
      version = $Version
      sha256  = $exeSha
      release = $installerRelease
      note    = 'One file. Download it and run it.'
    }
  }
} else {
  # The payload is published but hidden. The setup program asks the site for
  # it and fetches it, so it is on here for that and not for a person to pick.
  # Two buttons was the old way and it was one of them being the wrong one.
  # sha256 is what the setup program checks the download against.
  $meta = @{
    $exeOut = @{
      label   = 'Thornswood installer'
      version = $Version
      sha256  = $exeSha
      release = $installerRelease
      note    = 'One file. Download it and run it. It gets the mods itself, about 700 MB.'
    }
    $zipOut = @{
      label   = 'Thornswood installer, payload'
      version = $Version
      hidden  = $true
      note    = 'What the installer fetches. Nobody downloads this by hand.'
      sha256  = $zipSha
    }
  }
}
$b64 = [Convert]::ToBase64String(
  [Text.Encoding]::UTF8.GetBytes(($meta | ConvertTo-Json -Depth 4 -Compress)))

Write-Host ''
$listWrite = @(Remote @"
`$dir = '$rootWin\files'
`$f = Join-Path `$dir 'files.json'
`$all = @{}
if (Test-Path `$f) {
  # Read before the send as well; this is the read the list is written from,
  # so one that does not read now leaves it as it is and says so.
  try { (Get-Content `$f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties |
        ForEach-Object { `$all[`$_.Name] = `$_.Value } }
  catch { 'files.json does not read, so it was left as it is and the installer is not listed: ' + (`$_.Exception.Message -replace '[\r\n]+', ' '); exit 1 }
}
(([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))) |
  ConvertFrom-Json).PSObject.Properties | ForEach-Object { `$all[`$_.Name] = `$_.Value }

# Stable name overwrites in place via scp. Drop any leftover stamped tips
# (Thornswood-Setup-YYYYMMDD-HHMM.*) and their files.json keys. -KeepOld is
# ignored for the stable name; one tip is enough.
Get-ChildItem `$dir -Filter 'Thornswood-Setup-*.*' | ForEach-Object {
  if (`$_.Name -match '^Thornswood-Setup-\d{8}-\d{4}\.') {
    Remove-Item `$_.FullName -Force -EA SilentlyContinue
    `$all.Remove(`$_.Name)
    'removed old ' + `$_.Name
  }
}

# Set-Content -Encoding UTF8 on Windows PowerShell puts a byte order mark on
# the front, Node's JSON.parse refuses it, and the site's try/catch swallows
# the error, so the downloads page silently goes empty.
[IO.File]::WriteAllText(`$f, (`$all | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding(`$false)))
'published, ' + `$all.Count + ' files listed'
"@)
$listWriteCode = $LASTEXITCODE
$listWrite | ForEach-Object { Write-Host "  $_" }
if ($listWriteCode -ne 0) {
  throw ("The installer is on the site, but files.json was not written (exit $listWriteCode): " + (($listWrite | ForEach-Object { [string]$_ }) -join ' ').Trim() +
         ". The Downloads page still lists the installer before this one, so its hash does not match the file now served. Fix files.json on the box and run this again.")
}

Write-Host ''
# The site answers on https://thornswood.net through Caddy. Port 3001 is
# loopback only since Setup-Domain ran, so the old http address here was a
# door that no longer exists, and it read as if the password still crossed
# the wire in clear.
Write-Host "  on the site under Downloads: https://thornswood.net" -ForegroundColor Green
