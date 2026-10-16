<#
  test-459-engine-workflow.ps1

      pwsh -NoProfile -File .\tests\test-459-engine-workflow.ps1

  The engine built in CI (#459): the shape of .github\workflows\engine.yml,
  and the part Build-Engine.ps1, Build-Server.ps1, EngineJobs.ps1 and
  Bootstrap-VPS.ps1 play in it.

  WHY. Patrick decided on 15 Oct: the engine is built on GitHub's hosted
  runner first, and on the VPS runners when that is refused ("C, then B"),
  the way the build check falls back (#2407). Each piece of that is a line of
  YAML or a line of a script that a later edit could drop without anything
  else going red: the fallback's condition, the manual start (a pull
  request's code reaches the box through build-pr.yml alone, #1306), the
  image the fork's generator needs, the steps that make
  the records a pin pull request takes, the cleanup that keeps four runners'
  build folders off the box's disk, the CI=true the fork's CMakeLists.txt
  reads, and the SKYRIM_DIR a runner does not have.

  Read only, apart from a child pwsh that dot-sources EngineJobs.ps1 and
  Build-Engine.ps1 -Check against an empty folder, which changes nothing. Runs
  anywhere pwsh runs; nothing is built.
#>
[CmdletBinding()]
param([string]$WorkflowPath)
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$root = Split-Path -Parent $Here
if (-not $WorkflowPath) { $WorkflowPath = Join-Path $root '.github/workflows/engine.yml' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$wf = [IO.File]::ReadAllText($WorkflowPath).Replace("`r`n", "`n")
$lines = $wf -split "`n"
# The text with every comment line taken out, so a word in a comment is not
# read as a setting.
$code = (@($lines | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")

# The text of one job: from "  <name>:" to the next line indented two spaces.
function Get-Job([string]$name) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq "  ${name}:") { $start = $i; break } }
    if ($start -lt 0) { return '' }
    $end = $lines.Count
    for ($j = $start + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^  \S') { $end = $j; break } }
    return (($lines[$start..($end - 1)] | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}
# One step's text, by the start of its name, up to the next step or job.
function Get-Step([string]$text, [string]$nameStart) {
    return [regex]::Match($text, ("(?ms)^      - name: " + [regex]::Escape($nameStart) + "[^\n]*\n(.*?)(?=^      - (name|uses):|^  \S|\z)")).Value
}

$head = $code.Substring(0, [Math]::Max(0, $code.IndexOf("`njobs:")))
$vps = Get-Job 'engine-vps'
$hosted = Get-Job 'engine'

# ---- 1. when it runs ----------------------------------------------------------
Yes 'it is the Engine build workflow' ($code -match '(?m)^name: Engine build$')
Yes 'a manual run names the fork commit, empty for the pin' ($head -match '(?ms)workflow_dispatch:.*?commit:.*?default: ''''')
Yes 'a manual run may ask for hosted or vps, hosted the default' ($head -match '(?ms)runner:.*?options: \[hosted, vps\].*?default: hosted')
Yes 'it runs only when started by hand: no pull request, push or other trigger reaches the box through it (#1306)' (
    @([regex]::Matches(($head -replace '(?s)^.*?\non:\n', '' -replace '(?s)\npermissions:.*$', ''), '(?m)^  (\w+):') | ForEach-Object { $_.Groups[1].Value }) -join ',' -eq 'workflow_dispatch')
Yes 'the token reads the repository and writes nothing' ($head -match '(?m)^permissions:\n  contents: read$' -and $code -notmatch ':\s*write\b')
Yes 'a build is never cancelled by another run for the same commit' ($head -match '(?m)^  cancel-in-progress: false$')

# ---- 2. where: hosted first, the box when it did not succeed (#2407) ----------
Yes 'the hosted job is GitHub''s windows-2022, the image with the generator the fork demands' ($hosted -match '(?m)^    runs-on: windows-2022$')
Yes 'the hosted job is skipped when BUILD_RUNNER is vps or the run asked for the box' ($hosted -match "if: \$\{\{ vars\.BUILD_RUNNER != 'vps' && inputs\.runner != 'vps' \}\}")
Yes 'the fallback waits on the hosted job' ($vps -match '(?m)^    needs: engine$')
Yes 'the fallback runs when the hosted job did not succeed and was not cancelled' ($vps -match "!cancelled\(\) && needs\.engine\.result != 'success' && needs\.engine\.result != 'cancelled'")
Yes 'the fallback is the VPS runners'' label' ($vps -match '(?m)^    runs-on: \[self-hosted, Windows, thornswood-vps\]$')
Yes 'the VPS label is in the fallback alone' (([regex]::Matches($code, 'thornswood-vps')).Count -eq 1)
Yes 'the two jobs run one list of steps (the anchor)' ($vps -match '(?m)^    steps: &engine$' -and $hosted -match '(?m)^    steps: \*engine$')
$tv = [regex]::Match($vps, 'timeout-minutes: (\d+)'); $th = [regex]::Match($hosted, 'timeout-minutes: (\d+)')
Yes 'each job has its own limit: the box 360 minutes, GitHub''s runner 300' ($tv.Success -and [int]$tv.Groups[1].Value -eq 360 -and $th.Success -and [int]$th.Groups[1].Value -eq 300)

# ---- 3. what it runs, in order ------------------------------------------------
$order = @('uses: actions/checkout@', '- name: Which fork commit', '- name: Fetch the fork at that commit', '- name: Where vcpkg keeps',
           'uses: actions/cache/restore@', '- name: Build the engine', 'uses: actions/cache/save@', '- name: Build every server file again',
           '- name: Record the client', '- name: Check the records name this commit', '- name: Gather what this run made',
           'uses: actions/upload-artifact@', '- name: Free the box''s disk')
$at = -1; $inOrder = $true
foreach ($o in $order) { $i = $vps.IndexOf($o); if ($i -le $at) { $inOrder = $false; Write-Host "  out of order or missing: $o" }; $at = $i }
Yes 'the steps run in the order the header gives' $inOrder
Yes 'every action is pinned to a full commit with its tag beside it' (@([regex]::Matches($code, '(?m)^\s*(- )?uses: (\S+)') | Where-Object { $_.Groups[2].Value -notmatch '@[0-9a-f]{40}$' }).Count -eq 0 -and
                                                                    @([regex]::Matches($wf, '(?m)^\s*(- )?uses: \S+@[0-9a-f]{40}(?! # v)')).Count -eq 0)
$which = Get-Step $vps 'Which fork commit'
# Named in two places only: the env line that hands it to the script, and the
# concurrency group. Anywhere else it would be pasted into a script's text.
$named = @($code -split "`n" | Where-Object { $_ -match 'github\.event\.inputs\.commit' })
Yes 'the commit asked for reaches the script through env, never pasted into it' ($which -match 'INPUT_COMMIT: \$\{\{ github\.event\.inputs\.commit \}\}' -and
                                                                                $named.Count -eq 2 -and @($named | Where-Object { $_ -match '^\s+INPUT_COMMIT: ' -or $_ -match '^  group: engine-' }).Count -eq 2)
Yes 'with none asked, the commit is the one this branch pins' ($which -match 'git ls-tree HEAD engine/skymp')
$fetch = Get-Step $vps 'Fetch the fork at that commit'
Yes 'only a commit on the fork''s thornswood/engine-changes is built (One engine)' ($fetch -match 'merge-base --is-ancestor \$env:COMMIT origin/thornswood/engine-changes')
Yes 'the fork''s upstream is fetched, for the records'' upstreamBase' ($fetch -match 'skyrim-multiplayer/skymp\.git' -and $fetch -match 'fetch upstream main')
$vc = Get-Step $vps 'Where vcpkg keeps'
Yes 'vcpkg keeps what it built in a files cache beside the checkout' ($vc -match 'VCPKG_BINARY_SOURCES=clear;files,' -and $vc -match 'RUNNER_WORKSPACE')
Yes 'the cache key is the fork''s vcpkg commit and its manifest and overlays' ($vc -match 'HEAD:vcpkg' -and $vc -match 'vcpkg\.json' -and $vc -match 'overlay_ports' -and $vc -match 'overlay_triplets')
Yes 'the Actions cache is GitHub''s runner''s only; the box keeps its own folder' (
    ([regex]::Matches($vps, "(?ms)uses: actions/cache/(restore|save)@[^\n]*\n\s+if: runner\.environment == 'github-hosted'")).Count -eq 2)
$build = Get-Step $vps 'Build the engine'
Yes 'the engine is built with no game: Build-Engine.ps1 -NoSkyrim' ($build -match '\.\\scripts\\release\\Build-Engine\.ps1 -NoSkyrim -NoPause')
Yes 'a build of a new commit (exit 2, the client is not the recorded one) goes on, anything else stops' ($build -match '\$code -ne 0 -and \$code -ne 2')
$srv = Get-Step $vps 'Build every server file again'
Yes 'the server is built again and recorded (Build-Server.ps1 without -NoRecord)' ($srv -match '\.\\scripts\\release\\Build-Server\.ps1 -NoPause' -and $srv -notmatch 'NoRecord')
Yes 'the client is recorded from the same fork' ((Get-Step $vps 'Record the client') -match 'New-ClientBuildRecord\.ps1 -Dist engine\\skymp\\build\\dist\\client -Clone engine\\skymp')
$check = Get-Step $vps 'Check the records name this commit'
Yes 'both records are held to their shape and to the commit built' ($check -match 'Check-Records\.ps1' -and $check -match 'source\.commit' -and $check -match 'forkCommit')
$gather = Get-Step $vps 'Gather what this run made'
Yes 'the server build is made the artifact the store keeps (ServerArtifact.ps1)' ($gather -match 'New-ThornswoodServerBuildArtifact -From engine\\skymp\\build\\dist\\server -Record records\\server-build\.json')
Yes 'the six client files go in, each held to the client record' ($gather -match 'client-build\.json' -and $gather -match 'is not the file the client record names')
Yes 'SHA256SUMS lists every file' ($gather -match 'SHA256SUMS')
Yes 'the artifact is engine-<fork commit 12>, kept 30 days, and none is an error' ($gather -match 'name=engine-' -and $vps -match 'if-no-files-found: error' -and $vps -match 'retention-days: 30')
$free = Get-Step $vps 'Free the box''s disk'
Yes 'the box''s copy of the fork and its build go however the run ended, on the box only' ($free -match "if: always\(\) && runner\.environment == 'self-hosted'" -and $free -match 'submodule deinit --force engine/skymp')
Yes 'always() is in that cleanup alone' (([regex]::Matches($code, 'always\(\)')).Count -eq 1)
Yes 'nothing is sent and nothing committed: no ssh, scp, push or Deploy' ($code -notmatch '\b(ssh|scp)\b' -and $code -notmatch 'git push' -and $code -notmatch 'Deploy-|Publish-')
Yes 'the header names the box''s one step for the fallback' ($wf -match "Bootstrap-VPS\.ps1 -Arguments '-IncludeEngineTools -SkipFirewall'")

# ---- 4. the scripts' part -----------------------------------------------------
$engine = [IO.File]::ReadAllText((Join-Path $root 'scripts/release/Build-Engine.ps1'))
$server = [IO.File]::ReadAllText((Join-Path $root 'scripts/release/Build-Server.ps1'))
$jobsLib = [IO.File]::ReadAllText((Join-Path $root 'scripts/release/EngineJobs.ps1'))
Yes 'Build-Engine.ps1 takes -NoSkyrim' ($engine -match '\[switch\]\$NoSkyrim')
Yes '  and leaves SKYRIM_DIR out of the configure with it, and only with it' ($engine -match '\$skyrimArg = @\(if \(-not \$NoSkyrim\) \{ "-DSKYRIM_DIR=\$SkyrimDir" \}\)' -and $engine -match "'-DBUILD_SKYRIM_PLATFORM=ON' @skyrimArg @pwshArg")
Yes '  and asks for no SkyrimSE.exe with it' ($engine -match '(?m)^if \(\$NoSkyrim\) \{ Ok ')
Yes 'EngineJobs.ps1 has Clear-EngineCiSwitch' ($jobsLib -match 'function Clear-EngineCiSwitch')
$firstCmake = $engine.IndexOf('Run $cmake')
$clear = $engine.IndexOf('$ciSaid = Clear-EngineCiSwitch')
Yes 'Build-Engine.ps1 clears CI before it runs cmake' ($clear -gt 0 -and $firstCmake -gt $clear)
$clearS = $server.IndexOf('$ciSaid = Clear-EngineCiSwitch')
$cmakeS = $server.IndexOf('& $cmake $BuildDir')
Yes 'Build-Server.ps1 clears CI before it generates the build again over its cache' ($clearS -gt 0 -and $cmakeS -gt $clearS -and $server.IndexOf("EngineJobs.ps1") -lt $clearS)

# Clear-EngineCiSwitch itself, in a child pwsh so this run's environment is untouched.
$pwsh = (Get-Process -Id $PID).Path
$probe = @'
param([string]$Lib, [string]$Ci)
if ($Ci -eq '<unset>') { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $Ci }
. $Lib
$said = Clear-EngineCiSwitch
'SAID ' + [bool]$said
'CI ' + $(if (Test-Path Env:CI) { $env:CI } else { '<unset>' })
'@
$probeFile = Join-Path ([IO.Path]::GetTempPath()) ('engine-ci-probe-' + [Guid]::NewGuid().ToString('N') + '.ps1')
[IO.File]::WriteAllText($probeFile, $probe)
try {
    $jobsPath = Join-Path $root 'scripts/release/EngineJobs.ps1'
    $a = @(& $pwsh -NoProfile -File $probeFile -Lib $jobsPath -Ci 'true')
    Yes 'with CI=true, it says so and takes CI out' ($a -contains 'SAID True' -and $a -contains 'CI <unset>')
    $b = @(& $pwsh -NoProfile -File $probeFile -Lib $jobsPath -Ci '<unset>')
    Yes 'with no CI, it says nothing and changes nothing' ($b -contains 'SAID False' -and $b -contains 'CI <unset>')
    $c = @(& $pwsh -NoProfile -File $probeFile -Lib $jobsPath -Ci 'false')
    Yes 'with CI anything but true (which the fork does not read), it leaves it' ($c -contains 'SAID False' -and $c -contains 'CI false')
} finally { Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue }

# Build-Engine.ps1 -Check -NoSkyrim against an empty folder, with CI=true: it
# says it cleared CI and asks for no game, whatever else this machine lacks.
$empty = Join-Path ([IO.Path]::GetTempPath()) ('engine-ci-fork-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $empty | Out-Null
$was = $env:CI
try {
    $env:CI = 'true'
    $said = @(& $pwsh -NoProfile -File (Join-Path $root 'scripts/release/Build-Engine.ps1') -Check -NoSkyrim -NoPause -Fork $empty -SkyrimDir (Join-Path $empty 'no-game') 2>&1 | ForEach-Object { "$_" })
    Yes 'Build-Engine.ps1 -Check with CI=true says it took CI out' (@($said | Where-Object { $_ -match 'CI=true was set' }).Count -eq 1)
    Yes '  and with -NoSkyrim asks for no SkyrimSE.exe' (@($said | Where-Object { $_ -match 'no game needed' }).Count -eq 1 -and @($said | Where-Object { $_ -match 'MISSING\s+SkyrimSE\.exe' }).Count -eq 0)
} finally {
    if ($null -eq $was) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $was }
    Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 5. the box's tools for the fallback --------------------------------------
$boot = [IO.File]::ReadAllText((Join-Path $root 'scripts/vps/Bootstrap-VPS.ps1'))
Yes 'Bootstrap-VPS.ps1 takes -IncludeEngineTools' ($boot -match '\[switch\]\$IncludeEngineTools')
Yes '  which takes -IncludeBuildTools with it' ($boot -match '(?m)^if \(\$IncludeEngineTools\) \{ \$IncludeBuildTools = \$true \}')
Yes '  adds the C++ workload and Visual Studio''s CMake to the Build Tools install' ($boot -match "'Microsoft\.VisualStudio\.Workload\.VCTools', '--includeRecommended'" -and $boot -match "'Microsoft\.VisualStudio\.Component\.VC\.CMake\.Project'" -and $boot -match "@\('modify', '--installPath'")
Yes '  through Microsoft''s installer, held to its signature' ($boot -match 'Installer\\setup\.exe' -and $boot -match '(?s)Get-AuthenticodeSignature -LiteralPath \$setup.*?Microsoft Corporation')
Yes '  and a pinned classic yarn into Node''s own folder' ($boot -match "\[string\]\`$YarnVersion = '1\.22\.22'" -and $boot -match "install --global --prefix \`$et\.NodeDir \('yarn@' \+ \`$YarnVersion\)")
Yes '  and finds them where Build-Engine.ps1 looks' ($boot -match 'Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake\.exe' -and $engine -match 'Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake\.exe')

# ---- 6. the page -------------------------------------------------------------
$readme = [IO.File]::ReadAllText((Join-Path $root 'engine/README.md'))
Yes 'engine\README.md has the engine built in CI, naming engine.yml' ($readme -match '(?m)^## The engine built in CI$' -and $readme -match 'engine\.yml')
Yes '  and the run that starts it and the artifact a pin pull request takes' ($readme -match 'gh workflow run engine\.yml' -and $readme -match 'gh run download')

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
