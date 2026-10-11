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

  The setup program the installer is built around comes the same way since
  issue #932: release.yml attaches setup-stub.exe beside the launcher and
  lists it in the same SHA256SUMS, a main Ship with -Package downloads and
  checks it with Get-ReleaseStub before anything is published, and hands it
  to Package-Thornswood.ps1 -Stub. On 28 September a main Ship -Package
  stopped on "setup-stub.exe is missing" after the release was out, because
  a main Ship never runs Build-Launcher, which is what compiles the stub.

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
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

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
Yes 'Ship.ps1 has Get-ReleaseStub' ($fns.ContainsKey('Get-ReleaseStub'))
if (-not ($fns.ContainsKey('Get-SourceRepo') -and $fns.ContainsKey('Get-ReleaseLauncher') -and $fns.ContainsKey('Get-ReleaseStub'))) { Done }
Invoke-Expression $fns['Get-SourceRepo']
Invoke-Expression $fns['Get-ReleaseLauncher']
Invoke-Expression $fns['Get-ReleaseStub']

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
    # On "release download" it writes each asset its --pattern names into --dir,
    # with a SHA256SUMS listing Thornswood.exe and setup-stub.exe, the way the
    # real gh would from the release CI drafted. TS_FAKE_GH_MODE bends it: good
    # (default), mismatch (wrong hashes), noline (no line for either), fail
    # (exits non-zero and writes nothing, as a missing release does), nostub (a
    # release drafted before #932: the launcher and its line, no setup program).
    $helper = Join-Path $bin 'fake-gh.ps1'
    [IO.File]::WriteAllText($helper, @'
$mode = $env:TS_FAKE_GH_MODE; if (-not $mode) { $mode = 'good' }
if ($mode -eq 'fail') { exit 3 }
$dir = ''
$want = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '--dir') { $dir = $args[$i + 1] }
    if ($args[$i] -eq '--pattern') { $want += [string]$args[$i + 1] }
}
if (-not $dir) { exit 0 }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$assets = [ordered]@{ 'Thornswood.exe' = 'the launcher CI built for this tag'; 'setup-stub.exe' = 'the setup program CI built for this tag' }
if ($mode -eq 'nostub') { $assets.Remove('setup-stub.exe') }
$lines = @()
foreach ($n in $assets.Keys) {
    $tmp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($tmp, $assets[$n])
    $h = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
    if ($want -contains $n) { Move-Item -LiteralPath $tmp -Destination (Join-Path $dir $n) -Force } else { Remove-Item -LiteralPath $tmp -Force }
    if ($mode -eq 'mismatch') { $h = ('0' * 64) }
    $name = if ($mode -eq 'noline') { 'something-else.exe' } else { $n }
    $lines += ("$h  $name")
}
if ($want -contains 'SHA256SUMS') { Set-Content -LiteralPath (Join-Path $dir 'SHA256SUMS') -Value $lines -Encoding ascii }
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

    # ---- Get-ReleaseStub (issue #932) ---------------------------------------------
    $stubInto = Join-Path $work 'stub'

    # 5. The setup program CI built verifies and lands in the folder.
    $env:TS_FAKE_GH_MODE = 'good'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes "the setup program CI built verifies and returns nothing: '$why'" ($why -eq '')
    Yes '  and setup-stub.exe is sitting in the folder' (Test-Path -LiteralPath (Join-Path $stubInto 'setup-stub.exe'))
    Yes '  and it is the one CI built, not a local one' ([IO.File]::ReadAllText((Join-Path $stubInto 'setup-stub.exe')) -eq 'the setup program CI built for this tag')

    # 6. A checksum that does not match is refused.
    $env:TS_FAKE_GH_MODE = 'mismatch'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes "a setup program whose checksum does not match is refused: '$why'" ($why -match 'does not match its SHA256SUMS' -and $why -match 'Do not ship it')

    # 7. No line for it cannot be verified, and says how to get one.
    $env:TS_FAKE_GH_MODE = 'noline'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes 'a SHA256SUMS with no setup-stub.exe line is refused' ($why -match 'no line for setup-stub\.exe')

    # 8. A release drafted before #932 has no setup program: build the tag again.
    $env:TS_FAKE_GH_MODE = 'nostub'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes "a release with no setup program stops the ship before anything is published: '$why'" ($why -match 'no setup program' -and $why -match 'Nothing was published')
    Yes '  and hands over the exact command that builds the tag again' ($why -match [regex]::Escape('gh workflow run release.yml --repo EvilPatrick06/Thornswood -f tag=v1.2.3'))
    Yes '  in the house words' ($why -notmatch 'player' -and $why.IndexOf([char]0x2014) -lt 0)

    $env:TS_FAKE_GH_MODE = 'fail'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes 'no release at all stops it too' ($why -match 'no setup program')
}
finally {
    $env:PATH = $oldPath
    $env:TS_FAKE_GH_MODE = $oldMode
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- the pieces are joined up -----------------------------------------------------
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ShipPath))
$rel = [IO.File]::ReadAllText((Join-Path $repoRoot '.github/workflows/release.yml'))
Yes 'release.yml stops when the build made no setup-stub.exe' ($rel -match [regex]::Escape("if (-not (Test-Path 'out\setup-stub.exe'))"))
Yes '  lists it in SHA256SUMS beside the launcher' ($rel -match [regex]::Escape("foreach (`$n in 'Thornswood.exe', 'setup-stub.exe')"))
Yes '  and attaches it to the draft' ($rel -match [regex]::Escape('foreach ($asset in @($exe, $stub, $sums))'))
Yes 'Ship fetches it for a main -Package, before the build and the publish' ($src -match '(?s)if \(\$Package -and -not \$Dev -and -not \$DryRun\) \{.*?Get-ReleaseStub.*?# -+ build')
Yes '  and hands it to Package-Thornswood as -Stub' ($src -match [regex]::Escape("if (`$ciStub) { `$pkgArgs['Stub'] = `$ciStub }") -and $src -match [regex]::Escape("& (Join-Path `$Here 'Package-Thornswood.ps1') @pkgArgs"))
# Issue #1213: the site carries the one file build, so -Package asks for it,
# and every Package-Thornswood line Ship prints for a person says -OneFile too.
Yes '  in the one file shape the site carries (#1213)' ($src -match [regex]::Escape("`$pkgArgs = @{ Root = `$Root; OutDir = `$DistDir; NoPause = `$true; OneFile = `$true }"))
$told = @([regex]::Matches($src, "\.\\scripts\\release\\Package-Thornswood\.ps1[^'`"\r\n]*") | ForEach-Object { $_.Value })
Yes ('  and every Package-Thornswood command Ship prints says -OneFile (' + $told.Count + ')') ($told.Count -ge 5 -and @($told | Where-Object { $_ -notmatch ' -OneFile\b' }).Count -eq 0)
$pkg = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/release/Package-Thornswood.ps1'))
Yes 'Package-Thornswood takes -Stub and packs that one, refusing one that is not there' ($pkg -match '\[string\]\$Stub = ' -and $pkg -match '(?s)if \(\$Stub\) \{\s*if \(-not \(Test-Path -LiteralPath \$Stub\)\) \{ Die' -and $pkg -match '\$stub = \$stubNow')

Done
