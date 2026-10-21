<#
  EngineArtifact.ps1

  CI's engine build of the pin, the artifact engine.yml keeps, made this
  machine's engine build after every file in it is held to the checkout's
  records. Issue #3047. Dot-sourced by Get-EngineArtifact.ps1 and
  tests\test-3047-ci-engine-build.ps1.

  WHY. An engine build is not the same bytes twice (engine\README.md,
  "Rebuilding the same commit"), so records\client-build.json and
  records\server-build.json match only the one build they were made from. Since
  #459 that is CI's: engine.yml records the pin from its own run, and its
  artifact engine-<fork commit 12> holds the very files the records name. Until
  21 Oct every script a Ship machine reads (Check-ShipReady, Sync-Client,
  Setup-ShipMachine, Update-ShipRoot, the Where.ps1 errors) still pointed at a
  fork build made on the machine itself, which can never match a record CI
  made. That night PR #3040 moved the pin to d3091eb4, One's recorded engine
  build was still a bf2b3b40 worktree, and the dev Ship stopped at "the build is
  not the recorded one" while run 39588485569's artifact held the exact client.

  So a Ship machine records {"ci": true} in Where.ps1 EngineBuilds
  (Setup-ShipMachine.ps1 -EngineBuild ci), and its engine build is then
  Where.ps1 EngineArtifact: a folder of its own data named for the pin the
  checkout records. A pin move is a new folder, never a stale one, and the
  folder is filled by fetching, not by building. Sync-Client.ps1 fetches it
  when it needs the client and the folder is not there yet, so every Ship and
  Go does.

  WHICH ARTIFACT. engine-<fork commit 12> in this repository, from a run of
  .github/workflows/engine.yml that finished green, and not expired (engine.yml
  keeps it 30 days). The newest such one. None: the Why says to run
  engine.yml again, which takes the fork's own build of the commit while the
  fork keeps it (90 days, ForkEngineBuild.ps1) and so makes the same bytes.

  WHAT IS HELD before it is this machine's engine build. The trust is the
  checkout's records, in git; the artifact is taken only because it is those
  bytes:
    - SHA256SUMS names every file in the artifact and each one hashes to it,
      and no file is there that it does not name;
    - its records\client-build.json and records\server-build.json are the
      checkout's own, line endings aside (a runner writes CR LF);
    - each client file the checkout's client record names is under client\
      with that size and sha256, and no other file is;
    - the one server zip for the commit is held to the checkout's server
      record with Test-ThornswoodServerBuildArtifact, the check the box makes
      before it takes one, and its files come out of it through
      Expand-ThornswoodStoredServerBuild, which holds each again.
  Anything wrong throws one sentence and nothing is put in place.

  WHERE IT GOES. Where.ps1 EngineArtifact, laid out as an engine build so
  ClientDist and ServerDist are under it as for any other:
    build\dist\client\<the record's paths>   the six client files
    build\dist\server\...                    the server files the record lists
    artifact\                                the artifact as it came, so
                                             Deploy-Server.ps1 -ServerBuild
                                             and Publish-Server.ps1 can send
                                             its zip
    engine-artifact.json                     which artifact, which run, when
  It is made in a folder beside it and moved into place whole, so a folder
  there is one that passed.

  Keep it Windows PowerShell 5.1 and pwsh alike. It reads nothing over the
  network itself: Get-EngineArtifact.ps1 hands it gh, the harness a stand-in.
#>

. (Join-Path $PSScriptRoot '..\deploy\ServerArtifact.ps1')

$EngineArtifactRepo = 'EvilPatrick06/Thornswood'
$EngineArtifactWorkflow = '.github/workflows/engine.yml'

# The artifact engine.yml keeps for one fork commit.
function Get-EngineArtifactName([string]$Commit) {
    return ('engine-' + $Commit.ToLowerInvariant().Substring(0, 12))
}

# A member of a parsed object, or $null, without tripping strict mode.
function Get-EngineArtifactValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } else { return $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

# A record file's text as the records compare it: no BOM, LF.
function Get-EngineArtifactRecordText([string]$Path) {
    return [IO.File]::ReadAllText($Path).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
}

function Get-EngineArtifactSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# The fork commit the checkout at $Repo pins: records\server-build.json's
# source.commit, which tests\test-one-engine.js holds to the submodule pin,
# with the client record's forkCommit the start of it. Throws a sentence.
function Get-EngineArtifactPin([string]$Repo) {
    $srv = Join-Path $Repo 'records\server-build.json'
    $cli = Join-Path $Repo 'records\client-build.json'
    foreach ($f in $srv, $cli) { if (-not (Test-Path -LiteralPath $f)) { throw "$f is not there, so which engine commit this checkout pins is not known." } }
    $s = $null; $c = $null
    try { $s = (Get-EngineArtifactRecordText $srv) | ConvertFrom-Json } catch { throw "$srv does not read as JSON, so which engine commit this checkout pins is not known." }
    try { $c = (Get-EngineArtifactRecordText $cli) | ConvertFrom-Json } catch { throw "$cli does not read as JSON, so which engine commit this checkout pins is not known." }
    $commit = ([string](Get-EngineArtifactValue (Get-EngineArtifactValue $s 'source') 'commit')).ToLowerInvariant()
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw "$srv names no fork commit (source.commit), so which engine commit this checkout pins is not known." }
    $short = ([string](Get-EngineArtifactValue $c 'forkCommit')).ToLowerInvariant()
    if (-not $short -or -not $commit.StartsWith($short)) { throw "records\client-build.json names fork commit '$short' and records\server-build.json $commit, so the two records are not one engine. tests\test-one-engine.js says which is wrong." }
    return $commit
}

<#
  Which engine.yml artifact of $Commit there is. $Get is called with a path
  under https://api.github.com/ and returns the parsed JSON, or throws on any
  failure, which is not "there is none" and is not caught here. Returns
  @{ State; Why; Run; Artifact }, State one of:
    found  Artifact is engine-<commit 12> of the green engine.yml run Run
    none   there is no artifact of it to take: Why says how to make one
#>
function Find-EngineArtifact([string]$Commit, [scriptblock]$Get) {
    $Commit = $Commit.ToLowerInvariant()
    $name = Get-EngineArtifactName $Commit
    $again = "Make it again with  gh workflow run engine.yml --ref main  (it takes the fork's own build of $($Commit.Substring(0, 8)) while the fork keeps it, so the files are the ones the records name), then run this again."
    $list = & $Get ("repos/{0}/actions/artifacts?name={1}&per_page=100" -f $EngineArtifactRepo, $name)
    $all = @(@(Get-EngineArtifactValue $list 'artifacts') | Where-Object { $_ -and [string]$_.name -eq $name } | Sort-Object { [long]$_.id } -Descending)
    if (-not $all.Count) {
        return [pscustomobject]@{ State = 'none'; Run = $null; Artifact = $null
            Why = "engine.yml has kept no $name, so CI has not built $($Commit.Substring(0, 8)) here. $again" }
    }
    $kept = @($all | Where-Object { -not $_.expired })
    foreach ($a in $kept) {
        $runId = [long](Get-EngineArtifactValue (Get-EngineArtifactValue $a 'workflow_run') 'id')
        if (-not $runId) { continue }
        $run = & $Get ("repos/{0}/actions/runs/{1}" -f $EngineArtifactRepo, $runId)
        if ([string]$run.path -ne $EngineArtifactWorkflow) { continue }
        if ([string]$run.status -ne 'completed' -or [string]$run.conclusion -ne 'success') { continue }
        return [pscustomobject]@{ State = 'found'; Run = $run; Artifact = $a
            Why = ("engine.yml run {0} ({1}) built {2} and keeps {3}" -f $run.id, $run.html_url, $Commit.Substring(0, 8), $name) }
    }
    if (-not $kept.Count) {
        return [pscustomobject]@{ State = 'none'; Run = $null; Artifact = $null
            Why = "engine.yml's $name is past the 30 days it is kept. $again" }
    }
    return [pscustomobject]@{ State = 'none'; Run = $null; Artifact = $null
        Why = "no $name is from an engine.yml run that finished green. $again" }
}

<#
  Why the artifact unpacked at $From is not CI's build of what the checkout
  at $Repo records, one sentence each; none when it is. The header, WHAT IS
  HELD, says what is asked.
#>
function Get-EngineArtifactProblems([string]$From, [string]$Repo) {
    $why = @()
    $sumsFile = Join-Path $From 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $sumsFile)) { return @('the artifact has no SHA256SUMS, so nothing says what is in it') }
    $named = @{}
    foreach ($line in @([IO.File]::ReadAllLines($sumsFile))) {
        if (-not $line.Trim()) { continue }
        $m = [regex]::Match($line, '^([0-9a-f]{64})  (\S.*)$')
        if (-not $m.Success) { $why += "SHA256SUMS has a line this does not read: '$line'"; continue }
        $rel = $m.Groups[2].Value
        if ($rel -match '(^|/)\.\.?(/|$)' -or $rel -match '[\\:]' -or $rel.StartsWith('/')) { $why += "SHA256SUMS names $rel, which is not a path in the artifact"; continue }
        $named[$rel] = $true
        $p = Join-Path $From $rel
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $why += "$rel is in SHA256SUMS and not in the artifact"; continue }
        if ((Get-EngineArtifactSha256 $p) -ne $m.Groups[1].Value) { $why += "$rel is not the file SHA256SUMS names" }
    }
    $base = (Resolve-Path -LiteralPath $From).ProviderPath.TrimEnd('\', '/')
    foreach ($f in @(Get-ChildItem -LiteralPath $From -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
        if ($rel -ne 'SHA256SUMS' -and -not $named.ContainsKey($rel)) { $why += "$rel is in the artifact and SHA256SUMS does not name it" }
    }

    foreach ($r in 'client-build.json', 'server-build.json') {
        $theirs = Join-Path $From ('records\' + $r)
        if (-not (Test-Path -LiteralPath $theirs)) { $why += "the artifact has no records\$r"; continue }
        if ((Get-EngineArtifactRecordText $theirs) -ne (Get-EngineArtifactRecordText (Join-Path $Repo ('records\' + $r)))) {
            $why += "the artifact's records\$r is not this checkout's, so it is CI's build of another record"
        }
    }

    $rec = (Get-EngineArtifactRecordText (Join-Path $Repo 'records\client-build.json')) | ConvertFrom-Json
    $want = @{}
    foreach ($p in @($rec.files.PSObject.Properties)) {
        $rel = ([string]$p.Name).Replace('\', '/')
        $want[$rel] = $true
        $file = Join-Path (Join-Path $From 'client') $rel
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $why += "client\$($p.Name) is not in the artifact"; continue }
        if ((Get-Item -LiteralPath $file).Length -ne [long]$p.Value.bytes -or (Get-EngineArtifactSha256 $file) -ne ([string]$p.Value.sha256).ToLowerInvariant()) {
            $why += "client\$($p.Name) in the artifact is not the file records\client-build.json names"
        }
    }
    $clientDir = Join-Path $From 'client'
    if (Test-Path -LiteralPath $clientDir) {
        $cbase = (Resolve-Path -LiteralPath $clientDir).ProviderPath.TrimEnd('\', '/')
        foreach ($f in @(Get-ChildItem -LiteralPath $clientDir -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($cbase.Length + 1).Replace('\', '/')
            if (-not $want.ContainsKey($rel)) { $why += "client\$rel is in the artifact and records\client-build.json does not name it" }
        }
    }
    if ($why.Count) { return $why }

    $srvRecord = Join-Path $Repo 'records\server-build.json'
    $commit = Get-EngineArtifactPin $Repo
    $zips = @(Get-ChildItem -LiteralPath (Join-Path $From 'server') -Filter ('server-' + $commit.Substring(0, 12) + '-*.zip') -File -ErrorAction SilentlyContinue)
    if ($zips.Count -ne 1) { return @("the artifact holds $($zips.Count) server builds of $($commit.Substring(0, 8)), and engine.yml keeps one") }
    try { $null = Test-ThornswoodServerBuildArtifact -Zip $zips[0].FullName -Record $srvRecord }
    catch { $why += ($_.Exception.Message -replace ' Nothing was sent\.$', '') }
    return $why
}

<#
  Holds the artifact unpacked at $From to the checkout at $Repo and makes it
  the engine build at $Into (Where.ps1 EngineArtifact), with $Run and
  $Artifact (Find-EngineArtifact's) named in engine-artifact.json. Throws a
  sentence for anything that is not right, and then nothing is at $Into.
  Returns engine-artifact.json, parsed.
#>
function Install-EngineArtifact([string]$From, [string]$Repo, [string]$Into, $Run, $Artifact) {
    if (Test-Path -LiteralPath $Into) { throw "$Into is there already; CI's engine build goes into a folder of its own, so it is never mixed with another" }
    $why = @(Get-EngineArtifactProblems $From $Repo)
    if ($why.Count) { throw ('the artifact is not CI''s build of what this checkout records, and nothing was put in place: ' + ($why -join '; ')) }
    $commit = Get-EngineArtifactPin $Repo
    $parent = Split-Path -Parent $Into
    $null = New-Item -ItemType Directory -Force -Path $parent
    $stage = Join-Path $parent ('.partial-' + [Guid]::NewGuid().ToString('N'))
    try {
        $rec = (Get-EngineArtifactRecordText (Join-Path $Repo 'records\client-build.json')) | ConvertFrom-Json
        foreach ($p in @($rec.files.PSObject.Properties)) {
            $to = Join-Path (Join-Path $stage 'build\dist\client') ([string]$p.Name)
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to)
            Copy-Item -LiteralPath (Join-Path (Join-Path $From 'client') ([string]$p.Name).Replace('\', '/')) -Destination $to
        }
        $srvRecord = Join-Path $Repo 'records\server-build.json'
        $raw = [IO.File]::ReadAllBytes($srvRecord)
        $srvRec = [Text.Encoding]::UTF8.GetString($raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
        $server = Join-Path $stage 'build\dist\server'
        $null = New-Item -ItemType Directory -Force -Path $server
        $got = Expand-ThornswoodStoredServerBuild -Store (Join-Path $From 'server') -Record $srvRec -RecordSum (Get-ThornswoodRecordSum $raw) -Into $server
        if ($got.Problem) { throw ('the artifact''s server build did not come out as the record names, and nothing was put in place: ' + $got.Problem) }
        Copy-Item -LiteralPath $From -Destination (Join-Path $stage 'artifact') -Recurse
        $stamp = [ordered]@{
            _note      = 'CI''s engine build of this commit, engine.yml''s artifact held to the records by scripts\release\Get-EngineArtifact.ps1 (#3047).'
            commit     = $commit
            artifact   = [string](Get-EngineArtifactValue $Artifact 'name')
            artifactId = [long](Get-EngineArtifactValue $Artifact 'id')
            digest     = [string](Get-EngineArtifactValue $Artifact 'digest')
            runId      = [long](Get-EngineArtifactValue $Run 'id')
            run        = [string](Get-EngineArtifactValue $Run 'html_url')
            serverZip  = $got.Name
            fetchedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        [IO.File]::WriteAllText((Join-Path $stage 'engine-artifact.json'), (ConvertTo-Json -InputObject $stamp), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $stage -Destination $Into
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return ([IO.File]::ReadAllText((Join-Path $Into 'engine-artifact.json')) | ConvertFrom-Json)
}

<#
  Why the engine build at $Into is not CI's build of what the checkout at
  $Repo records now; none when it is. A folder this put there for the pin is
  one, unless a client file in it has changed since.
#>
function Get-EngineArtifactFolderProblems([string]$Into, [string]$Repo) {
    $stampFile = Join-Path $Into 'engine-artifact.json'
    if (-not (Test-Path -LiteralPath $stampFile)) { return @("$Into has no engine-artifact.json, so it is not a folder Get-EngineArtifact.ps1 made") }
    $stamp = $null
    try { $stamp = [IO.File]::ReadAllText($stampFile) | ConvertFrom-Json } catch { return @("$stampFile does not read as JSON") }
    $why = @()
    $commit = Get-EngineArtifactPin $Repo
    if ([string]$stamp.commit -ne $commit) { $why += "it holds CI's build of $([string]$stamp.commit), and this checkout pins $commit" }
    $rec = (Get-EngineArtifactRecordText (Join-Path $Repo 'records\client-build.json')) | ConvertFrom-Json
    foreach ($p in @($rec.files.PSObject.Properties)) {
        $f = Join-Path (Join-Path $Into 'build\dist\client') ([string]$p.Name)
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { $why += "build\dist\client\$($p.Name) is not in it"; continue }
        if ((Get-EngineArtifactSha256 $f) -ne ([string]$p.Value.sha256).ToLowerInvariant()) { $why += "build\dist\client\$($p.Name) in it is not the file records\client-build.json names" }
    }
    return $why
}
