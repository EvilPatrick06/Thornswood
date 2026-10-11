<#
  Resolve-ReleaseTag.ps1

  Says which commit a launcher release builds, or refuses (#2202). The release
  workflow (.github/workflows/release.yml) can be started by hand with a free
  form tag input. It used to hand that string straight to actions/checkout and
  draft the release against the run's own SHA. A branch name, a bare SHA, a tag
  on a commit that never reached main, or a tag that has moved could then be
  built and labelled as a release, with provenance that did not match.

      . .\scripts\release\Resolve-ReleaseTag.ps1
      $commit = Resolve-ThornswoodReleaseTag -Tag v1.2.3 -RepoDir . [-ExpectedSha <sha>] [-MainRef origin/main]

  The tag has to be named v<version>, exist as a tag (refs/tags, not a branch
  or a SHA), and point at a commit. Then either that commit is -ExpectedSha
  (a tag push passes its own GITHUB_SHA; a manual run may pass one), or, with
  no -ExpectedSha, the commit is on -MainRef. Anything else throws, naming the
  tag and why. Returns the full commit SHA. Reads git only; changes nothing.
  Works on Windows PowerShell 5.1 and PowerShell 7.
#>

function Invoke-ThornswoodReleaseGit([string]$RepoDir, [string[]]$GitArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>$null
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = (@($out) -join "`n").Trim() }
}

function Resolve-ThornswoodReleaseTag {
    param(
        [Parameter(Mandatory)][string]$Tag,
        [string]$RepoDir = '.',
        [string]$ExpectedSha = '',
        [string]$MainRef = 'origin/main'
    )
    $Tag = $Tag.Trim()
    if ($Tag.StartsWith('refs/tags/')) { $Tag = $Tag.Substring('refs/tags/'.Length) }
    if ($Tag -notmatch '^v[0-9][0-9A-Za-z.\-]*$') {
        throw "Refused: '$Tag' is not a v<version> tag name. Nothing was built."
    }
    $r = Invoke-ThornswoodReleaseGit $RepoDir @('rev-parse', '--verify', '--quiet', ('refs/tags/' + $Tag + '^{commit}'))
    if ($r.Code -ne 0 -or $r.Out -notmatch '^[0-9a-f]{40}$') {
        throw "Refused: there is no tag $Tag in this repository (a branch or a SHA is not a release tag). Nothing was built."
    }
    $commit = $r.Out
    $ExpectedSha = $ExpectedSha.Trim().ToLowerInvariant()
    if ($ExpectedSha) {
        if ($ExpectedSha -notmatch '^[0-9a-f]{7,40}$') { throw "Refused: the expected SHA '$ExpectedSha' is not a commit SHA. Nothing was built." }
        if (-not $commit.StartsWith($ExpectedSha)) {
            throw ("Refused: tag {0} is commit {1}, not the expected {2}. Nothing was built." -f $Tag, $commit, $ExpectedSha)
        }
        return $commit
    }
    $m = Invoke-ThornswoodReleaseGit $RepoDir @('rev-parse', '--verify', '--quiet', ($MainRef + '^{commit}'))
    if ($m.Code -ne 0) { throw "Refused: $MainRef is not in this checkout, so it cannot be told whether tag $Tag is on it. Nothing was built." }
    $a = Invoke-ThornswoodReleaseGit $RepoDir @('merge-base', '--is-ancestor', $commit, $MainRef)
    if ($a.Code -ne 0) {
        throw ("Refused: tag {0} is commit {1}, which is not on {2}. Pass the commit as the expected SHA if that is meant. Nothing was built." -f $Tag, $commit, $MainRef)
    }
    return $commit
}
