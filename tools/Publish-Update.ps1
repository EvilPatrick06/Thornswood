<#
  Publish-Update.ps1

  Diffs the current build against the last published state, packs only what
  changed, uploads it as a release asset, and updates version.json so everyone's
  launcher picks it up.

  First time:   .\Publish-Update.ps1 -Baseline
  After that:   .\Publish-Update.ps1 -Notes "Swapped the map mod"
  Launcher:     .\Publish-Update.ps1 -Launcher -Notes "New launcher"
#>
[CmdletBinding()]
param(
    [string]$Root    = 'C:\Thornswood',
    [string]$RepoDir,
    [string]$Repo,
    [string]$Id,
    [string]$Notes   = '',
    [switch]$Baseline,
    [switch]$Launcher,
    [switch]$NoUpload,
    [switch]$NoPush,
    [switch]$NoPause
    ,[switch]$MoveServer
)


# The launcher was SkyrimTogether.exe and is Thornswood.exe now. It replaces
# itself in place when it updates rather than being reinstalled, so an install
# made before the rename still carries the old name and both have to be looked
# for, newest first.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) { $RepoDir = Split-Path -Parent $Here }
if (-not (Test-Path (Join-Path $RepoDir 'version.json'))) { Die "No version.json in $RepoDir. Point -RepoDir at your clone." }

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$DistDir    = Join-Path $Root '_dist'
$StateFile  = Join-Path $DistDir 'published.json'
$VersionFile = Join-Path $RepoDir 'version.json'
if (-not (Test-Path $GameDir)) { Die "No build at $GameDir." }
$null = New-Item -ItemType Directory -Force -Path $DistDir

. (Join-Path $Here 'Close-Launcher.ps1')
# Every file below gets hashed and compared against what friends already have.
# A game still running underneath would publish a file that is mid-write.
$null = Stop-Game -Root $Root

Head 'Thornswood - publish'

# ------------------------------------------------------------ what is ours
$vanillaDataFiles = @('Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm','_ResourcePack.esl','_ResourcePack.bsa')
$vanillaDataPatterns = @('Skyrim - *.bsa','cc*.esm','cc*.esl','cc*.esp','cc*.bsa')
$vanillaDataDirs = @('Video','Strings')
$vanillaRootFiles = @('SkyrimSE.exe','SkyrimSELauncher.exe','steam_api64.dll','bink2w64.dll','Skyrim.ccc','installscript.vdf','Skyrim_Default.ini','High.ini','Low.ini','Medium.ini','Ultra.ini')
$vanillaRootDirs = @('_DowngraderBackups','Creations','Mods','Skyrim','src')

function Test-Vanilla([string]$rel) {
    $parts = $rel -split '\\'
    $top = $parts[0]
    if ($vanillaRootDirs -contains $top) { return $true }
    if ($parts.Count -eq 1) { return ($vanillaRootFiles -contains $top) }
    if ($top -ne 'Data') { return $false }
    if ($parts.Count -ge 3 -and ($vanillaDataDirs -contains $parts[1])) { return $true }
    if ($parts.Count -eq 2) {
        $leaf = $parts[1]
        if ($vanillaDataFiles -contains $leaf) { return $true }
        foreach ($p in $vanillaDataPatterns) { if ($leaf -like $p) { return $true } }
    }
    return $false
}

# The multiplayer client's menu is a Chromium window, and it keeps a browser
# profile beside itself: caches, cookie databases, shader blobs, its own logs.
# All of it is per machine, all of it is rewritten on every launch, and it is
# locked while the client is running. Publishing it churned hundreds of files
# per release, sent one player's browser state to everyone else, and eventually
# failed outright on a file the game still had open.
$runtimeDirs = @(
    'Data\SkyrimTogetherReborn\cache\',
    'Data\SkyrimTogetherReborn\logs\',
    '.sentry-native\'
)
function Test-Runtime([string]$rel) {
    foreach ($d in $runtimeDirs) {
        if ($rel.StartsWith($d, 'OrdinalIgnoreCase')) { return $true }
    }
    return $false
}

# Settings that belong to the machine rather than to the build. SSE Display
# Tweaks holds the screen resolution, so publishing it stamped one person's
# monitor onto everyone: a friend on a 2560x1440 screen was running the game at
# 3440x1440 because that is what the pack carried. The launcher writes this one
# per machine on every start, so it must not ride along in a pack.
#
# It must also be kept out of the removal list. Dropping a file from the scan
# makes it look deleted, and delete.txt would then strip it from every install.
$machineFiles = @(
    'Data\SKSE\Plugins\SSEDisplayTweaks.ini'
)
function Test-Machine([string]$rel) {
    foreach ($f in $machineFiles) {
        if ($rel -eq $f) { return $true }
    }
    return $false
}

Say '  Scanning the build...'
$prefix = $GameDir.TrimEnd('\') + '\'
$now = @{}
foreach ($f in (Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($prefix.Length)
    if (Test-Vanilla $rel) { continue }
    if (Test-Runtime $rel) { continue }
    if (Test-Machine $rel) { continue }
    if ($f.Extension -in '.pdb', '.log') { continue }
    $now[$rel] = ('{0}:{1}' -f $f.Length, $f.LastWriteTimeUtc.Ticks)
}
Say ("  {0:n0} mod files" -f $now.Count) 'Green'

# The reference plugin list is part of what ships, so a load order change on its
# own has to be enough to make a pack. Hashed rather than timestamped, because
# rewriting the same list is not a change worth sending anyone.
foreach ($f in 'plugins.txt', 'loadorder.txt') {
    $src = Join-Path $ProfileDir "Default\$f"
    if (Test-Path $src) { $now[":profile:$f"] = (Get-FileHash $src -Algorithm SHA256).Hash }
}

# The launcher's own source. Nothing here ships as a file, it all ends up
# compiled into one exe, which is why a release that only changed the launcher
# used to produce an empty file list and a news post that said nothing. Hashed
# so the news can at least name which parts of it moved.
$srcDir = Join-Path $RepoDir 'tools'
if (Test-Path $srcDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $srcDir -Recurse -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -in '.cs', '.xaml' })) {
        $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
        $now[":src:$rel"] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    }
}

$prev = @{}
if (Test-Path $StateFile) {
    $obj = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $prev[$p.Name] = $p.Value }
}

function Save-State {
    $o = [ordered]@{}
    foreach ($k in ($now.Keys | Sort-Object)) { $o[$k] = $now[$k] }
    $o | ConvertTo-Json -Depth 3 -Compress | Set-Content $StateFile -Encoding UTF8
}

if ($Baseline) {
    Save-State
    Head 'Done'
    Say "Baseline recorded: $($now.Count) files." 'Green'
    Say 'Future runs will pack only what changes from here.' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}
if (-not $prev.Count) { Die "No baseline yet. Run this once with -Baseline first." }

# ------------------------------------------------------------ diff
Head 'Changes'
$changed = @(); $removed = @()
foreach ($k in $now.Keys) { if (-not $prev.ContainsKey($k) -or $prev[$k] -ne $now[$k]) { $changed += $k } }
foreach ($k in $prev.Keys) { if (-not $now.ContainsKey($k)) { $removed += $k } }

$profileChanged = @($changed | Where-Object { $_ -like ':profile:*' })
$srcChanged     = @($changed | Where-Object { $_ -like ':src:*' })
$changed        = @($changed | Where-Object { $_ -notlike ':profile:*' -and $_ -notlike ':src:*' })
$removed        = @($removed | Where-Object { $_ -notlike ':profile:*' -and $_ -notlike ':src:*' -and -not (Test-Machine $_) })

$changedBytes = 0
foreach ($c in $changed) { $changedBytes += [int64](($now[$c] -split ':')[0]) }
if ($profileChanged.Count) { Say '  the plugin list changed' 'Green' }
Say ("  {0:n0} added or changed ({1:n1} MB)" -f $changed.Count, ($changedBytes / 1MB)) $(if ($changed.Count) { 'Green' } else { 'DarkGray' })
Say ("  {0:n0} removed" -f $removed.Count) $(if ($removed.Count) { 'Yellow' } else { 'DarkGray' })

if (-not $changed.Count -and -not $removed.Count -and -not $profileChanged.Count -and -not $Launcher) {
    Head 'Nothing to do'
    Say 'The build matches what is already published.' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}

# Running Ship twice in a row used to cut a second release that carried
# nothing: no mod files, no removals, no launcher source, just a higher
# version number that everyone still had to download. Exit code 2 tells Ship
# that happened so it can put the version number back.
if (-not $changed.Count -and -not $removed.Count -and -not $profileChanged.Count -and -not $srcChanged.Count) {
    Head 'Nothing to do'
    Say 'No mod files changed and no launcher source changed since the last release.' 'Gray'
    Say 'Publishing now would hand everyone a new launcher that does nothing.' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 2
}

if (-not $Id) { $Id = Get-Date -Format 'yyyyMMdd-HHmm' }

# ------------------------------------------------------------ pack
# GitHub refuses a release asset over 2 GiB, and a body mod release goes well
# past that. So the pack is split into chunks that each stay under the limit,
# and version.json lists each one separately. The launcher already applies
# whatever packs it has not seen, in order, so nothing on that side had to
# change: three packs simply look like three updates that arrive together.
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Measured uncompressed. Zipping game data usually lands around 60 percent,
# but textures and meshes are often already compressed and come out near 100,
# so the cap is set where even no compression at all stays under the limit.
$ChunkCap = 1800MB

$chunks = @()
if ($changed.Count -or $removed.Count -or $profileChanged.Count) {
    Head 'Building the pack'

    # Work out the split first, so the number of parts is known before any
    # zipping starts and the progress means something.
    $groups = @()
    $current = @()
    $currentBytes = [int64]0
    foreach ($rel in $changed) {
        $size = [int64](($now[$rel] -split ':')[0])
        if ($current.Count -and ($currentBytes + $size) -gt $ChunkCap) {
            $groups += ,$current
            $current = @()
            $currentBytes = 0
        }
        $current += $rel
        $currentBytes += $size
    }
    if ($current.Count -or -not $groups.Count) { $groups += ,$current }

    if ($groups.Count -gt 1) { Say "  splitting into $($groups.Count) parts, GitHub will not take one over 2 GB" 'Yellow' }

    for ($g = 0; $g -lt $groups.Count; $g++) {
        $part   = $g + 1
        $partId = if ($groups.Count -eq 1) { $Id } else { "$Id-$part" }
        $zipPath = Join-Path $DistDir "pack-$partId.zip"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
        try {
            $n = 0
            foreach ($rel in $groups[$g]) {
                $src = Join-Path $GameDir $rel
                if (-not (Test-Path -LiteralPath $src)) { continue }
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, ('game/' + ($rel -replace '\\', '/')), 'Optimal')
                $n++
                if ($n % 500 -eq 0) { Write-Host ("    part $part  {0:n0}/{1:n0}" -f $n, $groups[$g].Count) -ForegroundColor DarkGray }
            }

            # Removals go in the first part, so nothing is deleted after the
            # files that replace it have already arrived.
            if ($part -eq 1 -and $removed.Count) {
                $e = $zip.CreateEntry('delete.txt')
                $sw = New-Object IO.StreamWriter ($e.Open())
                foreach ($rel in $removed) { $sw.WriteLine(($rel -replace '\\', '/')) }
                $sw.Flush(); $sw.Dispose()
            }

            # The load order rides in the last part. Anyone who stops halfway
            # then has the new files sitting there but not yet switched on,
            # which is the harmless way round.
            #
            # Profile\Default is the only source. This used to prefer
            # %LOCALAPPDATA%\Skyrim Special Edition, which is only this build's
            # folder while the game is actually running. Publishing with the
            # game closed therefore shipped the ordinary Skyrim's plugin list
            # as this build's reference, and every launcher that took the
            # update quietly overwrote its own correct list with it.
            if ($part -eq $groups.Count) {
                foreach ($f in 'plugins.txt', 'loadorder.txt') {
                    $src = Join-Path $ProfileDir "Default\$f"
                    if (-not (Test-Path $src)) { Die "$src is missing. That file is this build's reference plugin list." }
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, "profile/$f", 'Optimal')
                }
            }
        } finally { $zip.Dispose() }

        $bytes = (Get-Item $zipPath).Length
        $mb = [math]::Round($bytes / 1MB, 1)
        if ($bytes -ge 2147483648) {
            Die "pack-$partId.zip came to $mb MB, which GitHub will refuse. Lower `$ChunkCap in this script and run again."
        }
        Say "  pack-$partId.zip  -  $mb MB" 'Green'

        $chunks += [pscustomobject]@{
            Id   = $partId
            Path = $zipPath
            Sha  = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
            Url  = ''
        }
    }
}

# ------------------------------------------------------------ launcher exe
$exePath = Get-LauncherExe (Join-Path $Root 'Launcher')
$launcherVersion = ''
if ($Launcher) {
    if (-not (Test-Path $exePath)) { Die "No launcher at $exePath. Run Build-Launcher.ps1 first." }
    $updaterCs = Join-Path $Here 'app\Updater.cs'
    if (Test-Path $updaterCs) {
        $m = [regex]::Match((Get-Content $updaterCs -Raw), 'Version\s*=\s*"([^"]+)"')
        if ($m.Success) { $launcherVersion = $m.Groups[1].Value }
    }
    if (-not $launcherVersion) { Die 'Could not read the version out of app\Updater.cs. Bump it before publishing a launcher.' }
    Say "  launcher $launcherVersion" 'Green'
}

# ------------------------------------------------------------ upload
$doc = Get-Content $VersionFile -Raw | ConvertFrom-Json

# ConvertFrom-Json gives back an object with only the keys the file had, and
# assigning to a key that was never there throws. Anything new has to be added.
function Set-Prop($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# And reading one that is not there throws outright under strict mode, which is
# how a missing ServerPassword quietly took the whole server block down once.
function Val($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties.Name -contains $k) { return [string]$o.$k }
    return ''
}
if (-not $Repo -and ($doc.PSObject.Properties.Name -contains 'repo')) { $Repo = $doc.repo }

# Without this the asset lookup builds a broken API path, version.json ends up
# with an empty url, and everyone's launcher downloads nothing.
if (-not $Repo) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $remote = (& git -C $RepoDir remote get-url origin 2>$null) | Select-Object -First 1
    $ErrorActionPreference = $old
    if ($remote -and $remote -match 'github\.com[:/](.+?)(?:\.git)?\s*$') { $Repo = $Matches[1] }
}
if (-not $Repo) { Die 'Could not work out which repo to publish to. Pass -Repo owner/name.' }
Say "  repo: $Repo" 'DarkGray'

$gh = Get-Command gh -EA SilentlyContinue
$exeUrl = ''

if (-not $NoUpload -and $gh) {
    Head 'Uploading'
    $assets = @()
    foreach ($c in $chunks) { $assets += $c.Path }
    if ($Launcher) { $assets += $exePath }

    $repoArg = @(); if ($Repo) { $repoArg = @('--repo', $Repo) }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'

    # Tried three times, because GitHub answers HTTP 500 to the release call
    # often enough to be a nuisance rather than an event: it happened on 1.0.133
    # and again on 1.0.135, and both times the identical command worked on the
    # next run. There is nothing to fix at this end. What there was to fix is
    # that one 500 cost a whole Ship, a burnt version number and a rebuild, so
    # it is retried here instead of by hand.
    #
    # Creating is what fails; uploading into a release that already exists is
    # the fallback, and it gets the same treatment.
    $tries = 3
    for ($try = 1; $try -le $tries; $try++) {
        & gh release create $Id @assets @repoArg --title "Update $Id" --notes $(if ($Notes) { $Notes } else { "Update $Id" }) 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { break }

        Say '  Release exists, uploading into it instead.' 'DarkGray'
        & gh release upload $Id @assets @repoArg --clobber 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { break }

        if ($try -lt $tries) {
            $wait = 5 * $try
            Say ('  GitHub did not take it. Trying again in {0}s ({1} of {2}).' -f $wait, ($try + 1), $tries) 'Yellow'
            Start-Sleep -Seconds $wait
        }
    }

    $json = & gh api ("repos/{0}/releases/tags/{1}" -f $Repo, $Id) 2>$null
    $ErrorActionPreference = $old

    # Strict mode throws on a missing property rather than giving back null,
    # and a failed upload leaves exactly that, which is how one bad upload
    # used to end in an unreadable error instead of a plain one.
    $rel = $null
    if ($json) { $rel = ($json -join '') | ConvertFrom-Json }
    $relAssets = @()
    if ($rel -and $rel.PSObject.Properties['assets'] -and $rel.assets) { $relAssets = @($rel.assets) }

    foreach ($a in $relAssets) {
        $u = "https://api.github.com/repos/$Repo/releases/assets/$($a.id)"
        if ($a.name -eq 'Thornswood.exe' -or $a.name -eq 'SkyrimTogether.exe') { $exeUrl = $u; continue }
        foreach ($c in $chunks) {
            if ($a.name -eq ('pack-' + $c.Id + '.zip')) { $c.Url = $u }
        }
    }

    $missing = @($chunks | Where-Object { -not $_.Url })
    if ($missing.Count) {
        Write-Host ''
        foreach ($m in $missing) { Say "  pack-$($m.Id).zip did not upload" 'Red' }
        Die 'Some parts never reached GitHub, so version.json has not been touched. Nobody has been sent a half release.'
    }
    if ($chunks.Count) { Say "  $($chunks.Count) pack asset$(if ($chunks.Count -eq 1) { '' } else { 's' }) ready" 'Green' }

    # The same check for the launcher, which did not have one.
    #
    # The pack guard above only looks at $chunks, and a release with nothing
    # to download has no chunks at all, so a run that changed no mod files and
    # only rebuilt the exe sailed straight past it. GitHub answered HTTP 500 to
    # the release call, $exeUrl came back empty, and version.json was written
    # and pushed saying launcher 1.0.133 with no address to get it from.
    #
    # Nobody was hurt, because the launcher checks:
    #
    #     bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
    #                        && !string.IsNullOrEmpty(v.launcherUrl);
    #
    # so an empty url offers nothing rather than downloading nothing. But it
    # also means anybody on an older launcher is quietly stuck on it until the
    # next release that uploads properly, with the feed insisting there is a
    # newer one. Better to stop here, while the only copy is on this machine
    # and git has not been touched.
    if ($Launcher -and -not $exeUrl) {
        Write-Host ''
        Say '  the launcher was built but never reached GitHub.' 'Red'
        Die 'version.json has not been touched, so the feed still points at the last launcher that actually uploaded. Usually the token or a GitHub hiccup: run Ship again.'
    }
    if ($exeUrl)  { Say "  launcher asset ready" 'Green' }
} elseif (-not $NoUpload) {
    Say '  The GitHub CLI is not installed, so nothing was uploaded.' 'Yellow'
    Say '  winget install GitHub.cli   then   gh auth login' 'Yellow'
}

# ------------------------------------------------------------ version.json
Head 'version.json'
if ($chunks.Count) {
    $packs = @()
    if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs) }
    # In order. The launcher applies whatever it has not seen, in the order it
    # finds them, so part one has to be listed before part two.
    foreach ($c in $chunks) {
        $packs += [pscustomobject]@{
            id     = $c.Id
            url    = $c.Url
            sha256 = $c.Sha
            notes  = $Notes
        }
        Say "  pack $($c.Id) added" 'Green'
    }
    Set-Prop $doc 'packs' $packs
}
if ($Launcher -and (Test-Path $exePath)) {
    $wasVersion = Val $doc 'launcherVersion'
    $wasSha     = Val $doc 'launcherSha256'
    $nowSha     = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()

    Set-Prop $doc 'launcherVersion' $launcherVersion
    Set-Prop $doc 'launcherUrl' $exeUrl
    Set-Prop $doc 'launcherSha256' $nowSha
    Say "  launcher $launcherVersion recorded" 'Green'

    # The updater decides by version number alone. A changed exe under an
    # unchanged version reaches nobody who already has that version, and says
    # nothing while it does not.
    if ($wasSha -and $wasSha -ne $nowSha -and $wasVersion -eq $launcherVersion) {
        Write-Host ''
        Say "  WARNING: the launcher changed but is still version $launcherVersion." 'Red'
        Say '  Anyone already on that version will never be offered this build.' 'Red'
        Say '  Re-run without -NoBump, or with -Version, to get it to them.' 'Yellow'
        Say '  If only mod files changed, -ModsOnly skips the launcher entirely.' 'DarkGray'
        Write-Host ''
    }
}

# Whatever this machine's launcher is pointed at becomes what everyone else is
# pointed at. It is how the password reaches four other people without anyone
# being told what it is, and how a server move fixes itself.
$cfgPath = Join-Path $Root 'config.json'
if (Test-Path $cfgPath) {
    try {
        $raw = [IO.File]::ReadAllBytes($cfgPath)
        $skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { 3 } else { 0 }
        $cfg = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
        # Everyone's launcher takes the address out of version.json and writes
        # it into their own config, so whatever is in THIS machine's config.json
        # at publish time becomes the server for all five people. A stale local
        # config quietly moves the whole group onto a box that is not running
        # anything, and the symptom lands on them rather than here. So a change
        # has to be deliberate.
        $wasAddr = Val $doc 'serverAddress'
        $wasPort = Val $doc 'serverPort'
        $nowAddr = Val $cfg 'ServerAddress'
        $nowPort = Val $cfg 'ServerPort'

        if ($wasAddr -and $nowAddr -and ("$wasAddr`:$wasPort" -ne "$nowAddr`:$nowPort") -and -not $MoveServer) {
            Write-Host ''
            Say 'The server address in version.json is about to change:' 'Red'
            Say ("    was  {0}:{1}" -f $wasAddr, $wasPort) 'Red'
            Say ("    now  {0}:{1}" -f $nowAddr, $nowPort) 'Red'
            Write-Host ''
            Say 'That comes from the config.json on this machine, and it moves everybody.' 'Yellow'
            Say 'If the server really has moved, run Ship again with -MoveServer.' 'Yellow'
            Say 'If it has not, fix the address in the launcher first, or with:' 'Yellow'
            Say '    .\tools\Set-Server.ps1 -Address <ip> -Port <port>' 'Yellow'
            Write-Host ''
            [void](Read-Host 'Enter to exit')
            exit 1
        }

        # UpdateRepo and VoicePort ride along for the same reason the address
        # does: they are facts about the server, not choices, and they used to
        # be boxes on the Settings page that nobody should have been editing.
        #
        # UpdateRepo is the one that matters. A launcher too old to know the
        # repository was renamed cannot be told, because telling it means
        # reaching it through the repository it can no longer find. Publishing
        # the new name under the OLD one, before renaming, is what lets a stale
        # copy read it once and find its way home.
        foreach ($pair in @(@('ServerAddress', 'serverAddress'), @('ServerPort', 'serverPort'),
                            @('ServerPassword', 'serverPassword'),
                            @('UpdateRepo', 'updateRepo'), @('VoicePort', 'voicePort'))) {
            if ($cfg.PSObject.Properties.Name -contains $pair[0]) { Set-Prop $doc $pair[1] ([string]$cfg.($pair[0])) }
        }
        $shown = if (Val $cfg 'ServerPassword') { 'set' } else { 'not set' }
        Say "  server $(Val $cfg 'ServerAddress'):$(Val $cfg 'ServerPort'), password $shown" 'Green'
        Say "  updates from $(Val $cfg 'UpdateRepo'), voice on $(Val $cfg 'VoicePort')" 'Green'
    } catch {
        Say "  could not read config.json, left the server details alone: $($_.Exception.Message)" 'Yellow'
    }
}

# The launcher's News page reads this. Without it the page sits empty however
# many releases go out, because the notes were only ever going into the GitHub
# release body, which nobody playing the game ever sees.
$news = @()
if ($doc.PSObject.Properties['news'] -and $doc.news) { $news = @($doc.news) }

# A note can be a headline on its own, or a headline followed by lines. Any
# line starting with - or * becomes its own bullet on the News page, which is
# the only way a launcher change gets described at all: none of it ships as a
# file, so the diff below cannot see it and only the person who made the
# change can say what it now does.
#
#     .\tools\Ship.ps1 "Quieter publish output
#     - git progress no longer prints as a red error
#     - the Recheck button checks for updates too"
#
$noteLines = @($Notes -split "`r?`n")
$title   = $noteLines[0].Trim()
$bullets = @()
$bodyBits = @()
for ($i = 1; $i -lt $noteLines.Count; $i++) {
    $line = $noteLines[$i].Trim()
    if (-not $line) { continue }
    if ($line -match '^[-*\u2022]\s*(.+)$') { $bullets += $Matches[1].Trim() }
    else { $bodyBits += $line }
}
$body = ($bodyBits -join ' ').Trim()

# One long line with no breaks still splits on its first sentence, the way it
# always did, so old habits keep working.
if ($noteLines.Count -eq 1) {
    $split = [regex]::Match($Notes, '^(.{1,70}?)(?:\.\s+)(.+)$', 'Singleline')
    if ($split.Success) {
        $title = $split.Groups[1].Value.Trim()
        $body  = $split.Groups[2].Value.Trim()
    }
}

# The note is whatever Gavin typed. These lines are what actually moved,
# worked out from the diff, so nobody has to take the note's word for it and
# nobody has to ask what a release contained.
function Listed($names, [int]$cap) {
    if ($names.Count -le $cap) { return ($names -join ', ') }
    return (($names[0..($cap - 1)]) -join ', ') + (', and {0} more' -f ($names.Count - $cap))
}
function LeafNames($paths, [string]$pattern) {
    return @($paths | Where-Object { $_ -match $pattern } |
             ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique)
}

$details = @()

# What Gavin wrote comes first, because it is the only part that knows why.
foreach ($bpt in $bullets) { $details += $bpt }

if ($Launcher -and $launcherVersion) { $details += "Launcher $launcherVersion" }

$newMods  = @(LeafNames $changed '\\.(esp|esm|esl)$')
$goneMods = @(LeafNames $removed '\\.(esp|esm|esl)$')
$newDlls  = @(LeafNames $changed '[\\/]SKSE[\\/]Plugins[\\/][^\\/]+\\.dll$')

if ($newMods.Count)  { $details += 'Mods added or updated: ' + (Listed $newMods 8) }
if ($goneMods.Count) { $details += 'Mods removed: ' + (Listed $goneMods 8) }
if ($newDlls.Count)  { $details += 'Under the hood: ' + (Listed $newDlls 8) }

# Name the parts of the launcher that moved. Not useful on its own, but it is
# the difference between a release that says nothing and one that at least
# shows something happened.
if ($srcChanged.Count) {
    $parts = @($srcChanged | ForEach-Object { Split-Path ($_ -replace '^:src:', '') -Leaf } | Sort-Object -Unique)
    $details += 'Launcher rebuilt: ' + (Listed $parts 6)
}

if ($changed.Count) {
    $details += ('{0:n0} file{1} to download, {2:n1} MB' -f $changed.Count, $(if ($changed.Count -eq 1) { '' } else { 's' }), ($changedBytes / 1MB))
}
elseif (-not $srcChanged.Count) { $details += 'Nothing to download, this one is bookkeeping' }
if ($profileChanged.Count) { $details += 'The load order moved, so start a new character or expect the old save to complain' }

# The actual list, not a count of it. Every path that moved, changed ones
# first and removed ones marked, so a release can be read rather than trusted.
# Capped because a texture pack would otherwise bury the page, and the cap
# says how many it swallowed.
$Cap = 80
$log = @()
foreach ($c in @($changed | Sort-Object)) { $log += $c }
foreach ($r in @($removed | Sort-Object)) { $log += '- ' + $r }
foreach ($p in @($profileChanged | Sort-Object)) { $log += ($p -replace '^:profile:', '') + '  (load order)' }
foreach ($p in @($srcChanged | Sort-Object)) { $log += 'tools\' + ($p -replace '^:src:', '') + '  (launcher)' }
if ($log.Count -gt $Cap) {
    $rest = $log.Count - $Cap
    $log  = @($log[0..($Cap - 1)]) + ('... and {0:n0} more file{1}' -f $rest, $(if ($rest -eq 1) { '' } else { 's' }))
}

$entry = [pscustomobject]@{
    date    = (Get-Date).ToString('d MMM yyyy')
    title   = $title
    body    = $body
    details = @($details)
    files   = @($log)
}
# Shipping twice in a row with the same note is a re-publish, not two pieces
# of news. Only the first one is worth reading.
$repeat = $false
if ($news.Count -gt 0) {
    $top = $news[0]
    if ((Val $top 'title') -eq $entry.title -and (Val $top 'body') -eq $entry.body) { $repeat = $true }
}

if ($repeat) {
    Say '  same note as last time, so no new news entry' 'DarkGray'
} else {
    # Newest first, and only the last forty. It is a news feed, not a changelog.
    #
    # Twenty until one evening of fixes filled it and started pushing real
    # releases off the bottom. Publish-Server writes here too now, so the
    # feed has two sources and needs the room.
    $news = @($entry) + $news
    if ($news.Count -gt 40) { $news = $news[0..39] }
    Set-Prop $doc 'news' $news
    Say '  news entry added' 'Green'
}

# Set-Content -Encoding UTF8 writes a byte order mark on Windows PowerShell,
# and a BOM is not JSON. The launcher's reader stops on it and reports an
# unexpected character, which takes out the update check for everyone at once,
# including their route to a fix. So this file is written without one.
[IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))

# A pack with no url is not a warning. It is a release that switches Play off
# for every person who takes it, because their launcher tries to download from
# an empty address, fails, and treats a pack it cannot apply as one the server
# is expecting. It locks out whoever would have to publish the fix as well.
# So this stops here, before the push, while the only copy is the one on this
# machine and git has not been touched.
$blank = @($chunks | Where-Object { -not $_.Url })
if ($blank.Count) {
    Write-Host ''
    Say ("{0} pack(s) uploaded no asset, so their url is empty:" -f $blank.Count) 'Red'
    foreach ($b in $blank) { Say ("    " + $b.Id) 'Red' }
    Write-Host ''
    Say 'version.json has been written but NOT pushed. Nobody has this yet.' 'Yellow'
    Say 'The upload is what failed, usually the token or the release. Fix that and run Ship again.' 'Yellow'
    Say 'If a bad one did go out, .\tools\Repair-Manifest.ps1 takes it back out and pushes.' 'Yellow'
    Write-Host ''
    [void](Read-Host 'Enter to exit')
    exit 1
}

# ------------------------------------------------------------ the server copy
# ModCheck compares against the server's own Data/loadorder.txt. Change the
# plugin list here and forget that file, and the server refuses everyone,
# including whoever changed it. So the file to upload is written out every time
# the list moves, already in the form the server parses.
if ($profileChanged.Count) {
    $serverDir = Join-Path $DistDir 'server'
    $null = New-Item -ItemType Directory -Force -Path $serverDir
    $lo = Join-Path $ProfileDir 'Default\loadorder.txt'
    $names = @(Get-Content $lo | ForEach-Object { $_.Trim() } |
               Where-Object { $_ -and -not $_.StartsWith('#') })
    $serverFile = Join-Path $serverDir 'loadorder.txt'
    [IO.File]::WriteAllLines($serverFile, [string[]]$names, (New-Object Text.UTF8Encoding($false)))

    Head 'The server needs this too'
    Say "  $serverFile  -  $($names.Count) plugins" 'Yellow'
    Say "  Upload it to the server's Data folder, replacing what is there, then restart." 'Yellow'
    Say '  If ModCheck is on, the server turns away anyone with the new list until you do.' 'Yellow'
}

# ------------------------------------------------------------ push
if (-not $NoPush) {
    Head 'Pushing'
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location $RepoDir
    try {
        # git writes its progress to stderr, and Out-Host renders anything on
        # stderr as a red error record even when the push succeeded. Flattening
        # each line to a string first keeps the output honest about what it is.
        function Relay { process { Write-Host ('  ' + $_.ToString()) -ForegroundColor DarkGray } }
        & git add version.json
        & git commit -m "Update $Id$(if ($Notes) { ": $Notes" })" 2>&1 | Relay
        & git push 2>&1 | Relay
    } finally { Pop-Location; $ErrorActionPreference = $old }
}

Save-State

Head 'Done'
Say "Everyone's launcher will offer update $Id on next start." 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
