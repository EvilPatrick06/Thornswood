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

  Since issue #2432 the draft is found in GitHub's REST list of releases and
  each file is downloaded by its asset id, because gh release download finds
  a draft by its tag through GraphQL, and on 12 October GraphQL's secondary
  limit made a main Ship say there was no launcher while the draft held all
  three files. The fake gh answers those two REST calls, and the exe it hands
  over is every byte value with CR, LF and Ctrl-Z among them, so a download
  that went through a text pipe would not come out the same.

  This lifts the functions that do it, Get-SourceRepo, Get-ReleaseLauncher,
  Get-ReleaseStub and the REST helpers they call, out of the shipped Ship.ps1
  by the parser, the way the other ship tests lift their blocks, and drives
  them with a fake gh on PATH so nothing here reaches GitHub. If a function is
  renamed or moved, this says so rather than quietly testing nothing.

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
$lift = 'Get-SourceRepo', 'Get-ReleaseLauncher', 'Get-ReleaseStub', 'ConvertTo-GhArgument', 'Invoke-GhToStream', 'Find-ReleaseByTag', 'Save-ReleaseAssets'
foreach ($n in $lift) { Yes "Ship.ps1 has $n" ($fns.ContainsKey($n)) }
if (@($lift | Where-Object { -not $fns.ContainsKey($_) }).Count) { Done }
foreach ($n in $lift) { Invoke-Expression $fns[$n] }
# Issue #2432: nothing in the release download asks GraphQL any more.
$dl = ($lift | Where-Object { $_ -ne 'Get-SourceRepo' } | ForEach-Object { $fns[$_] }) -join "`n"
Yes 'the launcher and the setup program are no longer fetched with gh release download (GraphQL)' ($dl -notmatch 'release download' -and $dl -notmatch '(?i)graphql')
Yes '  but from the REST list of releases, drafts included' ($dl.Contains('repos/$repo/releases?per_page=100&page=$page'))
Yes '  and by asset id, as application/octet-stream' ($dl.Contains("'Accept: application/octet-stream', `"repos/`$repo/releases/assets/`$(`$a.id)`""))
Yes '  straight from gh''s standard output into the file, not through a PowerShell redirect' ($dl.Contains('$p.StandardOutput.BaseStream.CopyTo($to)') -and $dl.Contains('[IO.File]::Create($path)'))

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
    # It answers the two REST calls Ship makes (#2432), the way GitHub does for
    # the drafts release.yml makes:
    #   api ... repos/<repo>/releases?per_page=100&page=<n>   the list, as JSON
    #   api -H Accept: application/octet-stream repos/<repo>/releases/assets/<id>
    #                                                          the file's bytes
    # Every call is written to TS_FAKE_GH_LOG. TS_FAKE_GH_MODE bends it: good
    # (default), mismatch (wrong hashes), noline (no line for either), nostub
    # (a release drafted before #932: the launcher and its line, no setup
    # program), norelease (the repository has no release for the tag), fail
    # (gh stops on GitHub's rate limit, the 12 October case), twodrafts (an
    # older draft for the same tag with wrong hashes, listed first), paged (the
    # draft is on the second page of the list), short (the file comes down
    # shorter than the release lists), dlfail (the list answers, the download
    # does not).
    $helper = Join-Path $bin 'fake-gh.ps1'
    [IO.File]::WriteAllText($helper, @'
$mode = $env:TS_FAKE_GH_MODE; if (-not $mode) { $mode = 'good' }
if ($env:TS_FAKE_GH_LOG) { [IO.File]::AppendAllText($env:TS_FAKE_GH_LOG, ((@('gh') + @($args | ForEach-Object { [string]$_ })) -join ' ') + "`n") }
function Out-Bytes([byte[]]$b) { $o = [Console]::OpenStandardOutput(); $o.Write($b, 0, $b.Length); $o.Flush() }
if ($mode -eq 'fail') { [Console]::Error.WriteLine('HTTP 403: You have exceeded a secondary rate limit.'); exit 1 }
$utf8 = New-Object Text.UTF8Encoding($false)
$exe = New-Object byte[] 518
for ($i = 0; $i -lt 512; $i++) { $exe[$i] = [byte]($i % 256) }
$tail = 13, 10, 10, 13, 26, 0
for ($j = 0; $j -lt $tail.Count; $j++) { $exe[512 + $j] = [byte]$tail[$j] }
$stub = $utf8.GetBytes('the setup program CI built for this tag')
function Hash([byte[]]$b) { $s = [Security.Cryptography.SHA256]::Create(); try { return (($s.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $s.Dispose() } }
function Sums([bool]$bad, [bool]$withStub) {
    $l = @()
    foreach ($p in @(@('Thornswood.exe', $exe), @('setup-stub.exe', $stub))) {
        if ($p[0] -eq 'setup-stub.exe' -and -not $withStub) { continue }
        $h = if ($bad) { '0' * 64 } else { Hash $p[1] }
        $n = if ($mode -eq 'noline') { 'something-else.exe' } else { $p[0] }
        $l += "$h  $n"
    }
    return $utf8.GetBytes(($l -join "`n") + "`n")
}
$withStub = $mode -ne 'nostub'
$files = @{ 11 = $exe; 12 = $stub; 13 = (Sums ($mode -eq 'mismatch') $withStub); 51 = $exe; 52 = $stub; 53 = (Sums $true $true) }
function Asset([int]$id, [string]$name, [int]$extra = 0) { return [ordered]@{ id = $id; name = $name; size = $files[$id].Length + $extra } }
function Release([long]$id, [string]$tag, $assets) { return [ordered]@{ id = $id; tag_name = $tag; draft = $true; assets = @($assets) } }
$extra = if ($mode -eq 'short') { 7 } else { 0 }
$mine = @((Asset 11 'Thornswood.exe' $extra), (Asset 13 'SHA256SUMS'))
if ($withStub) { $mine = @((Asset 12 'setup-stub.exe' $extra)) + $mine }
$other = Release 300 'v1.2.2' @()
$list = switch ($mode) {
    'norelease' { @($other) }
    'twodrafts' { @((Release 400 'v1.2.3' @((Asset 51 'Thornswood.exe'), (Asset 52 'setup-stub.exe'), (Asset 53 'SHA256SUMS'))), $other, (Release 401 'v1.2.3' $mine)) }
    default { @((Release 401 'v1.2.3' $mine), $other) }
}
$target = [string]$args[$args.Count - 1]
$m = [regex]::Match($target, '^repos/[^/]+/[^/]+/releases\?per_page=100&page=(\d+)$')
if ($m.Success) {
    $page = [int]$m.Groups[1].Value
    if ($mode -eq 'paged') {
        if ($page -eq 1) { $list = @(1..100 | ForEach-Object { Release (1000 + $_) ('v0.0.' + $_) @() }) } elseif ($page -ne 2) { $list = @() }
    } elseif ($page -ne 1) { $list = @() }
    Out-Bytes ($utf8.GetBytes((ConvertTo-Json -InputObject @($list) -Depth 5 -Compress)))
    exit 0
}
$m = [regex]::Match($target, '^repos/[^/]+/[^/]+/releases/assets/(\d+)$')
if ($m.Success -and ($args -contains 'Accept: application/octet-stream')) {
    if ($mode -eq 'dlfail') { [Console]::Error.WriteLine('HTTP 502: Bad Gateway'); exit 1 }
    $id = [int]$m.Groups[1].Value
    if (-not $files.ContainsKey($id)) { [Console]::Error.WriteLine('HTTP 404: Not Found'); exit 1 }
    Out-Bytes $files[$id]
    exit 0
}
[Console]::Error.WriteLine("the fake gh does not know: $($args -join ' ')")
exit 9
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
    $ghLog = Join-Path $work 'gh-calls.txt'
    $env:TS_FAKE_GH_LOG = $ghLog
    function Calls { if (Test-Path -LiteralPath $ghLog) { return @(Get-Content -LiteralPath $ghLog | Where-Object { $_ }) } return @() }
    # The exe the fake hands over: every byte value, then CR LF LF CR, Ctrl-Z
    # and a zero, which a text pipe would change or cut short.
    $exeBytes = New-Object byte[] 518
    for ($i = 0; $i -lt 512; $i++) { $exeBytes[$i] = [byte]($i % 256) }
    $tail = 13, 10, 10, 13, 26, 0
    for ($j = 0; $j -lt $tail.Count; $j++) { $exeBytes[512 + $j] = [byte]$tail[$j] }

    # ---- Get-ReleaseLauncher -----------------------------------------------------
    $into = Join-Path $work 'download'

    # 1. A good download verifies and leaves the exe in place.
    $env:TS_FAKE_GH_MODE = 'good'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "a matching download verifies and returns nothing: '$why'" ($why -eq '')
    Yes '  and the exe is sitting in the folder' (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe'))
    $got = if (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe')) { [IO.File]::ReadAllBytes((Join-Path $into 'Thornswood.exe')) } else { @() }
    Yes ("  byte for byte, CR, LF, Ctrl-Z and zero bytes included ({0} of {1} bytes)" -f $got.Length, $exeBytes.Length) (
        $got.Length -eq $exeBytes.Length -and [Convert]::ToBase64String($got) -eq [Convert]::ToBase64String($exeBytes))
    $calls = Calls
    Yes ("  found through the REST list of releases and downloaded by asset id, nothing else asked of gh: " + ($calls -join '; ')) (
        $calls.Count -eq 3 -and $calls[0] -match '^gh api .*repos/EvilPatrick06/Thornswood/releases\?per_page=100&page=1$' -and
        @($calls | Where-Object { $_ -match '^gh api -H Accept: application/octet-stream repos/EvilPatrick06/Thornswood/releases/assets/(11|13)$' }).Count -eq 2)
    Yes '  and nothing in this folder is left beside them' (@(Get-ChildItem -LiteralPath $into -File | Where-Object { $_.Name -notin 'Thornswood.exe', 'SHA256SUMS' }).Count -eq 0)

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
    $env:TS_FAKE_GH_MODE = 'norelease'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes 'no release yet stops the ship' ($why -ne '')
    Yes "  and says this machine does not compile it: '$why'" ($why -match 'this machine does not compile it')
    Yes '  and hands over the exact tag commands' ($why -match 'git tag v1\.2\.3' -and $why -match 'git push origin v1\.2\.3')
    Yes '  in the house words' ($why -notmatch 'player' -and $why.IndexOf([char]0x2014) -lt 0)
    Yes '  and nothing is left in the folder to be taken for it' (-not (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe')))

    # 4a. GitHub refusing gh (the 12 October rate limit) is not "no launcher":
    # it says what gh said and that the release is not the problem (#2432).
    $env:TS_FAKE_GH_MODE = 'fail'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "gh failing stops the ship with what gh said: '$why'" ($why -match 'secondary rate limit' -and $why -match 'Nothing was published')
    Yes '  and does not say there is no launcher for the tag' ($why -notmatch 'There is no verified launcher' -and $why -notmatch 'git push origin')
    Yes '  in the house words' ($why -notmatch 'player' -and $why.IndexOf([char]0x2014) -lt 0)

    # 4b. Two drafts for one tag (v1.1.96 has two): the newest is taken, even
    # listed after the older one, whose hashes would not match.
    Remove-Item -LiteralPath $ghLog -Force -ErrorAction SilentlyContinue
    $env:TS_FAKE_GH_MODE = 'twodrafts'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "two drafts for the tag: the newest is taken and verifies: '$why'" ($why -eq '')
    Yes '  its files, not the older draft''s' (@(Calls | Where-Object { $_ -match 'releases/assets/1[13]$' }).Count -ge 2 -and @(Calls | Where-Object { $_ -match 'releases/assets/5[13]$' }).Count -eq 0)

    # 4c. A draft on the second page of the list is still found.
    Remove-Item -LiteralPath $ghLog -Force -ErrorAction SilentlyContinue
    $env:TS_FAKE_GH_MODE = 'paged'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "a draft on the second page of 100 is found: '$why'" ($why -eq '' -and @(Calls | Where-Object { $_ -match 'page=2$' }).Count -eq 1 -and @(Calls | Where-Object { $_ -match 'page=3$' }).Count -eq 0)

    # 4d. A file that comes down shorter than the release lists is refused and
    # not left in the folder.
    $env:TS_FAKE_GH_MODE = 'short'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "a download shorter than the release lists is refused: '$why'" ($why -match 'came down as 518 bytes, and the release lists 525' -and $why -match 'Nothing was published')
    Yes '  and the short file is not left there' (-not (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe')))

    # 4e. The list answers and the download does not: said as that.
    $env:TS_FAKE_GH_MODE = 'dlfail'
    $why = Get-ReleaseLauncher 'EvilPatrick06/Thornswood' '1.2.3' $into
    Yes "a download gh could not make is refused with what gh said: '$why'" ($why -match 'could not download Thornswood\.exe' -and $why -match 'HTTP 502' -and $why -notmatch 'There is no verified launcher')

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

    $env:TS_FAKE_GH_MODE = 'norelease'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes 'no release at all stops it too' ($why -match 'no setup program')

    # 9. GitHub refusing gh is said as that here too, not as a missing stub.
    $env:TS_FAKE_GH_MODE = 'fail'
    $why = Get-ReleaseStub 'EvilPatrick06/Thornswood' '1.2.3' $stubInto
    Yes "gh failing stops it with what gh said, not as no setup program: '$why'" ($why -match 'secondary rate limit' -and $why -notmatch 'no setup program' -and $why -match 'Nothing was published')
}
finally {
    $env:PATH = $oldPath
    $env:TS_FAKE_GH_MODE = $oldMode
    $env:TS_FAKE_GH_LOG = $null
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
