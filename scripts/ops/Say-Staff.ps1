<#
  Say-Staff.ps1

  Posts one staff notice in #staff-updates through the bot, from One, a
  developer's PC or a cloud thread: only when staff must act: something staff
  must act on, a server restart or outage staff will see, or a change to how
  staff do their job. Never for releases, merges, progress, pull requests,
  issues, test tasks or routine deploys (Patrick, 22 Oct 2026, 8:51 AM).
  Agents post their own notices this way instead of asking a person to
  (Patrick, 20 Oct 2026, #2934).

      pwsh scripts/ops/Say-Staff.ps1 -From claude -Text "Restarting the dev server at 4:30 PM for about 5 minutes."
                       queue it; prints its id
      pwsh scripts/ops/Say-Staff.ps1 -Check agent-claude-20261020214500-1a2b3c
                       whether the bot has said it yet, or taken it back
      pwsh scripts/ops/Say-Staff.ps1 -Unsay agent-claude-20261020214500-1a2b3c
                       takes it back out of #staff-updates (#3328): the bot
                       deletes its post within a minute, or never says it if
                       it has not yet. Only the sender's own notices.

  HOW IT GETS THERE. The notice goes on ssh's standard input, base64, to
  C:\Thornswood-Watch\say-staff.ps1 on the box (scripts\vps\vps-say-staff.ps1,
  put there by Watch-Services.ps1 -Install), which appends one line to the
  watchdog's outbox, alerts.jsonl. The bot reads that every minute and says
  each new line in #staff-updates, by the id in bot\staff-channel.txt, and
  the watchdog says it through its own #staff-updates webhook when the bot is
  down (#447). No Discord token or webhook leaves the box, and nothing here
  knows one. The text is never on a command line.

  WHICH WAY, the first that fits:
    -OnTheBox (the staff-notice workflow, on a VPS runner; #3045): ssh to
        127.0.0.1, the box's own sshd, with the notices key in
        THORNSWOOD_NOTICE_KEY_B64. The box takes every agent key only from
        127.0.0.1, and a runner is on the box, so no bridge and no token: the
        key is no use anywhere else. The host key is checked against the
        three vps.json pins, and the key and known_hosts live in a folder of
        this run's own that goes when it ends.
    THORNSWOOD_NOTICE_KEY_B64 and THORNSWOOD_NOTICE_TOKEN set (an agent
        environment given a notices key by Grant-BoxAccess.ps1 -NoticesOnly
        -MakeKey): that key, through the bridge with that token. The box
        runs say-staff.ps1 for it whatever is asked, with -From set to the
        key's own name, so -From here is not needed and is not what shows.
    ssh here: ssh to the box the way every script here goes (One, a
        developer's PC set up by Setup-SshKey.ps1). -From is then who the
        notice is from: one lower case word, claude, codex, djinn.
    no ssh here, gh here (a cloud thread; #3045): it starts
        .github/workflows/staff-notice.yml on main with the notice, waits for
        the run to end, and prints the run's answer. The workflow runs this
        script with -OnTheBox on a VPS runner, with the notices key named
        claude out of the "notices" environment, which only main may use. So
        the notice says [claude], and -From, if given, has to be claude.
        Nothing secret is in the container or crosses it: the text and the
        answer do. A run that has not ended in -WaitMinutes still posts when
        a runner takes it, and -Run <its id> reads its answer then.

  WHAT IT SAYS AND EXITS.
    queued    0, with the id, after the box wrote it to the outbox
    posted    0 (-Check), by the bot or the webhook
    waiting   2 (-Check), in the outbox, not said yet; the bot reads every
              minute and the webhook takes over after two and a half
    waiting   2, through GitHub: the run had not ended in -WaitMinutes, or
              GitHub started it and a read of its answer failed; the notice
              was sent either way, and -Run <its id> reads the answer
    unsay     0, with the id, after the box wrote the ask down
    taken back 0 (-Check): deleted, already gone, or withheld (never said)
    waiting   2 (-Check), asked to be taken back, the bot not there yet
    refused, not found, expired, no watchdog, or the box not reached: 1,
              with why. Nothing was posted. A notice the watchdog's webhook
              said, or one the bot could not delete: 1, with why.
  In a GitHub Actions job it also writes the box's answer, or why it
  stopped, as an annotation titled Say-Staff, which is how the cloud half
  reads the runner's answer.

  The notice: 1800 characters at most, 30 an hour for each sender, no
  mentions (the bot and the webhook both send with mentions off).
  tests\test-say-staff.ps1 runs this against the box half in a scratch folder.
#>
[CmdletBinding(DefaultParameterSetName = 'Say')]
param(
    [Parameter(ParameterSetName = 'Say', Mandatory = $true)]
    [string]$Text,
    # Who the notice is from, or whose notice is taken back (-Unsay).
    [string]$From = '',
    [Parameter(ParameterSetName = 'Check', Mandatory = $true)]
    [string]$Check,
    # Takes a notice back (#3328).
    [Parameter(ParameterSetName = 'Unsay', Mandatory = $true)]
    [string]$Unsay,
    # Through GitHub: the answer of a staff-notice run that had not ended.
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [long]$Run,
    # The staff-notice workflow's half: this runs on the box itself.
    [switch]$OnTheBox,
    [int]$WaitMinutes = 15,
    [string]$GitHubRepo = 'EvilPatrick06/Thornswood',
    [string]$VpsHost = '',
    [string]$VpsUser = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$vpsDir = Join-Path (Split-Path -Parent $Here) 'vps'
. (Join-Path $vpsDir 'Vps.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$far = 'C:\Thornswood-Watch\say-staff.ps1'
$maxText = 1800
$workflow = 'staff-notice.yml'
# The name the workflow's notices key was made with (Grant-BoxAccess.ps1
# -Name claude -MakeKey -NoticesOnly -ToEnvironment notices). The box sets
# -From to it, so it is what a notice through GitHub says.
$workflowSender = 'claude'
$inActions = ($env:GITHUB_ACTIONS -eq 'true')

# An annotation on the job, which GitHub keeps on its check run, so the cloud
# half reads the answer without reading the log.
function Note([string]$level, [string]$m) {
    if ($inActions) { Write-Host ('::' + $level + ' title=Say-Staff::' + ($m -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A')) }
}
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Note 'error' $m; Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

$noticeKey = [string]$env:THORNSWOOD_NOTICE_KEY_B64
$noticeToken = [string]$env:THORNSWOOD_NOTICE_TOKEN
$withNoticeKey = [bool]($noticeKey -and $noticeToken)

# ------------------------------------------------------------- the way -----
$route = ''
if ($OnTheBox) {
    if (-not $noticeKey) { Die 'THORNSWOOD_NOTICE_KEY_B64 is not set, so there is no key to post with. In the staff-notice workflow it is the NOTICE_KEY_B64 secret of the "notices" environment, which .\scripts\vps\Grant-BoxAccess.ps1 -Name claude -MakeKey -NoticesOnly -ToEnvironment notices puts there from One. Nothing was posted.' }
    $route = 'box'
} elseif ($noticeKey -or $noticeToken) {
    if (-not $withNoticeKey) { Die 'only one of THORNSWOOD_NOTICE_KEY_B64 and THORNSWOOD_NOTICE_TOKEN is set; a notices key needs both. Grant-BoxAccess.ps1 -NoticesOnly -MakeKey on One makes the pair. Nothing was posted.' }
    $route = 'bridge'
} elseif (Get-Command ssh -ErrorAction SilentlyContinue) {
    $route = 'ssh'
} elseif (Get-Command gh -ErrorAction SilentlyContinue) {
    $route = 'github'
} else {
    Die 'there is no ssh here to reach the box and no gh to start the staff-notice workflow with. Nothing was posted.'
}
if ($PSCmdlet.ParameterSetName -eq 'Run' -and $route -ne 'github') { Die '-Run reads a staff-notice run on GitHub, which is the way only where there is no ssh.' }

# ----------------------------------------------------------- what to send --
if ($PSCmdlet.ParameterSetName -eq 'Check') {
    if ($Check -notmatch '^agent-[a-z0-9-]{1,80}$') { Die "$Check is not a notice id; Say-Staff.ps1 printed one like agent-claude-20261020214500-1a2b3c." }
    $line = 'check ' + $Check
} elseif ($PSCmdlet.ParameterSetName -eq 'Unsay') {
    if ($Unsay -notmatch '^agent-[a-z0-9-]{1,80}$') { Die "$Unsay is not a notice id; Say-Staff.ps1 printed one like agent-claude-20261020214500-1a2b3c." }
    $line = 'unsay ' + $Unsay
    if ($route -eq 'ssh' -and $From -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') {
        Die '-From says whose notice it is: one lower case word (claude, codex, djinn). Only its own notices can be taken back. Nothing was changed.'
    }
} elseif ($PSCmdlet.ParameterSetName -eq 'Say') {
    $t = ($Text -replace '\r\n?', "`n").Trim()
    if (-not $t) { Die 'the notice is empty. Nothing was posted.' }
    if ($t.Length -gt $maxText) { Die ('the notice is ' + $t.Length + ' characters and ' + $maxText + ' is the most. Say it shorter; nothing was cut and nothing was posted.') }
    $line = 'say ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t))
    if ($route -eq 'ssh' -and $From -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') {
        Die '-From says who the notice is from: one lower case word, letters, digits and hyphens (claude, codex, djinn). Nothing was posted.'
    }
    if ($route -eq 'github' -and $From -and $From -cne $workflowSender) {
        Die ("through GitHub a notice is from the workflow's key, named $workflowSender, and the box sets that, so it cannot say it is from $From. Post it from a machine with ssh to the box for another name. Nothing was posted.")
    }
}
if (-not $From) { $From = 'agent' }

# ----------------------------------------------------------- through GitHub --
# The run the dispatch started, once GitHub has named it. From then on the
# notice is GitHub's to run, so a read that fails here is said as that, with
# the line that reads the answer later, and never as nothing having been sent.
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

# Sent, and the answer not read: exit 2, as for a run that has not ended.
function Unread([string]$why) {
    Note 'warning' ("sent as run $sentRun; its answer was not read: $why")
    Say ("the notice was sent: GitHub started run $sentRun with it, and the run posts it. Its answer was not read here: $why") 'Yellow'
    Say ('  its answer: pwsh scripts/ops/Say-Staff.ps1 -Run ' + $sentRun) 'DarkGray'
    exit 2
}

# Waits for the run to end, then reads what the runner said: the Say-Staff
# annotation on its job. Returns the box's answer line.
#
# -Started: the dispatch has just named this run. GitHub writes the run, then
# answers the dispatch with its id, and serves reads from copies that catch
# up a moment later, so the first read of a run that new can be Not Found
# (#3081: run 39647569632 was 404 within the second it was made, during
# GitHub's Actions incident of 21 Oct, and served a few seconds after). Until
# a read first serves it, that run is one more state of the wait below, which
# reads every 5 seconds until the run has ended or -WaitMinutes is up, the
# same as queued. A run given by -Run, or one already read, that is Not Found
# stops at once: GitHub never said it exists, or it no longer does.
function Read-RunAnswer([long]$id, [switch]$Started) {
    $runPath = "repos/$GitHubRepo/actions/runs/$id"
    $deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
    $run = Get-GitHub $runPath -NotYet:$Started
    $told = ''
    while (-not $run -or $run.status -ne 'completed') {
        $state = if ($run) { $run.status } else { 'not served by GitHub yet' }
        if ([DateTime]::UtcNow -gt $deadline) {
            Say ("the run has not ended after $WaitMinutes minutes (it was " + $state + '), so every runner is busy. It still posts when one takes it.') 'Yellow'
            Say ('  its answer then: pwsh scripts/ops/Say-Staff.ps1 -Run ' + $id) 'DarkGray'
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
    if ($run.path -notmatch ('/' + [regex]::Escape($workflow) + '$')) { Die ("run $id is not a staff-notice run (it is " + $run.path + ').') }
    $notes = @()
    foreach ($job in @((Get-GitHub "$runPath/jobs").jobs)) {
        $notes += @(Get-GitHub ("repos/$GitHubRepo/check-runs/" + $job.id + '/annotations') | Where-Object { $_.title -eq 'Say-Staff' })
    }
    $said = @($notes | Where-Object { $_.annotation_level -eq 'notice' }) | Select-Object -Last 1
    if ($said) { return ([string]$said.message).Trim() }
    $why = @($notes | Where-Object { $_.annotation_level -eq 'failure' }) | Select-Object -Last 1
    if ($why) { Die ('the runner stopped: ' + ([string]$why.message).Trim() + ' (' + $run.html_url + ')') }
    Die ('the run ended ' + $run.conclusion + ' without an answer from the box, so nothing was posted that it knows of. Its log says why: ' + $run.html_url)
}

if ($route -eq 'github') {
    if ($PSCmdlet.ParameterSetName -eq 'Run') {
        $answer = Read-RunAnswer $Run
    } else {
        # The body on gh's standard input, so the text is on no command line.
        $inputs = if ($PSCmdlet.ParameterSetName -eq 'Check') { @{ check = $Check } } elseif ($PSCmdlet.ParameterSetName -eq 'Unsay') { @{ unsay = $Unsay } } else { @{ text = $t } }
        $body = @{ ref = 'main'; inputs = $inputs; return_run_details = $true } | ConvertTo-Json -Compress
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $o = @($body | & gh api -X POST "repos/$GitHubRepo/actions/workflows/$workflow/dispatches" --input - 2>&1 | ForEach-Object { "$_" })
        $c = $LASTEXITCODE
        $ErrorActionPreference = $old
        if ($c -ne 0) { Die ('GitHub did not start the staff-notice workflow: ' + (($o | Select-Object -Last 2) -join ' ') + '. Nothing was posted.') }
        $started = ($o -join "`n") | ConvertFrom-Json
        if (-not $started.workflow_run_id) {
            Say ('the notice was sent: GitHub started the staff-notice workflow with it, but named no run, so its answer cannot be read here. Its runs: https://github.com/' + $GitHubRepo + '/actions/workflows/' + $workflow) 'Yellow'
            exit 2
        }
        Say ('sent to the staff-notice workflow: ' + $started.html_url) 'DarkGray'
        $sentRun = [long]$started.workflow_run_id
        $answer = Read-RunAnswer $sentRun -Started
    }
    $out = @($answer)
    $code = 1
} else {
    # What the box is asked to run. A notices key runs it anyway, with its own name.
    $target = "$VpsUser@$VpsHost"
    $remote = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $far -From $From"
    $sshArgs = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20')
    $restore = $null
    # The key, when there is one, for this run only.
    $work = ''
    try {
        if ($route -eq 'box' -or $route -eq 'bridge') {
            $base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
            $work = Join-Path $base ('thornswood-notice-' + [Guid]::NewGuid().ToString('N'))
            # ssh reads a -o file option up to the first space as one file.
            if ($work -match '\s') { Die "the temp folder ($work) has a space in it, which ssh would read as two files. Nothing was posted." }
            New-Item -ItemType Directory -Path $work -Force | Out-Null
            $keyText = ''
            try { $keyText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($noticeKey -replace '\s', ''))) } catch { $keyText = '' }
            if (-not $keyText.Trim()) { Die 'THORNSWOOD_NOTICE_KEY_B64 is not a base64 key. Make it again with Grant-BoxAccess.ps1 -NoticesOnly -MakeKey on One. Nothing was posted.' }
            $keyFile = Join-Path $work 'notice_ed25519'
            Write-ThornswoodPrivateFile -Path $keyFile -Text ($keyText.Replace("`r`n", "`n").TrimEnd() + "`n")
            $keyText = $null
            $sshArgs = @('-F', 'none', '-i', $keyFile, '-o', 'IdentitiesOnly=yes') + $sshArgs
        }
        if ($route -eq 'box') {
            # The box's own sshd, its host key held to the pins in a
            # known_hosts of this run's own: nothing in the runner account's
            # .ssh is read or written. The pins and the user are the
            # checkout's vps.json alone, not a machine's own override file,
            # which an earlier job on the same runner account could leave.
            $pinned = Get-ThornswoodVpsCommitted
            $knownHosts = Join-Path $work 'known_hosts'
            try { $null = Add-ThornswoodKnownHost -Address '127.0.0.1' -KnownHosts $knownHosts -Pinned @($pinned.hostKeys) }
            catch { Die ('the box''s own sshd on 127.0.0.1: ' + $_.Exception.Message) }
            $sshArgs += @('-o', "UserKnownHostsFile=$knownHosts")
            $target = ([string]$pinned.user) + '@127.0.0.1'
        }
        if ($route -eq 'bridge') {
            $node = Get-Command node -ErrorAction SilentlyContinue
            if (-not $node) { Die 'node is not on PATH, and the bridge client is node. Nothing was posted.' }
            $client = Install-ThornswoodBridgeClient (Join-Path $vpsDir 'bridge')
            # connect.js and listen.js read the token from the environment, for
            # this process and what it starts, and from no command line.
            $restore = @{ Token = $env:THORNSWOOD_BOX_TOKEN }
            $env:THORNSWOOD_BOX_TOKEN = $noticeToken
            $null = Add-ThornswoodKnownHostThroughBridge -Address $VpsHost -Node $node.Source -Listen (Join-Path $client 'listen.js')
            $sshArgs += @('-o', ('ProxyCommand="' + $node.Source + '" "' + (Join-Path $client 'connect.js') + '"'))
        }

        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = @(Invoke-ThornswoodNative { @($line) | & ssh @sshArgs $target $remote } 2>&1 | ForEach-Object { "$_".Trim() } |
                 Where-Object { $_ -and $_ -notmatch 'post-quantum|store now, decrypt later|openssh\.com/pq\.html' })
        $code = $LASTEXITCODE
        $ErrorActionPreference = $old
    }
    finally {
        if ($null -ne $restore) {
            if ($null -ne $restore.Token) { $env:THORNSWOOD_BOX_TOKEN = $restore.Token } else { Remove-Item Env:THORNSWOOD_BOX_TOKEN -ErrorAction SilentlyContinue }
        }
        if ($work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ------------------------------------------------------------ the answer ---
$answer = @($out | Where-Object { $_ -match '^(QUEUED|POSTED|WAITING|EXPIRED|NOT FOUND|NOWATCHER|REFUSED|READY|UNSAY|UNSAID)\b' }) | Select-Object -Last 1
if ($answer -and $route -ne 'github') { Note 'notice' $answer }
switch -Regex ("$answer") {
    '^QUEUED (\S+)$' {
        Say ('queued ' + $Matches[1] + '. The bot says it in #staff-updates within a minute.') 'Green'
        Say ('  to see it was said: pwsh scripts/ops/Say-Staff.ps1 -Check ' + $Matches[1]) 'DarkGray'
        exit 0
    }
    '^UNSAY QUEUED (\S+)$' {
        Say ('asked the bot to take ' + $Matches[1] + ' back. It deletes its post in #staff-updates within a minute, or never says it if it has not yet.') 'Green'
        Say ('  to see it was done: pwsh scripts/ops/Say-Staff.ps1 -Check ' + $Matches[1]) 'DarkGray'
        exit 0
    }
    '^UNSAY WAITING$' { Say 'asked to be taken back, and the bot has not done it yet. It reads every minute.' 'Yellow'; exit 2 }
    '^UNSAID deleted$' { Say 'taken back: the bot deleted its post in #staff-updates.' 'Green'; exit 0 }
    '^UNSAID gone$' { Say 'taken back: the post was not in #staff-updates any more, so there was nothing to delete.' 'Green'; exit 0 }
    '^UNSAID withheld$' { Say 'taken back before it was said: it was never posted, and the watchdog''s webhook will not post it either.' 'Green'; exit 0 }
    '^UNSAID webhook$' { Die 'the watchdog''s webhook said it, and the bot can delete only its own posts. Somebody with Manage Messages in #staff-updates deletes it by hand.' }
    '^UNSAID unknown$' { Die 'the bot found no notice with that id in the outbox, so it took nothing back.' }
    '^UNSAID (.*)$' { Die ('the bot could not take it back: ' + $Matches[1] + '. bot.log on the box says why.') }
    '^POSTED (bot|webhook)$' { Say ('posted in #staff-updates, by the ' + $Matches[1] + '.') 'Green'; exit 0 }
    '^WAITING$' { Say 'in the outbox, not said yet. The bot reads it every minute; the watchdog''s webhook takes over after two and a half.' 'Yellow'; exit 2 }
    '^EXPIRED$' { Die 'it was never said, and it is over a day old now, so it never will be. Post it again if it still matters.' }
    '^NOT FOUND$' { Die 'the box holds no notice with that id.' }
    '^NOWATCHER$' { Die 'the watchdog is not installed on the box, so nothing there would say it. Nothing was posted. It goes on with .\scripts\vps\Watch-Services.ps1 -Install, run from One (a Releases job).' }
    '^REFUSED (.*)$' { Die ('the box refused it: ' + $Matches[1]) }
}
$out | Select-Object -Last 5 | ForEach-Object { Say "  $_" 'DarkGray' }
# What powershell.exe says when the file it is given to run is not there.
if (($out -join ' ') -match 'to the -File parameter does not exist') {
    Die "the box has no $far yet, so nothing was posted. It goes on with .\scripts\vps\Watch-Services.ps1 -Install, run from One (a Releases job)."
}
Die ('the box did not answer (ssh exit ' + $code + '), so nothing was posted. The lines above say why: a "box bridge:" line is the bridge or the token, "Permission denied" is the key.')
