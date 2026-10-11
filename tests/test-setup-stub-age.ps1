<#
  test-setup-stub-age.ps1

  Package-Thornswood.ps1 refuses a setup program compiled before the last
  change to the source it is compiled from.

  25 September: the installer went on the site straight after the pull that
  brought #340, the fix for old installer zips in the Downloads folder.
  Package-Thornswood copies out\setup-stub.exe and never compiles it;
  Build-Launcher.ps1 does, and had not run since the pull, so nothing could say
  which Bootstrap.cs the published setup program came from.

  This never runs the packager. It lifts Get-StubRefusal from between the setup
  stub markers and asks it about files under its own temp folder, and reads
  where the check sits. If the markers move, it stops rather than quietly
  testing nothing.
#>
[CmdletBinding()]
param([string]$PackagePath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here0 = $PSScriptRoot
if (-not $Here0) { $Here0 = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here0 = Split-Path -Parent $Here0
if (-not $PackagePath) { $PackagePath = Join-Path $Here0 'scripts\release\Package-Thornswood.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$src = [IO.File]::ReadAllText($PackagePath)
$a = $src.IndexOf('# ==== thornswood setup stub ====')
$b = $src.IndexOf('# ==== end thornswood setup stub ====')
Yes 'Package-Thornswood.ps1 has the setup stub block' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) { Done }
$block = $src.Substring($a, $b - $a)

# Where it sits: before anything is staged or any game closed, so a refusal
# costs nothing, and after the release feed check, which is the other stop
# that comes first.
$staged = $src.IndexOf("Head 'Packaging'")
$closed = $src.IndexOf("Close-Launcher.ps1')")
$feed = $src.IndexOf('# ==== end thornswood release feed ====')
Yes 'the check comes before the game is closed and anything is staged' ($staged -gt $b -and $closed -gt $b)
Yes 'and after the release feed check' ($feed -ge 0 -and $feed -lt $a)
Yes 'it stops the packager when there is a reason' ($block.Contains('if ($stubWhy) { Die $stubWhy }'))
# The stub that is checked is the stub that ships: the copy further down takes
# the one found here rather than looking again (issue #932). -Stub, a main
# Ship's from CI, comes first; without it, out\ and then the output folder.
$pick = "@((Join-Path (& (Join-Path `$Here 'Where.ps1') Out) 'setup-stub.exe'), (Join-Path `$OutDir 'setup-stub.exe'))"
Yes 'it checks the stub the installer is built from' ($block.Contains($pick) -and $src.Contains("`$stub = `$stubNow") -and
    ([regex]::Matches($src, [regex]::Escape("Out) 'setup-stub.exe')"))).Count -eq 1)
Yes 'a stub given with -Stub is the one, and one that is not there stops it' ($block -match '(?s)if \(\$Stub\) \{\s*if \(-not \(Test-Path -LiteralPath \$Stub\)\) \{ Die .*?\$stubNow = \(Resolve-Path -LiteralPath \$Stub\)\.Path\s*\} else \{')
Yes 'against installer\setup\Bootstrap.cs' ($block.Contains("(Join-Path `$Here '..\..\installer\setup\Bootstrap.cs')"))

$m = [regex]::Match($block, '(?s)function Get-StubRefusal\(.*?\n\}')
Yes 'Get-StubRefusal is in the block' ($m.Success)
if (-not $m.Success) { Done }
Invoke-Expression $m.Value

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-stub-age-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    $stub = Join-Path $work 'setup-stub.exe'
    $boot = Join-Path $work 'Bootstrap.cs'
    [IO.File]::WriteAllBytes($stub, [byte[]](0x4D, 0x5A))
    [IO.File]::WriteAllText($boot, 'static class Setup { }')
    $t = [DateTime]::UtcNow.AddHours(-2)

    # 1. What happened on 25 September: the source pulled after the stub was built.
    (Get-Item $stub).LastWriteTimeUtc = $t
    (Get-Item $boot).LastWriteTimeUtc = $t.AddMinutes(90)
    $why = Get-StubRefusal $stub $boot
    Yes 'a stub compiled before the last change to Bootstrap.cs is refused' ($why.Length -gt 0)
    Yes 'and the refusal names the stub and the source' ($why.Contains($stub) -and $why.Contains($boot))
    Yes 'and says what compiles it, into a scratch root' ($why.Contains('Build-Launcher.ps1') -and $why.Contains('-Root'))
    Yes 'and in the house words' ($why -notmatch 'player' -and $why.IndexOf([char]0x2014) -lt 0)

    # 2. Built after the pull, which is what Build-Launcher then Package gives.
    (Get-Item $stub).LastWriteTimeUtc = $t.AddMinutes(95)
    Yes 'a stub compiled after it goes through' ((Get-StubRefusal $stub $boot) -eq '')
    (Get-Item $stub).LastWriteTimeUtc = $t.AddMinutes(90)
    Yes 'and so does one compiled the same minute' ((Get-StubRefusal $stub $boot) -eq '')

    # 3. No stub is the later stop's to say, and no source means nothing to compare.
    Yes 'no stub is left to the stop that already says so' ((Get-StubRefusal (Join-Path $work 'none.exe') $boot) -eq '')
    Yes 'and so is no stub found at all' ((Get-StubRefusal $null $boot) -eq '')
    Yes 'no Bootstrap.cs refuses nothing' ((Get-StubRefusal $stub (Join-Path $work 'none.cs')) -eq '')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
