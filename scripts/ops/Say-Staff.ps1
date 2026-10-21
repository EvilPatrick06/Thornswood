<#
  Say-Staff.ps1

  Posts one staff notice in #staff-updates through the bot, from any machine
  that reaches the box: a line before an edit to one of the six shared files,
  taking the dev feed, what was merged or published. Agents post their own
  notices this way instead of asking a person to (Patrick, 20 Oct 2026,
  #2934).

      pwsh scripts/ops/Say-Staff.ps1 -From claude -Text "Taking the dev feed for the cooking fix, Ship at 4:30 PM."
                       queue it; prints its id
      pwsh scripts/ops/Say-Staff.ps1 -Check agent-claude-20261020214500-1a2b3c
                       whether the bot has said it yet

  HOW IT GETS THERE. The notice goes on ssh's standard input, base64, to
  C:\Thornswood-Watch\say-staff.ps1 on the box (scripts\vps\vps-say-staff.ps1,
  put there by Watch-Services.ps1 -Install), which appends one line to the
  watchdog's outbox, alerts.jsonl. The bot reads that every minute and says
  each new line in #staff-updates, by the id in bot\staff-channel.txt, and
  the watchdog says it through its own #staff-updates webhook when the bot is
  down (#447). No Discord token or webhook leaves the box, and nothing here
  knows one. The text is never on a command line.

  WHICH KEY.
    THORNSWOOD_NOTICE_KEY_B64 and THORNSWOOD_NOTICE_TOKEN set (an agent
        environment given a notices key by Grant-BoxAccess.ps1 -NoticesOnly
        -MakeKey): that key, through the bridge with that token. The box
        runs say-staff.ps1 for it whatever is asked, with -From set to the
        key's own name, so -From here is not needed and is not what shows.
    otherwise: ssh to the box the way every script here goes (One, a
        developer's PC set up by Setup-SshKey.ps1, a cloud thread after
        Setup-CloudSsh.ps1). -From is then who the notice is from: one lower
        case word, claude, codex, djinn.

  WHAT IT SAYS AND EXITS.
    queued    0, with the id, after the box wrote it to the outbox
    posted    0 (-Check), by the bot or the webhook
    waiting   2 (-Check), in the outbox, not said yet; the bot reads every
              minute and the webhook takes over after two and a half
    refused, not found, expired, no watchdog, or the box not reached: 1,
              with why. Nothing was posted.

  The notice: 1800 characters at most, 30 an hour for each sender, no
  mentions (the bot and the webhook both send with mentions off).
  tests\test-say-staff.ps1 runs this against the box half in a scratch folder.
#>
[CmdletBinding(DefaultParameterSetName = 'Say')]
param(
    [Parameter(ParameterSetName = 'Say', Mandatory = $true)]
    [string]$Text,
    [Parameter(ParameterSetName = 'Say')]
    [string]$From = '',
    [Parameter(ParameterSetName = 'Check', Mandatory = $true)]
    [string]$Check,
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
$target = "$VpsUser@$VpsHost"
$far = 'C:\Thornswood-Watch\say-staff.ps1'
$maxText = 1800

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

$noticeKey = [string]$env:THORNSWOOD_NOTICE_KEY_B64
$noticeToken = [string]$env:THORNSWOOD_NOTICE_TOKEN
$withNoticeKey = [bool]($noticeKey -and $noticeToken)
if (($noticeKey -or $noticeToken) -and -not $withNoticeKey) {
    Die 'only one of THORNSWOOD_NOTICE_KEY_B64 and THORNSWOOD_NOTICE_TOKEN is set; a notices key needs both. Grant-BoxAccess.ps1 -NoticesOnly -MakeKey on One makes the pair. Nothing was posted.'
}

# ----------------------------------------------------------- what to send --
if ($PSCmdlet.ParameterSetName -eq 'Check') {
    if ($Check -notmatch '^agent-[a-z0-9-]{1,80}$') { Die "$Check is not a notice id; Say-Staff.ps1 printed one like agent-claude-20261020214500-1a2b3c." }
    $line = 'check ' + $Check
} else {
    $t = ($Text -replace '\r\n?', "`n").Trim()
    if (-not $t) { Die 'the notice is empty. Nothing was posted.' }
    if ($t.Length -gt $maxText) { Die ('the notice is ' + $t.Length + ' characters and ' + $maxText + ' is the most. Say it shorter; nothing was cut and nothing was posted.') }
    $line = 'say ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t))
}
if (-not $withNoticeKey -and $PSCmdlet.ParameterSetName -eq 'Say' -and $From -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') {
    Die '-From says who the notice is from: one lower case word, letters, digits and hyphens (claude, codex, djinn). Nothing was posted.'
}
if (-not $From) { $From = 'agent' }
# What the box is asked to run. A notices key runs it anyway, with its own name.
$remote = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $far -From $From"

# --------------------------------------------------------------- the way ---
$sshArgs = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=20')
$restore = $null
$keyFile = ''
try {
    if ($withNoticeKey) {
        $node = Get-Command node -ErrorAction SilentlyContinue
        if (-not $node) { Die 'node is not on PATH, and the bridge client is node. Nothing was posted.' }
        $keyText = ''
        try { $keyText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($noticeKey -replace '\s', ''))) } catch { $keyText = '' }
        if (-not $keyText.Trim()) { Die 'THORNSWOOD_NOTICE_KEY_B64 is not a base64 key. Make it again with Grant-BoxAccess.ps1 -NoticesOnly -MakeKey on One. Nothing was posted.' }
        $keyFile = Join-Path (Join-Path $HOME '.ssh') 'thornswood_notice_ed25519'
        Write-ThornswoodPrivateFile -Path $keyFile -Text ($keyText.Replace("`r`n", "`n").TrimEnd() + "`n")
        $keyText = $null
        $client = Install-ThornswoodBridgeClient (Join-Path $vpsDir 'bridge')
        # connect.js and listen.js read the token from the environment, for
        # this process and what it starts, and from no command line.
        $restore = @{ Token = $env:THORNSWOOD_BOX_TOKEN }
        $env:THORNSWOOD_BOX_TOKEN = $noticeToken
        $null = Add-ThornswoodKnownHostThroughBridge -Address $VpsHost -Node $node.Source -Listen (Join-Path $client 'listen.js')
        $sshArgs = @('-F', 'none', '-i', $keyFile, '-o', 'IdentitiesOnly=yes') + $sshArgs +
                   @('-o', ('ProxyCommand="' + $node.Source + '" "' + (Join-Path $client 'connect.js') + '"'))
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
}

# ------------------------------------------------------------ the answer ---
$answer = @($out | Where-Object { $_ -match '^(QUEUED|POSTED|WAITING|EXPIRED|NOT FOUND|NOWATCHER|REFUSED|READY)\b' }) | Select-Object -Last 1
switch -Regex ("$answer") {
    '^QUEUED (\S+)$' {
        Say ('queued ' + $Matches[1] + '. The bot says it in #staff-updates within a minute.') 'Green'
        Say ('  to see it was said: pwsh scripts/ops/Say-Staff.ps1 -Check ' + $Matches[1]) 'DarkGray'
        exit 0
    }
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
