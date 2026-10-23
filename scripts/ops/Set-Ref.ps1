<#
  Set-Ref.ps1

  Makes a release tag, deletes a branch, or deletes a dev launcher tag no
  release came from, on GitHub for a session whose git cannot write refs: a
  cloud Claude thread (#3107, #3314, #3312).

      pwsh scripts/ops/Set-Ref.ps1 -Tag release/dev/20261022-154916-dev -Commit <40 hex> -MessageFile <file>
                       the annotated release tag on that commit
      pwsh scripts/ops/Set-Ref.ps1 -DeleteBranch claude/what -Commit <40 hex>
                       the branch, when it is still at that commit
      pwsh scripts/ops/Set-Ref.ps1 -Fork -DeleteBranch claude/what -Commit <40 hex>
                       the same in the fork, EvilPatrick06/skymp
      pwsh scripts/ops/Set-Ref.ps1 -DeleteTag v1.2.6.8 -Commit <40 hex>
                       a dev launcher tag a stopped release left, when it is
                       still on that commit and no release came from it
      pwsh scripts/ops/Set-Ref.ps1 -Run 39712345678
                       the answer of a run that had not ended

  WHY. A cloud session reaches GitHub through the cloud environment's proxy,
  which refuses every ref write before GitHub sees it. Measured 22 Oct 2026:
  `git push origin refs/tags/...` is "RPC failed; HTTP 403" (the cloud Ship of
  dev release 20261022-154916-dev, #3314), and DELETE git/refs/heads/<branch>
  and POST git/refs, for a tag or a branch, are 403 "Write access to this
  GitHub API path is not permitted through this proxy". Starting a workflow
  is allowed. So the tag went to One, and so did every branch a cloud thread
  left behind (#3107, #2862). The proxy's policy belongs to the cloud
  environment, and nothing in this repository changes it.

  HOW. This starts .github/workflows/git-ref.yml on main with what to do,
  waits for the run to end, and prints its answer, the way Say-Staff.ps1 and
  Read-Board.ps1 do. The workflow runs this script with -OnGitHub on a VPS
  runner, where the run's own token (contents: write, pull requests read,
  nothing else) makes the call. No secret is in the session or the workflow.
  -Fork starts the fork's .github/workflows/thornswood-git-ref.yml instead,
  on GitHub's hosted runner (free in that public repository), which deletes
  a branch by the same rules written into it; it makes no tags. A run's
  token reaches only its own repository, so each has its own workflow.

  WHAT THE GITHUB HALF DOES, AND WHAT IT REFUSES.
    -Tag: only release/dev/<id>-dev and release/main/<id>, the names
        Release-Name.ps1 gives a release, never v<...>, which starts the
        launcher build in release.yml. The commit has to be on main. It
        makes an annotated tag with the message given, by
        github-actions[bot]. A tag already on that commit is the answer
        ALREADY, not a failure; one on another commit is left alone and is a
        failure.
    -DeleteBranch: never the default branch. The branch has to be at the
        commit given, so a commit pushed after the caller looked is never
        deleted with it, and no open pull request may come from it or be
        built onto it. A branch already gone is the answer GONE. GitHub's
        "Restore branch" button on a closed pull request brings one back.
    -DeleteTag (#3312): only a dev launcher tag, v<a.b.c.d>, never a main
        one (v<a.b.c>) or any other name. A release from the feed asks
        release-tag.yml for that tag before release.yml builds on it, so a
        release that stopped leaves its tag with nothing behind it (v1.2.6.8
        on acc0715f, 22 Oct). The tag has to be on the commit given, no
        release on GitHub (a draft included) may name it, and here, before
        anything starts, neither feed's launcher may be that number. A tag
        already gone is GONE.

  WHAT IT SAYS AND EXITS.
    TAGGED, ALREADY, DELETED, GONE    0
    refused, or GitHub said no        1, with why; nothing changed
    the run had not ended             2, after -WaitMinutes; the run still
                                      does it, and -Run <its id> reads it
  In the workflow it writes its answer, or why it stopped, as an annotation
  titled Set-Ref, which is how the session reads the runner's answer.
  tests\test-3107-set-ref.ps1 runs both halves against a stand-in GitHub.
#>
[CmdletBinding(DefaultParameterSetName = 'Tag')]
param(
    [Parameter(ParameterSetName = 'Tag', Mandatory = $true)]
    [string]$Tag,
    [Parameter(ParameterSetName = 'Tag')]
    [string]$Message = '',
    [Parameter(ParameterSetName = 'Tag')]
    [string]$MessageFile = '',
    [Parameter(ParameterSetName = 'Delete', Mandatory = $true)]
    [string]$DeleteBranch,
    # A dev launcher tag a stopped release left (#3312).
    [Parameter(ParameterSetName = 'DeleteTag', Mandatory = $true)]
    [string]$DeleteTag,
    [Parameter(ParameterSetName = 'Tag', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Delete', Mandatory = $true)]
    [Parameter(ParameterSetName = 'DeleteTag', Mandatory = $true)]
    [string]$Commit,
    # A git-ref run that had not ended: read its answer.
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [long]$Run,
    # The fork's branch, through the fork's thornswood-git-ref.yml.
    [Parameter(ParameterSetName = 'Delete')]
    [Parameter(ParameterSetName = 'Run')]
    [switch]$Fork,
    # The workflow's half. What to do comes from the environment the
    # workflow sets from its inputs, never from a command line.
    [Parameter(ParameterSetName = 'OnGitHub', Mandatory = $true)]
    [switch]$OnGitHub,
    [int]$WaitMinutes = 15,
    [string]$GitHubRepo = 'EvilPatrick06/Thornswood'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workflow = 'git-ref.yml'
if ($Fork) { $GitHubRepo = 'EvilPatrick06/skymp'; $workflow = 'thornswood-git-ref.yml' }
$inActions = ($env:GITHUB_ACTIONS -eq 'true')
$tagShape = '^release/(dev/\d{8}-\d{4}(\d{2})?-dev|main/\d{8}-\d{4}(\d{2})?)$'
# A dev launcher number's tag, the only v tag this deletes (#3312).
$devTagShape = '^v\d+\.\d+\.\d+\.\d+$'
$maxMessage = 4000

# An annotation on the job, which GitHub keeps on its check run, so the
# session reads the answer without reading the log.
function Note([string]$level, [string]$m) {
    if ($inActions) { Write-Host ('::' + $level + ' title=Set-Ref::' + ($m -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A')) }
}
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Note 'error' $m; Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

# What a tag or branch name may be here: git's own rules, narrowed to the
# characters branch names in this repository use.
function Test-RefName([string]$n) {
    return ($n -match '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -and $n -notmatch '\.\.|//|/\.|\.lock(/|$)|[/.]$')
}

# Each part of a ref name escaped on its own, the slashes kept.
function Get-RefPath([string]$n) { return (@($n.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/') }

# ======================================================== the GitHub half ===
if ($OnGitHub) {
    $Tag = [string]$env:REF_TAG
    $DeleteBranch = [string]$env:REF_DELETE_BRANCH
    $DeleteTag = [string]$env:REF_DELETE_TAG
    $Commit = [string]$env:REF_COMMIT
    $Message = [string]$env:REF_MESSAGE
    $default = if ($env:REF_DEFAULT_BRANCH) { [string]$env:REF_DEFAULT_BRANCH } else { 'main' }
    if (-not $env:GH_TOKEN) { Die 'GH_TOKEN is not set, so there is nothing to call GitHub with. In git-ref.yml it is the run''s own token.' }
    if (-not $env:GITHUB_REPOSITORY) { Die 'GITHUB_REPOSITORY is not set, so this is not a workflow run and there is no repository to change.' }
    $apiBase = $(if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL } else { 'https://api.github.com' }) + '/repos/' + $env:GITHUB_REPOSITORY

    # One call. Code is GitHub's HTTP answer, Body its JSON as an object.
    function Api([string]$method, [string]$path, $body = $null) {
        $p = @{
            Method = $method; Uri = "$apiBase/$path"; SkipHttpErrorCheck = $true; TimeoutSec = 60
            Headers = @{ Authorization = "Bearer $env:GH_TOKEN"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
        }
        if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Compress -Depth 5); $p.ContentType = 'application/json' }
        $r = Invoke-WebRequest @p
        $text = [string]$r.Content
        $o = if ($text.Trim()) { $text | ConvertFrom-Json } else { $null }
        return [pscustomobject]@{ Code = [int]$r.StatusCode; Body = $o }
    }
    function Said($a) {
        $m = if ($a.Body -and $a.Body.PSObject.Properties['message']) { ': ' + $a.Body.message } else { '' }
        return ('HTTP ' + $a.Code + $m)
    }
    # The commit a tag ref names, through its tag object when it is annotated.
    function Get-TagCommit($refBody) {
        $o = $refBody.object
        if ($o.type -ne 'tag') { return [string]$o.sha }
        $t = Api GET ('git/tags/' + $o.sha)
        if ($t.Code -ne 200) { Die ("GitHub would not read the tag object " + $o.sha + ' (' + (Said $t) + '). Nothing was changed.') }
        return [string]$t.Body.object.sha
    }

    if ($Commit -notmatch '^[0-9a-f]{40}$') { Die "the commit has to be a full 40 character commit id, and it is '$Commit'. Nothing was changed." }
    if (@(@($Tag, $DeleteBranch, $DeleteTag) | Where-Object { $_ }).Count -gt 1) { Die 'give one thing to do: a tag to make, a branch to delete or a tag to delete. Nothing was changed.' }

    if ($Tag) {
        if ($Tag -notmatch $tagShape) { Die "$Tag is not a release tag (release/dev/<id>-dev or release/main/<id>), and this makes no other. Nothing was changed." }
        $Message = ($Message -replace '\r\n?', "`n").Trim()
        if (-not $Message) { Die 'the tag message is empty. Ship writes one for every release tag. Nothing was changed.' }
        if ($Message.Length -gt $maxMessage) { Die "the tag message is $($Message.Length) characters and $maxMessage is the most. Nothing was changed." }
        $cmp = Api GET ("compare/$Commit..." + [Uri]::EscapeDataString($default))
        if ($cmp.Code -eq 404) { Die "GitHub has no commit $Commit in $env:GITHUB_REPOSITORY, so $Tag was not made. Push the commit first." }
        if ($cmp.Code -ne 200) { Die ("GitHub would not compare $Commit with $default (" + (Said $cmp) + "), so $Tag was not made.") }
        if (@('ahead', 'identical') -notcontains [string]$cmp.Body.status) {
            Die ("commit $Commit is not on $default (GitHub says $default is " + $cmp.Body.status + ' of it), so ' + $Tag + ' was not made. A release tag goes only on a commit main has.')
        }
        $refPath = 'git/ref/tags/' + (Get-RefPath $Tag)
        $has = Api GET $refPath
        if ($has.Code -eq 200) {
            $on = Get-TagCommit $has.Body
            if ($on -eq $Commit) { Note 'notice' "ALREADY $Tag $Commit"; Say "ALREADY $Tag $Commit" 'Green'; exit 0 }
            Die "$Tag already names commit $on, not $Commit; it was left alone."
        }
        if ($has.Code -ne 404) { Die ("GitHub would not say whether $Tag is there (" + (Said $has) + '). Nothing was changed.') }
        $tagger = [ordered]@{
            name = 'github-actions[bot]'; email = '41898282+github-actions[bot]@users.noreply.github.com'
            date = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        $obj = Api POST 'git/tags' ([ordered]@{ tag = $Tag; message = ($Message + "`n"); object = $Commit; type = 'commit'; tagger = $tagger })
        if ($obj.Code -ne 201) { Die ("GitHub did not make the tag object for $Tag (" + (Said $obj) + '). Nothing was changed.') }
        $made = Api POST 'git/refs' ([ordered]@{ ref = "refs/tags/$Tag"; sha = [string]$obj.Body.sha })
        if ($made.Code -eq 201) { Note 'notice' "TAGGED $Tag $Commit"; Say "TAGGED $Tag $Commit" 'Green'; exit 0 }
        # 422 is GitHub saying the ref is there: another run made it between
        # the read above and this one, so what it names is the answer.
        if ($made.Code -eq 422) {
            $has = Api GET $refPath
            if ($has.Code -eq 200) {
                $on = Get-TagCommit $has.Body
                if ($on -eq $Commit) { Note 'notice' "ALREADY $Tag $Commit"; Say "ALREADY $Tag $Commit" 'Green'; exit 0 }
                Die "$Tag was made on commit $on by something else while this ran, not on $Commit; it was left alone."
            }
        }
        Die ("GitHub did not put $Tag on (" + (Said $made) + ').')
    }

    if ($DeleteBranch) {
        if (-not (Test-RefName $DeleteBranch)) { Die "'$DeleteBranch' is not a branch name this deletes. Nothing was changed." }
        if ($DeleteBranch -eq $default) { Die "$DeleteBranch is the default branch, which this never deletes." }
        $refPath = 'git/ref/heads/' + (Get-RefPath $DeleteBranch)
        $has = Api GET $refPath
        if ($has.Code -eq 404) { Note 'notice' "GONE $DeleteBranch"; Say "GONE $DeleteBranch" 'Green'; exit 0 }
        if ($has.Code -ne 200) { Die ("GitHub would not say where $DeleteBranch is (" + (Said $has) + '). Nothing was changed.') }
        $tip = [string]$has.Body.object.sha
        if ($tip -ne $Commit) { Die "$DeleteBranch is at $tip, not ${Commit}: a commit came after the one given, so it stays. Look at it, then ask again with its commit." }
        $owner = $env:GITHUB_REPOSITORY.Split('/')[0]
        $q = [Uri]::EscapeDataString($DeleteBranch)
        $open = @()
        foreach ($ask in @("pulls?state=open&per_page=100&head=$owner`:$q", "pulls?state=open&per_page=100&base=$q")) {
            $a = Api GET $ask
            if ($a.Code -ne 200) { Die ("GitHub would not list the open pull requests on $DeleteBranch (" + (Said $a) + '). Nothing was changed.') }
            $open += @($a.Body | Where-Object { $_ -and $_.PSObject.Properties['number'] })
        }
        if ($open.Count) {
            Die ("$DeleteBranch stays: open pull request(s) " + ((@($open | ForEach-Object { '#' + $_.number }) | Sort-Object -Unique) -join ', ') + ' come from it or are built onto it.')
        }
        $gone = Api DELETE ('git/refs/heads/' + (Get-RefPath $DeleteBranch))
        if ($gone.Code -eq 204) { Note 'notice' "DELETED $DeleteBranch $Commit"; Say "DELETED $DeleteBranch $Commit" 'Green'; exit 0 }
        # 422 is GitHub saying the ref is not there any more: it went between
        # the read and the delete, which is the state this run is for.
        if ($gone.Code -eq 422) { Note 'notice' "GONE $DeleteBranch"; Say "GONE $DeleteBranch" 'Green'; exit 0 }
        Die ("GitHub did not delete $DeleteBranch (" + (Said $gone) + ').')
    }
    if ($DeleteTag) {
        if ($DeleteTag -notmatch $devTagShape) { Die "$DeleteTag is not a dev launcher tag (v<a.b.c.d>), the only tag this deletes. Nothing was changed." }
        $refPath = 'git/ref/tags/' + (Get-RefPath $DeleteTag)
        $has = Api GET $refPath
        if ($has.Code -eq 404) { Note 'notice' "GONE $DeleteTag"; Say "GONE $DeleteTag" 'Green'; exit 0 }
        if ($has.Code -ne 200) { Die ("GitHub would not say where $DeleteTag is (" + (Said $has) + '). Nothing was changed.') }
        $on = Get-TagCommit $has.Body
        if ($on -ne $Commit) { Die "$DeleteTag names commit $on, not ${Commit}, so it stays. Look at it, then ask again with its commit." }
        # The releases list, not /releases/tags/<tag>: only the list holds
        # drafts (release.yml, ONE DRAFT PER TAG). Newest first, a page at a
        # time, until a short page says there is no more.
        for ($page = 1; $page -le 50; $page++) {
            $a = Api GET "releases?per_page=100&page=$page"
            if ($a.Code -ne 200) { Die ("GitHub would not list the releases (" + (Said $a) + "), so $DeleteTag stays.") }
            $batch = @($a.Body | Where-Object { $_ -and $_.PSObject.Properties['tag_name'] })
            $same = @($batch | Where-Object { $_.tag_name -eq $DeleteTag })
            if ($same.Count) { Die ("$DeleteTag stays: release " + (@($same | ForEach-Object { [string]$_.id + $(if ($_.draft) { ' (a draft)' } else { '' }) }) -join ', ') + ' names it.') }
            if ($batch.Count -lt 100) { break }
        }
        $gone = Api DELETE ('git/refs/tags/' + (Get-RefPath $DeleteTag))
        if ($gone.Code -eq 204) { Note 'notice' "DELETED $DeleteTag $Commit"; Say "DELETED $DeleteTag $Commit" 'Green'; exit 0 }
        if ($gone.Code -eq 422) { Note 'notice' "GONE $DeleteTag"; Say "GONE $DeleteTag" 'Green'; exit 0 }
        Die ("GitHub did not delete $DeleteTag (" + (Said $gone) + ').')
    }
    Die 'the run was given no tag to make, no branch to delete and no tag to delete.'
}

# ======================================================= the session half ===
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die 'there is no gh here to start the git-ref workflow with. Nothing was changed.' }

if ($PSCmdlet.ParameterSetName -ne 'Run') {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { Die "-Commit has to be a full 40 character commit id, and it is '$Commit'. Nothing was changed." }
}
if ($PSCmdlet.ParameterSetName -eq 'Tag') {
    if ($Tag -notmatch $tagShape) { Die "$Tag is not a release tag (release/dev/<id>-dev or release/main/<id>), the only tags this makes. Nothing was changed." }
    if ($MessageFile) {
        if (-not (Test-Path -LiteralPath $MessageFile -PathType Leaf)) { Die "there is no message file at $MessageFile. Nothing was changed." }
        $Message = [IO.File]::ReadAllText($MessageFile)
    }
    $Message = ($Message -replace '\r\n?', "`n").Trim()
    if (-not $Message) { Die 'the tag has no message: give -Message or -MessageFile. Nothing was changed.' }
    if ($Message.Length -gt $maxMessage) { Die "the tag message is $($Message.Length) characters and $maxMessage is the most. Nothing was changed." }
}
if ($PSCmdlet.ParameterSetName -eq 'Delete') {
    if (-not (Test-RefName $DeleteBranch)) { Die "'$DeleteBranch' is not a branch name this deletes. Nothing was changed." }
}
if ($PSCmdlet.ParameterSetName -eq 'DeleteTag') {
    if ($DeleteTag -notmatch $devTagShape) { Die "$DeleteTag is not a dev launcher tag (v<a.b.c.d>), the only tag this deletes. Nothing was changed." }
    # Neither feed's launcher may be this number: Ship reads a feed launcher's
    # tag to see what changed since it. The run cannot ask, since the runner
    # it runs on reaches GitHub alone (#2161), so it is asked here.
    . (Join-Path $PSScriptRoot '..\release\Feed-Rules.ps1')
    foreach ($dev in $false, $true) {
        $url = Get-HostFeedVersionUrl -Dev:$dev
        try { $have = [string](Invoke-RestMethod -Uri $url -TimeoutSec 60).launcherVersion }
        catch { Die ("$url could not be read (" + $_.Exception.Message + "), so whether a feed offers $DeleteTag is not known. Nothing was changed.") }
        if (-not $have) { Die "$url names no launcher, so whether a feed offers $DeleteTag is not known. Nothing was changed." }
        if ('v' + $have -eq $DeleteTag) { Die "$url offers launcher $have, so $DeleteTag stays. Nothing was changed." }
    }
}

. (Join-Path $PSScriptRoot 'WorkflowRun.ps1')
$again = 'pwsh scripts/ops/Set-Ref.ps1 ' + $(if ($Fork) { '-Fork ' } else { '' }) + '-Run '

# Waits for the run to end, then reads what the runner said: the Set-Ref
# annotation on its job. -Started: this session started it, so from then on
# the change is GitHub's to make, and a read that fails is said as that, with
# the line that reads the answer later, never as nothing having been asked.
function Read-Answer([long]$id, [switch]$Started) {
    $a = Read-ThornswoodRunAnswer -Repo $GitHubRepo -Workflow $workflow -Run $id -Title 'Set-Ref' -WaitMinutes $WaitMinutes -Started:$Started -Say { param($m) Say $m 'DarkGray' }
    switch ($a.State) {
        'answer' { return $a.Text }
        'waiting' {
            Say ("the run has not ended after $WaitMinutes minutes (it was " + $a.Text + '), so every runner is busy. It still makes the change when one takes it.') 'Yellow'
            Say ('  its answer then: ' + $again + $id) 'DarkGray'
            if ($a.Url) { Say ('  ' + $a.Url) 'DarkGray' }
            exit 2
        }
        'unread' {
            if (-not $Started) { Die $a.Text }
            Say ("GitHub started run $id with it, and the run makes the change. Its answer was not read here: " + $a.Text) 'Yellow'
            Say ('  its answer: ' + $again + $id) 'DarkGray'
            exit 2
        }
        'stopped' { Die ('the runner stopped: ' + $a.Text + ' (' + $a.Url + ')') }
        'other' { Die ($a.Text + '.') }
    }
    Die ($a.Text + ', so nothing it knows of was changed. Its log says why: ' + $a.Url)
}

if ($PSCmdlet.ParameterSetName -eq 'Run') {
    $answer = Read-Answer $Run
} else {
    $inputs = switch ($PSCmdlet.ParameterSetName) {
        'Tag' { [ordered]@{ tag = $Tag; commit = $Commit; message = $Message } }
        'DeleteTag' { [ordered]@{ delete_tag = $DeleteTag; commit = $Commit } }
        default { [ordered]@{ delete_branch = $DeleteBranch; commit = $Commit } }
    }
    try { $started = Start-ThornswoodWorkflow -Repo $GitHubRepo -Workflow $workflow -Inputs $inputs }
    catch { Die ($_.Exception.Message + '. Nothing was changed.') }
    if (-not $started.Run) {
        Say ("GitHub started $workflow, but named no run" + ', so its answer cannot be read here. Its runs: ' + $started.Url) 'Yellow'
        exit 2
    }
    Say ("sent to $workflow" + ': ' + $started.Url) 'DarkGray'
    $answer = Read-Answer $started.Run -Started
}

switch -Regex ("$answer") {
    '^TAGGED (\S+) (\S+)$' { Say ($Matches[1] + ' is on GitHub, on ' + $Matches[2].Substring(0, 12) + '.') 'Green'; exit 0 }
    '^ALREADY (\S+) (\S+)$' { Say ($Matches[1] + ' was already on GitHub, on ' + $Matches[2].Substring(0, 12) + '.') 'Green'; exit 0 }
    '^DELETED (\S+) (\S+)$' { Say ($Matches[1] + ' is deleted on GitHub (it was at ' + $Matches[2].Substring(0, 12) + ').') 'Green'; exit 0 }
    '^GONE (\S+)$' { Say ($Matches[1] + ' was already gone from GitHub.') 'Green'; exit 0 }
}
Die ("the run answered '$answer', which is none of the answers this knows. Nothing it knows of was changed.")
