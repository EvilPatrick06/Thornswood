<#
  test-ship-ci-launcher.ps1

  A main release takes the launcher CI built and verifies it, and never
  compiles the shipped binary here. Issue #457.

  Ship.ps1 no longer runs csc on the exe that reaches every launcher on a main
  release. .github\workflows\release.yml builds Thornswood.exe on a clean
  runner from the tag, writes SHA256SUMS beside it, and drafts a release; Ship
  downloads that asset and checks it against SHA256SUMS before a byte is packed.
  Byte-identical local and runner builds are impossible with the Framework 4
  csc, so the checksum file is the whole of the verification.

  This lifts the two functions that do it, Get-SourceRepo and
  Get-ReleaseLauncher, out of the shipped Ship.ps1 by the parser, the way the
  other ship tests lift their blocks, and drives them with a fake gh on PATH so
  nothing here reaches GitHub. If a function is renamed or moved, this says so
  rather than quietly testing nothing.

  Cross platform on purpose, so it runs in the cloud and on the VPS: the fake gh
  is a .ps1 on Windows and a shell script elsewhere calling the same
  PowerShell. Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ShipPath) { $ShipPath = Join-Path (Split-Path -Parent $Here) 'scripts/release/Ship.ps1' }

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

# ---- lift the two functions -------------------------------------------------
$src = [IO.File]::ReadAllText($ShipPath)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)

$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) { $fns[$f.Name] = $f.Extent.Text }
Yes 'Ship.ps1 has Get-SourceRepo' ($fns.ContainsKey('Get-SourceRepo'))
Yes 'Ship.ps1 has Get-ReleaseLauncher' ($fns.ContainsKey('Get-ReleaseLauncher'))
if (-not ($fns.ContainsKey('Get-SourceRepo') -and $fns.ContainsKey('Get-ReleaseLauncher'))) { Done }
Invoke-Expression $fns['Get-SourceRepo']
Invoke-Expression $fns['Get-ReleaseLauncher']

$onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

function Run-Git {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git @args 2>&1 | Out-Null; return $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-ci-launcher-' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $work 'bin'
$oldPath = $env:PATH
$oldMode = $env:TS_FAKE_GH_MODE
$ps = (Get-Process -Id $PID).Path
try {
    New-Item -ItemType Directory -Force -Path $work, $bin | Out-Null

    # ---- Get-SourceRepo: owner/name off origin, or the fallback -------------------
    if (Get-Command git -EA SilentlyContinue) {
        $repoA = Join-Path $work 'repoA'
        New-Item -ItemType Directory -Force -Path $repoA | Out-Null
        [void](Run-Git init -q $repoA)
        [void](Run-Git -C $repoA remote add origin 'https://x-access-token:SECRET@github.com/EvilPatrick06/Thornswood')
        Yes "Get-SourceRepo reads owner/name off an https origin with a token: '$(Get-SourceRepo $repoA)'" ((Get-SourceRepo $repoA) -eq 'EvilPatrick06/Thornswood')

        $repoB = Join-Path $work 'repoB'
        New-Item -ItemType Directory -Force -Path $repoB | Out-Null
        [void](Run-Git init -q $repoB)
        [void](Run-Git -C $repoB remote add origin 'git@github.com:Some-Owner/Some-Repo.git')
        Yes "Get-SourceRepo reads owner/name off an ssh origin: '$(Get-SourceRepo $repoB)'" ((Get-SourceRepo $repoB) -eq 'Some-Owner/Some-Repo')

        $repoC = Join-Path $work 'repoC'
        New-Item -ItemType Directory -Force -Path $repoC | Out-Null
        [void](Run-Git init -q $repoC)
        Yes "Get-SourceRepo falls back when there is no origin: '$(Get-SourceRepo $repoC)'" ((Get-SourceRepo $repoC) -eq 'EvilPatrick06/Thornswood')
    } else {
        Write-Host 'SKIP  git is not on PATH, so Get-SourceRepo is not exercised'
    }

    # ---- a fake gh on PATH -------------------------------------------------------
    # On "release download" it writes Thornswood.exe and a SHA256SUMS into --dir,
    # the way the real gh would from the release CI drafted. TS_FAKE_GH_MODE bends
    # it: good (default), mismatch (wrong hash), noline (no Thornswood.exe line),
    # fail (exits non-zero and writes nothing, as a missing release does).
    $helper = Join-Path $bin 'fake-gh.ps1'
    [IO.File]::WriteAllText($helper, @'
$mode = $env:TS_FAKE_GH_MODE; if (-not $mode) { $mode = 'good' }
if ($mode -eq 'fail') { exit 3 }
$dir = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--dir') { $dir = $args[$i + 1] } }
if (-not $dir) { exit 0 }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$exe = Join-Path $dir 'Thornswood.exe'
[IO.File]::WriteAllText($exe, 'the launcher CI built for this tag')
$h = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
if ($mode -eq 'mismatch') { $h = ('0' * 64) }
$name = if ($mode -eq 'noline') { 'something-else.exe' } else { 'Thornswood.exe' }
Set-Content -LiteralPath (Join-Path $dir 'SHA256SUMS') -Value ("$h  $name") -Encoding ascii
exit 0
'@)
    if ($onWindows) {
        # A .ps1, not a .cmd (issue #1092): PowerShell finds it on PATH ahead of
        # the real gh.exe and hands it every argument whole. A .cmd gets them
        # through cmd.exe, which ends a command at a bare &, so a temp folder
        # under C:\ThornswoodTemps&Worktrees cut --dir in two.
        Copy-Item -LiteralPath $helper -Destination (Join-Path $bin 'gh.ps1')
    } else {
        $sh = Join-Path $bin 'gh'
        [IO.File]::WriteAllText($sh, "#!/usr/bin/env bash`nexec `"$ps`" -NoProfile -File `"$helper`" `"`$@`"`n")
        & chmod +x $sh
    }
    $env:PATH = $bin + [IO.Path]::PathSeparator + $oldPath

    # ---- Get-ReleaseLauncher -----------------------------------------------------
    $into = Join-Path $work 'download'

    # 1. A good download verifies and leaves the exe in place.
    $env:TS_FAKE_GH_MODE = 'good'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "a matching download verifies and returns nothing: '$why'" ($why -eq '')
    Yes '  and the exe is sitting in the folder' (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe'))

    # 2. A checksum that does not match is refused, and says so.
    $env:TS_FAKE_GH_MODE = 'mismatch'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes 'a download whose checksum does not match is refused' ($why -ne '')
    Yes "  and the refusal names the mismatch: '$why'" ($why -match 'does not match its SHA256SUMS')
    Yes '  and says not to ship it' ($why -match 'Do not ship it')

    # 3. A SHA256SUMS with no line for the exe cannot be verified.
    $env:TS_FAKE_GH_MODE = 'noline'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes 'a SHA256SUMS with no Thornswood.exe line is refused' ($why -match 'no line for Thornswood\.exe')

    # 4. No release yet is the handoff: push the tag, wait for CI, Ship again.
    $env:TS_FAKE_GH_MODE = 'fail'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes 'no release yet stops the ship' ($why -ne '')
    Yes "  and says this machine does not compile it: '$why'" ($why -match 'this machine does not compile it')
    Yes '  and hands over the exact tag commands' ($why -match 'git tag v1\.2\.3' -and $why -match 'git push origin v1\.2\.3')
    Yes '  in the house words' ($why -notmatch 'player' -and $why.IndexOf([char]0x2014) -lt 0)
}
finally {
    $env:PATH = $oldPath
    $env:TS_FAKE_GH_MODE = $oldMode
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
