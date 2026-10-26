<#
  EngineArtifact.ps1

  CI's engine build of the pin, the public fork's own build of the commit
  (thornswood-engine-<commit>), made this machine's engine build after every
  file in it is held to the checkout's records. Issues #3047 and #3399.
  Dot-sourced by Get-EngineArtifact.ps1 and tests\test-3047-ci-engine-build.ps1.

  WHY. An engine build is not the same bytes twice (engine\README.md,
  "Rebuilding the same commit"), so records\client-build.json and
  records\server-build.json match only the one build they were made from. Since
  #459 that is CI's: engine.yml records the pin from the fork's own build of
  it. Until 21 Oct every script a Ship machine reads (Check-ShipReady,
  Sync-Client, Setup-ShipMachine, Update-ShipRoot, the Where.ps1 errors) still
  pointed at a fork build made on the machine itself, which can never match a
  record CI made. That night PR #3040 moved the pin to 1a7b6eec, One's
  recorded engine build was still a b6c76e45 worktree, and the dev Ship stopped
  at "the build is not the recorded one" while CI held the exact client.

  So a Ship machine records {"ci": true} in Where.ps1 EngineBuilds
  (Setup-ShipMachine.ps1 -EngineBuild ci), and its engine build is then
  Where.ps1 EngineArtifact: a folder of its own data named for the pin the
  checkout records. A pin move is a new folder, never a stale one, and the
  folder is filled by fetching, not by building. Sync-Client.ps1 fetches it
  when it needs the client and the folder is not there yet, so every Ship and
  Go does.

  FROM THE FORK, NOT FROM THIS REPOSITORY (#3399, Patrick's A of 26 Oct).
  Until then the fetch took engine.yml's own artifact, engine-<commit 12>,
  out of this repository's artifact storage. That storage is metered over the
  month and is private, and on 25 Oct it filled: engine.yml's upload was
  refused (run 40249618462), and after the prune (#3410) it stayed refused,
  because what is used up is time stored, which a delete does not give back.
  The fork, EvilPatrick06/skymp, is public, so its artifacts cost nothing and
  count against no quota, and every push to thornswood/engine-changes keeps
  the build as thornswood-engine-<commit> for 90 days (ForkEngineBuild.ps1).
  engine.yml makes the records from exactly that build, so those are the
  bytes the records name, and a Ship machine takes them from there.

  WHICH BUILD. A green push build of the commit to thornswood/engine-changes
  in the fork itself whose artifact is still kept, and whose files are the
  ones the checkout's records name: the newest such one that passes WHAT IS
  HELD below. A commit can have more than one (a build run again in the
  fork), and a build run again is new bytes, so only the one the records
  were made from passes. Find-EngineArtifact lists every one as Candidates,
  newest first, and Get-EngineArtifact.ps1 holds each in turn and takes the
  first that passes. None: the Why says what the fork has of it.

  WHAT IS HELD before it is this machine's engine build. The trust is the
  checkout's records, in git; the fork's build is taken only because it is
  those bytes:
    - fork-build.json is of this commit, that run, a push to the branch in the
      fork, and names every file in the download with its sha256 and size,
      and no other file is there (Get-ForkEngineBuildProblems, the check
      engine.yml makes before it records the build);
    - each client file records\client-build.json names is under
      build\dist\client with that size and sha256, and no other file is;
    - the server files under build\dist\server are the ones
      records\server-build.json names (Get-ThornswoodServerBuildProblems, the
      check every deploy makes), and the server zip made from them
      (New-ThornswoodServerBuildArtifact, which holds them again) comes back
      out through Expand-ThornswoodStoredServerBuild, which holds each again.
  Anything wrong throws one sentence and nothing is put in place.

  WHERE IT GOES. Where.ps1 EngineArtifact, laid out as an engine build so
  ClientDist and ServerDist are under it as for any other:
    build\dist\client\<the record's paths>   the six client files
    build\dist\server\...                    the server files the record lists
    artifact\server\server-<...>.zip, .json  the server build as the box's
                                             store keeps it, which
                                             Deploy-Server.ps1 -ServerBuild
                                             and Publish-Server.ps1 send
    artifact\fork-build.json                 the fork's own list of its build
    engine-artifact.json                     which build, which run, when
  It is made in a folder beside it and moved into place whole, so a folder
  there is one that passed.

  Keep it Windows PowerShell 5.1 and pwsh alike. It reads nothing over the
  network itself: Get-EngineArtifact.ps1 hands it gh, the harness a stand-in.
#>

. (Join-Path $PSScriptRoot '..\deploy\ServerArtifact.ps1')
. (Join-Path $PSScriptRoot 'ForkEngineBuild.ps1')

$EngineArtifactRepo = $ForkEngineRepo

# The artifact the fork's build keeps for one commit.
function Get-EngineArtifactName([string]$Commit) {
    return (Get-ForkEngineArtifactName $Commit)
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
  Which fork build of $Commit there is to take. $Get is called with a path
  under https://api.github.com/ and returns the parsed JSON, or throws on any
  failure, which is not "there is none" and is not caught here. Returns
  @{ State; Why; Run; Artifact; Candidates }, State one of:
    found  Candidates is every kept thornswood-engine-<commit> of a green
           push build in the fork, newest first, each @{ Run; Artifact }; Run
           and Artifact are the newest. Which one is this checkout's build is
           known only once it is held to the records
           (Get-EngineArtifactProblems)
    none   there is no build of it to take: Why says what the fork has
#>
function Find-EngineArtifact([string]$Commit, [scriptblock]$Get) {
    $Commit = $Commit.ToLowerInvariant()
    $name = Get-EngineArtifactName $Commit
    $short = $Commit.Substring(0, 8)
    $what = "the fork's $ForkEngineWorkflow"
    $runs = @(Get-ForkEngineBuildRuns $Commit $Get)
    $green = @($runs | Where-Object { [string]$_.status -eq 'completed' -and [string]$_.conclusion -eq 'success' })
    $kept = @()
    foreach ($r in $green) {
        $arts = & $Get ("repos/{0}/actions/runs/{1}/artifacts?name={2}&per_page=100" -f $ForkEngineRepo, $r.id, $name)
        $a = @(@(Get-EngineArtifactValue $arts 'artifacts') | Where-Object { $_ -and [string]$_.name -eq $name -and -not $_.expired }) | Select-Object -First 1
        if ($a) { $kept += [pscustomobject]@{ Run = $r; Artifact = $a } }
    }
    if ($kept.Count) {
        $list = ($kept | ForEach-Object { "{0} ({1})" -f $_.Run.id, $_.Run.html_url }) -join ', '
        $why = "$what run $list built $short and keeps $name"
        if ($kept.Count -gt 1) { $why = "$what keeps $($kept.Count) $name, from runs $list, newest first; the newest whose files are the ones this checkout records is taken" }
        return [pscustomobject]@{ State = 'found'; Run = $kept[0].Run; Artifact = $kept[0].Artifact; Candidates = $kept; Why = $why }
    }
    $none = { param($w) [pscustomobject]@{ State = 'none'; Run = $null; Artifact = $null; Candidates = @(); Why = $w } }
    if (-not $runs.Count) {
        return (& $none "$what has no build of a push of $short to $ForkEngineBranch, so there is no engine build of this pin to take. A pin names a head of $ForkEngineBranch, which the push that made it the head built (engine\README.md, The engine built in CI).")
    }
    $going = @($runs | Where-Object { [string]$_.status -ne 'completed' })
    if ($going.Count) {
        return (& $none ("$what is still building $short ({0}, {1}). Run this again once it has finished." -f $going[0].html_url, $going[0].status))
    }
    if ($green.Count) {
        return (& $none ("$what built $short ({0}) and keeps no $name any more: its 90 days are over. A build run again is new bytes, so the pin then needs new records: run that build again in the fork, then engine.yml for the commit, and put the records it hands back in a pull request (engine\README.md)." -f $green[0].html_url))
    }
    return (& $none ("$what build of $short ended {0} ({1}), so there is no engine build of it to take." -f $runs[0].conclusion, $runs[0].html_url))
}

<#
  Why the fork's build unpacked at $From (fork-build.json and build\, as
  gh run download leaves thornswood-engine-<commit>) is not the build the
  checkout at $Repo records, from run $RunId, one sentence each; none when it
  is. The header, WHAT IS HELD, says what is asked.
#>
function Get-EngineArtifactProblems([string]$From, [string]$Repo, [long]$RunId) {
    $commit = Get-EngineArtifactPin $Repo
    $held = Get-ForkEngineBuildProblems $From $commit $RunId
    if (-not $held.Manifest) { return @($held.Why) }
    $why = @($held.Why)

    $clientDir = Join-Path $From 'build\dist\client'
    $rec = (Get-EngineArtifactRecordText (Join-Path $Repo 'records\client-build.json')) | ConvertFrom-Json
    $want = @{}
    foreach ($p in @($rec.files.PSObject.Properties)) {
        $rel = ([string]$p.Name).Replace('\', '/')
        $want[$rel] = $true
        $file = Join-Path $clientDir $rel
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $why += "build\dist\client\$($p.Name) is not in the fork's build"; continue }
        if ((Get-Item -LiteralPath $file).Length -ne [long]$p.Value.bytes -or (Get-EngineArtifactSha256 $file) -ne ([string]$p.Value.sha256).ToLowerInvariant()) {
            $why += "build\dist\client\$($p.Name) in the fork's build is not the file records\client-build.json names"
        }
    }
    if (Test-Path -LiteralPath $clientDir) {
        $cbase = (Resolve-Path -LiteralPath $clientDir).ProviderPath.TrimEnd('\', '/')
        foreach ($f in @(Get-ChildItem -LiteralPath $clientDir -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($cbase.Length + 1).Replace('\', '/')
            if (-not $want.ContainsKey($rel)) { $why += "build\dist\client\$rel is in the fork's build and records\client-build.json does not name it" }
        }
    }

    $srvRec = $null
    try { $srvRec = (Get-EngineArtifactRecordText (Join-Path $Repo 'records\server-build.json')) | ConvertFrom-Json } catch { $srvRec = $null }
    $sums = Get-ThornswoodServerFolderSums (Join-Path $From 'build\dist\server')
    $why += @(Get-ThornswoodServerBuildProblems $srvRec $sums "the fork's build\dist\server" 'records\server-build.json')
    return $why
}

<#
  Holds the fork's build unpacked at $From to the checkout at $Repo and makes
  it the engine build at $Into (Where.ps1 EngineArtifact), with $Run and
  $Artifact (Find-EngineArtifact's) named in engine-artifact.json. Throws a
  sentence for anything that is not right, and then nothing is at $Into.
  Returns engine-artifact.json, parsed.
#>
function Install-EngineArtifact([string]$From, [string]$Repo, [string]$Into, $Run, $Artifact) {
    if (Test-Path -LiteralPath $Into) { throw "$Into is there already; CI's engine build goes into a folder of its own, so it is never mixed with another" }
    $why = @(Get-EngineArtifactProblems $From $Repo ([long](Get-EngineArtifactValue $Run 'id')))
    if ($why.Count) { throw ('the fork''s build is not the one this checkout records, and nothing was put in place: ' + ($why -join '; ')) }
    $commit = Get-EngineArtifactPin $Repo
    $parent = Split-Path -Parent $Into
    $null = New-Item -ItemType Directory -Force -Path $parent
    $stage = Join-Path $parent ('.partial-' + [Guid]::NewGuid().ToString('N'))
    try {
        $rec = (Get-EngineArtifactRecordText (Join-Path $Repo 'records\client-build.json')) | ConvertFrom-Json
        foreach ($p in @($rec.files.PSObject.Properties)) {
            $to = Join-Path (Join-Path $stage 'build\dist\client') ([string]$p.Name)
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to)
            Copy-Item -LiteralPath (Join-Path (Join-Path $From 'build\dist\client') ([string]$p.Name).Replace('\', '/')) -Destination $to
        }
        # The server build as the box's store keeps it, made from the fork's
        # files and held to the record as it is made (ServerArtifact.ps1): the
        # same record and the same files make the same name on any machine,
        # so it is the zip engine.yml names in its log.
        $srvRecord = Join-Path $Repo 'records\server-build.json'
        $store = Join-Path $stage 'artifact\server'
        $made = New-ThornswoodServerBuildArtifact -From (Join-Path $From 'build\dist\server') -Record $srvRecord -OutDir $store
        Copy-Item -LiteralPath (Join-Path $From 'fork-build.json') -Destination (Join-Path $stage 'artifact\fork-build.json')
        $raw = [IO.File]::ReadAllBytes($srvRecord)
        $srvRec = [Text.Encoding]::UTF8.GetString($raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
        $server = Join-Path $stage 'build\dist\server'
        $null = New-Item -ItemType Directory -Force -Path $server
        $got = Expand-ThornswoodStoredServerBuild -Store $store -Record $srvRec -RecordSum (Get-ThornswoodRecordSum $raw) -Into $server
        if ($got.Problem) { throw ('the fork''s server build did not come out as the record names, and nothing was put in place: ' + $got.Problem) }
        if ($got.Name -ne $made.Name) { throw ("the server zip made from the fork's build is $($made.Name), and the one that came out is $($got.Name); nothing was put in place") }
        $stamp = [ordered]@{
            _note      = 'CI''s engine build of this commit: the public fork''s own build of it, held to the records by scripts\release\Get-EngineArtifact.ps1 (#3047, #3399).'
            commit     = $commit
            repository = $EngineArtifactRepo
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
