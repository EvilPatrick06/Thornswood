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
    .\Publish-Installer.ps1 -OutDir 'C:\Thornswood\_dist'
    .\Publish-Installer.ps1 -KeepOld     keep the previous pair as a rollback

  Only the current pair is kept by default. At a gigabyte each, three
  generations is several gigabytes of VPS disk for something nobody has ever
  rolled back to.
#>
[CmdletBinding()]
param(
  [string]$OutDir = 'C:\Thornswood\_dist',
  [string]$Version,
  [string]$Note,
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Docs',
  [switch]$KeepOld,
  # The payload is inside the exe, so there is one file to publish and the
  # downloads page has one button. Package-Thornswood -OneFile passes this
  # through. Without it the pair is published the old way.
  [switch]$OneFile
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$rootWin = $Root.Replace('/','\')

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

$exe = Join-Path $OutDir 'Thornswood-Setup.exe'
$zip = Join-Path $OutDir 'Thornswood-Setup.zip'
if (-not (Test-Path -LiteralPath $exe)) {
  throw "not built: $exe  (run Package-Thornswood.ps1 first, or pass -OutDir)"
}
$exeItem = Get-Item -LiteralPath $exe

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
}

if (-not $Version) {
  # The number people see in the launcher, rather than a build date nobody
  # recognises.
  try {
    $v = Get-Content (Join-Path (Split-Path -Parent $Here) 'version.json') -Raw | ConvertFrom-Json
    if ($v.launcher) { $Version = "launcher $($v.launcher)" }
  } catch { }
}
# Date and time, not just the date. Two builds in one day are normal here
# and a bare date cannot tell them apart, which is how somebody ends up
# testing this morning's installer and reporting a bug fixed at lunch.
# Shown under the download button, so it is read the way a clock is read
# rather than the way a log line is. The site reformats an older 24 hour
# stamp too, for the one already sitting in files.json.
if (-not $Version) { $Version = $exeItem.LastWriteTime.ToString('M-d-yyyy h:mm tt') }

$stamp  = $exeItem.LastWriteTime.ToString('yyyyMMdd-HHmm')
$exeOut = "Thornswood-Setup-$stamp.exe"
$zipOut = "Thornswood-Setup-$stamp.zip"

'{0,-26} {1:N0} bytes' -f 'Thornswood-Setup.exe', $exeItem.Length | Write-Host
if (-not $single) { '{0,-26} {1:N0} bytes' -f 'Thornswood-Setup.zip', $zipItem.Length | Write-Host }
Write-Host ''
Write-Host '  Sending. This is about a gigabyte, so it takes a few minutes.'
Write-Host ''

$send = @(, @($exeItem.FullName, $exeOut))
if (-not $single) { $send += , @($zipItem.FullName, $zipOut) }
foreach ($pair in $send) {
  & scp @ssh $pair[0] "$User@${Vps}:$Root/files/$($pair[1])"
  if ($LASTEXITCODE -ne 0) { throw "scp failed: $($pair[1])" }
  Write-Host "  $($pair[1])"
}

if ($single) {
  $meta = @{
    $exeOut = @{
      label   = 'Thornswood installer'
      version = $Version
      note    = 'One file. Download it and run it.'
    }
  }
} else {
  # The payload is published but hidden. The setup program asks the site for
  # it and fetches it, so it is on here for that and not for a person to pick.
  # Two buttons was the old way and it was one of them being the wrong one.
  $meta = @{
    $exeOut = @{
      label   = 'Thornswood installer'
      version = $Version
      note    = 'One file. Download it and run it. It gets the mods itself, about 700 MB.'
    }
    $zipOut = @{
      label   = 'Thornswood installer, payload'
      version = $Version
      hidden  = $true
      note    = 'What the installer fetches. Nobody downloads this by hand.'
    }
  }
}
$b64 = [Convert]::ToBase64String(
  [Text.Encoding]::UTF8.GetBytes(($meta | ConvertTo-Json -Depth 4 -Compress)))
$keep = if ($KeepOld) { 2 } else { 1 }

Write-Host ''
Remote @"
`$dir = '$rootWin\files'
`$f = Join-Path `$dir 'files.json'
`$all = @{}
if (Test-Path `$f) {
  try { (Get-Content `$f -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { `$all[`$_.Name] = `$_.Value } } catch { }
}
(([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))) |
  ConvertFrom-Json).PSObject.Properties | ForEach-Object { `$all[`$_.Name] = `$_.Value }

# Prune by pair. The stamp in the name is what ties an exe to its zip, so both
# halves of an old build go or neither does.
`$stamps = Get-ChildItem `$dir -Filter 'Thornswood-Setup-*.*' |
  ForEach-Object { if (`$_.Name -match 'Thornswood-Setup-(\d{8}-\d{4})\.') { `$Matches[1] } } |
  Sort-Object -Unique -Descending
`$drop = `$stamps | Select-Object -Skip $keep
foreach (`$s in `$drop) {
  Get-ChildItem `$dir -Filter ('Thornswood-Setup-' + `$s + '.*') | ForEach-Object {
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
"@ | ForEach-Object { "  $_" }

Write-Host ''
# The site answers on https://thornswood.net through Caddy. Port 3001 is
# loopback only since Setup-Domain ran, so the old http address here was a
# door that no longer exists, and it read as if the password still crossed
# the wire in clear.
Write-Host "  on the site under Downloads: https://thornswood.net" -ForegroundColor Green
