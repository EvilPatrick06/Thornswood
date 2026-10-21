<#
  test-say-staff.ps1

      pwsh -NoProfile -File .\tests\test-say-staff.ps1
      powershell -NoProfile -File .\tests\test-say-staff.ps1

  Agents post their own staff notices in #staff-updates through the bot
  (#2934): scripts\ops\Say-Staff.ps1 hands the notice over ssh to
  scripts\vps\vps-say-staff.ps1 on the box, which appends one line to the
  watchdog's outbox, and a key from Grant-BoxAccess.ps1 -NoticesOnly can run
  that and nothing else.

  WHAT IT HOLDS THEM TO.
    1. All three parse, and Watch-Services.ps1 -Install sends the box half.
    2. The box half, run as its own process against a scratch watchdog
       folder: nothing on its input says READY and writes nothing; a notice
       is one outbox line of the watchdog's shape (id, at, service, kind,
       text) with the sender in front; no watchdog, a bad sender, an empty,
       too long or unreadable notice, and the 31st in an hour are refused
       with nothing written; a check says WAITING, POSTED bot, POSTED
       webhook, EXPIRED and NOT FOUND from the files the bot and the
       watchdog keep.
    3. The bot's own reader (bot\bot.py watch_alerts_due) takes the line the
       box half wrote, when discord.py is here to import it.
    4. Say-Staff.ps1 end to end, with a stand-in for ssh that runs the box
       half: queued, then checked, the text on standard input and never on
       the command line; and it refuses before connecting what the box would.
       -OnTheBox (#3045), the staff-notice workflow's half: ssh to the box's
       own sshd at 127.0.0.1 with only the notices key, the host key held to
       the pins in a known_hosts of its own, both gone when it ends, and the
       answer left as an annotation. With no ssh, through GitHub: it starts
       staff-notice.yml on main with the text on gh's standard input, reads
       the runner's annotation, and says what the box said; -From other than
       claude, a stopped runner, a run with no answer, a run not taken in
       time and -Run of another workflow each say so.
    5. Grant-BoxAccess.ps1: a notices key's line is taken only through the
       bridge and only runs say-staff.ps1 as its own name; -List reads that
       back; the box change stops with nothing changed when say-staff.ps1 is
       not there; and -NoticesOnly goes only with -MakeKey. -ToEnvironment
       makes the GitHub environment main's alone, or stops naming the other
       branch it lets in, before the box is touched, and the key goes to gh
       secret set on standard input.
    6. .github\workflows\staff-notice.yml: started by hand only, contents
       read, on the VPS runners, the notices environment's key, no token
       kept by the checkout, pwsh with no profile, nothing pasted into its
       script; and that script, run against a stand-in Say-Staff.ps1.
  Nothing connects anywhere and nothing outside the temp folder is touched.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function P([string[]]$parts) { return [IO.Path]::Combine([string[]](@($repo) + $parts)) }

$box = P 'scripts', 'vps', 'vps-say-staff.ps1'
$say = P 'scripts', 'ops', 'Say-Staff.ps1'
$grantPath = P 'scripts', 'vps', 'Grant-BoxAccess.ps1'
$watchPath = P 'scripts', 'vps', 'Watch-Services.ps1'
$shell = (Get-Process -Id $PID).Path
$enc = New-Object Text.UTF8Encoding($false)

# ---- 1. they parse ---------------------------------------------------------
$asts = @{}
foreach ($f in $box, $say, $grantPath) {
    $e = $null
    $asts[$f] = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
    Yes ((Split-Path -Leaf $f) + ' parses') (@($e).Count -eq 0)
}
$watch = [IO.File]::ReadAllText($watchPath)
Yes 'Watch-Services.ps1 -Install writes say-staff.ps1 beside watch.ps1, from vps-say-staff.ps1' (
    $watch.Contains("Join-Path `$Here 'vps-say-staff.ps1'") -and $watch.Contains("[IO.File]::WriteAllBytes('`$Root\say-staff.ps1'"))

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-say-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$root = Join-Path $tmp 'Thornswood-Watch'
$alerts = Join-Path $root 'alerts.jsonl'

# The box half as sshd runs it: its own process, the line on its input.
function Box([string]$from, [string[]]$in, [string]$at = $root) {
    $args2 = @('-NoProfile', '-NonInteractive', '-File', $box, '-From', $from, '-Root', $at)
    $out = @($in | & $shell @args2 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE; Last = ($out | Select-Object -Last 1) }
}
function SayLine([string]$text) { return ('say ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))) }
function Rows {
    if (-not (Test-Path -LiteralPath $alerts)) { return @() }
    return @([IO.File]::ReadAllLines($alerts) | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-Json $_ })
}
function Fresh {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'watch.ps1'), '# stand-in')
}
function UnixNow { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

try {
    # ---- 2. the box half -----------------------------------------------------
    Fresh
    Remove-Item -LiteralPath (Join-Path $root 'watch.ps1')
    $r = Box 'cloud' @((SayLine 'hello'))
    Yes 'no watchdog on the box: NOWATCHER, exit 1, nothing written' ($r.Last -eq 'NOWATCHER' -and $r.Code -eq 1 -and -not (Test-Path -LiteralPath $alerts))

    Fresh
    $r = Box 'cloud' @()
    Yes 'nothing on its input: READY, exit 0, nothing written (how a new key is proved)' ($r.Last -eq 'READY' -and $r.Code -eq 0 -and -not (Test-Path -LiteralPath $alerts))

    foreach ($bad in 'Cloud', 'cloud x', 'cloud"', '-cloud', '') {
        $r = Box $bad @((SayLine 'hello'))
        Yes ("a sender that is not one lower case word ('" + $bad + "') is refused") ($r.Last -like 'REFUSED*' -and $r.Code -eq 1 -and -not (Test-Path -LiteralPath $alerts))
    }

    $before = UnixNow
    $r = Box 'cloud' @('', (SayLine "  Taking the dev feed for the cooking fix.`r`nShip at 4:30 PM.  "))
    $rows = @(Rows)
    $raw = [IO.File]::ReadAllText($alerts)
    Yes 'a notice: QUEUED <id>, exit 0' ($r.Last -match '^QUEUED agent-cloud-\d{14}-[0-9a-f]{6}$' -and $r.Code -eq 0)
    Yes '  one outbox line, no byte order mark, ending in CRLF the way the watchdog writes them' ($rows.Count -eq 1 -and $raw.EndsWith("}`r`n") -and ([IO.File]::ReadAllBytes($alerts))[0] -eq 0x7B)
    $row = $rows[0]
    Yes '  its id is the one printed' ($r.Last -eq ('QUEUED ' + $row.id))
    Yes '  at is now, in unix seconds' ([int64]$row.at -ge $before -and [int64]$row.at -le ((UnixNow) + 1))
    Yes '  service "agent cloud", kind "notice"' ($row.service -eq 'agent cloud' -and $row.kind -eq 'notice')
    Yes '  the text is the sender in front of the notice, trimmed, line ends made LF' ($row.text -eq "[cloud] Taking the dev feed for the cooking fix.`nShip at 4:30 PM.")
    $first = $row.id

    $r = Box 'claude' @((SayLine ([string][char]0x00e9 + ' @everyone <ok> & "quoted"')))
    $rows = @(Rows)
    Yes 'a second notice is a second line, and the text survives non-ASCII, quotes and markup' ($rows.Count -eq 2 -and $rows[1].text -eq ('[claude] ' + [string][char]0x00e9 + ' @everyone <ok> & "quoted"'))

    $n = @(Rows).Count
    $r = Box 'cloud' @((SayLine "   `n  "))
    Yes 'an empty notice is refused, nothing written' ($r.Last -like 'REFUSED*empty*' -and @(Rows).Count -eq $n)
    $r = Box 'cloud' @((SayLine ('x' * 1801)))
    Yes 'a notice over 1800 characters is refused, not cut' ($r.Last -like 'REFUSED*1801 characters*' -and @(Rows).Count -eq $n)
    $r = Box 'cloud' @((SayLine ('x' * 1800)))
    Yes '  and one of exactly 1800 goes' ($r.Last -like 'QUEUED*' -and @(Rows).Count -eq ($n + 1))
    $n = @(Rows).Count
    $r = Box 'cloud' @('say not*base64')
    Yes 'a line that is not "say <base64>" or "check <id>" is refused' ($r.Last -like 'REFUSED*' -and @(Rows).Count -eq $n)
    $r = Box 'cloud' @('say @@@@')
    Yes '  and so is a say line whose notice is not base64' ($r.Last -like 'REFUSED*' -and @(Rows).Count -eq $n)

    # Thirty an hour for each sender: the outbox already holding 30 recent
    # ones from it, written here directly, and one from an hour and a half ago.
    Fresh
    $now = UnixNow
    $lines = @()
    for ($i = 0; $i -lt 30; $i++) { $lines += (ConvertTo-Json @{ id = ('agent-busy-x' + $i); at = ($now - 60); service = 'agent busy'; kind = 'notice'; text = 't' } -Compress) }
    $lines += (ConvertTo-Json @{ id = 'agent-calm-old'; at = ($now - 5400); service = 'agent calm'; kind = 'notice'; text = 't' } -Compress)
    $lines += 'not json at all'
    [IO.File]::WriteAllText($alerts, (($lines -join "`r`n") + "`r`n"), $enc)
    $r = Box 'busy' @((SayLine 'one more'))
    Yes 'the 31st notice in an hour from one sender is refused' ($r.Last -like 'REFUSED busy has queued 30*' -and @([IO.File]::ReadAllLines($alerts)).Count -eq 32)
    $r = Box 'calm' @((SayLine 'one'))
    Yes '  another sender, and an old line or a broken one, do not count against it' ($r.Last -like 'QUEUED agent-calm-*')

    # Checks, from the files the bot and the watchdog keep.
    Fresh
    $now = UnixNow
    $lines = @(
        (ConvertTo-Json @{ id = 'agent-a-1'; at = $now; service = 'agent a'; kind = 'notice'; text = 't' } -Compress),
        (ConvertTo-Json @{ id = 'agent-a-2'; at = $now; service = 'agent a'; kind = 'notice'; text = 't' } -Compress),
        (ConvertTo-Json @{ id = 'agent-a-3'; at = $now; service = 'agent a'; kind = 'notice'; text = 't' } -Compress),
        (ConvertTo-Json @{ id = 'agent-a-4'; at = ($now - 90000); service = 'agent a'; kind = 'notice'; text = 't' } -Compress))
    [IO.File]::WriteAllText($alerts, (($lines -join "`r`n") + "`r`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $root 'alerts-sent-bot.txt'), "agent-a-1`r`n")
    [IO.File]::WriteAllText((Join-Path $root 'alerts-sent-webhook.txt'), "agent-a-2`r`n")
    Yes 'check: the bot said it' ((Box 'a' @('check agent-a-1')).Last -eq 'POSTED bot')
    Yes 'check: the webhook said it' ((Box 'a' @('check agent-a-2')).Last -eq 'POSTED webhook')
    $r = Box 'a' @('check agent-a-3')
    Yes 'check: in the outbox, not said yet, exit 0' ($r.Last -eq 'WAITING' -and $r.Code -eq 0)
    Yes 'check: over a day old and never said' ((Box 'a' @('check agent-a-4')).Last -eq 'EXPIRED')
    Yes 'check: no such notice' ((Box 'a' @('check agent-a-9')).Last -eq 'NOT FOUND')
    Yes 'check: only an agent notice''s id is asked about' ((Box 'a' @('check outside-20261020-caddy-down')).Last -like 'REFUSED*')

    # ---- 3. the bot's reader takes it ----------------------------------------
    Fresh
    $r = Box 'cloud' @((SayLine 'for the bot'))
    $py = $null
    foreach ($c in 'python', 'python3') { if (-not $py) { $py = Get-Command $c -ErrorAction SilentlyContinue } }
    $probe = ''
    if ($py) {
        $env:DISCORD_TOKEN = 'not-a-real-token'
        $code = @"
import json, sys, time
sys.path.insert(0, sys.argv[1])
try:
    import bot
except Exception as e:
    print('SKIP ' + type(e).__name__)
    sys.exit(0)
lines = [l.strip() for l in open(sys.argv[2], encoding='utf-8-sig') if l.strip()]
due = bot.watch_alerts_due(lines, set(), int(time.time()))
print('DUE %d' % len(due))
for aid, text in due:
    print('ID ' + aid)
    print('TEXT ' + json.dumps(text))
"@
        $pyFile = Join-Path $tmp 'probe.py'
        [IO.File]::WriteAllText($pyFile, $code, $enc)
        $said = @(& $py.Source -I $pyFile (P 'bot') $alerts 2>&1 | ForEach-Object { "$_" })
        $probe = @($said | Where-Object { $_ -match '^(SKIP|DUE) ' }) | Select-Object -Last 1
        $dueId = @($said | Where-Object { $_ -like 'ID *' } | ForEach-Object { $_.Substring(3) })
        $dueText = @($said | Where-Object { $_ -like 'TEXT *' } | ForEach-Object { ConvertFrom-Json $_.Substring(5) })
        Remove-Item Env:DISCORD_TOKEN -ErrorAction SilentlyContinue
    }
    if ($probe -like 'DUE *') {
        Yes 'bot.py watch_alerts_due takes the line the box half wrote, with its text' (
            $probe -eq 'DUE 1' -and $dueId.Count -eq 1 -and ('QUEUED ' + $dueId[0]) -eq $r.Last -and $dueText.Count -eq 1 -and $dueText[0] -eq '[cloud] for the bot')
    } else {
        Write-Host ('SKIP  bot.py could not be imported here (' + $(if ($probe) { $probe } else { 'no python' }) + '); bot\test-watch-services.py covers its reader')
    }

    # ---- 4. Say-Staff.ps1 end to end -----------------------------------------
    # A stand-in for ssh, first on the path of the process Say-Staff.ps1 runs
    # in: writes down what it was given, then runs the box half with what
    # came on its input, the way sshd would.
    $bin = Join-Path $tmp 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $standIn = Join-Path $tmp 'ssh-stand-in.ps1'
    $argsFile = Join-Path $tmp 'ssh-args.txt'
    [IO.File]::WriteAllText($standIn, @"
`$all = @(`$args | ForEach-Object { [string]`$_ })
[IO.File]::WriteAllLines('$argsFile', [string[]]`$all)
`$cmd = `$all[-1]
`$from = if (`$cmd -match '-From ([a-z0-9-]+)`$') { `$Matches[1] } else { '' }
`$in = @([Console]::In.ReadToEnd() -split '\r?\n' | Where-Object { `$_ })
[IO.File]::WriteAllLines('$argsFile.in', [string[]]`$in)
`$in | & '$shell' -NoProfile -NonInteractive -File '$box' -From `$from -Root '$root'
exit `$LASTEXITCODE
"@, $enc)
    if ($env:OS -eq 'Windows_NT') {
        [IO.File]::WriteAllText((Join-Path $bin 'ssh.cmd'), ('@"' + $shell + '" -NoProfile -NonInteractive -File "' + $standIn + '" %*' + "`r`n"), $enc)
    } else {
        $sh = Join-Path $bin 'ssh'
        [IO.File]::WriteAllText($sh, ("#!/bin/sh`nexec '" + $shell + "' -NoProfile -NonInteractive -File '" + $standIn + "' `"`$@`"`n"), $enc)
        & chmod 755 $sh
    }
    Remove-Item Env:THORNSWOOD_NOTICE_KEY_B64, Env:THORNSWOOD_NOTICE_TOKEN -ErrorAction SilentlyContinue
    function SayStaff([string[]]$a) {
        $path = $env:PATH
        $env:PATH = $bin + [IO.Path]::PathSeparator + $path
        try { $out = @(& $shell -NoProfile -NonInteractive -File $say @a -VpsHost 'box.invalid' -VpsUser 'Administrator' 2>&1 | ForEach-Object { "$_" }) }
        finally { $env:PATH = $path }
        return [pscustomobject]@{ Out = ($out -join "`n"); Code = $LASTEXITCODE }
    }
    Fresh
    Remove-Item -LiteralPath $argsFile, "$argsFile.in" -ErrorAction SilentlyContinue
    $text = 'Editing Shell.cs for the scan button, PR to follow.'
    $s = SayStaff @('-From', 'claude', '-Text', $text)
    $rows = @(Rows)
    Yes 'Say-Staff.ps1: queued, exit 0, and the notice is in the outbox from claude' ($s.Code -eq 0 -and $s.Out -match 'queued (agent-claude-\d{14}-[0-9a-f]{6})' -and $rows.Count -eq 1 -and $rows[0].text -eq ('[claude] ' + $text))
    $id = [regex]::Match($s.Out, 'agent-claude-\d{14}-[0-9a-f]{6}').Value
    $sent = @([IO.File]::ReadAllLines($argsFile))
    Yes '  ssh is asked for the box with BatchMode and StrictHostKeyChecking, to run say-staff.ps1 as claude' (
        $sent -contains 'BatchMode=yes' -and $sent -contains 'StrictHostKeyChecking=yes' -and $sent -contains 'Administrator@box.invalid' -and
        $sent[-1] -eq 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Thornswood-Watch\say-staff.ps1 -From claude')
    Yes '  the text went on standard input and is on no command line' (
        -not (($sent -join ' ').Contains('Shell.cs')) -and ([IO.File]::ReadAllText("$argsFile.in")).Trim() -eq (SayLine $text))
    $s = SayStaff @('-Check', $id)
    Yes 'Say-Staff.ps1 -Check: not said yet is exit 2' ($s.Code -eq 2 -and $s.Out -match 'not said yet')
    [IO.File]::WriteAllText((Join-Path $root 'alerts-sent-bot.txt'), "$id`r`n")
    $s = SayStaff @('-Check', $id)
    Yes '  and said by the bot is exit 0' ($s.Code -eq 0 -and $s.Out -match 'posted in #staff-updates, by the bot')

    Remove-Item -LiteralPath $argsFile -ErrorAction SilentlyContinue
    $s = SayStaff @('-From', 'claude', '-Text', ('y' * 1801))
    Yes 'Say-Staff.ps1 refuses a notice over 1800 characters before connecting' ($s.Code -eq 1 -and $s.Out -match '1801 characters' -and -not (Test-Path -LiteralPath $argsFile))
    $s = SayStaff @('-From', 'claude', '-Text', '   ')
    Yes '  and an empty one' ($s.Code -eq 1 -and $s.Out -match 'empty' -and -not (Test-Path -LiteralPath $argsFile))
    $s = SayStaff @('-Text', 'hello')
    Yes '  and one with no -From and no notices key' ($s.Code -eq 1 -and $s.Out -match '-From says who' -and -not (Test-Path -LiteralPath $argsFile))
    $s = SayStaff @('-Check', 'outside-x')
    Yes '  and a check of an id that is not a notice''s' ($s.Code -eq 1 -and -not (Test-Path -LiteralPath $argsFile))
    $env:THORNSWOOD_NOTICE_KEY_B64 = 'AAAA'
    $s = SayStaff @('-From', 'claude', '-Text', 'hello')
    Remove-Item Env:THORNSWOOD_NOTICE_KEY_B64 -ErrorAction SilentlyContinue
    Yes '  and a notices key with no token beside it' ($s.Code -eq 1 -and $s.Out -match 'needs both' -and -not (Test-Path -LiteralPath $argsFile))
    Remove-Item -LiteralPath (Join-Path $root 'watch.ps1')
    $s = SayStaff @('-From', 'claude', '-Text', 'hello')
    Yes 'Say-Staff.ps1 says plainly when the box has no watchdog, exit 1' ($s.Code -eq 1 -and $s.Out -match 'watchdog is not installed')

    # ---- 4b. -OnTheBox: the staff-notice workflow's half (#3045) ----------
    # ssh-keyscan and ssh-keygen stand-ins beside the ssh one: the box shows
    # one key, whose fingerprint is the one a scratch vps.json pins (or not).
    # The first host key the repository's vps.json pins: -OnTheBox reads the
    # pins from there alone, never from a machine's own override file.
    $pin = [string]@((Get-Content -LiteralPath (P 'scripts', 'vps', 'vps.json') -Raw | ConvertFrom-Json).hostKeys)[0]
    $fpFile = Join-Path $tmp 'fingerprint.txt'
    $keyscanIn = Join-Path $tmp 'ssh-keyscan-stand-in.ps1'
    $keygenIn = Join-Path $tmp 'ssh-keygen-stand-in.ps1'
    [IO.File]::WriteAllText($keyscanIn, "'127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBoxhostkeystandin'`n", $enc)
    [IO.File]::WriteAllText($keygenIn, @"
if (`$args -ccontains '-F') { exit 1 }
if (`$args -ccontains '-l') { '256 ' + [IO.File]::ReadAllText('$fpFile').Trim() + ' 127.0.0.1 (ED25519)'; exit 0 }
exit 1
"@, $enc)
    foreach ($pair in @(@('ssh-keyscan', $keyscanIn), @('ssh-keygen', $keygenIn))) {
        if ($env:OS -eq 'Windows_NT') {
            [IO.File]::WriteAllText((Join-Path $bin ($pair[0] + '.cmd')), ('@"' + $shell + '" -NoProfile -NonInteractive -File "' + $pair[1] + '" %*' + "`r`n"), $enc)
        } else {
            $sh = Join-Path $bin $pair[0]
            [IO.File]::WriteAllText($sh, ("#!/bin/sh`nexec '" + $shell + "' -NoProfile -NonInteractive -File '" + $pair[1] + "' `"`$@`"`n"), $enc)
            & chmod 755 $sh
        }
    }
    # The ssh stand-in also keeps what the key and known_hosts files held
    # while it ran, since they are gone once Say-Staff.ps1 ends.
    $seenKey = Join-Path $tmp 'seen-key'
    $seenHosts = Join-Path $tmp 'seen-known-hosts'
    $peek = Join-Path $tmp 'peek.ps1'
    [IO.File]::WriteAllText($peek, @"
`$all = @(`$args | ForEach-Object { [string]`$_ })
`$i = [array]::IndexOf(`$all, '-i')
if (`$i -ge 0) { Copy-Item -LiteralPath `$all[`$i + 1] -Destination '$seenKey' }
`$k = @(`$all | Where-Object { `$_ -like 'UserKnownHostsFile=*' }) | Select-Object -First 1
if (`$k) { Copy-Item -LiteralPath `$k.Substring(19) -Destination '$seenHosts' }
"@, $enc)
    [IO.File]::WriteAllText($standIn, ('. ''' + $peek + "' @args`n" + [IO.File]::ReadAllText($standIn)), $enc)
    # A machine's own vps.json pinning something else, as an earlier job on
    # the runner account could leave: -OnTheBox goes by the repository's.
    $localVps = Join-Path $tmp 'local-vps.json'
    [IO.File]::WriteAllText($localVps, '{"hostKeys":["SHA256:someothermachine00000000000000000000000000"],"user":"elsewhere"}', $enc)
    $fakeKey = "a stand-in for the notices key, which is never read here`n"
    function OnTheBox([string[]]$a, [string]$key) {
        $path = $env:PATH
        $env:PATH = $bin + [IO.Path]::PathSeparator + $path
        $env:THORNSWOOD_VPS_LOCAL = $localVps
        $env:GITHUB_ACTIONS = 'true'
        if ($key) { $env:THORNSWOOD_NOTICE_KEY_B64 = $key } else { Remove-Item Env:THORNSWOOD_NOTICE_KEY_B64 -ErrorAction SilentlyContinue }
        try { $out = @(& $shell -NoProfile -NonInteractive -File $say -OnTheBox @a 2>&1 | ForEach-Object { "$_" }) }
        finally {
            $env:PATH = $path
            Remove-Item Env:THORNSWOOD_VPS_LOCAL, Env:GITHUB_ACTIONS, Env:THORNSWOOD_NOTICE_KEY_B64 -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{ Out = ($out -join "`n"); Code = $LASTEXITCODE }
    }
    Fresh
    Remove-Item -LiteralPath $argsFile, $seenKey, $seenHosts -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($fpFile, $pin)
    $keyB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fakeKey))
    $s = OnTheBox @('-Text', 'From the workflow.') $keyB64
    $rows = @(Rows)
    $sent = @(if (Test-Path -LiteralPath $argsFile) { [IO.File]::ReadAllLines($argsFile) })
    Yes '-OnTheBox: queued, exit 0, and the notice is in the outbox' ($s.Code -eq 0 -and $s.Out -match 'queued agent-' -and $rows.Count -eq 1 -and $rows[0].text -like '*From the workflow.')
    Yes '  it goes to the box''s own sshd at 127.0.0.1 as vps.json''s user, with no ssh config and only the notices key, whatever this machine''s own vps file says' (
        $sent -contains 'Administrator@127.0.0.1' -and ($sent -join ' ') -match '-F none -i \S+ -o IdentitiesOnly=yes' -and ($sent -join ' ') -notmatch 'ProxyCommand')
    Yes '  the key it used is the one in THORNSWOOD_NOTICE_KEY_B64' ((Test-Path -LiteralPath $seenKey) -and [IO.File]::ReadAllText($seenKey) -eq $fakeKey)
    $kh = @($sent | Where-Object { $_ -like 'UserKnownHostsFile=*' })
    Yes '  host keys from a known_hosts of its own holding the pinned key, with StrictHostKeyChecking' (
        $kh.Count -eq 1 -and $sent -contains 'StrictHostKeyChecking=yes' -and (Test-Path -LiteralPath $seenHosts) -and
        ([IO.File]::ReadAllText($seenHosts)).Trim() -eq '127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBoxhostkeystandin')
    $keyAt = $sent[[array]::IndexOf($sent, '-i') + 1]
    Yes '  and the key and known_hosts are gone when it ends' (-not (Test-Path -LiteralPath $keyAt) -and -not (Test-Path -LiteralPath (Split-Path -Parent $keyAt)))
    Yes '  in a GitHub job it leaves the box''s answer as a Say-Staff notice annotation' ($s.Out -match '::notice title=Say-Staff::QUEUED agent-[a-z0-9-]+')

    Remove-Item -LiteralPath $argsFile -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($fpFile, 'SHA256:someothermachine00000000000000000000000000')
    $s = OnTheBox @('-Text', 'hello') $keyB64
    Yes '-OnTheBox: a sshd on 127.0.0.1 that shows no pinned key gets nothing, exit 1, with an error annotation' (
        $s.Code -eq 1 -and $s.Out -match 'pins' -and $s.Out -match '::error title=Say-Staff::' -and -not (Test-Path -LiteralPath $argsFile))
    [IO.File]::WriteAllText($fpFile, $pin)
    $s = OnTheBox @('-Text', 'hello') ''
    Yes '-OnTheBox with no key stops before connecting and names the environment secret' ($s.Code -eq 1 -and $s.Out -match 'NOTICE_KEY_B64 secret of the "notices" environment' -and -not (Test-Path -LiteralPath $argsFile))

    # ---- 4c. with no ssh: through the staff-notice workflow (#3045) --------
    # A path holding only a stand-in for gh, which answers as GitHub does and
    # writes down each call. The run's annotations come from a file per case.
    $bin2 = Join-Path $tmp 'bin2'
    New-Item -ItemType Directory -Path $bin2 -Force | Out-Null
    $ghIn = Join-Path $tmp 'gh-stand-in.ps1'
    $ghCalls = Join-Path $tmp 'gh-calls.txt'
    $ghBody = Join-Path $tmp 'gh-body.json'
    $ghRun = Join-Path $tmp 'gh-run.json'
    $ghNotes = Join-Path $tmp 'gh-annotations.json'
    [IO.File]::WriteAllText($ghIn, @"
`$all = @(`$args | ForEach-Object { [string]`$_ })
[IO.File]::AppendAllText('$ghCalls', ((`$all -join ' ') + "``n"))
`$p = @(`$all | Where-Object { `$_ -like 'repos/*' }) | Select-Object -First 1
if (`$all -contains '--input') { [IO.File]::WriteAllText('$ghBody', [Console]::In.ReadToEnd()) }
switch -Regex (`$p) {
    'actions/workflows/staff-notice\.yml/dispatches$' { '{"workflow_run_id":77,"run_url":"https://api.github.com/x/runs/77","html_url":"https://github.com/x/actions/runs/77"}'; exit 0 }
    'actions/runs/77$' { [IO.File]::ReadAllText('$ghRun'); exit 0 }
    'actions/runs/77/jobs$' { '{"total_count":1,"jobs":[{"id":555}]}'; exit 0 }
    'check-runs/555/annotations$' { [IO.File]::ReadAllText('$ghNotes'); exit 0 }
}
[Console]::Error.WriteLine('gh: Not Found (HTTP 404)')
exit 1
"@, $enc)
    if ($env:OS -eq 'Windows_NT') {
        [IO.File]::WriteAllText((Join-Path $bin2 'gh.cmd'), ('@"' + $shell + '" -NoProfile -NonInteractive -File "' + $ghIn + '" %*' + "`r`n"), $enc)
    } else {
        $sh = Join-Path $bin2 'gh'
        [IO.File]::WriteAllText($sh, ("#!/bin/sh`nexec '" + $shell + "' -NoProfile -NonInteractive -File '" + $ghIn + "' `"`$@`"`n"), $enc)
        & chmod 755 $sh
    }
    $done = '{"status":"completed","conclusion":"success","path":".github/workflows/staff-notice.yml","html_url":"https://github.com/x/actions/runs/77"}'
    function Note([string]$level, [string]$title, [string]$message) { return @{ annotation_level = $level; title = $title; message = $message } }
    function ThroughGitHub([string[]]$a, [string]$run, [object[]]$notes) {
        Remove-Item -LiteralPath $ghCalls, $ghBody -ErrorAction SilentlyContinue
        [IO.File]::WriteAllText($ghRun, $run, $enc)
        [IO.File]::WriteAllText($ghNotes, (ConvertTo-Json -InputObject @($notes) -Compress), $enc)
        $path = $env:PATH
        # Only the stand-in: no ssh is found, the way a cloud container has none.
        $env:PATH = $bin2
        try { $out = @(& $shell -NoProfile -NonInteractive -File $say @a 2>&1 | ForEach-Object { "$_" }) }
        finally { $env:PATH = $path }
        return [pscustomobject]@{
            Out = ($out -join "`n"); Code = $LASTEXITCODE
            Calls = @(if (Test-Path -LiteralPath $ghCalls) { [IO.File]::ReadAllLines($ghCalls) })
            Body = $(if (Test-Path -LiteralPath $ghBody) { ConvertFrom-Json ([IO.File]::ReadAllText($ghBody)) } else { $null })
        }
    }
    $queued = 'QUEUED agent-claude-20261021130000-0a1b2c'
    $text = 'Merged the scan button fix; it goes out with the next dev Ship.'
    $g = ThroughGitHub @('-From', 'claude', '-Text', $text) $done @((Note 'failure' '' 'Process completed with exit code 1.'), (Note 'notice' 'Say-Staff' $queued))
    Yes 'no ssh: it starts staff-notice.yml on main, with the text, and asks for the run' (
        $g.Body -and $g.Body.ref -eq 'main' -and $g.Body.inputs.text -eq $text -and -not $g.Body.inputs.PSObject.Properties['check'] -and $g.Body.return_run_details -eq $true -and
        @($g.Calls | Where-Object { $_ -match '^api -X POST repos/EvilPatrick06/Thornswood/actions/workflows/staff-notice\.yml/dispatches --input -$' }).Count -eq 1)
    Yes '  the text went on gh''s standard input and is on no command line' (-not (($g.Calls -join ' ').Contains('scan button')))
    Yes '  it reads the runner''s Say-Staff annotation off the run''s job and says queued, exit 0' (
        $g.Code -eq 0 -and $g.Out -match 'queued agent-claude-20261021130000-0a1b2c' -and @($g.Calls | Where-Object { $_ -like 'api repos/EvilPatrick06/Thornswood/check-runs/555/annotations*' }).Count -eq 1)
    $g = ThroughGitHub @('-Text', $text) $done @((Note 'notice' 'Say-Staff' $queued))
    Yes '  -From is not needed there' ($g.Code -eq 0 -and $g.Out -match 'queued agent-claude-')
    $g = ThroughGitHub @('-From', 'codex', '-Text', $text) $done @()
    Yes '  and a -From other than the workflow key''s name is refused before anything starts' ($g.Code -eq 1 -and $g.Out -match 'named claude' -and $null -eq $g.Body)
    $g = ThroughGitHub @('-Check', 'agent-claude-20261021130000-0a1b2c') $done @((Note 'notice' 'Say-Staff' 'WAITING'))
    Yes 'no ssh, -Check: the id goes as check, and not said yet is exit 2' (
        $g.Body.inputs.check -eq 'agent-claude-20261021130000-0a1b2c' -and -not $g.Body.inputs.PSObject.Properties['text'] -and $g.Code -eq 2 -and $g.Out -match 'not said yet')
    $g = ThroughGitHub @('-Text', $text) $done @((Note 'notice' 'Say-Staff' 'REFUSED claude has queued 30 notices in the last hour, and 30 is the most.'))
    Yes '  what the box refused is said as the box said it, exit 1' ($g.Code -eq 1 -and $g.Out -match 'the box refused it: claude has queued 30')
    $g = ThroughGitHub @('-Text', $text) $done @((Note 'failure' 'Say-Staff' 'THORNSWOOD_NOTICE_KEY_B64 is not set'))
    Yes '  a runner that stopped says why, exit 1' ($g.Code -eq 1 -and $g.Out -match 'the runner stopped: THORNSWOOD_NOTICE_KEY_B64 is not set')
    $g = ThroughGitHub @('-Text', $text) $done.Replace('"success"', '"failure"') @()
    Yes '  a run that ended with no answer at all points at its log, exit 1' ($g.Code -eq 1 -and $g.Out -match 'without an answer from the box' -and $g.Out -match 'actions/runs/77')
    $g = ThroughGitHub @('-Text', $text, '-WaitMinutes', '0') $done.Replace('"completed"', '"queued"') @()
    Yes '  a run no runner has taken by -WaitMinutes is exit 2, with the line that reads it later' ($g.Code -eq 2 -and $g.Out -match 'Say-Staff\.ps1 -Run 77')
    $g = ThroughGitHub @('-Run', '77') $done @((Note 'notice' 'Say-Staff' 'POSTED bot'))
    Yes '-Run reads that run''s answer, starting nothing' ($g.Code -eq 0 -and $g.Out -match 'by the bot' -and $null -eq $g.Body)
    $g = ThroughGitHub @('-Run', '77') $done.Replace('staff-notice.yml', 'build.yml') @((Note 'notice' 'Say-Staff' 'POSTED bot'))
    Yes '  and refuses a run of another workflow' ($g.Code -eq 1 -and $g.Out -match 'not a staff-notice run')

    # ---- 5. Grant-BoxAccess.ps1's notices key ------------------------------
    $gast = $asts[$grantPath]
    $BridgeRoot = Join-Path $tmp 'bridge'
    $PutBack = 'Thornswood box access put back'
    $SayStaff = 'C:\Thornswood-Watch\say-staff.ps1'
    # The change script carries the folder lock from here, as Grant-BoxAccess.ps1 loads it (#3034).
    . (P 'scripts', 'vps', 'Lock-Folder.ps1')
    foreach ($n in 'Get-BoxKeyLine', 'Read-BoxKeyLine', 'Get-BoxChangeScript') {
        $fn = @($gast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true))
        Yes ("Grant-BoxAccess.ps1 has one $n") ($fn.Count -eq 1)
        Invoke-Expression $fn[0].Extent.Text
    }
    Yes 'Grant-BoxAccess.ps1 says the forced command is say-staff.ps1 in the watchdog''s folder' ([IO.File]::ReadAllText($grantPath).Contains("`$SayStaff = 'C:\Thornswood-Watch\say-staff.ps1'"))
    $pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGRZxJ2G1nGDrjqLMTed+Bui13icdTMAODXpx0ZQd55T'
    $plain = Get-BoxKeyLine $pub 'djinn' $false
    $notice = Get-BoxKeyLine $pub 'codex' $true
    Yes 'an ordinary key line is as it was: from="127.0.0.1" <key> thornswood-<name>' ($plain -eq ('from="127.0.0.1" ' + $pub + ' thornswood-djinn'))
    Yes 'a notices key line: only through the bridge, restricted, forced to say-staff.ps1 as its own name' (
        $notice -eq ('from="127.0.0.1",restrict,command="powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Thornswood-Watch\say-staff.ps1 -From codex" ' + $pub + ' thornswood-codex'))
    $rp = Read-BoxKeyLine $plain
    $rn = Read-BoxKeyLine $notice
    Yes '-List reads an ordinary line: its key, through the bridge, not a notices key' ($rp.Key -eq $pub -and $rp.Bridge -and -not $rp.Notices)
    Yes '-List reads a notices line: its key, through the bridge, a notices key' ($rn.Key -eq $pub -and $rn.Bridge -and $rn.Notices)
    $ro = Read-BoxKeyLine ($pub + ' thornswood')
    $rw = Read-BoxKeyLine ('command="powershell.exe -File C:\Thornswood-Watch\say-staff.ps1 -From codex" ' + $pub + ' thornswood-codex')
    Yes '  and a line with no options, which any address may use' ($ro.Key -eq $pub -and -not $ro.Bridge -and -not $ro.Notices)
    Yes '  and a forced command without restrict is not called a notices key' ($rw.Key -eq $pub -and -not $rw.Notices)

    # The box change with say-staff.ps1 missing, against a scratch key file.
    $keys = Join-Path $tmp 'administrators_authorized_keys'
    New-Item -ItemType Directory -Path (Join-Path $BridgeRoot 'tokens') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $BridgeRoot 'bridge.js'), '// stand-in')
    [IO.File]::WriteAllLines($keys, [string[]]@('from="127.0.0.1" ssh-ed25519 AAAAcloudkey thornswood-cloud'))
    $global:Armed = $false
    $stubs = @'
function Get-ScheduledTask { param($TaskName, $EA, $ErrorAction) if ($global:Armed) { 'a task' } }
function Register-ScheduledTask { $global:Armed = $true }
function icacls { }
'@
    $missing = Join-Path $tmp 'no-such-say-staff.ps1'
    $script = (Get-BoxChangeScript 'codex' ('d' * 64) $notice (($pub -split ' ')[1]) $missing).Replace('C:\ProgramData\ssh\administrators_authorized_keys', $keys).Replace('; exit 1 }', '; return }')
    $out = @(& ([scriptblock]::Create($stubs + "`n" + $script)) 2>&1 | ForEach-Object { "$_" })
    Yes 'a notices grant with no say-staff.ps1 on the box: STOP, nothing armed, nothing changed' (
        ($out -join ' ') -match '^STOP there is no .*no-such-say-staff\.ps1 on the box' -and -not $global:Armed -and
        @([IO.File]::ReadAllLines($keys)).Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path (Join-Path $BridgeRoot 'tokens') 'codex')))

    # It looks for ssh and ssh-keygen before it reads its switches.
    if ((Get-Command ssh -ErrorAction SilentlyContinue) -and (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        $g = @(& $shell -NoProfile -NonInteractive -File $grantPath -Name codex -FromClipboard -NoticesOnly -NoPause 2>&1 | ForEach-Object { "$_" }) -join ' '
        Yes 'Grant-BoxAccess.ps1 -NoticesOnly without -MakeKey stops before anything is done' ($g -match '-NoticesOnly goes with -MakeKey')
    } else { Write-Host 'SKIP  Grant-BoxAccess.ps1 -NoticesOnly without -MakeKey: no ssh here, and it stops on that first' }

    # ---- 5b. -ToEnvironment: the workflow's key on GitHub (#3045) ----------
    # Set-MainOnlyEnvironment against a stand-in gh, a function here, which
    # answers each GET from the case's table and writes down each call.
    foreach ($n in 'Invoke-GitHub', 'Set-MainOnlyEnvironment') {
        $fn = @($gast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true))
        Yes ("Grant-BoxAccess.ps1 has one $n") ($fn.Count -eq 1)
        Invoke-Expression $fn[0].Extent.Text
    }
    $GitHubRepo = 'EvilPatrick06/Thornswood'
    function Say { }
    function Die([string]$m) { throw "DIE $m" }
    $script:ghAnswers = @{}
    $script:ghCalls = @()
    function gh {
        $all = @($args | ForEach-Object { [string]$_ })
        $body = @($input) -join ''
        $script:ghCalls += ,(($all -join ' ') + $(if ($body) { ' <<' + $body } else { '' }))
        $method = $all[[array]::IndexOf($all, '-X') + 1]
        $path = @($all | Where-Object { $_ -like 'repos/*' })[0]
        $key = $method + ' ' + $path
        if ($script:ghAnswers.ContainsKey($key)) { $global:LASTEXITCODE = $script:ghAnswers[$key][0]; return $script:ghAnswers[$key][1] }
        $global:LASTEXITCODE = 0
        return '{}'
    }
    function EnvCase([hashtable]$answers) {
        $script:ghAnswers = $answers
        $script:ghCalls = @()
        $err = ''
        try { Set-MainOnlyEnvironment 'notices' } catch { $err = $_.Exception.Message }
        return [pscustomobject]@{ Err = $err; Calls = $script:ghCalls; Changes = @($script:ghCalls | Where-Object { $_ -notmatch '^api -X GET ' }) }
    }
    $envPath = 'repos/EvilPatrick06/Thornswood/environments/notices'
    $c = EnvCase @{ ("GET " + $envPath) = @(1, 'gh: Not Found (HTTP 404)') }
    Yes '-ToEnvironment: no environment yet, so it is made for chosen branches and main is the one let in' (
        -not $c.Err -and $c.Changes.Count -eq 2 -and
        $c.Changes[0] -eq ('api -X PUT ' + $envPath + ' --input - <<{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}') -and
        $c.Changes[1] -eq ('api -X POST ' + $envPath + '/deployment-branch-policies --input - <<{"name":"main","type":"branch"}'))
    $custom = '{"name":"notices","deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
    $c = EnvCase @{ ("GET " + $envPath) = @(0, $custom); ("GET " + $envPath + '/deployment-branch-policies?per_page=100') = @(0, '{"total_count":1,"branch_policies":[{"id":1,"name":"main","type":"branch"}]}') }
    Yes '  there already, for main only: nothing is changed' (-not $c.Err -and $c.Changes.Count -eq 0)
    $c = EnvCase @{ ("GET " + $envPath) = @(0, $custom); ("GET " + $envPath + '/deployment-branch-policies?per_page=100') = @(0, '{"total_count":2,"branch_policies":[{"id":1,"name":"main","type":"branch"},{"id":2,"name":"claude/*","type":"branch"}]}') }
    Yes '  there, and another branch let in too: it stops, naming it, and changes nothing' ($c.Err -match '^DIE .*branch claude/\*' -and $c.Changes.Count -eq 0)
    $c = EnvCase @{ ("GET " + $envPath) = @(0, '{"name":"notices","deployment_branch_policy":null}') }
    Yes '  there with every branch let in: it is narrowed to main' ($c.Err -eq '' -and $c.Changes.Count -eq 2 -and $c.Changes[1] -match '"name":"main"')
    $c = EnvCase @{ ("GET " + $envPath) = @(1, 'gh: Must have admin rights to Repository. (HTTP 403)') }
    Yes '  GitHub refusing the read stops it, changing nothing' ($c.Err -match '^DIE .*HTTP 403' -and $c.Changes.Count -eq 0)
    $grantText = [IO.File]::ReadAllText($grantPath)
    Yes 'the key goes to gh secret set NOTICE_KEY_B64 for that environment on its standard input, and to no file' (
        $grantText -match [regex]::Escape('[Convert]::ToBase64String([IO.File]::ReadAllBytes($newKey)) | & gh secret set NOTICE_KEY_B64 --env $ToEnvironment --repo $GitHubRepo') -and
        $grantText.IndexOf('if ($ToEnvironment) {', $grantText.IndexOf('Proving the new key through the bridge')) -lt $grantText.IndexOf('notice-access.txt', $grantText.IndexOf('Proving the new key through the bridge')))
    Yes '  and the environment is settled before the box is touched' ($grantText.IndexOf('Set-MainOnlyEnvironment $ToEnvironment') -lt $grantText.IndexOf('Get-BoxChangeScript $Name'))

    # ---- 6. .github\workflows\staff-notice.yml (#3045) ---------------------
    $wfPath = P '.github', 'workflows', 'staff-notice.yml'
    Yes 'staff-notice.yml is there' (Test-Path -LiteralPath $wfPath)
    $wf = ([IO.File]::ReadAllText($wfPath)) -replace "`r`n", "`n"
    $on = [regex]::Match($wf, '(?ms)^on:\n(.*?)^\S').Groups[1].Value
    Yes 'it is started by hand (workflow_dispatch) and by nothing else' ($on -match '(?m)^  workflow_dispatch:\s*$' -and @([regex]::Matches($on, '(?m)^  [a-z_]+:')).Count -eq 1)
    Yes '  with a text and a check input, neither required' ($on -match '(?ms)^      text:\n.*?required: false' -and $on -match '(?ms)^      check:\n.*?required: false')
    $perm = [regex]::Match($wf, '(?ms)^permissions:\n(.*?)^\S').Groups[1].Value
    $grants = @([regex]::Matches($perm, '(?m)^\s+([a-z-]+):\s*(\S+)') | ForEach-Object { $_.Groups[1].Value + ': ' + $_.Groups[2].Value })
    Yes ('its token can read the repository and nothing more (' + ($grants -join ', ') + '), and no job widens it') ($grants.Count -eq 1 -and $grants[0] -eq 'contents: read' -and @([regex]::Matches($wf, '(?m)^\s+permissions:')).Count -eq 0)
    $runsOn = [regex]::Match($wf, '(?m)^\s*runs-on:\s*(.+)$').Groups[1].Value.Trim()
    Yes ('it runs on the VPS runners, which are on the box the key works from (' + $runsOn + ')') ($runsOn -eq '[self-hosted, Windows, thornswood-vps]')
    Yes '  in the "notices" environment, with a timeout' ($wf -match '(?m)^    environment:\s*notices\s*$' -and $wf -match '(?m)^\s+timeout-minutes:\s*\d+\s*$')
    Yes '  the key is that environment''s NOTICE_KEY_B64, handed over as THORNSWOOD_NOTICE_KEY_B64' ($wf -match [regex]::Escape('THORNSWOOD_NOTICE_KEY_B64: ${{ secrets.NOTICE_KEY_B64 }}') -and @([regex]::Matches($wf, 'secrets\.')).Count -eq 1)
    Yes '  the checkout keeps no token in the runner''s folder' ($wf -match '(?ms)uses: actions/checkout@[0-9a-f]{40}[^\n]*\n\s+with:\n\s+persist-credentials: false')
    Yes '  its script runs under pwsh with no profile' ($wf -match [regex]::Escape('shell: pwsh -NoProfile -NonInteractive -Command ". ''{0}''"'))
    $run = [regex]::Match($wf, '(?ms)^(\s+)run: \|\n(.*)$')
    $wfScript = ''
    if ($run.Success) {
        $lines = $run.Groups[2].Value -split "`n"
        $indent = [regex]::Match($lines[0], '^\s*').Value
        $body = @()
        foreach ($l in $lines) {
            if ($l.Trim().Length -and -not $l.StartsWith($indent)) { break }
            $body += $(if ($l.Length -ge $indent.Length) { $l.Substring($indent.Length) } else { '' })
        }
        $wfScript = ($body -join "`n").TrimEnd() + "`n"
    }
    Yes 'the script has no ${{ }} in it: the text and the id come in through the environment' ($wfScript.Length -gt 0 -and $wfScript -notmatch '\$\{\{' -and
        $wf -match [regex]::Escape('NOTICE_TEXT: ${{ inputs.text }}') -and $wf -match [regex]::Escape('NOTICE_CHECK: ${{ inputs.check }}'))
    $sayText = [IO.File]::ReadAllText($say)
    Yes 'Say-Staff.ps1 starts this workflow by its file name, and says notices through it are from claude' (
        $sayText.Contains("`$workflow = 'staff-notice.yml'") -and $sayText.Contains("`$workflowSender = 'claude'") -and $wf.Contains('-Name claude -MakeKey -NoticesOnly'))

    # The script itself, against a stand-in Say-Staff.ps1 that writes down how
    # it was called and exits with the case's code.
    $ws = Join-Path $tmp 'workspace'
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $ws 'scripts') 'ops') -Force | Out-Null
    $called = Join-Path $tmp 'called.txt'
    [IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $ws 'scripts') 'ops') 'Say-Staff.ps1'), @"
param([switch]`$OnTheBox, [string]`$Text, [string]`$Check)
[IO.File]::WriteAllText('$called', ('OnTheBox=' + `$OnTheBox + ' Text=' + `$Text + ' Check=' + `$Check))
exit [int]`$env:STAND_IN_EXIT
"@, $enc)
    $wfFile = Join-Path $tmp 'staff-notice-step.ps1'
    [IO.File]::WriteAllText($wfFile, $wfScript, $enc)
    function Step([string]$text, [string]$check, [int]$exit) {
        Remove-Item -LiteralPath $called -ErrorAction SilentlyContinue
        $env:GITHUB_WORKSPACE = $ws; $env:NOTICE_TEXT = $text; $env:NOTICE_CHECK = $check; $env:STAND_IN_EXIT = [string]$exit
        try { $out = @(& $shell -NoProfile -NonInteractive -Command ". '$wfFile'" 2>&1 | ForEach-Object { "$_" }) }
        finally { Remove-Item Env:GITHUB_WORKSPACE, Env:NOTICE_TEXT, Env:NOTICE_CHECK, Env:STAND_IN_EXIT -ErrorAction SilentlyContinue }
        return [pscustomobject]@{ Out = ($out -join "`n"); Code = $LASTEXITCODE; Called = $(if (Test-Path -LiteralPath $called) { [IO.File]::ReadAllText($called) } else { '' }) }
    }
    $st = Step 'Merged it.' '' 0
    Yes 'the step: a text is said with -OnTheBox, exit 0' ($st.Code -eq 0 -and $st.Called -eq 'OnTheBox=True Text=Merged it. Check=')
    $st = Step '' 'agent-claude-1' 2
    Yes '  an id is checked, and "not said yet" (2) is a green run' ($st.Code -eq 0 -and $st.Called -eq 'OnTheBox=True Text= Check=agent-claude-1')
    $st = Step 'Merged it.' '' 1
    Yes '  Say-Staff.ps1 stopping turns the run red' ($st.Code -eq 1)
    $st = Step 'Merged it.' 'agent-claude-1' 0
    Yes '  both, or neither, is refused with a Say-Staff error and nothing is run' ($st.Code -eq 1 -and $st.Out -match '::error title=Say-Staff::' -and -not $st.Called -and (Step '' '' 0).Code -eq 1)
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
exit 0
