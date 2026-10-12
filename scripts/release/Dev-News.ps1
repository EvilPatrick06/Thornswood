<#
  Dev-News.ps1

  Which notes on the dev feed are marked DEV, worked out from main's feed, and
  the one place that writes those marks and the dev feed's mainVersion.

      . (Join-Path $PSScriptRoot 'Dev-News.ps1')

  WHY IT EXISTS. The dev feed carries main's whole news list with the dev
  notes on top, and the dev launcher's News tab marks a note DEV when the dev
  build has it and main does not (Config.cs NewsItem.channel, ShellNews.cs).
  Until 6 Oct those marks were worked out only inside a dev publish that
  released something, in Publish-Update.ps1. Measured on 6 Oct 2026 at about
  11 AM: the dev feed had 40 notes, 27 marked DEV, and mainVersion 1.1.106,
  while main had shipped 1.2.0 (release 20261005-235125, from 1c0caabe) after
  the last dev Ship. Three things kept them stale:

    - a dev Ship with nothing new stopped at "Nothing to do" before the marks
      were worked out;
    - a main Ship never touched the dev feed, so after every main release the
      dev News tab showed finished work as DEV until somebody shipped dev;
    - on 5 Oct that was put right by hand with a dev Ship titled "Dev and main
      match again", a release made only to move the marks.

  So the rule lives here, once, and three things call it: a dev publish that
  releases (Set-DevFeedMarks on the feed it is about to send), a dev publish
  with nothing new, and a main Ship once main's feed is out (both through
  Update-DevFeedMarks, the second by Refresh-DevNews.ps1). A refresh makes no
  release, sends no pack, launcher or baseline, posts nothing and tells no
  server: it sends version.json alone, through Feed-Store.ps1 like any other
  feed edit, and only when a mark or mainVersion moved.

      Update-DevNewsChannels $doc $news $mainDoc $repo   the rule, note by note
      Set-DevFeedMarks $doc $mainDoc $repo               the rule and mainVersion on a feed in memory
      Update-DevFeedMarks -SourceRepo ...                receive the dev feed, mark it, send it back if it moved
      Get-DevFeedMarksLines $result                      what to say about a result
#>

. (Join-Path $PSScriptRoot 'Feed-Store.ps1')
. (Join-Path $PSScriptRoot 'Release-Name.ps1')
. (Join-Path $PSScriptRoot 'Feed-News.ps1')

# ConvertFrom-Json hands back an object with only the keys the file had:
# reading one that is not there throws under strict mode, and assigning one
# that was never there throws too. Publish-Update has its own Val and Set-Prop,
# defined well after the point where a publish with nothing new stops, so this
# file carries its own.
function Get-DevNewsVal($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties.Name -contains $k) { return [string]$o.$k }
    return ''
}
function Set-DevNewsProp($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# Every dev release Ship tagged that this clone has (release/dev/<id>,
# Add-ReleaseTag in Release-Name.ps1), each with the commit it was built from,
# whether it was built with uncommitted files, and the minutes its note can
# carry: from the minute its id names (Publish-Update mints the id before it
# writes the note) to the minute Ship tagged it (after the feed with the note
# was sent), both on the clock of the machine that shipped it, the one the
# note's date is written on. A tag with no tagger, made by hand without -a,
# has no end to that span and no message, so it is left out.
function Get-DevReleaseTags([string]$sourceRepo) {
    $tags = @()
    # The caller's last exit code is put back, as Is-Published does below.
    $hadCode = Test-Path -LiteralPath 'variable:global:LASTEXITCODE'
    $was = if ($hadCode) { $global:LASTEXITCODE } else { 0 }
    try {
        $g = Invoke-ReleaseGit $sourceRepo @('for-each-ref', 'refs/tags/release/dev',
            '--format=@@%(refname)%09%(objecttype)%09%(*objectname)%09%(taggerdate:iso)%0a%(contents)')
    } finally {
        if ($hadCode) { $global:LASTEXITCODE = $was }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
    if ($g.Code -ne 0) { return @() }
    $cur = $null
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($l in @($g.Lines)) {
        $s = [string]$l
        if ($s.StartsWith('@@')) {
            if ($cur) { $tags += $cur }
            $cur = $null
            $f = $s.Substring(2).Split("`t")
            if ($f.Count -lt 4 -or $f[1] -ne 'tag' -or $f[2] -notmatch '^[0-9a-f]{40}$') { continue }
            $id = $f[0] -replace '^refs/tags/release/dev/', ''
            $from = [datetime]::MinValue; $to = [datetime]::MinValue
            # The first 13 characters of an id are its minute in both shapes
            # it has had, yyyyMMdd-HHmm and yyyyMMdd-HHmmss (New-ReleaseId).
            if ($id.Length -lt 13 -or -not [datetime]::TryParseExact($id.Substring(0, 13), 'yyyyMMdd-HHmm', $inv, 'None', [ref]$from)) { continue }
            # "2026-10-01 20:04:26 -0600": the tagger's own clock.
            $at = $f[3].Trim()
            if ($at.Length -lt 16 -or -not [datetime]::TryParseExact($at.Substring(0, 16), 'yyyy-MM-dd HH:mm', $inv, 'None', [ref]$to)) { continue }
            $cur = [pscustomobject]@{ Id = $id; Commit = $f[2]; From = $from; To = $to; Clean = $true }
        } elseif ($cur -and $s -match '^built with \d+ uncommitted change') {
            # Get-ReleaseTagMessage writes this line for a release whose
            # record says uncommitted above 0.
            $cur.Clean = $false
        }
    }
    if ($cur) { $tags += $cur }
    return $tags
}

# The release a note from before sourceCommit came with: the tagged dev
# release whose span holds the note's date. $null when none does, when two do
# that were built from different commits (no one proof), or when the date is
# not a date and a time (entries older than the time on them carry a bare
# date). Two at once from the same commit are the same proof: measured on the
# 12 Oct dev feed, "Safer updates and a quieter journal key" (2 Oct 2:37 PM)
# sits in 20261002-143545-dev and 20261002-143641-dev, both from 85e44094.
function Find-DevNoteRelease($tags, [string]$date) {
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(([string]$date).Trim(), 'M-d-yyyy h:mm tt', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$t)) { return $null }
    $hits = @(@($tags) | Where-Object { $_.From -le $t -and $t -le $_.To })
    if ($hits.Count -eq 0) { return $null }
    if (@($hits | ForEach-Object { $_.Commit } | Select-Object -Unique).Count -ne 1) { return $null }
    return [pscustomobject]@{
        Ids    = @($hits | ForEach-Object { $_.Id })
        Commit = $hits[0].Commit
        Clean  = (@($hits | Where-Object { -not $_.Clean }).Count -eq 0)
    }
}

# Which of these notes the dev build has and main does not.
#
# Main's fresh release record proves which source commits have shipped. A
# note proves its own: its sourceCommit, or before that field existed, the
# commit of the dev release it came with (Find-DevNoteRelease). Headline
# changes therefore cannot leave completed work marked Dev-only.
function Update-DevNewsChannels($doc, $news, $mainDoc, [string]$sourceRepo) {
    if ($null -eq $mainDoc) { return }
    $mainRelease = $mainDoc.PSObject.Properties['release']
    $mainCommit = if ($mainRelease) { Get-DevNewsVal $mainDoc.release 'commit' } else { '' }
    $mainClean = $mainRelease -and $mainDoc.release.PSObject.Properties['uncommitted'] -and $mainDoc.release.uncommitted -eq 0
    # Main has a Dev source when the commit is an ancestor of Main's, or when
    # Main took everything in it as a commit of its own.
    #
    # The second half is for squash merges, which is how pull requests merge
    # here. A Dev release is often built from a branch; the branch is squashed
    # onto main as one new commit and deleted, so the commit the Dev release
    # recorded never becomes an ancestor of main, and its note stayed marked
    # DEV after Main shipped the same work. Measured 5 Oct: 39 of the Dev
    # feed's 40 notes were marked, the 1 and 2 Oct ones included, which went
    # out on Main 1.1.105 on 3 Oct.
    #
    # The proof is by content, never by a headline: some commit on Main's own
    # line since the two parted, one that touched the files the Dev commit
    # changed, already held all of it, because merging the Dev commit into
    # that commit gives that commit's own tree back. That is the squash commit
    # itself. Main is not compared at its tip, because later work on the same
    # lines (a newer engine pin, the next gamemode change) makes the merge
    # conflict there although the work went in. Against main at c63e9fab this
    # reads 3 of the 39 as still Dev, the three whose Dev release was built
    # with uncommitted files: no commit records what those carried, so
    # nothing can prove them.
    #
    # The release tags Ship pushes (release/dev/<id>) keep those commits
    # fetchable after the branch is gone. A git too old for
    # merge-tree --write-tree (before 2.38), or a commit this clone does not
    # have, proves nothing, and the note stays marked.
    $script:publishedSeen = @{}
    function Is-Published([string]$commit) {
        if (-not $mainClean -or $commit -notmatch '^[0-9a-f]{40}$' -or $mainCommit -notmatch '^[0-9a-f]{40}$') { return $false }
        if ($script:publishedSeen.ContainsKey($commit)) { return $script:publishedSeen[$commit] }
        # Put back as it was, so a caller's own last exit code is not git's.
        # It may not be set at all: Refresh-DevNews.ps1 runs nothing native
        # before this, and under strict mode reading it unset throws.
        $hadCode = Test-Path -LiteralPath 'variable:global:LASTEXITCODE'
        $was = if ($hadCode) { $global:LASTEXITCODE } else { 0 }
        $yes = $false
        try {
            if ((Invoke-ReleaseGit $sourceRepo @('merge-base', '--is-ancestor', $commit, $mainCommit)).Code -eq 0) { $yes = $true }
            else {
                $base = Invoke-ReleaseGit $sourceRepo @('merge-base', $commit, $mainCommit)
                if ($base.Code -eq 0 -and $base.First -match '^[0-9a-f]{40}$') {
                    $files = @((Invoke-ReleaseGit $sourceRepo @('diff', '--name-only', $base.First, $commit)).Lines |
                        Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
                    # Every Main commit since they parted that touched those
                    # files, oldest first, each with its tree. Past 200 files
                    # the list would not fit on a Windows command line, so
                    # every Main commit since they parted is tried instead.
                    $walk = @('rev-list', '--first-parent', '--reverse', '--format=%T', ($base.First + '..' + $mainCommit))
                    if ($files.Count -gt 0 -and $files.Count -le 200) { $walk += @('--') + $files }
                    $lines = @((Invoke-ReleaseGit $sourceRepo $walk).Lines | ForEach-Object { ([string]$_).Trim() })
                    for ($i = 0; $i + 1 -lt $lines.Count -and -not $yes; $i += 2) {
                        if ($lines[$i] -notmatch '^commit ([0-9a-f]{40})$') { $i--; continue }
                        $at = $Matches[1]
                        $tree = $lines[$i + 1]
                        $merged = Invoke-ReleaseGit $sourceRepo @('merge-tree', '--write-tree', $at, $commit)
                        if ($merged.Code -eq 0 -and $merged.First -eq $tree) { $yes = $true }
                        elseif ($merged.Code -gt 1) { break }   # this git has no merge-tree --write-tree
                    }
                }
            }
        }
        finally {
            if ($hadCode) { $global:LASTEXITCODE = $was }
            else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        }
        $script:publishedSeen[$commit] = $yes
        return $yes
    }
    # Before sourceCommit existed (3 Oct, 1:57 PM) a note recorded no source,
    # so its proof is the dev release it came with, found by that release's
    # tag (Find-DevNoteRelease), and never by its headline.
    #
    # Until 12 Oct every such note took the commit of the dev feed's current
    # release instead. Between main releases the newest dev release is always
    # ahead of main, so every one of them was marked DEV: measured on 12 Oct,
    # the 16 notes of 1 to 3 Oct, all shipped on main 1.1.105 on 3 Oct, were
    # marked DEV beside the 4 that really were (#2401).
    #
    # No proof is not proof of the opposite. A note whose release this clone
    # has no tag for, or whose release was built with uncommitted files (no
    # commit records what those carried), keeps the mark it was last given.
    $devTags = $null
    $marked = 0
    foreach ($n in @($news)) {
        $commit = Get-DevNewsVal $n 'sourceCommit'
        if ($n.PSObject.Properties['sourceCommit']) { $published = Is-Published $commit }
        else {
            if ($null -eq $devTags) { $devTags = @(Get-DevReleaseTags $sourceRepo) }
            $rel = Find-DevNoteRelease $devTags (Get-DevNewsVal $n 'date')
            if ($rel -and $rel.Clean) { $published = Is-Published $rel.Commit }
            else { $published = ((Get-DevNewsVal $n 'channel') -ne 'dev') }
        }
        $want = if ($published) { '' } else { 'dev' }
        Set-DevNewsProp $n 'channel' $want
        if ($want -eq 'dev') { $marked++ }
    }
    Set-DevNewsProp $doc 'news' $news
    return $marked
}

# The rule above over a whole dev feed in memory, and mainVersion with it: the
# main feed's launcherVersion, so the dev News tab says what main is on. What
# moved comes back, note by note, so a caller can say so and send only when
# something did. A note with no channel at all reads the same as '' (main),
# which is how the launcher reads it, so giving it '' is not a change.
#
# Every note, wherever the feed keeps them (Feed-News.ps1, #1050): "news", and
# the news file once the dev feed's minLauncher reads it. $SiteDir and
# $SiteUrl are where that file is read from. The marked list is left whole in
# "news"; whoever sends the feed puts it back the way the channel keeps it
# (Set-FeedNewsList), as Update-DevFeedMarks below and Publish-Update do.
function Set-DevFeedMarks($doc, $mainDoc, [string]$SourceRepo, [string]$SiteDir, [string]$SiteUrl = 'https://thornswood.net') {
    if ($null -eq $doc) { throw 'There is no dev feed to mark.' }
    if ($null -eq $mainDoc) { throw "There is no main feed to mark the dev feed against, so the dev marks were left alone." }
    $news = @(Open-FeedNewsList $doc (Get-FeedStoreSiteDir $SiteDir) $SiteUrl)
    $before = @($news | ForEach-Object { Get-DevNewsVal $_ 'channel' })
    $wasMain = Get-DevNewsVal $doc 'mainVersion'
    $marked = Update-DevNewsChannels $doc $news $mainDoc $SourceRepo
    $mainVer = Get-DevNewsVal $mainDoc 'launcherVersion'
    Set-DevNewsProp $doc 'mainVersion' $mainVer
    $cleared = @(); $gained = @(); $kept = @()
    for ($i = 0; $i -lt $news.Count; $i++) {
        $now = Get-DevNewsVal $news[$i] 'channel'
        $t = Get-DevNewsVal $news[$i] 'title'
        if ($before[$i] -eq 'dev' -and $now -ne 'dev') { $cleared += $t }
        elseif ($before[$i] -ne 'dev' -and $now -eq 'dev') { $gained += $t }
        elseif ($now -eq 'dev') { $kept += $t }
    }
    $mainRel = if ($mainDoc.PSObject.Properties['release'] -and $mainDoc.release) { $mainDoc.release } else { $null }
    return [pscustomobject]@{
        Changed        = ($cleared.Count -gt 0 -or $gained.Count -gt 0 -or $wasMain -ne $mainVer)
        Sent           = $false
        Notes          = $news.Count
        Was            = @($before | Where-Object { $_ -eq 'dev' }).Count
        Marked         = [int]$marked
        Cleared        = @($cleared)
        Gained         = @($gained)
        Kept           = @($kept)
        WasMainVersion = $wasMain
        MainVersion    = $mainVer
        MainRelease    = $(if ($mainRel) { Get-DevNewsVal $mainRel 'id' } else { '' })
        MainCommit     = $(if ($mainRel) { Get-DevNewsVal $mainRel 'commit' } else { '' })
    }
}

# Receives the dev feed into this machine's working folder for dev (the one a
# dev publish uses, Get-FeedStoreDir), reads main's feed as the site serves
# it, marks the dev feed, and sends version.json back through Send-FeedStore
# only when something moved. Nothing else is sent: no pack, no launcher, no
# baseline, no release record, no news entry.
#
#   -Received   the folder already holds the feed as received (a dev publish
#               that has just received it); nothing is fetched again.
#   -NoSend     work it out and say what would move; nothing is written or sent.
#
# Throws, with nothing sent, when the dev feed cannot be received, main's feed
# cannot be read or is not there, or the store moved since it was received.
function Update-DevFeedMarks {
    param(
        [string]$SourceRepo,
        [string]$Dir,
        [switch]$Received,
        [switch]$NoSend,
        [string]$SiteDir,
        [string]$SiteUrl = 'https://thornswood.net',
        [hashtable]$To
    )
    if (-not $Dir) { $Dir = Get-FeedStoreDir 'dev' }
    if (-not $SourceRepo) { $SourceRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    if (-not $Received) {
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        [void](Receive-FeedStore 'dev' $Dir -SiteDir $SiteDir -To $To)
    }
    $file = Join-Path $Dir 'version.json'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'The VPS has no version.json for the dev channel, so there is nothing to mark.' }
    $mainDoc = Read-SiteFeed 'main' -SiteDir $SiteDir -SiteUrl $SiteUrl
    if ($null -eq $mainDoc) { throw 'The site has no main feed, so the dev marks were left alone.' }
    $doc = (([IO.File]::ReadAllText($file)) -replace '^\uFEFF', '') | ConvertFrom-Json
    $r = Set-DevFeedMarks $doc $mainDoc $SourceRepo $SiteDir $SiteUrl
    if ($r.Changed -and -not $NoSend) {
        # The notes back the way the dev feed keeps them (#1050): in "news",
        # or once its minLauncher reads it, a news file sent to the site first.
        $min = Get-DevNewsVal $doc 'minLauncher'
        if (-not $min) { $min = Get-DevNewsVal $doc 'launcherVersion' }
        [void](Set-FeedNewsList $doc @($doc.news) 'dev' $min (Join-Path $Dir 'news-out') $SiteDir)
        # Compact, no byte order mark (Feed-Store.ps1, Write-FeedVersionFile).
        Write-FeedVersionFile $file $doc
        $sent = Send-FeedStore 'dev' $Dir @('version.json') -SiteDir $SiteDir -To $To
        $r.Sent = (@($sent.Sent).Count -gt 0)
    }
    return $r
}

# What to say about a result, one line each, for Publish-Update, Ship and
# Refresh-DevNews.ps1 alike.
function Get-DevFeedMarksLines($r, [switch]$NoSend) {
    $lines = @()
    $main = if ($r.MainVersion) { "main $($r.MainVersion)" } else { 'main' }
    if ($r.MainRelease) { $main += " (release $($r.MainRelease))" }
    $lines += ("{0} of {1} notes marked DEV against {2}, {3} before" -f $r.Marked, $r.Notes, $main, $r.Was)
    if (@($r.Cleared).Count) { $lines += ("{0} lost the mark, main has them: {1}" -f @($r.Cleared).Count, (@($r.Cleared) -join '; ')) }
    if (@($r.Gained).Count) { $lines += ("{0} gained the mark, main does not have them: {1}" -f @($r.Gained).Count, (@($r.Gained) -join '; ')) }
    if ($r.WasMainVersion -ne $r.MainVersion) { $lines += ("mainVersion {0} -> {1}" -f $(if ($r.WasMainVersion) { $r.WasMainVersion } else { '(none)' }), $r.MainVersion) }
    if (-not $r.Changed) { $lines += 'the dev feed already matched main, so nothing was sent' }
    elseif ($NoSend) { $lines += 'nothing was sent: this run sends nothing' }
    elseif ($r.Sent) { $lines += 'the dev feed''s version.json was sent, and the site serves it' }
    else { $lines += 'the dev feed on the VPS already had these marks' }
    return $lines
}
