<#
  CollectionRevision.ps1

  Which collection revision a release is built against, and the one place
  that number comes from (#3597).

      $r = Get-ShipRecordedCollectionRevision -RepoDir <repo>
      $why = Get-ShipCollectionRevisionProblem -RepoDir <repo> -Built <n> -Slug <slug> -Source <words> -Remedy <words>

  records\collection-plugins.json names the collection and the revision its
  plugins are, and both deploys already hold every plugin they send to it
  (CollectionPlugins.ps1, #2019). It is the revision Nexus gives people and the
  servers are deployed against, so it is what the feed's collectionRevision
  says, and the launcher holds Play until an install is on it (Shell.cs,
  CollectionProblem).

  Until #3597 the feed's number came from somewhere else: a Ship from One wrote
  the revision One's Vortex had installed, and a Ship from the feed carried the
  last release's. One's Vortex stayed on revision 2 while revisions 3, 4 and 5
  were made and published without it, so both feeds said 2 from 21 to 27 Oct,
  and a launcher on revision 2 read as current and was let in (Patrick, 27 Oct:
  "my local collection is on #2 and the launcher never made me update to the
  newest one and still let me in").

  So a release names the recorded revision, and it may only be built from a
  source that is on it: One's Vortex for a Ship from One (its plugin list, load
  order and bodies are read there), the last release for a Ship from the feed
  (it carries that release's plugin list). When the source is on another
  revision, or cannot say which, the Ship stops, naming both numbers, before
  anything is built. It never writes the source's number instead.

  Dot-sourced by Ship-Rules.ps1 and New-FeedRoot.ps1; defines functions and
  nothing else. Works on Windows PowerShell 5.1 and PowerShell 7.
#>

# The record's collection and revision, as { Slug; Revision }. Throws, naming
# the file, when it is not there, does not read, or names no whole revision.
function Get-ShipRecordedCollectionRevision([string]$RepoDir, [string]$Path) {
    if (-not $Path) { $Path = Join-Path $RepoDir 'records\collection-plugins.json' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "There is no $Path, so nothing says which collection revision this release is built against."
    }
    try { $doc = ([IO.File]::ReadAllText($Path) -replace '^﻿', '') | ConvertFrom-Json }
    catch { throw ("$Path does not read as JSON, so nothing says which collection revision this release is built against: " + ($_.Exception.Message -replace '\s+', ' ')) }
    $slug = if ($doc.PSObject.Properties['collection']) { [string]$doc.collection } else { '' }
    $raw = if ($doc.PSObject.Properties['revision']) { $doc.revision } else { $null }
    $n = 0
    if ($null -eq $raw -or $raw -is [bool] -or $raw -is [string] -or -not [int]::TryParse([string]$raw, [ref]$n) -or $n -lt 1) {
        throw "$Path names no whole collection revision, so nothing says which one this release is built against."
    }
    if ($slug -notmatch '^[A-Za-z0-9]+$') { throw "$Path names no collection, so the revision it records is not known to be this collection's." }
    return [pscustomobject]@{ Slug = $slug; Revision = $n; Path = $Path }
}

# '' when a release built from a source on revision $Built may go out naming
# the recorded revision; otherwise the reason it may not, with both numbers
# and $Remedy. $Source says what $Built was read from ("this machine's Vortex",
# "the dev feed's last release"). A record that does not read is a reason too.
function Get-ShipCollectionRevisionProblem([string]$RepoDir, [int]$Built, [string]$Slug, [string]$Source, [string]$Remedy, [string]$Path) {
    try { $rec = Get-ShipRecordedCollectionRevision $RepoDir $Path }
    catch { return $_.Exception.Message }
    if ($Slug -and $Slug -ne $rec.Slug) {
        return "This release names collection $Slug and records\collection-plugins.json is collection $($rec.Slug)'s, so which revision it is built against is not known. $Remedy"
    }
    if ($Built -le 0) {
        return "$Source does not say which collection revision it is on, and the collection is on revision $($rec.Revision) (records\collection-plugins.json). A release has to be built from revision $($rec.Revision) to say so. $Remedy"
    }
    if ($Built -lt $rec.Revision) {
        return "The collection is on revision $($rec.Revision) (records\collection-plugins.json, what Nexus gives people and the deploys hold the servers' plugins to) and $Source is on revision $Built. A release built from it would carry revision $Built's plugins and tell every launcher that $Built is current, so an install left on $Built would be let in. $Remedy"
    }
    if ($Built -gt $rec.Revision) {
        return "$Source is on collection revision $Built and records\collection-plugins.json is still on $($rec.Revision). Record revision $Built (scripts\mods\New-CollectionPluginRecord.ps1) in its own pull request first, so the deploys and this release agree on it. $Remedy"
    }
    return ''
}
