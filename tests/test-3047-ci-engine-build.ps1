<#
  test-3047-ci-engine-build.ps1

      pwsh -NoProfile -File .\tests\test-3047-ci-engine-build.ps1

  Issue #3047. A Ship machine takes CI's build of the pin, held to the
  records, and never needs an engine build of its own.

  WHAT WAS WRONG, measured on 21 Oct 2026. Engine builds are not the same
  bytes twice, so records CI made match only CI's artifact. PR #3040 moved the
  pin to d3091eb4; One's recorded engine build was still a bf2b3b40 fork
  worktree; the dev Ship stopped at Check-ShipReady with "the build is not the
  recorded one", and every fix Check-ShipReady, Sync-Client, Setup-ShipMachine,
  Update-ShipRoot and Where.ps1 printed led to building the engine on One
  again, which could not have matched either. Run 39588485569's artifact held
  the exact client.

  WHAT IT HOLDS, in a scratch copy of the scripts with records made here and
  a stand-in GitHub, nothing sent anywhere:
    1. Find-EngineArtifact (EngineArtifact.ps1): no artifact, one past its
       days, one from another workflow, one from a red run are each "none",
       saying how to make it again; every green engine.yml one is a
       candidate, newest first, and a red one is not; a GitHub that cannot be read throws rather than saying none.
    2. Install-EngineArtifact: the right artifact goes in as an engine build
       (build\dist\client and build\dist\server, the artifact beside them,
       engine-artifact.json naming the run), CR LF records and all. Refused,
       with nothing put in place and no half folder left: a client file
       that is not the record's (with SHA256SUMS made to agree), a file
       SHA256SUMS does not name, one it names wrongly, records of another
       commit, a client file the record does not name, no
       client-licences.json, a licence text that is not the checkout's or
       that it does not have (#3099), a server zip of another record, and a
       folder that is there already.
       Get-EngineArtifactFolderProblems: a folder of another pin is not this
       one's.
    3. Where.ps1 and where.js: EngineArtifact is engine-ci\<pin 12> in the
       machine's data, answered with no record and whether or not it is
       there; {"ci": true} makes it EngineBuild, so ClientDist and ServerDist
       are under it, the two agree, and a pin move is another folder; a
       server record with no commit stops with a sentence.
    4. Get-EngineArtifact.ps1 whole, with a stand-in gh: -Check says it is on
       GitHub (exit 2) and writes nothing; a run fetches it (exit 0) and
       removes its scratch; a second run finds it there (exit 0); no artifact
       and a gh that fails each stop (exit 1) saying why. Two kept for the
       pin, the newer recorded later (#3243): the older, the checkout's, is
       taken after the newer is held and passed over with why; neither the
       checkout's stops (exit 1) naming both runs.
    5. Sync-Client.ps1 on a machine that takes CI's build, with a stand-in
       Get-EngineArtifact.ps1: without -Check it fetches the missing folder and
       copies the client in; -Check fetches nothing and names the script; a
       fetch that fails stops it; a game folder that already holds the
       client fetches nothing; another -Dist is never filled. Its stop for a
       build that is not the record names CI's build and no rebuild.
    6. Setup-ShipMachine.ps1: Save-EngineBuild ci writes {"ci": true};
       Test-EngineBuildIsCi reads it; no fix offers -Rebuild. Check-ShipReady's
       Get-ClientRows: a CI build GitHub keeps passes before the Ship fetches
       it, one it cannot have fails saying why, and the fix otherwise names
       -EngineBuild ci. No fix in the five scripts sends a Ship machine to
       Build-Engine or a new record.

  Writes only in its own scratch folder, which it removes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$env:THORNSWOOD_HARNESS = '1'
$Here = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Threw([scriptblock]$b) { try { & $b | Out-Null; return '' } catch { return $_.Exception.Message } }
function Put([string]$p, [string]$text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $p))
    [IO.File]::WriteAllText($p, $text, $utf8)
}
function ShaText([string]$t) { return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($t))) -replace '-', '').ToLowerInvariant() }
function ShaFile([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Same([string]$a, [string]$b) { return $a -and $b -and ([IO.Path]::GetFullPath($a).TrimEnd('\', '/') -eq [IO.Path]::GetFullPath($b).TrimEnd('\', '/')) }

$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-3047-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
$oldLad = $env:LOCALAPPDATA
$oldScratch = $env:THORNSWOOD_SCRATCH_ROOT
try {
    # ---- a scratch checkout: the real scripts, records made here ----------
    $repo = Join-Path $T 'repo'
    $null = New-Item -ItemType Directory -Force -Path $repo
    Copy-Item -LiteralPath (Join-Path $Here 'scripts') -Destination (Join-Path $repo 'scripts') -Recurse
    Copy-Item -LiteralPath (Join-Path $Here 'layout.json') -Destination $repo
    $env:LOCALAPPDATA = Join-Path $T 'localappdata'
    $env:THORNSWOOD_SCRATCH_ROOT = Join-Path $T 'scratch'
    $null = New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA

    $commit = 'd3091eb4aec1a08c1c68700b9c3cba7373291e1a'
    $client = [ordered]@{
        'Data\SKSE\Plugins\MpClientPlugin.dll'   = 'CLIENT-PLUGIN'
        'Data\Platform\Plugins\skymp5-client.js' = 'CLIENT-BUNDLE'
        'Data\Scripts\TESModPlatform.pex'        = 'CLIENT-PEX'
    }
    $fork = [ordered]@{
        'scam_native.node'               = 'the addon'
        'dist_back/skymp5-server.js'     = 'the javascript half'
        'dist_back/skymp5-server.js.map' = 'its map'
        'package.json'                   = '{"name":"skymp5-server"}'
        'yarn.lock'                      = '# lock'
        'launch_server.bat'              = 'node dist_back/skymp5-server.js'
        'data/scripts/ActiveMagicEffect.pex' = 'compiled papyrus'
    }
    function ClientRecordText([string]$c, [string]$at = '2026-10-21T11:00:08Z') {
        $files = [ordered]@{}
        foreach ($k in $client.Keys) { $files[$k] = [ordered]@{ sha256 = (ShaText $client[$k]); bytes = $client[$k].Length } }
        return (([ordered]@{ recordedUtc = $at; fork = 'https://github.com/EvilPatrick06/skymp'; forkBranch = 'thornswood/engine-changes'; forkCommit = $c.Substring(0, 8); files = $files }) | ConvertTo-Json -Depth 5).Replace("`r`n", "`n")
    }
    function ServerRecordText([string]$c) {
        $files = [ordered]@{}
        foreach ($k in $fork.Keys) { $files[$k] = [ordered]@{ sha256 = (ShaText $fork[$k]); bytes = $fork[$k].Length; commit = $c } }
        $src = [ordered]@{ repo = 'https://github.com/EvilPatrick06/skymp.git'; commit = $c }
        return (([ordered]@{ binary = 'scam_native.node'; sha256 = (ShaText $fork['scam_native.node']); source = $src; files = $files }) | ConvertTo-Json -Depth 5).Replace("`r`n", "`n")
    }
    # The libraries in the client file and their texts (#3099).
    $libText = "Copyright (c) 2012 - present, Victor Zverovich`nPermission is hereby granted"
    function LicenceRecordText([string]$c) {
        $ports = [ordered]@{ fmt = [ordered]@{ version = '11.2.0'; portVersion = 0; licence = 'MIT'; in = @('Data\SKSE\Plugins\MpClientPlugin.dll'); sha256 = (ShaText $libText); bytes = $libText.Length } }
        return (([ordered]@{ forkCommit = $c.Substring(0, 8); readWith = 'llvm-pdbutil'; files = [ordered]@{ 'Data\SKSE\Plugins\MpClientPlugin.dll' = @('fmt') }; ports = $ports }) | ConvertTo-Json -Depth 5).Replace("`r`n", "`n")
    }
    function Put-Licences([string]$dir, [string]$c) {
        Put (Join-Path $dir 'records\client-licences.json') (LicenceRecordText $c)
        Put (Join-Path $dir 'records\client-licences\fmt.txt') $libText
    }
    function Set-Records([string]$c) {
        Put (Join-Path $repo 'records\client-build.json') (ClientRecordText $c)
        Put (Join-Path $repo 'records\server-build.json') (ServerRecordText $c)
        Put-Licences $repo $c
    }
    Set-Records $commit

    . (Join-Path $repo 'scripts\release\EngineArtifact.ps1')

    # An artifact as engine.yml's "Gather what this run made" writes it, for
    # the records at $recDir (this checkout's unless told otherwise).
    $srvDist = Join-Path $T 'server-dist'
    foreach ($k in $fork.Keys) { Put (Join-Path $srvDist ($k -replace '/', '\')) $fork[$k] }
    function Write-Sums([string]$dir) {
        $base = (Resolve-Path -LiteralPath $dir).ProviderPath.TrimEnd('\', '/')
        $lines = foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object FullName)) {
            (ShaFile $f.FullName) + '  ' + $f.FullName.Substring($base.Length + 1).Replace('\', '/')
        }
        [IO.File]::WriteAllLines((Join-Path $dir 'SHA256SUMS'), [string[]]@($lines))
    }
    # -RecordedUtc: the client record another engine.yml run of the same build
    # writes, which differs only in when it was written (#3243).
    function New-Artifact([string]$dir, [string]$recCommit = $commit, [switch]$Crlf, [string]$RecordedUtc = '2026-10-21T11:00:08Z') {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        foreach ($k in $client.Keys) { Put (Join-Path $dir ('client\' + $k)) $client[$k] }
        $cr = ClientRecordText $recCommit $RecordedUtc; $sr = ServerRecordText $recCommit
        if ($Crlf) { $cr = $cr.Replace("`n", "`r`n"); $sr = $sr.Replace("`n", "`r`n") }
        Put (Join-Path $dir 'records\client-build.json') $cr
        Put (Join-Path $dir 'records\server-build.json') $sr
        Put-Licences $dir $recCommit
        $recFile = Join-Path $T ('server-record-' + [Guid]::NewGuid().ToString('N') + '.json')
        Put $recFile (ServerRecordText $recCommit)
        $null = New-ThornswoodServerBuildArtifact -From $srvDist -Record $recFile -OutDir (Join-Path $dir 'server')
        Put (Join-Path $dir 'fork-build.json') ('{"commit":"' + $recCommit + '"}')
        Write-Sums $dir
        return $dir
    }
    $run = [pscustomobject]@{ id = 39588485569; html_url = 'https://github.com/EvilPatrick06/Thornswood/actions/runs/39588485569'; path = '.github/workflows/engine.yml'; status = 'completed'; conclusion = 'success' }
    $art = [pscustomobject]@{ id = 12340888147; name = 'engine-d3091eb4aec1'; expired = $false; digest = 'sha256:' + ('a' * 64); size_in_bytes = 1234; workflow_run = [pscustomobject]@{ id = 39588485569 } }

    # ================================================ 1. Find-EngineArtifact ==
    Write-Host ''; Write-Host '1. Find-EngineArtifact'
    function Stand-In($arts, $runs) {
        $o = [pscustomobject]@{ Asked = New-Object Collections.Generic.List[string]; Get = $null }
        $o.Get = {
            param($path)
            $o.Asked.Add($path)
            if ($path -like 'repos/EvilPatrick06/Thornswood/actions/artifacts?name=engine-d3091eb4aec1*') { return [pscustomobject]@{ artifacts = @($arts) } }
            if ($path -match '^repos/EvilPatrick06/Thornswood/actions/runs/(\d+)$') { return @($runs | Where-Object { [string]$_.id -eq $Matches[1] })[0] }
            throw "stand-in GitHub was asked $path"
        }.GetNewClosure()
        return $o
    }
    $f = Find-EngineArtifact $commit (Stand-In @() @()).Get
    Yes '1. no artifact at all: none, saying to run engine.yml again' ($f.State -eq 'none' -and $f.Why -match 'gh workflow run engine\.yml --ref main')
    $old = $art.PSObject.Copy(); $old.expired = $true
    $f = Find-EngineArtifact $commit (Stand-In @($old) @($run)).Get
    Yes '1. one past its days: none, saying so' ($f.State -eq 'none' -and $f.Why -match 'past the 30 days' -and $f.Why -match 'gh workflow run engine\.yml')
    $other = $run.PSObject.Copy(); $other.path = '.github/workflows/build.yml'
    $f = Find-EngineArtifact $commit (Stand-In @($art) @($other)).Get
    Yes '1. one from another workflow: none' ($f.State -eq 'none' -and $f.Why -match 'finished green')
    $red = $run.PSObject.Copy(); $red.conclusion = 'failure'
    $f = Find-EngineArtifact $commit (Stand-In @($art) @($red)).Get
    Yes '1. one from a red engine.yml run: none' ($f.State -eq 'none')
    $newRun = $run.PSObject.Copy(); $newRun.id = 39600000000
    $newArt = $art.PSObject.Copy(); $newArt.id = 12350000000; $newArt.workflow_run = [pscustomobject]@{ id = 39600000000 }
    $f = Find-EngineArtifact $commit (Stand-In @($art, $newArt) @($run, $newRun)).Get
    Yes '1. two green ones: both are candidates, newest first' ($f.State -eq 'found' -and @($f.Candidates).Count -eq 2 -and [long]$f.Candidates[0].Artifact.id -eq 12350000000 -and [long]$f.Candidates[0].Run.id -eq 39600000000 -and [long]$f.Candidates[1].Run.id -eq 39588485569)
    Yes '1.   Run and Artifact are the newest, and the Why names both runs' ([long]$f.Artifact.id -eq 12350000000 -and [long]$f.Run.id -eq 39600000000 -and $f.Why -match '39600000000' -and $f.Why -match '39588485569' -and $f.Why -match "records are this checkout's")
    $redNew = $newRun.PSObject.Copy(); $redNew.conclusion = 'failure'
    $f = Find-EngineArtifact $commit (Stand-In @($art, $newArt) @($run, $redNew)).Get
    Yes '1. a red newer run is no candidate' ($f.State -eq 'found' -and @($f.Candidates).Count -eq 1 -and [long]$f.Run.id -eq 39588485569)
    $f = Find-EngineArtifact $commit (Stand-In @($art) @($run)).Get
    Yes '1. the green engine.yml one is found, naming its run' ($f.State -eq 'found' -and $f.Why -match '39588485569')
    $e = Threw { Find-EngineArtifact $commit { param($p) throw 'HTTP 401: Bad credentials' } }
    Yes '1. a GitHub that cannot be read throws, and is not "none"' ($e -match 'Bad credentials')

    # ============================================ 2. Install-EngineArtifact ==
    Write-Host ''; Write-Host '2. Install-EngineArtifact'
    $into = [string](& (Join-Path $repo 'scripts\release\Where.ps1') EngineArtifact)
    $parent = Split-Path -Parent $into
    function Left { return @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.partial-*' }).Count }
    function Refused([string]$tag, [scriptblock]$spoil, [string]$says) {
        $a = New-Artifact (Join-Path $T ('art-' + $tag))
        & $spoil $a
        $e = Threw { Install-EngineArtifact -From $a -Repo $repo -Into $into -Run $run -Artifact $art }
        Yes ("2. refused: $tag" + $(if ($e) { '  (' + $e.Substring(0, [Math]::Min(150, $e.Length)) + ')' } else { '' })) (
            $e -match 'nothing was put in place' -and $e -match $says -and -not (Test-Path -LiteralPath $into) -and (Left) -eq 0)
    }
    Refused 'a client file that is not the record''s, SHA256SUMS made to agree' { param($a) Put (Join-Path $a 'client\Data\Scripts\TESModPlatform.pex') 'A REBUILT PEX'; Write-Sums $a } 'TESModPlatform\.pex in the artifact is not the file records\\client-build\.json names'
    Refused 'a file SHA256SUMS does not name' { param($a) Put (Join-Path $a 'client\Data\extra.dll') 'x' } 'extra\.dll is in the artifact and SHA256SUMS does not name it'
    Refused 'a file SHA256SUMS names wrongly' { param($a) Put (Join-Path $a 'fork-build.json') '{"commit":"other"}' } 'fork-build\.json is not the file SHA256SUMS names'
    Refused 'a client file the record does not name, SHA256SUMS made to agree' { param($a) Put (Join-Path $a 'client\Data\extra.dll') 'x'; Write-Sums $a } 'records\\client-build\.json does not name it'
    Refused 'records of another commit' { param($a) Put (Join-Path $a 'records\server-build.json') (ServerRecordText ('bf2b3b40' + ('0' * 32))); Write-Sums $a } 'records\\server-build\.json is not this checkout''s'
    Refused 'no client-licences.json' { param($a) Remove-Item -LiteralPath (Join-Path $a 'records\client-licences.json'); Write-Sums $a } 'the artifact has no records\\client-licences\.json'
    Refused 'a licence text that is not the checkout''s, SHA256SUMS made to agree' { param($a) Put (Join-Path $a 'records\client-licences\fmt.txt') 'another text'; Write-Sums $a } 'records\\client-licences\\fmt\.txt in the artifact is not this checkout''s'
    Refused 'a licence text the checkout does not have' { param($a) Put (Join-Path $a 'records\client-licences\zlib.txt') 'zlib'; Write-Sums $a } 'records\\client-licences\\zlib\.txt is in the artifact and not in this checkout'
    Refused 'a server zip of another record' {
        param($a)
        Get-ChildItem -LiteralPath (Join-Path $a 'server') -File | Remove-Item -Force
        $rf = Join-Path $T 'server-record-other.json'
        $txt = ServerRecordText $commit
        Put $rf ($txt.Replace('"repo": "https://github.com/EvilPatrick06/skymp.git"', '"repo": "https://github.com/EvilPatrick06/skymp.git", "note": "another record"'))
        $null = New-ThornswoodServerBuildArtifact -From $srvDist -Record $rf -OutDir (Join-Path $a 'server')
        Write-Sums $a
    } 'another record'

    $a = New-Artifact (Join-Path $T 'art-good') -Crlf
    $stamp = Install-EngineArtifact -From $a -Repo $repo -Into $into -Run $run -Artifact $art
    Yes '2. the right artifact goes in, CR LF records and all' ((Test-Path -LiteralPath $into) -and (Left) -eq 0)
    $allClient = $true
    foreach ($k in $client.Keys) { $p = Join-Path $into ('build\dist\client\' + $k); if (-not (Test-Path -LiteralPath $p) -or (ShaFile $p) -ne (ShaText $client[$k])) { $allClient = $false } }
    Yes '2.   every client file is in build\dist\client, as recorded' $allClient
    $sums = Get-ThornswoodServerFolderSums (Join-Path $into 'build\dist\server')
    Yes '2.   the server files are in build\dist\server, and hold to the record' ($sums.Count -eq $fork.Count -and $sums['scam_native.node'] -eq (ShaText $fork['scam_native.node']))
    Yes '2.   the artifact is beside them as it came, its zip for -ServerBuild' ((Test-Path -LiteralPath (Join-Path $into 'artifact\SHA256SUMS')) -and @(Get-ChildItem -LiteralPath (Join-Path $into 'artifact\server') -Filter '*.zip').Count -eq 1)
    Yes '2.   engine-artifact.json names the commit, the artifact and the run' ($stamp.commit -eq $commit -and $stamp.artifact -eq 'engine-d3091eb4aec1' -and [long]$stamp.runId -eq 39588485569 -and $stamp.serverZip -match '^server-d3091eb4aec1-')
    $e = Threw { Install-EngineArtifact -From $a -Repo $repo -Into $into -Run $run -Artifact $art }
    Yes '2. a folder that is there already is never written into' ($e -match 'is there already')
    Yes '2. Get-EngineArtifactFolderProblems: the folder is this pin''s' (@(Get-EngineArtifactFolderProblems $into $repo).Count -eq 0)
    $sf = Join-Path $into 'engine-artifact.json'
    $keep = [IO.File]::ReadAllText($sf)
    [IO.File]::WriteAllText($sf, $keep.Replace($commit, ('bf2b3b40' + ('0' * 32))), $utf8)
    Yes '2.   and one that holds another pin''s build is not' (@(Get-EngineArtifactFolderProblems $into $repo) -match 'this checkout pins').Count -gt 0
    [IO.File]::WriteAllText($sf, $keep, $utf8)

    # ============================================ 3. Where.ps1 and where.js ==
    Write-Host ''; Write-Host '3. Where.ps1 and where.js'
    $w = Join-Path $repo 'scripts\release\Where.ps1'
    $wj = Join-Path $repo 'scripts\release\where.js'
    function AskJs([string]$what) { $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return ([string](& node $wj $what 2>&1)).Trim() } finally { $ErrorActionPreference = $o } }
    $machine = Join-Path $env:LOCALAPPDATA 'Thornswood'
    Yes '3. EngineArtifact is engine-ci\<pin 12> in this machine''s data' (Same (& $w EngineArtifact) (Join-Path $machine 'engine-ci\d3091eb4aec1'))
    Yes '3.   and where.js says the same' (Same (AskJs EngineArtifact) (& $w EngineArtifact))
    Yes '3. with no record, EngineBuild is still the checkout''s engine' (Same (& $w EngineBuild) (Join-Path $repo 'engine\skymp'))
    $recFile = Join-Path $machine 'engine-build.json'
    [IO.File]::WriteAllText($recFile, '{ "ci": true }', $utf8)
    Yes '3. {"ci": true}: EngineBuild is EngineArtifact' (Same (& $w EngineBuild) (& $w EngineArtifact))
    Yes '3.   ClientDist and ServerDist are under it' ((Same (& $w ClientDist) (Join-Path $into 'build\dist\client')) -and (Same (& $w ServerDist) (Join-Path $into 'build\dist\server')))
    Yes '3.   and where.js agrees' ((Same (AskJs EngineBuild) (& $w EngineBuild)) -and (Same (AskJs ClientDist) (& $w ClientDist)))
    $moved = 'c63fe63700000000000000000000000000000000'
    Set-Records $moved
    Yes '3. a pin move is another folder, not the old one' (Same (& $w ClientDist) (Join-Path $machine 'engine-ci\c63fe6370000\build\dist\client'))
    Yes '3.   answered though it is not there yet' (-not (Test-Path -LiteralPath (& $w ClientDist)))
    Put (Join-Path $repo 'records\server-build.json') '{"binary":"scam_native.node"}'
    $e = Threw { & $w ClientDist }
    Yes '3. a server record with no commit stops with a sentence' ($e -match 'names no fork commit')
    Yes '3.   and where.js stops too' ((AskJs ClientDist) -match 'names no fork commit')
    Set-Records $commit
    Remove-Item -LiteralPath $recFile -Force

    # ==================================== 4. Get-EngineArtifact.ps1 whole ==
    Write-Host ''; Write-Host '4. Get-EngineArtifact.ps1'
    Remove-Item -LiteralPath $into -Recurse -Force
    $good = New-Artifact (Join-Path $T 'art-for-gh')
    $ghState = Join-Path $T 'gh-state'
    $null = New-Item -ItemType Directory -Force -Path $ghState
    [IO.File]::WriteAllText((Join-Path $ghState 'artifacts.json'), (ConvertTo-Json -InputObject ([ordered]@{ artifacts = @($art) }) -Depth 5), $utf8)
    [IO.File]::WriteAllText((Join-Path $ghState 'run.json'), (ConvertTo-Json -InputObject $run -Depth 5), $utf8)
    $ghFake = Join-Path $T 'gh-stand-in.ps1'
    [IO.File]::WriteAllText($ghFake, @'
$state = $env:TS_GH_STATE
[IO.File]::AppendAllText((Join-Path $state 'calls.txt'), (($args -join ' ') + "`n"))
if ($env:TS_GH_FAIL) { [Console]::Error.WriteLine('HTTP 401: Bad credentials'); exit 1 }
if ($args[0] -eq 'api' -and $args[1] -like 'repos/EvilPatrick06/Thornswood/actions/artifacts?name=*') {
  if ($env:TS_GH_NONE) { '{"artifacts":[]}' } else { [IO.File]::ReadAllText((Join-Path $state 'artifacts.json')) }
  exit 0
}
if ($args[0] -eq 'api' -and $args[1] -like 'repos/EvilPatrick06/Thornswood/actions/runs/*') {
  $one = Join-Path $state ('run-' + ($args[1] -replace '^.*/', '') + '.json')
  if (Test-Path -LiteralPath $one) { [IO.File]::ReadAllText($one) } else { [IO.File]::ReadAllText((Join-Path $state 'run.json')) }
  exit 0
}
if ($args[0] -eq 'run' -and $args[1] -eq 'download') {
  $dir = $args[[Array]::IndexOf($args, '--dir') + 1]
  $from = $env:TS_GH_ARTIFACT
  $one = Join-Path $state ('artifact-' + $args[2] + '.txt')
  if (Test-Path -LiteralPath $one) { $from = [IO.File]::ReadAllText($one).Trim() }
  Copy-Item -LiteralPath $from -Destination $dir -Recurse
  exit 0
}
[Console]::Error.WriteLine('stand-in gh was asked ' + ($args -join ' ')); exit 1
'@, $utf8)
    $env:TS_GH_STATE = $ghState; $env:TS_GH_ARTIFACT = $good
    $env:TS_GH_FAIL = ''; $env:TS_GH_NONE = ''
    $get = Join-Path $repo 'scripts\release\Get-EngineArtifact.ps1'
    $ps = (Get-Process -Id $PID).Path
    function Fetch([string[]]$more) {
        $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $t = & $ps -NoProfile -ExecutionPolicy Bypass -File $get -Gh $ghFake -NoPause @more 2>&1 | Out-String; return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $t } }
        finally { $ErrorActionPreference = $o }
    }
    $r = Fetch @('-Check')
    Yes ("4. -Check: on GitHub, exit 2 (exit {0})" -f $r.Code) ($r.Code -eq 2 -and $r.Out -match 'keeps engine-d3091eb4aec1')
    Yes '4.   and nothing was fetched or written' (-not (Test-Path -LiteralPath $into) -and -not ([IO.File]::ReadAllText((Join-Path $ghState 'calls.txt')) -match 'run download'))
    $r = Fetch @()
    Yes ("4. a run fetches it and makes it the engine build (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'every file held to the records' -and (Test-Path -LiteralPath (Join-Path $into 'build\dist\client\Data\Scripts\TESModPlatform.pex')))
    Yes '4.   it downloaded the artifact by its run and name' ([IO.File]::ReadAllText((Join-Path $ghState 'calls.txt')) -match 'run download 39588485569 --name engine-d3091eb4aec1 --dir .+ --repo EvilPatrick06/Thornswood')
    Yes '4.   and left no scratch behind' (@(Get-ChildItem -LiteralPath $env:THORNSWOOD_SCRATCH_ROOT -Force -ErrorAction SilentlyContinue).Count -eq 0)
    $r = Fetch @()
    Yes ("4. a second run finds it there and fetches nothing (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'here already')
    Remove-Item -LiteralPath $into -Recurse -Force
    $env:TS_GH_NONE = '1'
    $r = Fetch @()
    Yes ("4. no artifact: exit 1, saying how to make it again (exit {0})" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'STOP\. .*gh workflow run engine\.yml' -and -not (Test-Path -LiteralPath $into))
    $env:TS_GH_NONE = ''; $env:TS_GH_FAIL = '1'
    $r = Fetch @()
    Yes ("4. a gh that fails: exit 1, naming what it said (exit {0})" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'could not be asked' -and $r.Out -match 'Bad credentials')
    $env:TS_GH_FAIL = ''

    # Two green runs of the pin, as on 22 Oct: the newer one (the #3014 proof
    # run) recorded the same build a few minutes later, so its client record
    # is not this checkout's, and the older one's is.
    $later = New-Artifact (Join-Path $T 'art-later') -RecordedUtc '2026-10-21T11:07:23Z'
    [IO.File]::WriteAllText((Join-Path $ghState 'artifacts.json'), (ConvertTo-Json -InputObject ([ordered]@{ artifacts = @($art, $newArt) }) -Depth 5), $utf8)
    [IO.File]::WriteAllText((Join-Path $ghState 'run-39600000000.json'), (ConvertTo-Json -InputObject $newRun -Depth 5), $utf8)
    [IO.File]::WriteAllText((Join-Path $ghState 'artifact-39600000000.txt'), $later, $utf8)
    [IO.File]::WriteAllText((Join-Path $ghState 'calls.txt'), '', $utf8)
    $r = Fetch @('-Check')
    Yes ("4. two kept: -Check says it is on GitHub, exit 2 (exit {0})" -f $r.Code) ($r.Code -eq 2 -and $r.Out -match 'keeps 2 engine-d3091eb4aec1' -and -not ([IO.File]::ReadAllText((Join-Path $ghState 'calls.txt')) -match 'run download'))
    $r = Fetch @()
    $calls = @([IO.File]::ReadAllLines((Join-Path $ghState 'calls.txt')) | Where-Object { $_ -match '^run download' })
    Yes ("4. two kept, the newer of another record: the older is taken (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'every file held to the records' -and ([IO.File]::ReadAllText((Join-Path $into 'engine-artifact.json')) | ConvertFrom-Json).runId -eq 39588485569)
    Yes '4.   it held the newer first and said why it passed it over' ($calls.Count -eq 2 -and $calls[0] -match '^run download 39600000000 ' -and $calls[1] -match '^run download 39588485569 ' -and $r.Out -match "run 39600000000's engine-d3091eb4aec1 is not CI's build of what this checkout records \(the artifact's records\\client-build\.json is not this checkout's")
    Yes '4.   and left no scratch behind' (@(Get-ChildItem -LiteralPath $env:THORNSWOOD_SCRATCH_ROOT -Force -ErrorAction SilentlyContinue).Count -eq 0)
    Remove-Item -LiteralPath $into -Recurse -Force
    $alsoLater = New-Artifact (Join-Path $T 'art-also-later') -RecordedUtc '2026-10-21T11:03:00Z'
    [IO.File]::WriteAllText((Join-Path $ghState 'artifact-39588485569.txt'), $alsoLater, $utf8)
    $r = Fetch @()
    Yes ("4. two kept and neither this checkout's: exit 1 naming both runs (exit {0})" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'STOP\. no engine-d3091eb4aec1 engine\.yml keeps is CI''s build' -and $r.Out -match 'run 39600000000: ' -and $r.Out -match 'run 39588485569: ' -and -not (Test-Path -LiteralPath $into))
    Yes '4.   and left no scratch behind' (@(Get-ChildItem -LiteralPath $env:THORNSWOOD_SCRATCH_ROOT -Force -ErrorAction SilentlyContinue).Count -eq 0)
    foreach ($x in 'run-39600000000.json', 'artifact-39600000000.txt', 'artifact-39588485569.txt') { Remove-Item -LiteralPath (Join-Path $ghState $x) -Force }
    [IO.File]::WriteAllText((Join-Path $ghState 'artifacts.json'), (ConvertTo-Json -InputObject ([ordered]@{ artifacts = @($art) }) -Depth 5), $utf8)

    # ================================================= 5. Sync-Client.ps1 ==
    Write-Host ''; Write-Host '5. Sync-Client.ps1'
    [IO.File]::WriteAllText($recFile, '{ "ci": true }', $utf8)
    $real = Join-Path $repo 'scripts\release\Get-EngineArtifact-real.ps1'
    Move-Item -LiteralPath $get -Destination $real
    [IO.File]::WriteAllText($get, @'
param([switch]$Check, [switch]$NoPause)
[IO.File]::AppendAllText($env:TS_FETCH_CALLS, "fetch`n")
if ($env:TS_FETCH_FAIL) { Write-Host 'STOP. stand-in: engine.yml keeps no engine-d3091eb4aec1.'; exit 1 }
& (Join-Path $PSScriptRoot 'Get-EngineArtifact-real.ps1') -Gh $env:TS_GH -NoPause
exit $LASTEXITCODE
'@, $utf8)
    $env:TS_GH = $ghFake
    $env:TS_FETCH_CALLS = Join-Path $T 'fetch-calls.txt'
    $env:TS_FETCH_FAIL = ''
    $sync = Join-Path $repo 'scripts\release\Sync-Client.ps1'
    $game = Join-Path $T 'ship-root\Game'
    function Sync([string[]]$more) {
        $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $t = & $ps -NoProfile -ExecutionPolicy Bypass -File $sync -Game $game -NoPause @more 2>&1 | Out-String; return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $t } }
        finally { $ErrorActionPreference = $o }
    }
    function Fetches { if (Test-Path -LiteralPath $env:TS_FETCH_CALLS) { return @([IO.File]::ReadAllLines($env:TS_FETCH_CALLS)).Count } else { return 0 } }
    $null = New-Item -ItemType Directory -Force -Path $game
    $r = Sync @('-Check')
    Yes ("5. -Check with the folder not there: exit 1, naming Get-EngineArtifact (exit {0})" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'Get-EngineArtifact\.ps1 fetches')
    Yes '5.   and it fetched nothing' ((Fetches) -eq 0)
    $env:TS_FETCH_FAIL = '1'
    $r = Sync @()
    Yes ("5. a fetch that fails stops it (exit {0})" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'could not be fetched' -and (Fetches) -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $game 'Data')))
    $env:TS_FETCH_FAIL = ''
    $r = Sync @()
    $inGame = $true
    foreach ($k in $client.Keys) { $p = Join-Path $game $k; if (-not (Test-Path -LiteralPath $p) -or (ShaFile $p) -ne (ShaText $client[$k])) { $inGame = $false } }
    Yes ("5. without -Check it fetches CI's build and copies the client in (exit {0})" -f $r.Code) ($r.Code -eq 0 -and (Fetches) -eq 2 -and $inGame -and (Test-Path -LiteralPath $into))
    Remove-Item -LiteralPath $into -Recurse -Force
    $r = Sync @()
    Yes ("5. a game folder that holds the client fetches nothing (exit {0})" -f $r.Code) ($r.Code -eq 0 -and (Fetches) -eq 2)
    Remove-Item -LiteralPath (Join-Path $game 'Data') -Recurse -Force
    $r = Sync @('-Dist', (Join-Path $T 'someone-elses-build'))
    Yes ("5. another -Dist is never filled from GitHub (exit {0})" -f $r.Code) ($r.Code -eq 1 -and (Fetches) -eq 2 -and $r.Out -match 'Setup-ShipMachine\.ps1 -EngineBuild ci')
    $stale = Join-Path $T 'stale-build'
    foreach ($k in $client.Keys) { Put (Join-Path $stale $k) ('REBUILT ' + $client[$k]) }
    $r = Sync @('-Dist', $stale)
    Yes ("5. a build that is not the record names CI's build, not a rebuild (exit {0})" -f $r.Code) (
        $r.Code -eq 1 -and $r.Out -match 'Setup-ShipMachine\.ps1 -EngineBuild ci' -and $r.Out -notmatch 'Rebuild, then' -and $r.Out -notmatch 'New-ClientBuildRecord\.ps1, then')
    Remove-Item -LiteralPath $get -Force
    Move-Item -LiteralPath $real -Destination $get
    Remove-Item -LiteralPath $recFile -Force

    # ============================== 6. Setup-ShipMachine and Check-ShipReady ==
    Write-Host ''; Write-Host '6. Setup-ShipMachine.ps1 and Check-ShipReady.ps1'
    $setup = Join-Path $Here 'scripts\release\Setup-ShipMachine.ps1'
    $ready = Join-Path $Here 'scripts\release\Check-ShipReady.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($setup, [ref]$null, [ref]$null)
    foreach ($n in 'Save-EngineBuild', 'Test-EngineBuildIsCi') {
        $fn = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }.GetNewClosure(), $true)
        Yes ("6. Setup-ShipMachine.ps1 has $n") ([bool]$fn)
        if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
    }
    $rf = Join-Path $T 'setup\engine-build.json'
    Yes '6. Save-EngineBuild ci writes {"ci": true}, with no folder asked for' (-not (Save-EngineBuild $rf 'ci') -and ([IO.File]::ReadAllText($rf) | ConvertFrom-Json).ci -eq $true)
    Yes '6.   and Test-EngineBuildIsCi reads it' (Test-EngineBuildIsCi $rf)
    $why = Save-EngineBuild $rf (Join-Path $T 'no-such-fork')
    Yes '6. a fork folder with no build is refused, naming -EngineBuild ci' ($why -match '-EngineBuild ci' -and (Test-EngineBuildIsCi $rf))
    # No fix offers -Rebuild, and since #3056 the switch itself is gone: the
    # guide no longer names it, and a build made on the machine never matches
    # a record CI made.
    $offered = @()
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($setup, [ref]$tokens, [ref]$null)
    foreach ($t in $tokens) { if ($t.Kind -in 'StringLiteral', 'StringExpandable' -and $t.Text -match 'Setup-ShipMachine\.ps1 -Rebuild') { $offered += $t.Extent.StartLineNumber } }
    Yes ('6. no fix in Setup-ShipMachine.ps1 offers -Rebuild' + $(if ($offered.Count) { ': line ' + ($offered -join ', ') } else { '' })) ($offered.Count -eq 0)
    $setupAst = [System.Management.Automation.Language.Parser]::ParseFile($setup, [ref]$null, [ref]$null)
    Yes '6. Setup-ShipMachine.ps1 has no -Rebuild switch (#3056)' (-not ($setupAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Rebuild' }))

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ready, [ref]$null, [ref]$null)
    foreach ($n in 'New-Row', 'Get-ClientRows') {
        $fn = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }.GetNewClosure(), $true)
        if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
    }
    $null = New-Item -ItemType Directory -Force -Path $game
    $cliRec = Join-Path $repo 'records\client-build.json'
    $missing = Join-Path $T 'not-fetched\build\dist\client'
    function Row($ci) { return @(Get-ClientRows $sync $cliRec $game $missing $ci | Where-Object { $_.What -like 'the recorded client*' })[0] }
    $r = Row ([pscustomobject]@{ Code = 2; Said = '' })
    Yes '6. Check-ShipReady: CI''s build GitHub keeps passes before the Ship fetches it' ($r.Ok -and $r.Detail -match 'the Ship fetches it first')
    $r = Row ([pscustomobject]@{ Code = 1; Said = 'engine.yml has kept no engine-d3091eb4aec1' })
    Yes '6.   one it cannot have fails as a need, saying why' (-not $r.Ok -and $r.Level -eq 'need' -and $r.Detail -match 'cannot be fetched: engine\.yml has kept no' -and $r.Fix -match 'Get-EngineArtifact\.ps1')
    $r = Row $null
    Yes '6.   with no CI build asked about, the fix names -EngineBuild ci and no rebuild' (-not $r.Ok -and $r.Fix -match 'Setup-ShipMachine\.ps1 -EngineBuild ci' -and $r.Fix -notmatch 'Build-Engine')

    # No fix a Ship machine reads sends it to a rebuild or a new record.
    $sent = @()
    foreach ($n in 'Check-ShipReady.ps1', 'Sync-Client.ps1', 'Setup-ShipMachine.ps1', 'Update-ShipRoot.ps1', 'Ship.ps1', 'Where.ps1') {
        $tokens = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Here ('scripts\release\' + $n)), [ref]$tokens, [ref]$null)
        foreach ($t in $tokens) {
            if ($t.Kind -in 'StringLiteral', 'StringExpandable' -and ($t.Text -match '(?i)build the fork with|build it there|Rebuild, then|Rebuild the client|Build-Engine\.ps1 -Fork built')) { $sent += ('{0}:{1}' -f $n, $t.Extent.StartLineNumber) }
        }
    }
    Yes ('6. no fix in the scripts a Ship machine reads sends it to build the engine' + $(if ($sent.Count) { ': ' + ($sent -join ', ') } else { '' })) ($sent.Count -eq 0)
}
finally {
    $env:LOCALAPPDATA = $oldLad
    $env:THORNSWOOD_SCRATCH_ROOT = $oldScratch
    foreach ($v in 'TS_GH_STATE', 'TS_GH_ARTIFACT', 'TS_GH_FAIL', 'TS_GH_NONE', 'TS_GH', 'TS_FETCH_CALLS', 'TS_FETCH_FAIL') { Remove-Item -LiteralPath ('Env:' + $v) -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $T) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
