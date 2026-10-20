<#
  BuildStamp.ps1

  What a server's gamemode is, written down beside it. Dot-sourced by
  Deploy-Gamemode.ps1, which leaves thornswood-build.json next to gamemode.js
  in the server build; Deploy-Server.ps1, which sends it up with gamemode.js
  and makes it again if it does not describe the gamemode being sent; and
  Deploy-DevGamemode.ps1, which makes one and sends it to the dev server:

      {
        "channel":               "main" or "dev",
        "commit":                the repo's short commit when it was stamped,
        "gamemodeMatchesCommit": false when gamemode.js had edits not in it,
        "gamemodeSha256":        the gamemode.js this describes,
        "launcherVersion":       launcher\app\Updater.cs, the number Ship reads,
        "feedVersion":           what that channel's version.json offers,
        "stampedUtc":            when the stamp was made
      }

  stampedUtc and not deployedUtc, because Deploy-Server.ps1 sends the stamp
  Deploy-Gamemode.ps1 made, which can be some minutes older than the send.

  WHY THIS EXISTS. Entry 202 on the To Do List: "The server half is not part
  of the release, and nothing ever compares the client build against the
  server build." Ship.ps1 never carries the gamemode, and nothing on the
  server says which one it is running. Check-LiveGamemode.ps1 can hash the
  live file against this repo, but only this repo as it is today: a server
  that is behind can say it is different and never what it is. This is the
  first step, so the server can say. Reading it in the gamemode and showing
  it on the launcher come after, once Patrick has said what the build string
  should be.

  THE COMMIT ALONE CAN LIE, and that is why the hash and the flag are there.
  A dev deploy may run from any branch with the gamemode edited and not yet
  committed, and then the commit names a gamemode that is not the one on the
  server. gamemodeSha256 is what was actually sent, and gamemodeMatchesCommit
  says whether the commit is enough to get it back. It is null when git cannot
  tell, which is not the same as true.

  TWO VERSIONS, because a dev build carries a number no source file does.
  Ship puts 1.1.92.2 into Updater.cs for the build and then puts 1.1.92 back,
  so the four part number exists only in the dev feed's version.json. The
  feeds are this machine's working copies of what Ship.ps1 publishes,
  %LOCALAPPDATA%\Thornswood\feed\main and ...\feed\dev (Feed-Store.ps1,
  #907), the same from every checkout and worktree; until #907 they were the
  Thornswood-Releases clones beside the repo. Not the version.json inside the
  repo: it stopped being the feed when releases moved to their own
  repository, and on 24 September it said 1.0.196 while Updater.cs and the
  real feed both said 1.1.92. feedVersion is empty when no feed is found,
  because a wrong number here is worse than none.

  Nothing here talks to anything but git and the local disk.
#>

function New-ThornswoodBuildStamp {
  param(
    [Parameter(Mandatory = $true)][string]$Gamemode,
    [Parameter(Mandatory = $true)][ValidateSet('main', 'dev')][string]$Channel,
    [Parameter(Mandatory = $true)][string]$RepoDir,
    [string]$FeedDir,
    # The deploy artifact the gamemode came out of (Artifact.ps1, #459). Its
    # commit is the answer, since a gamemode read out of a zip is outside the
    # repo and git cannot say, and an artifact is always the commit's own
    # bytes: a deploy with uncommitted changes is refused (#1121).
    $Artifact
  )

  # git writes to stderr in normal operation and the deploy scripts run with
  # Stop, which turns that into a halt. A stamp that cannot be made whole is
  # still made; the deploy is never stopped for it.
  $ErrorActionPreference = 'Continue'

  if (-not (Test-Path -LiteralPath $Gamemode)) { throw "no gamemode at $Gamemode to stamp" }
  $sha = (Get-FileHash -LiteralPath $Gamemode -Algorithm SHA256).Hash.ToLowerInvariant()

  $commit = ''
  $atCommit = $null
  if ($Artifact) {
    $commit = [string]$Artifact.Short
    $atCommit = $true
  } elseif (Get-Command git -ErrorAction SilentlyContinue) {
    # No git on the path is the one thing that threw here, and it is asked
    # for directly: then git cannot tell, so commit is '' and the flag null,
    # which Format-ThornswoodBuildStamp prints as "no commit".
    $out = & git -C $RepoDir rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { $commit = ([string]($out | Select-Object -First 1)).Trim() }
    if ($commit) {
      # Compared by git rather than by hashing HEAD's copy, because the checkout
      # converts line endings and the two hashes differ for a file that has not
      # changed at all. 0 is the same, 1 is edited, anything else is git saying
      # it cannot answer, such as a gamemode from outside the repo.
      $full = (Resolve-Path -LiteralPath $Gamemode).ProviderPath.Replace('\', '/')
      & git -C $RepoDir diff --quiet HEAD -- $full 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $atCommit = $true }
      elseif ($LASTEXITCODE -eq 1) { $atCommit = $false }
    }
  }

  $launcher = ''
  $updater = Join-Path $RepoDir 'launcher\app\Updater.cs'
  if (Test-Path -LiteralPath $updater) {
    $m = [regex]::Match([IO.File]::ReadAllText($updater), 'Version\s*=\s*"([^"]+)"')
    if ($m.Success) { $launcher = $m.Groups[1].Value }
  }

  if (-not $FeedDir) {
    # This machine's working copy of the channel's feed (Feed-Store.ps1), the
    # same folder whichever checkout or worktree this runs from.
    $c = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Thornswood') 'feed') $Channel
    if (Test-Path -LiteralPath (Join-Path $c 'version.json')) { $FeedDir = $c }
  }
  $feed = ''
  if ($FeedDir) {
    try {
      $feed = [string]((Get-Content -LiteralPath (Join-Path $FeedDir 'version.json') -Raw -ErrorAction Stop | ConvertFrom-Json).launcherVersion)
    } catch { $feed = '' }
  }

  $now = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)

  return [ordered]@{
    channel               = $Channel
    commit                = $commit
    gamemodeMatchesCommit = $atCommit
    gamemodeSha256        = $sha
    launcherVersion       = $launcher
    feedVersion           = $feed
    stampedUtc            = $now
  }
}

# Writes the stamp and hands it back. WriteAllText with an explicit encoding,
# for the reason Deploy-Gamemode.ps1 gives at length: Set-Content -Encoding
# UTF8 writes a byte order mark under Windows PowerShell 5.1, and node's
# JSON.parse stops on it.
function Save-ThornswoodBuildStamp {
  param(
    [Parameter(Mandatory = $true)][string]$Gamemode,
    [Parameter(Mandatory = $true)][ValidateSet('main', 'dev')][string]$Channel,
    [Parameter(Mandatory = $true)][string]$RepoDir,
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$FeedDir,
    $Artifact
  )
  $stamp = New-ThornswoodBuildStamp -Gamemode $Gamemode -Channel $Channel -RepoDir $RepoDir -FeedDir $FeedDir -Artifact $Artifact
  [IO.File]::WriteAllText($Path, ($stamp | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
  return $stamp
}

# True when the stamp at $Path is there, parses, and describes this gamemode.
# A stamp that names a different gamemode is worse than none, so a caller that
# gets false writes a fresh one rather than sending the old.
function Test-ThornswoodBuildStamp {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Gamemode
  )
  if (-not (Test-Path -LiteralPath $Path) -or -not (Test-Path -LiteralPath $Gamemode)) { return $false }
  try { $s = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
  $want = (Get-FileHash -LiteralPath $Gamemode -Algorithm SHA256).Hash.ToLowerInvariant()
  return ([string]$s.gamemodeSha256 -eq $want)
}

# One line for a deploy to print, so the run says what it stamped.
function Format-ThornswoodBuildStamp($stamp) {
  $c = $stamp.commit
  if (-not $c) { $c = 'no commit' }
  elseif ($stamp.gamemodeMatchesCommit -eq $false) { $c = $c + ' plus uncommitted edits' }
  $v = $stamp.launcherVersion
  if ($stamp.feedVersion -and $stamp.feedVersion -ne $stamp.launcherVersion) { $v = $v + ', feed ' + $stamp.feedVersion }
  return ('{0}, {1}, launcher {2}, gamemode {3}' -f $stamp.channel, $c, $v, $stamp.gamemodeSha256.Substring(0, 12))
}
