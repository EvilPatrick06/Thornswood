<#
  Fetch-Backups.ps1

  Brings the nightly backups off the VPS onto this machine, and checks that
  what arrived is readable. This is the half that makes them backups: a copy
  that only exists on the server is gone with the server.

      .\tools\Fetch-Backups.ps1              bring down anything new
      .\tools\Fetch-Backups.ps1 -All         bring down everything, again
      .\tools\Fetch-Backups.ps1 -NoVerify    just copy, do not open them

  Everything it brings down is encrypted, so where it lands matters less than
  it would otherwise. The passphrase is the thing to keep carefully, and it is
  not in here.

  Worth putting on a scheduled task on this machine, an hour or so after the
  one on the VPS. Until something does this on its own, the backups are only
  as good as somebody remembering.
#>
[CmdletBinding()]
param(
  [string]$VpsHost = '192.135.112.23',
  [string]$VpsUser = 'Administrator',
  [string]$Remote  = 'C:/Thornswood-Backup',
  [string]$To      = "$env:USERPROFILE\Downloads\Thornswood-Backups",
  [string]$KeyFile = "$env:USERPROFILE\Documents\thornswood-backup-key.txt",
  [switch]$All,
  [switch]$NoVerify,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new')
foreach ($t in 'ssh', 'scp') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Die "$t is not on PATH." }
}
if (-not (Test-Path -LiteralPath $To)) { [void](New-Item -ItemType Directory -Path $To -Force) }

$e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(@"
Get-ChildItem '$($Remote.Replace('/','\'))' -File -EA SilentlyContinue |
  Where-Object { `$_.Name -match '^thornswood-\d{8}-\d{6}\.zip(\.enc)?`$' } |
  ForEach-Object { `$_.Name + '|' + `$_.Length }
"@))
$listing = & ssh @ssh $target "powershell -NoProfile -EncodedCommand $e" 2>&1

Head 'On the VPS'
$onBox = @()
foreach ($line in $listing) {
  $s = "$line".Trim()
  if ($s -match '^(thornswood-\d{8}-\d{6}\.zip(?:\.enc)?)\|(\d+)$') {
    $onBox += [pscustomobject]@{ Name = $Matches[1]; Length = [long]$Matches[2] }
  } elseif ($s) { Say "  $s" 'DarkGray' }
}
if (-not $onBox.Count) { Die "No backups on the VPS at $Remote. Has Install-Backup.ps1 been run, and has the task fired yet?" }
Say ("  {0} backup(s)" -f $onBox.Count)

$want = @()
foreach ($b in ($onBox | Sort-Object Name)) {
  $local = Join-Path $To $b.Name
  # Matched on size, not just on the name. A copy that was interrupted halfway
  # is the one thing worse than no copy, because it looks like a copy.
  if (-not $All -and (Test-Path -LiteralPath $local) -and (Get-Item $local).Length -eq $b.Length) {
    Say ("  have    {0}" -f $b.Name) 'DarkGray'
    continue
  }
  $want += $b
}
if (-not $want.Count) {
  Head 'Nothing new'
  Say "  Everything on the box is already in $To" 'Green'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

Head ("Copying {0}" -f $want.Count)
$got = @()
foreach ($b in $want) {
  & scp @ssh "${target}:$Remote/$($b.Name)" (Join-Path $To $b.Name)
  if ($LASTEXITCODE -ne 0) { Say ("  FAILED  " + $b.Name) 'Red'; continue }
  $local = Join-Path $To $b.Name
  $len = (Get-Item $local).Length
  if ($len -ne $b.Length) {
    Say ("  SHORT   {0}  got {1} of {2} bytes" -f $b.Name, $len, $b.Length) 'Red'
    continue
  }
  Say ("  {0}  {1} MB" -f $b.Name, [math]::Round($len / 1MB, 2)) 'Green'
  $got += $local
}

if ($NoVerify -or -not $got.Count) {
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

Head 'Checking the newest one opens'
# Copying a file proves the bytes moved. It does not prove the backup is a
# backup, and that is the failure worth catching: the two that existed before
# any of this were both readable and both had no characters in them.
$newest = $got | Sort-Object | Select-Object -Last 1
$restore = Join-Path $Here 'Restore-Backup.ps1'
if (-not (Test-Path -LiteralPath $restore)) {
  Say '  Restore-Backup.ps1 is not next to this script, so it was not checked.' 'Yellow'
} elseif (-not (Test-Path -LiteralPath $KeyFile)) {
  Say "  No passphrase at $KeyFile, so it could not be opened. Pass -KeyFile." 'Yellow'
} else {
  & $restore -Backup $newest -KeyFile $KeyFile -CheckOnly -NoPause
  if ($LASTEXITCODE -ne 0) { Say '  THAT BACKUP DID NOT OPEN. Do not trust the rest until you know why.' 'Red' }
}

Write-Host ''
Say "  They are in $To" 'DarkGray'
Say '  Restoring one for real is docs\RESTORING.md.' 'DarkGray'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
