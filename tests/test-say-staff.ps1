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
    5. Grant-BoxAccess.ps1: a notices key's line is taken only through the
       bridge and only runs say-staff.ps1 as its own name; -List reads that
       back; the box change stops with nothing changed when say-staff.ps1 is
       not there; and -NoticesOnly goes only with -MakeKey.
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
print('DUE ' + json.dumps(bot.watch_alerts_due(lines, set(), int(time.time()))))
"@
        $pyFile = Join-Path $tmp 'probe.py'
        [IO.File]::WriteAllText($pyFile, $code, $enc)
        $probe = (@(& $py.Source -I $pyFile (P 'bot') $alerts 2>&1 | ForEach-Object { "$_" }) | Where-Object { $_ -match '^(SKIP|DUE) ' } | Select-Object -Last 1)
        Remove-Item Env:DISCORD_TOKEN -ErrorAction SilentlyContinue
    }
    if ($probe -like 'DUE *') {
        $due = ConvertFrom-Json $probe.Substring(4)
        Yes 'bot.py watch_alerts_due takes the line the box half wrote, with its text' (@($due).Count -eq 1 -and ('QUEUED ' + $due[0][0]) -eq $r.Last -and $due[0][1] -eq '[cloud] for the bot')
    } else {
        Write-Host ('SKIP  bot.py could not be imported here (' + $(if ($probe) { $probe } else { 'no python' }) + '); bot\test-watch-services.py covers its reader')
    }

    # ---- 4. Say-Staff.ps1 end to end -----------------------------------------
    # A stand-in for ssh: writes down what it was given, then runs the box
    # half with what came on its input, the way sshd would.
    $standIn = Join-Path $tmp 'ssh-stand-in.ps1'
    $argsFile = Join-Path $tmp 'ssh-args.txt'
    [IO.File]::WriteAllText($standIn, @"
`$all = @(`$args | ForEach-Object { [string]`$_ })
[IO.File]::WriteAllLines('$argsFile', [string[]]`$all)
`$cmd = `$all[-1]
`$from = if (`$cmd -match '-From ([a-z0-9-]+)`$') { `$Matches[1] } else { '' }
`$in = @(`$input)
[IO.File]::WriteAllLines('$argsFile.in', [string[]]`$in)
`$in | & '$shell' -NoProfile -NonInteractive -File '$box' -From `$from -Root '$root'
"@, $enc)
    Remove-Item Env:THORNSWOOD_NOTICE_KEY_B64, Env:THORNSWOOD_NOTICE_TOKEN -ErrorAction SilentlyContinue
    function SayStaff([string[]]$a) {
        $out = @(& $shell -NoProfile -NonInteractive -File $say @a -SshCommand $standIn -VpsHost 'box.invalid' -VpsUser 'Administrator' 2>&1 | ForEach-Object { "$_" })
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

    # ---- 5. Grant-BoxAccess.ps1's notices key ------------------------------
    $gast = $asts[$grantPath]
    $BridgeRoot = Join-Path $tmp 'bridge'
    $PutBack = 'Thornswood box access put back'
    $SayStaff = 'C:\Thornswood-Watch\say-staff.ps1'
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
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
exit 0
