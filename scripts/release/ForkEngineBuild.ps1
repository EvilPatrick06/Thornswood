<#
  ForkEngineBuild.ps1

  Finds the public fork's own build of an engine commit, and puts it where a
  build of that commit on this machine would be, for engine.yml to record.
  Dot-sourced by .github\workflows\engine.yml and tests\test-459-fork-build.ps1.

  WHY, issue #459. Patrick's B of 16 Oct: the fork, EvilPatrick06/skymp, is
  public, so GitHub builds it at no cost, and since fork #79 every push to
  thornswood/engine-changes builds the engine there and keeps what Thornswood
  records as one artifact, thornswood-engine-<commit> (the fork's
  .github\workflows\thornswood-pr-windows.yml says what is in it). engine.yml
  takes that build and records it, and builds the engine on GitHub's runner
  here or on the VPS only when the fork has no build of the commit. Recording
  is light work (no compiler), so the hour of compiling stays off the box the
  game servers run on.

  WHICH BUILD. Only a push to thornswood/engine-changes in the fork itself,
  of exactly that commit, that finished green, and whose artifact is still
  kept (90 days):
    - none at all, or a green one that kept no artifact (it ran before fork
      #79, or its 90 days are over): there is no fork build, and engine.yml
      builds it here;
    - one still running: engine.yml stops and says so, because building here
      what GitHub is building free is the hour this exists to save;
    - one that ended red (a compile error or a unit test): engine.yml stops
      and names it. The fork is public, so its runner is never refused for
      billing, and a red there is a red engine, not a reason to build it here
      without its tests.
  A lookup that fails (the network, the token) stops the run with the error:
  it is not "the fork has none".

  WHAT IS HELD before anything is recorded. The artifact's own sha256 (the
  digest GitHub keeps for it), then fork-build.json, which the fork's build
  wrote: its commit, run, repository, event and branch must be the ones
  asked for, every file it names must be in the artifact with its sha256 and
  size, and nothing else may be. Then each file goes to its path under the
  fork's build folder, where Build-Engine.ps1 and Build-Server.ps1 would have
  put it, and gets back the time fork-build.json gives: a zip keeps a time
  with no zone, so on a machine that is not on UTC it would read hours off,
  and the record's builtUtc is the binary's time. New-ServerBuildRecord.ps1
  and New-ClientBuildRecord.ps1 then hold every file to the fork's source as
  for any build, with -BuiltBy naming the fork's run.

  Keep it Windows PowerShell 5.1 and pwsh alike. It reads nothing over the
  network itself: engine.yml hands it the reader, and the harness a stand-in.
#>

$ForkEngineRepo = 'EvilPatrick06/skymp'
$ForkEngineWorkflow = 'thornswood-pr-windows.yml'
$ForkEngineBranch = 'thornswood/engine-changes'

# The artifact the fork's build keeps for one commit.
function Get-ForkEngineArtifactName([string]$Commit) {
    return ('thornswood-engine-' + $Commit.ToLowerInvariant())
}

# A member of a parsed object, or $null, without tripping strict mode.
function Get-ForkEngineValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } else { return $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

<#
  Which fork build of $Commit there is. $Get is called with a path under
  https://api.github.com/ and returns the parsed JSON, or throws on any
  failure. Returns @{ State; Why; Run; Artifact }, State one of:
    found  Run and Artifact are the fork's green push build and its artifact
    none   the fork has no build of it: build it here
    stop   the fork is still building it, or its build ended red: Why says
#>
function Find-ForkEngineBuild([string]$Commit, [scriptblock]$Get) {
    $Commit = $Commit.ToLowerInvariant()
    $name = Get-ForkEngineArtifactName $Commit
    $list = & $Get ("repos/{0}/actions/workflows/{1}/runs?head_sha={2}&event=push&branch={3}&per_page=100" -f $ForkEngineRepo, $ForkEngineWorkflow, $Commit, [Uri]::EscapeDataString($ForkEngineBranch))
    # Held again here, whatever the query gave: this repository, a push, the
    # branch, this commit. Newest first.
    $runs = @(@(Get-ForkEngineValue $list 'workflow_runs') | Where-Object {
            $_ -and [string]$_.head_sha -eq $Commit -and [string]$_.event -eq 'push' -and [string]$_.head_branch -eq $ForkEngineBranch -and
            [string](Get-ForkEngineValue (Get-ForkEngineValue $_ 'repository') 'full_name') -eq $ForkEngineRepo
        } | Sort-Object { [long]$_.id } -Descending)
    $what = "the fork's $ForkEngineWorkflow"
    if (-not $runs.Count) {
        return [pscustomobject]@{ State = 'none'; Run = $null; Artifact = $null
            Why = "$what has no build of a push of $Commit to $ForkEngineBranch, so this run builds it" }
    }
    $green = @($runs | Where-Object { [string]$_.status -eq 'completed' -and [string]$_.conclusion -eq 'success' })
    foreach ($r in $green) {
        $arts = & $Get ("repos/{0}/actions/runs/{1}/artifacts?name={2}&per_page=100" -f $ForkEngineRepo, $r.id, $name)
        $a = @(@(Get-ForkEngineValue $arts 'artifacts') | Where-Object { $_ -and [string]$_.name -eq $name -and -not $_.expired }) | Select-Object -First 1
        if ($a) {
            return [pscustomobject]@{ State = 'found'; Run = $r; Artifact = $a
                Why = ("$what built $Commit in run {0} ({1}); this run records that build" -f $r.id, $r.html_url) }
        }
    }
    $going = @($runs | Where-Object { [string]$_.status -ne 'completed' })
    if ($going.Count) {
        return [pscustomobject]@{ State = 'stop'; Run = $going[0]; Artifact = $null
            Why = ("$what is still building $Commit ({0}, {1}). Start this again once it has finished, and it records that build instead of building the engine a second time." -f $going[0].html_url, $going[0].status) }
    }
    if ($green.Count) {
        return [pscustomobject]@{ State = 'none'; Run = $green[0]; Artifact = $null
            Why = ("$what built $Commit ({0}) but keeps no {1}: it ran before the fork kept one, or its 90 days are over. So this run builds it." -f $green[0].html_url, $name) }
    }
    return [pscustomobject]@{ State = 'stop'; Run = $runs[0]; Artifact = $null
        Why = ("$what build of $Commit ended {0} ({1}). A red engine build is not built again here without its tests: fix it in the fork, or run that build again there if it failed for a reason of GitHub's own." -f $runs[0].conclusion, $runs[0].html_url) }
}

# A time fork-build.json gives, as UTC. ConvertFrom-Json in pwsh turns an ISO
# string into a DateTime already; Windows PowerShell leaves it a string.
function ConvertTo-ForkEngineUtc($Value) {
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { throw "a time in fork-build.json has no zone: $Value" }
        return $Value.ToUniversalTime()
    }
    $s = [string]$Value
    if ($s -notmatch '(Z|[+-]\d\d:\d\d)$') { throw "a time in fork-build.json has no zone: '$s'" }
    return [DateTime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
}

function Get-ForkEngineSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

<#
  Puts the fork's build, the artifact zip at $Zip, under $Fork\build, where a
  build of the commit on this machine would be, after holding it to what was
  asked for (the header, WHAT IS HELD). $Digest is GitHub's digest of the
  artifact ('sha256:<hex>'), or '' when GitHub gave none. $Scratch is an
  empty folder it may unpack into. Throws a sentence for anything that is not
  right, and then nothing is put in $Fork. Returns fork-build.json, parsed.
#>
function Expand-ForkEngineBuild([string]$Zip, [string]$Commit, [long]$RunId, [string]$Digest, [string]$Fork, [string]$Scratch) {
    $Commit = $Commit.ToLowerInvariant()
    if ($Digest) {
        if ($Digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw "GitHub gave the artifact a digest this does not read: $Digest" }
        $want = $Matches[1].ToLowerInvariant()
        $have = Get-ForkEngineSha256 $Zip
        if ($have -ne $want) { throw "the artifact downloaded is not the one GitHub keeps: sha256 $have, and GitHub says $want" }
    }
    $target = Join-Path $Fork 'build'
    if (Test-Path -LiteralPath $target) { throw "$target is there already; the fork build goes into a clean checkout only, so it is never mixed with another build" }
    if ((Test-Path -LiteralPath $Scratch) -and @(Get-ChildItem -LiteralPath $Scratch -Force).Count) { throw "$Scratch is not empty" }
    $null = New-Item -ItemType Directory -Force -Path $Scratch
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # ExtractToDirectory refuses an entry that would land outside $Scratch.
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Scratch)

    $mf = Join-Path $Scratch 'fork-build.json'
    if (-not (Test-Path -LiteralPath $mf)) { throw 'the artifact has no fork-build.json, so nothing says what it is' }
    $m = [IO.File]::ReadAllText($mf) | ConvertFrom-Json
    $why = @()
    if ([string]$m.commit -ne $Commit) { $why += "fork-build.json names commit $($m.commit), not $Commit" }
    if ([long]$m.runId -ne $RunId) { $why += "fork-build.json names run $($m.runId), not $RunId" }
    if ([string]$m.repository -ne $ForkEngineRepo) { $why += "fork-build.json names repository $($m.repository), not $ForkEngineRepo" }
    if ([string]$m.event -ne 'push' -or [string]$m.ref -ne ('refs/heads/' + $ForkEngineBranch)) { $why += "fork-build.json is of a $($m.event) of $($m.ref), not a push to $ForkEngineBranch" }
    $files = Get-ForkEngineValue $m 'files'
    $named = @{}
    if ($null -eq $files) { $why += 'fork-build.json names no files' }
    else {
        foreach ($p in $files.PSObject.Properties) {
            $rel = [string]$p.Name
            if ($rel -notmatch '^build/' -or $rel -match '(^|/)\.\.?(/|$)' -or $rel -match '[\\:]') { $why += "fork-build.json names $rel, which is not a path under build/"; continue }
            $named[$rel] = $true
            $path = Join-Path $Scratch ($rel.Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $why += "$rel is in fork-build.json and not in the artifact"; continue }
            if ((Get-ForkEngineSha256 $path) -ne ([string]$p.Value.sha256).ToLowerInvariant()) { $why += "$rel is not the file fork-build.json names (sha256)" }
            elseif ((Get-Item -LiteralPath $path).Length -ne [long]$p.Value.bytes) { $why += "$rel is not the size fork-build.json gives" }
            try { $null = ConvertTo-ForkEngineUtc $p.Value.lastWriteUtc } catch { $why += "$($rel): $($_.Exception.Message)" }
        }
    }
    $base = (Resolve-Path -LiteralPath $Scratch).ProviderPath.TrimEnd('\')
    foreach ($f in @(Get-ChildItem -LiteralPath $Scratch -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
        if ($rel -eq 'fork-build.json') { continue }
        if (-not $named.ContainsKey($rel)) { $why += "$rel is in the artifact and fork-build.json does not name it" }
    }
    # build/licences/licences.json: which vcpkg libraries are in the client
    # files, with their texts beside it, which New-ClientLicenceRecord.ps1
    # records (#3099). A build from before the fork measured them has none.
    foreach ($must in 'build/dist/server/scam_native.node', 'build/skymp5-server/launch_server.bat.tmp', 'build/licences/licences.json') {
        if (-not $named.ContainsKey($must)) { $why += "fork-build.json does not name $must" }
    }
    if ($why.Count) { throw ('the fork''s build is not the one asked for, and nothing was put in the fork: ' + ($why -join '; ')) }

    Move-Item -LiteralPath (Join-Path $Scratch 'build') -Destination $target
    foreach ($p in $files.PSObject.Properties) {
        $path = Join-Path $Fork ($p.Name.Replace('/', '\'))
        [IO.File]::SetLastWriteTimeUtc($path, (ConvertTo-ForkEngineUtc $p.Value.lastWriteUtc))
    }
    return $m
}
