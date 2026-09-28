<#
  Repair-Manifest.ps1

  Takes packs with no download url back out of version.json and pushes the fix.
  Since 24 September it takes out packs held anywhere but the repository
  launchers read the feed from as well.

  How one gets in there: publishing uploads each pack as a release asset and
  writes the returned url into version.json. When an upload fails, the pack is
  still written, with an empty url. Every launcher then tries to download from
  nothing, fails with "The path is not of a legal form", and because a pack it
  cannot apply is a pack the server is expecting, Play stays switched off. It
  locks out everybody at once, including the person who published it.

  A pack removed here is not lost work: the next publish rebuilds from the
  current build, so whatever was in it ships again in the next one.

  The other kind is a pack whose url is a release asset anywhere but the
  repository launchers read the feed from (Feed-Rules.ps1 has the rule and the
  measurement). On 24 September that was 164 of the 227 packs on the live feed,
  20260910-2345 to 20260914-1917, all in the private source repository, which
  has no releases left, so nothing can download them with or without a token.
  Taking them out loses nothing a launcher could have had. The installer is
  built from a game they were applied to, which is why Package-Thornswood.ps1
  seeds applied.txt with their ids.

  It works on the feed launchers read: version.json in the releases clone
  beside this repository, Thornswood-Releases, or Thornswood-Releases-dev with
  -Channel dev. Until 24 September it read version.json in the source
  repository, which stopped being the feed on 15 September, so it would have
  repaired a file no launcher downloads and pushed it to the source repository.

      .\Repair-Manifest.ps1            show what is broken and fix it
      .\Repair-Manifest.ps1 -DryRun    show it and change nothing
      .\Repair-Manifest.ps1 -Channel dev -DryRun    the same for the dev feed

  MOVING THE URLS TO THE SITE (#897). With -MoveToSite it takes nothing out:
  every url on the feed that still points at GitHub, and whose bytes the site
  already answers for at /feed[-dev]/assets/<sha256>, is rewritten to that
  address, and the feed is pushed like any other repair. A url the site does
  not answer for stays where it is. It is how the main feed moves without
  waiting for a main Ship; the site copy follows with
  .\scripts\deploy\Remirror-Site-Feed.ps1 (-Dev for dev).

      .\Repair-Manifest.ps1 -MoveToSite -DryRun     what would move
      .\Repair-Manifest.ps1 -MoveToSite             move it and push
#>
[CmdletBinding()]
param(
    [string]$RepoDir,
    [switch]$DryRun,
    [switch]$NoPush,
    [switch]$NoPause
    ,[ValidateSet('main', 'dev')][string]$Channel = 'main'
    ,[switch]$MoveToSite
    # Where the site answers. The tests point it at a copy on this machine.
    ,[string]$SiteUrl = 'https://thornswood.net'
    # The applied.txt settled on this machine. Left out, it is the install for
    # the channel, found the way Publish-Update.ps1 finds it rather than
    # assumed to be on C:. The harness points it at a scratch file, because the
    # live one is never touched to test anything.
    ,[string]$AppliedFile
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) {
    $RepoDir = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Here))) $(if ($Channel -eq 'dev') { 'Thornswood-Releases-dev' } else { 'Thornswood-Releases' })
}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

# ---- where the launcher is installed ----------------------------------------
#
# The same rule as Find-Root in Publish-Update.ps1, kept identical so the
# applied.txt settled below is the one the launcher on this machine reads.
# C:\Thornswood on most machines; when C: has no launcher, every fixed drive is
# tried for <drive>:\Thornswood\Launcher\Thornswood.exe, because a second
# developer may have installed on another drive. Until this it was always C:,
# so on that machine the repair wrote nothing, the dead pack ids were never
# marked as seen, and the launcher kept the update card up until the repaired
# feed came back down. The dev build is the main root plus -DevBuild, on the
# same drive; that is where the main launcher's Settings page installs it
# (DevBuild.cs). -AppliedFile still wins.
function Find-Root {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}

. (Join-Path $Here 'Feed-Rules.ps1')

$VersionFile = Join-Path $RepoDir 'version.json'
if (-not (Test-Path -LiteralPath $VersionFile)) { Die "not found: $VersionFile. That is where the releases clone is expected; pass -RepoDir if it is somewhere else." }

# Pulled first, the way Publish-Update does it, so the repair lands on top of
# whatever was published since this clone last looked rather than on a copy
# git push then refuses. A dry run reads the clone as it stands.
if (-not $DryRun -and -not $NoPush -and (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $pulled = & git -C $RepoDir pull --rebase --quiet 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) {
        Write-Host ($pulled | Out-String) -ForegroundColor Red
        Die "Could not pull $RepoDir. Nothing was written."
    }
}

Head 'Reading version.json'
Say "  $VersionFile" 'DarkGray'
$doc = Get-Content -LiteralPath $VersionFile -Raw | ConvertFrom-Json
$packs = @()
if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs) }
Say ("  {0} pack(s)" -f $packs.Count) 'DarkGray'

if ($MoveToSite) {
    $dev = ($Channel -eq 'dev')
    $prefix = if ($dev) { 'feed-dev' } else { 'feed' }
    Head "Moving urls to $SiteUrl/$prefix/assets/"
    $mv = Move-FeedUrlsToSite $doc -Dev:$dev -OnSite { param($sha, $bytes) Test-SiteAsset $SiteUrl $prefix $sha $bytes }
    $left = @($mv.Stayed)
    Say ("  {0} url(s) move to the site" -f $mv.Moved.Count) $(if ($mv.Moved.Count) { 'Green' } else { 'DarkGray' })
    if ($left.Count) {
        Say ("  {0} stay where they are, because the site does not answer for them:" -f $left.Count) 'Yellow'
        foreach ($l in $left) { Say "    $($l.What)" 'Yellow' }
        Say '  .\scripts\oneoff\Copy-ReleaseAssets-ToSite.ps1 puts them up.' 'Yellow'
    }
    if ($DryRun -or -not $mv.Moved.Count) {
        if ($DryRun) { Say '  Dry run. Nothing was written.' 'Yellow' }
        Write-Host ''
        if (-not $NoPause) { [void](Read-Host 'Enter to close') }
        exit 0
    }
    [IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    Say '  version.json written' 'Green'
    if ($NoPush) {
        Say 'Not pushed, as asked.' 'Yellow'
    } else {
        Head 'Pushing'
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & git -C $RepoDir add version.json 2>&1 | Out-Host
        & git -C $RepoDir commit -m "Downloads come from the site: $($mv.Moved.Count) url(s)" 2>&1 | Out-Host
        & git -C $RepoDir push 2>&1 | Out-Host
        $rc = $LASTEXITCODE
        $ErrorActionPreference = $old
        if ($rc -ne 0) { Die "git push exited with $rc. The file is moved here, it just is not up yet." }
        Say '  pushed' 'Green'
    }
    Say ("Now put it on the site: .\scripts\deploy\Remirror-Site-Feed.ps1{0}" -f $(if ($dev) { ' -Dev' } else { '' })) 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

$feedRepo = Get-FeedRepo $doc
$split = Split-FeedPacks $packs $feedRepo
$bad = @($split.Drop | ForEach-Object { $_.Pack })
$good = @($split.Keep)

if ($bad.Count -eq 0) {
    Say "  every pack downloads from $feedRepo. Nothing to repair." 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'Broken'
foreach ($why in @($split.Drop | ForEach-Object { $_.Why } | Sort-Object -Unique)) {
    $these = @($split.Drop | Where-Object { $_.Why -eq $why })
    Say ("  {0} pack(s) {1}, {2} to {3}" -f $these.Count, $why, $these[0].Pack.id, $these[$these.Count - 1].Pack.id) 'Red'
    foreach ($d in $these) {
        $note = ([string]$d.Pack.notes -split "`r?`n")[0]
        if ($note.Length -gt 70) { $note = $note.Substring(0, 70) + '...' }
        Say ("    {0}   {1}" -f $d.Pack.id, $note) 'DarkGray'
    }
}

# The launcher also stops asking about a pack once its id is in applied.txt, so
# the copy on this machine is settled here as well. Without it this launcher
# would keep the update card up until the repaired file comes back down.
$applied = $AppliedFile
if (-not $applied) {
    $root = Find-Root
    if ($Channel -eq 'dev') { $root = $root + '-DevBuild' }
    $applied = Join-Path $root 'Profile\applied.txt'
}
if ($DryRun) {
    Head 'Dry run'
    Say ("  would keep {0} pack(s) and drop {1}" -f $good.Count, $bad.Count) 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'Repairing'
$doc.packs = $good
# WriteAllText rather than Set-Content: Windows PowerShell puts a byte order
# mark on UTF8 output and a BOM is not JSON, which takes the update check out
# for everyone at once.
[IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Say ("  version.json now lists {0} pack(s)" -f $good.Count) 'Green'

if (Test-Path -LiteralPath $applied) {
    $have = @(Get-Content -LiteralPath $applied | Where-Object { $_.Trim() })
    $add = @($bad | ForEach-Object { [string]$_.id } | Where-Object { $have -notcontains $_ })
    if ($add.Count) {
        Add-Content -LiteralPath $applied -Value $add
        Say ("  marked {0} dead pack(s) as seen on this machine" -f $add.Count) 'DarkGray'
    }
}

if ($NoPush) {
    Write-Host ''
    Say 'Not pushed, as asked. Push it yourself with:' 'Yellow'
    Say "  git -C `"$RepoDir`" add version.json; git -C `"$RepoDir`" commit -m 'Drop packs no launcher can download'; git -C `"$RepoDir`" push" 'DarkGray'
}
else {
    Head 'Pushing'
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $RepoDir add version.json 2>&1 | Out-Host
    & git -C $RepoDir commit -m "Drop $($bad.Count) pack(s) no launcher can download" 2>&1 | Out-Host
    & git -C $RepoDir push 2>&1 | Out-Host
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) { Die "git push exited with $rc. The file is fixed here, it just is not up yet." }
    Say '  pushed' 'Green'
}

Write-Host ''
Say 'Open the launcher. The update card should clear and Play should come back.' 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
