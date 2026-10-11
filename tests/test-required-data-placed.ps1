<#
  test-required-data-placed.ps1

      pwsh -NoProfile -File .\tests\test-required-data-placed.ps1

  Ensure-ShipRequiredData returns the paths it actually copied, and nothing
  when the game folder already holds that file. Issue #1119.

  WHY THIS EXISTS. Ship printed "required data placed into the game folder:
  System.String[]" on every run. Ensure-ShipRequiredData ended with
  `return ,$placed.ToArray()`, and Publish-Update.ps1 and
  Package-Thornswood.ps1 both wrap the call in @() again. The unary comma
  plus @() is a one-element array whose element is the string array, so
  Count was always 1 and -join printed the type name. The same line also
  claimed a place when the folder already held the file.

  What it runs, against a scratch repo and game folder, no Skyrim install:
    1. The folder already holds the same bytes. The caller wrap @() has
       count 0, so the log line would not print.
    2. The file is missing. Count is 1 and the name is Data\<file>, not
       System.String[].
    3. The file is there but the bytes differ. It is replaced and named.
    4. README.md is never a placed path.

  Writes only to a temp folder of its own, and removes it.
#>
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Rules = Join-Path (Split-Path -Parent $Here) 'scripts\release\Ship-Rules.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
    else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

. $Rules

$work = Join-Path ([IO.Path]::GetTempPath()) ('required-data-placed-' + [guid]::NewGuid().ToString('n'))
$repo = Join-Path $work 'repo'
$game = Join-Path $work 'game'
$src = Join-Path $repo 'game\required-data'
New-Item -ItemType Directory -Force -Path $src | Out-Null
$payload = 'ELYS-BYTES-1119'
[IO.File]::WriteAllText((Join-Path $src 'Example.esp'), $payload)
[IO.File]::WriteAllText((Join-Path $src 'README.md'), 'not a plugin')

try {
    $dest = Join-Path $game 'Data\Example.esp'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    [IO.File]::WriteAllText($dest, $payload)
    $before = [IO.File]::ReadAllBytes($dest)

    # The same wrap both callers use. A unary-comma return makes this 1.
    # @() has to sit on the assignment: returning it from another function
    # enumerates an empty array away, which is the bug's shape again.
    $req = @(Ensure-ShipRequiredData $game $repo)
    Yes 'a folder that already holds the file places 0' ($req.Count -eq 0)
    Yes '  so the log line would not print' (-not $req.Count)
    Yes '  and -join is not System.String[]' (($req -join ', ') -notmatch 'System\.String')
    $after = [IO.File]::ReadAllBytes($dest)
    Yes '  and the file already there is left as it was' (
        ($before.Length -eq $after.Length) -and ($req.Count -eq 0))

    Remove-Item -LiteralPath $dest -Force
    $req = @(Ensure-ShipRequiredData $game $repo)
    Yes 'a missing file is placed once' ($req.Count -eq 1)
    Yes '  under its Data\ name' ($req[0] -eq 'Data\Example.esp')
    Yes '  and the log names the file, not the type' (
        (($req -join ', ') -eq 'Data\Example.esp') -and (($req -join ', ') -notmatch 'System\.String'))
    Yes '  and the bytes landed' ([IO.File]::ReadAllText($dest) -eq $payload)

    [IO.File]::WriteAllText($dest, 'STALE')
    $req = @(Ensure-ShipRequiredData $game $repo)
    Yes 'different bytes are replaced and named' (
        ($req.Count -eq 1) -and ($req[0] -eq 'Data\Example.esp') -and ([IO.File]::ReadAllText($dest) -eq $payload))

    $req = @(Ensure-ShipRequiredData $game $repo)
    Yes 'the same file on the next call is 0 again' ($req.Count -eq 0)
    Yes 'README.md is never placed' (@($req | Where-Object { $_ -like '*README*' }).Count -eq 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
