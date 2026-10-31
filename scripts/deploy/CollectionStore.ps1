<#
  CollectionStore.ps1

  The collection's plugins on the box, for the revision the repository
  records, so a server can move to a new collection revision with nothing of
  One's (#4069).

  WHY. A game server loads the collection's plugins and nothing else of it.
  Until 31 Oct 2026 every deploy that sent them read them from One's Vortex
  game (-Data), so a server could take a new revision only from One. On that
  day the dev move to revision 6 stopped at its first publish with
  "cheddars_mashups.esl is not on this machine": the box had none of
  revision 5's or 6's new plugins, and no cloud step could put them there.
  Patrick's rule of 30 Oct is that releases run from the cloud and do not
  rely on One.

  WHERE THEY COME FROM. Nexus, through Nexus-Run (scripts\release\Nexus-Run.ps1):
  Install-NexusRevision -KeepPlugins lays the revision out on GitHub's runner
  with the Nexus key of the "desk" environment and keeps the copy of each
  plugin the layout places. The output is sealed on the runner to a key the
  box makes for that run alone, so the authors' files reach the box and
  nobody else, the same way they reach a session. The box starts the run and
  reads its answer with the box admin App's token for that run alone
  (ShipAccess.ps1: Actions write and Contents read on Thornswood).

  WHAT IS HELD. Every plugin the layout keeps has to be in
  records\collection-plugins.json at the same size and sha256, and the
  layout has to be the revision and collection the record names; anything
  else stops here and nothing goes into the store. A plugin the record names
  that the layout does not have (the game's own masters, Skyrim.esm and the
  rest, which the servers already load) is not the store's to hold, and
  nor is ours (Thornswood-Content.esp), which every deploy sends from the
  repository.

  WHERE IT GOES. C:\Thornswood-Deploys\collection\<slug>-<revision>, beside
  the store of server builds, written into a folder of its own first and
  moved into place whole, with store.json saying what is there. A store that
  is already whole for the record is used as it is, read again by sha256.

  Dot-sourced. Defines variables and functions and nothing else.
  tests\test-4069-collection-store.ps1 holds it with no box and no Nexus.
#>
. (Join-Path $PSScriptRoot 'CollectionPlugins.ps1')

$ThornswoodCollectionStoreRoot = 'C:\Thornswood-Deploys\collection'

# The record's collection and revision, and its rows by name.
function Read-ThornswoodCollectionRecordHead([string]$RecordPath) {
    $doc = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($RecordPath)) $RecordPath
    $slug = [string]$doc.collection
    $rev = 0
    if (-not [int]::TryParse([string]$doc.revision, [ref]$rev) -or $rev -lt 1) { throw "$RecordPath names no collection revision." }
    if ($slug -notmatch '^[a-z0-9]+$') { throw "$RecordPath names no collection." }
    $rows = Read-ThornswoodCollectionPluginRecord $RecordPath
    return [pscustomobject]@{ Slug = $slug; Revision = $rev; Rows = $rows }
}

# The collection's plugins in $Dir: every .esp, .esm and .esl but ours
# (RepoPlugins.ps1), which the collection carries too and every deploy sends
# from the repository, never from a store.
function Get-ThornswoodCollectionStoreFiles([string]$Dir) {
    return @(Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Name -match '\.(esp|esm|esl)$' -and $ThornswoodRepoPlugins -notcontains $_.Name })
}

function Get-ThornswoodCollectionStoreDir([string]$Root, [string]$Slug, [int]$Revision) {
    return (Join-Path $Root ($Slug + '-' + $Revision))
}

# Why the plugins in $Dir are not the store for the record ($Head), one line
# each; none when they are. With $Layout (layout.json, read) the layout is
# held to the record's collection and revision too.
function Get-ThornswoodCollectionStoreProblems($Head, [string]$Dir, $Layout = $null) {
    $out = @()
    if ($null -ne $Layout) {
        $lc = $Layout.collection
        if ([string]$lc.slug -ne $Head.Slug -or [string]$lc.revision -ne [string]$Head.Revision) {
            $out += ('the layout is collection ' + [string]$lc.slug + ' revision ' + [string]$lc.revision + ', and the record is ' + $Head.Slug + ' revision ' + $Head.Revision)
            return $out
        }
    }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @("there is no $Dir") }
    $files = @(Get-ThornswoodCollectionStoreFiles $Dir)
    if (-not $files.Count) { return @("$Dir holds no plugin") }
    $out += @(Get-ThornswoodCollectionPluginProblems $Head.Rows @($files | ForEach-Object { $_.FullName }))
    return $out
}

# The store for the record, whole: Dir, Slug, Revision and Count. Uses the
# store when it is already whole; otherwise $Fetch, a scriptblock taking an
# empty folder, puts the layout's record and plugins folder into it (on the
# box, Invoke-ThornswoodCollectionFetch), and what it fetched is held to the
# record before it goes into the store. Throws, naming why, with nothing put
# in the store, when they are not the record's.
function Get-ThornswoodCollectionStore {
    param(
        [Parameter(Mandatory = $true)][string]$RecordPath,
        [string]$Root = $ThornswoodCollectionStoreRoot,
        [Parameter(Mandatory = $true)][scriptblock]$Fetch,
        [scriptblock]$Say = { param($m) Write-Host $m }
    )
    $head = Read-ThornswoodCollectionRecordHead $RecordPath
    $dir = Get-ThornswoodCollectionStoreDir $Root $head.Slug $head.Revision
    if (Test-Path -LiteralPath (Join-Path $dir 'store.json') -PathType Leaf) {
        $bad = @(Get-ThornswoodCollectionStoreProblems $head $dir)
        if (-not $bad.Count) {
            $n = @(Get-ThornswoodCollectionStoreFiles $dir).Count
            & $Say ('  the box holds collection ' + $head.Slug + ' revision ' + $head.Revision + '''s ' + $n + ' plugins, each the record''s bytes (' + $dir + ')')
            return [pscustomobject]@{ Dir = $dir; Slug = $head.Slug; Revision = $head.Revision; Count = $n }
        }
        & $Say ('  the store for revision ' + $head.Revision + ' is not the record''s, so it is fetched again: ' + ($bad -join '; '))
    }
    if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
    $work = Join-Path $Root ('.fetch-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        & $Say ('  fetching collection ' + $head.Slug + ' revision ' + $head.Revision + '''s plugins from Nexus through Nexus-Run')
        $record = & $Fetch $work $head
        $layoutPath = Join-Path $record 'layout.json'
        $plugins = Join-Path $record 'plugins'
        if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) { throw "the fetch brought back no layout.json, so nothing says which revision its plugins are. Nothing went into the store." }
        $layout = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($layoutPath)) $layoutPath
        $bad = @(Get-ThornswoodCollectionStoreProblems $head $plugins $layout)
        if ($bad.Count) { throw ("the plugins fetched are not the ones records\collection-plugins.json names, so nothing went into the store:`n    " + ($bad -join "`n    ")) }
        $files = @(Get-ThornswoodCollectionStoreFiles $plugins)
        $stage = $dir + '.new'
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        foreach ($f in $files) { [IO.File]::Copy($f.FullName, (Join-Path $stage $f.Name), $true) }
        $doc = [ordered]@{
            version    = 1
            builtBy    = 'scripts/deploy/CollectionStore.ps1'
            issue      = 4069
            collection = $head.Slug
            revision   = $head.Revision
            layoutMade = [string]$layout.made
            plugins    = @($files | Sort-Object Name | ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Length; sha256 = (Get-ThornswoodPluginSha256 $_.FullName) } })
        }
        [IO.File]::WriteAllText((Join-Path $stage 'store.json'), ($doc | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
        $bad = @(Get-ThornswoodCollectionStoreProblems $head $stage)
        if ($bad.Count) { throw ("the plugins copied into $stage are not the record's: " + ($bad -join '; ')) }
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        Move-Item -LiteralPath $stage -Destination $dir
        & $Say ('  ' + $files.Count + ' plugins of revision ' + $head.Revision + ' are in the store, each the record''s bytes (' + $dir + ')')
        return [pscustomobject]@{ Dir = $dir; Slug = $head.Slug; Revision = $head.Revision; Count = $files.Count }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath ($dir + '.new')) { Remove-Item -LiteralPath ($dir + '.new') -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# The fetch on the box: Nexus-Run's Install-NexusRevision -KeepPlugins for
# the record's revision, with the box admin App's token for this run alone,
# its scratch in $Work so its answer is the only one there. Returns the
# folder that holds layout.json and plugins. Throws with what Nexus-Run said
# when the run did not end 0.
function Invoke-ThornswoodCollectionFetch {
    param(
        [Parameter(Mandatory = $true)][string]$Work,
        [Parameter(Mandatory = $true)]$Head,
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$AdminState = 'C:\Thornswood-Admin\state'
    )
    . (Join-Path $Repo 'scripts\vps\admin\ShipAccess.ps1')
    $token = Get-ThornswoodShipAccess -Repo $Repo -AdminState $AdminState
    $pwsh = (Get-Process -Id $PID).Path
    $line = 'Install-NexusRevision -Revision ' + $Head.Revision + ' -Slug ' + $Head.Slug + ' -KeepPlugins'
    $hadScratch = $env:THORNSWOOD_SCRATCH_ROOT
    $env:THORNSWOOD_SCRATCH_ROOT = $Work
    $env:GH_TOKEN = $token
    $token = $null
    $was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = 0
        $said = @(& $pwsh -NoProfile -NonInteractive -File ([IO.Path]::Combine($Repo, 'scripts', 'release', 'Nexus-Run.ps1')) -Line $line 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $was
        Remove-Item -LiteralPath Env:\GH_TOKEN -ErrorAction SilentlyContinue
        if ($null -eq $hadScratch) { Remove-Item -LiteralPath Env:\THORNSWOOD_SCRATCH_ROOT -ErrorAction SilentlyContinue } else { $env:THORNSWOOD_SCRATCH_ROOT = $hadScratch }
    }
    foreach ($l in $said) { if ($l.Trim()) { Write-Host ('    ' + $l.TrimEnd()) -ForegroundColor DarkGray } }
    if ($code -ne 0) { throw ('Nexus-Run ' + $line + ' ended ' + $code + ': ' + ((@($said | Where-Object { $_.Trim() }) | Select-Object -Last 3) -join ' | ')) }
    $found = @(Get-ChildItem -LiteralPath (Join-Path $Work 'nexus-run') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path (Join-Path $_.FullName 'files') 'record' } | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'layout.json') })
    if ($found.Count -ne 1) { throw ('Nexus-Run ended 0 and left ' + $found.Count + ' layout record(s) in ' + $Work + ', where one belongs.') }
    return $found[0]
}
