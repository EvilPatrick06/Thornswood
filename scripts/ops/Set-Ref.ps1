<#
  Set-Ref.ps1

  Makes a release tag, or deletes a branch, on GitHub for a session whose git
  cannot write refs: a cloud Claude thread (#3107, #3314).

      pwsh scripts/ops/Set-Ref.ps1 -Tag release/dev/20261022-154916-dev -Commit <40 hex> -MessageFile <file>
                       the annotated release tag on that commit
      pwsh scripts/ops/Set-Ref.ps1 -DeleteBranch claude/what -Commit <40 hex>
                       the branch, when it is still at that commit
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
    [Parameter(ParameterSetName = 'Tag', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Delete', Mandatory = $true)]
    [string]$Commit,
    # A git-ref run that had not ended: read its answer.
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [long]$Run,
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
$inActions = ($env:GITHUB_ACTIONS -eq 'true')
$tagShape = '^release/(dev/\d{8}-\d{4}(\d{2})?-dev|main/\d{8}-\d{4}(\d{2})?)$'
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
    if ($Tag -and $DeleteBranch) { Die 'give a tag to make or a branch to delete, not both. Nothing was changed.' }

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
    Die 'the run was given no tag to make and no branch to delete.'
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

# The run the dispatch started, once GitHub has named it. From then on the
# change is GitHub's to make, so a read that fails is said as that, with the
# line that reads the answer later, and never as nothing having been asked.
$sentRun = 0

# One GET, its answer as an object; a refusal stops the script with why.
# -NotYet: GitHub's Not Found means not served yet, and comes back as $null.
function Get-GitHub([string]$path, [switch]$NotYet) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = @(& gh api $path 2>&1 | ForEach-Object { "$_" })
    $c = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($c -ne 0) {
        if ($NotYet -and ($o -join ' ') -match '\(HTTP 404\)') { return $null }
        $why = "GitHub answered GET $path with: " + (($o | Select-Object -Last 2) -join ' ')
        if ($sentRun) { Unread $why }
        Die $why
    }
    return (($o -join "`n") | ConvertFrom-Json)
}

# Asked, and the answer not read: exit 2, as for a run that has not ended.
function Unread([string]$why) {
    Say ("GitHub started run $sentRun with it, and the run makes the change. Its answer was not read here: $why") 'Yellow'
    Say ('  its answer: pwsh scripts/ops/Set-Ref.ps1 -Run ' + $sentRun) 'DarkGray'
    exit 2
}

# Waits for the run to end, then reads what the runner said: the Set-Ref
# annotation on its job. A run GitHub has only just named can be Not Found
# for a moment (#3081), which is one more state of the wait, as Say-Staff
# reads it.
function Read-RunAnswer([long]$id, [switch]$Started) {
    $runPath = "repos/$GitHubRepo/actions/runs/$id"
    $deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
    $run = Get-GitHub $runPath -NotYet:$Started
    $told = ''
    while (-not $run -or $run.status -ne 'completed') {
        $state = if ($run) { $run.status } else { 'not served by GitHub yet' }
        if ([DateTime]::UtcNow -gt $deadline) {
            Say ("the run has not ended after $WaitMinutes minutes (it was " + $state + '), so every runner is busy. It still makes the change when one takes it.') 'Yellow'
            Say ('  its answer then: pwsh scripts/ops/Set-Ref.ps1 -Run ' + $id) 'DarkGray'
            if ($run) { Say ('  ' + $run.html_url) 'DarkGray' }
            exit 2
        }
        if ($told -ne $state -and $state -ne 'in_progress') {
            if ($run) { Say ('  waiting for a runner (' + $state + ')') 'DarkGray' } else { Say '  started; GitHub does not serve the new run yet' 'DarkGray' }
            $told = $state
        }
        Start-Sleep -Seconds 5
        $run = Get-GitHub $runPath -NotYet:($Started -and -not $run)
    }
    if ($run.path -notmatch ('/' + [regex]::Escape($workflow) + '$')) { Die ("run $id is not a git-ref run (it is " + $run.path + ').') }
    $notes = @()
    foreach ($job in @((Get-GitHub "$runPath/jobs").jobs)) {
        $notes += @(Get-GitHub ("repos/$GitHubRepo/check-runs/" + $job.id + '/annotations') | Where-Object { $_.title -eq 'Set-Ref' })
    }
    $done = @($notes | Where-Object { $_.annotation_level -eq 'notice' }) | Select-Object -Last 1
    if ($done) { return ([string]$done.message).Trim() }
    $why = @($notes | Where-Object { $_.annotation_level -eq 'failure' }) | Select-Object -Last 1
    if ($why) { Die ('the runner stopped: ' + ([string]$why.message).Trim() + ' (' + $run.html_url + ')') }
    Die ('the run ended ' + $run.conclusion + ' without an answer, so nothing it knows of was changed. Its log says why: ' + $run.html_url)
}

if ($PSCmdlet.ParameterSetName -eq 'Run') {
    $answer = Read-RunAnswer $Run
} else {
    $inputs = if ($PSCmdlet.ParameterSetName -eq 'Tag') { [ordered]@{ tag = $Tag; commit = $Commit; message = $Message } } else { [ordered]@{ delete_branch = $DeleteBranch; commit = $Commit } }
    # The body on gh's standard input, so the message is on no command line.
    $body = [ordered]@{ ref = 'main'; inputs = $inputs; return_run_details = $true } | ConvertTo-Json -Compress
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = @($body | & gh api -X POST "repos/$GitHubRepo/actions/workflows/$workflow/dispatches" --input - 2>&1 | ForEach-Object { "$_" })
    $c = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($c -ne 0) { Die ('GitHub did not start the git-ref workflow: ' + (($o | Select-Object -Last 2) -join ' ') + '. Nothing was changed.') }
    $started = ($o -join "`n") | ConvertFrom-Json
    if (-not $started.PSObject.Properties['workflow_run_id'] -or -not $started.workflow_run_id) {
        Say ('GitHub started the git-ref workflow, but named no run, so its answer cannot be read here. Its runs: https://github.com/' + $GitHubRepo + '/actions/workflows/' + $workflow) 'Yellow'
        exit 2
    }
    Say ('sent to the git-ref workflow: ' + $started.html_url) 'DarkGray'
    $sentRun = [long]$started.workflow_run_id
    $answer = Read-RunAnswer $sentRun -Started
}

switch -Regex ("$answer") {
    '^TAGGED (\S+) (\S+)$' { Say ($Matches[1] + ' is on GitHub, on ' + $Matches[2].Substring(0, 12) + '.') 'Green'; exit 0 }
    '^ALREADY (\S+) (\S+)$' { Say ($Matches[1] + ' was already on GitHub, on ' + $Matches[2].Substring(0, 12) + '.') 'Green'; exit 0 }
    '^DELETED (\S+) (\S+)$' { Say ($Matches[1] + ' is deleted on GitHub (it was at ' + $Matches[2].Substring(0, 12) + ').') 'Green'; exit 0 }
    '^GONE (\S+)$' { Say ($Matches[1] + ' was already gone from GitHub.') 'Green'; exit 0 }
}
Die ("the run answered '$answer', which is none of the answers this knows. Nothing it knows of was changed.")
