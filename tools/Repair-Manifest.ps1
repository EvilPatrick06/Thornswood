<#
  Repair-Manifest.ps1

  Takes packs with no download url back out of version.json and pushes the fix.

  How one gets in there: publishing uploads each pack as a release asset and
  writes the returned url into version.json. When an upload fails, the pack is
  still written, with an empty url. Every launcher then tries to download from
  nothing, fails with "The path is not of a legal form", and because a pack it
  cannot apply is a pack the server is expecting, Play stays switched off. It
  locks out everybody at once, including the person who published it.

  A pack removed here is not lost work: the next publish rebuilds from the
  current build, so whatever was in it ships again in the next one.

      .\Repair-Manifest.ps1            show what is broken and fix it
      .\Repair-Manifest.ps1 -DryRun    show it and change nothing
#>
[CmdletBinding()]
param(
    [string]$RepoDir,
    [switch]$DryRun,
    [switch]$NoPush,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) { $RepoDir = Split-Path -Parent $Here }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$VersionFile = Join-Path $RepoDir 'version.json'
if (-not (Test-Path -LiteralPath $VersionFile)) { Die "not found: $VersionFile" }

Head 'Reading version.json'
$doc = Get-Content -LiteralPath $VersionFile -Raw | ConvertFrom-Json
$packs = @()
if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs) }
Say ("  {0} pack(s)" -f $packs.Count) 'DarkGray'

$bad = @($packs | Where-Object { -not $_.url -or [string]::IsNullOrWhiteSpace([string]$_.url) })
$good = @($packs | Where-Object { $_.url -and -not [string]::IsNullOrWhiteSpace([string]$_.url) })

if ($bad.Count -eq 0) {
    Say '  every pack has a url. Nothing to repair.' 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'Broken'
foreach ($p in $bad) {
    Say ("  {0}   {1}" -f $p.id, $p.notes) 'Red'
}

# The launcher also stops asking about a pack once its id is in applied.txt, so
# the copy on this machine is settled here as well. Without it this launcher
# would keep the update card up until the repaired file comes back down.
$applied = Join-Path 'C:\Thornswood' 'Profile\applied.txt'
if ($DryRun) {
    Head 'Dry run'
    Say ("  would keep {0} pack(s) and drop {1}" -f $good.Count, $bad.Count) 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'Repairing'
$doc.packs = $good
# WriteAllText rather than Set-Content: Windows PowerShell puts a byte order
# mark on UTF8 output and a BOM is not JSON, which takes the update check out
# for everyone at once.
[IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Say ("  version.json now lists {0} pack(s)" -f $good.Count) 'Green'

if (Test-Path -LiteralPath $applied) {
    $have = @(Get-Content -LiteralPath $applied | Where-Object { $_.Trim() })
    $add = @($bad | ForEach-Object { [string]$_.id } | Where-Object { $have -notcontains $_ })
    if ($add.Count) {
        Add-Content -LiteralPath $applied -Value $add
        Say ("  marked {0} dead pack(s) as seen on this machine" -f $add.Count) 'DarkGray'
    }
}

if ($NoPush) {
    Write-Host ''
    Say 'Not pushed, as asked. Push it yourself with:' 'Yellow'
    Say "  git -C `"$RepoDir`" add version.json; git -C `"$RepoDir`" commit -m 'Drop packs with no url'; git -C `"$RepoDir`" push" 'DarkGray'
}
else {
    Head 'Pushing'
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $RepoDir add version.json 2>&1 | Out-Host
    & git -C $RepoDir commit -m "Drop $($bad.Count) pack(s) that were published with no url" 2>&1 | Out-Host
    & git -C $RepoDir push 2>&1 | Out-Host
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) { Die "git push exited with $rc. The file is fixed here, it just is not up yet." }
    Say '  pushed' 'Green'
}

Write-Host ''
Say 'Open the launcher. The update card should clear and Play should come back.' 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
