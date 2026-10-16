<#
  test-2351-delete-person.ps1

      pwsh -NoProfile -File .\tests\test-2351-delete-person.ps1

  Issue #2351: a deletion request is carried out across every store with one
  action, a synthetic person's records are deleted end to end, the record of
  completed requests has a named restricted place, and a restore reapplies
  it before service opens (Patrick, 12 Oct 2026, option A).

  This builds stand-ins of every store scripts\vps\Delete-Person.ps1 knows,
  in a scratch folder under the temp folder, for one person who asked, one
  who did not and a character the two share, and runs the real script under
  Windows PowerShell 5.1, which is what runs it on the VPS:

    - the dry run changes no byte and says, by count, what a real run removes,
      what it keeps and which services it would stop
    - it refuses a Discord id that is not one, -Delete without -By, -Merge
      without -Reapply, a store that will not parse, and an unfinished save,
      each with nothing changed
    - the real run removes every record of theirs in every store, live and
      in every copy set aside beside it, keeps staff's records and reports and
      a session staff marked kept, leaves the shared character and everybody
      else's records as they were, takes their lines out of each chat day and
      leaves the other lines byte for byte
    - it writes one line to the record, with no name, no address and nothing
      a record said, in a folder only SYSTEM and Administrators can open
    - after the stand-ins are put back as a backup would put them, -Reapply
      removes it all again and adds no line; -Merge adds a request from
      another copy of the record and removes that one too, once
    - the nightly backup takes the record, Restore-Box.ps1 reapplies it from
      the backup before anything starts, and docs\RESTORING.md says so

  Nothing leaves this machine and nothing runs from the stand-ins.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$Script = Join-Path $Repo 'scripts\vps\Delete-Person.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$tokens, [ref]$errors)
Yes 'Delete-Person.ps1 parses' ($errors.Count -eq 0)

# ---- the rest of the chain, read --------------------------------------------
$nightly = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\vps\vps-nightly-backup.ps1'))
Yes 'the nightly backup takes the record of completed requests as deletions\requests.jsonl' (
    $nightly -match "Grab \(Join-Path \`$DeletionRoot 'requests\.jsonl'\)\s+'deletions\\requests\.jsonl'")
$boxText = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\vps\Restore-Box.ps1'))
Yes 'Restore-Box.ps1 sends Delete-Person.ps1 with the restore scripts' ($boxText -match "'Delete-Person\.ps1'")
$reAt = $boxText.IndexOf("OnBox 'Delete-Person.ps1'")
$svAt = $boxText.IndexOf("OnBox 'vps-restore-services.ps1'")
$rmAt = $boxText.IndexOf("Head 'Taking the copy off the box'")
Yes '  and reapplies the record, merged with the backup''s, after the restores and before the copy is taken off' (
    $reAt -gt $svAt -and $svAt -gt 0 -and $rmAt -gt $reAt -and
    $boxText -match "OnBox 'Delete-Person\.ps1' ""-Reapply -Delete -Merge \`$far\\unpacked\\deletions\\requests\.jsonl""")
$restoring = [IO.File]::ReadAllText((Join-Path $Repo 'docs\RESTORING.md'))
Yes 'docs\RESTORING.md names the reapply step' ($restoring -match 'Delete-Person\.ps1 -Reapply')
$ops = [IO.File]::ReadAllText((Join-Path $Repo 'docs\WEBSITE-OPERATIONS.md'))
$at = $ops.IndexOf("`n## Deletion requests")
Yes 'docs\WEBSITE-OPERATIONS.md has the procedure, "Deletion requests"' ($at -ge 0)
if ($at -ge 0) {
    $end = $ops.IndexOf("`n## ", $at + 5)
    $pt = if ($end -gt 0) { $ops.Substring($at, $end - $at) } else { $ops.Substring($at) }
    Yes '  and names the dry run, the real run, the record and the reapply' (
        $pt -match '-DiscordId' -and $pt -match '-Delete -By' -and $pt -match 'C:\\Thornswood-Deletions\\requests\.jsonl' -and $pt -match '-Reapply')
}

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $env:SystemRoot -or -not (Test-Path -LiteralPath $ps51)) {
    Write-Host 'SKIP  the runs need Windows PowerShell 5.1, which runs this on the VPS'
    Done
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP  the runs need node, which the script edits the JSON with'
    Done
}

$script:last = @()
function Run([string[]]$argv) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $script:last = @(& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @argv 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $eap }
    return $LASTEXITCODE
}
function Show { foreach ($l in $script:last | Select-Object -Last 40) { Write-Host ('        ' + $l) } }
function Said([string]$pattern) { return (($script:last -join "`n") -match ('(?m)' + $pattern)) }
function Put([string]$path, [string]$text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text)
}
function Get([string]$path) { if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) } return $null }
function J([string]$path) { return ((Get $path) | ConvertFrom-Json) }
function Hashes([string]$root) {
    $h = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)) { $h[$f.FullName.Substring($root.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
    return $h
}
function Same($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if ($b[$k] -ne $a[$k]) { return $false } }
    return $true
}

$T = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-2351-' + [Guid]::NewGuid().ToString('N'))
$Box = Join-Path $T 'box'
$Rec = Join-Path $T 'Thornswood-Deletions'
$Site = Join-Path $Box 'Thornswood-Docs'
$Live = Join-Path $Box 'Thornswood-Server'
$Dev  = Join-Path $Box 'Thornswood-Server-Dev'
$Vl   = Join-Path $Box 'Thornswood-Voice'
$Vd   = Join-Path $Box 'Thornswood-Voice-Dev'
$Bot  = Join-Path $Box 'Thornswood-Bot'
$roots = @('-SiteRoot', $Site, '-GameRoot', $Live, '-DevGameRoot', $Dev, '-VoiceRoot', $Vl, '-DevVoiceRoot', $Vd, '-BotRoot', $Bot, '-RecordRoot', $Rec, '-NoServices', '-AllowGamingPc')

$ME = '111111111111111111'      # asked to be deleted
$YOU = '222222222222222222'     # did not
$THEM = '333333333333333333'    # asked, in another copy of the record
$P1 = 5001; $P2 = 5002          # P2 is held by both accounts
$PY = 6001; $PT = 7001

function Build {
    if (Test-Path -LiteralPath $Box) { Remove-Item -LiteralPath $Box -Recurse -Force }
    $D = Join-Path $Site 'data'
    Put (Join-Path $D 'linked.json') ('{"' + $ME + '":{"name":"Me","profiles":[' + $P1 + ',' + $P2 + ']},"' + $YOU + '":{"name":"You","profiles":[' + $PY + ',' + $P2 + ']},"' + $THEM + '":{"name":"Them","profiles":[' + $PT + ']}}')
    Put (Join-Path $D 'rules-accepted.json') ('{"' + $ME + '":{"yes":true},"' + $YOU + '":{"yes":true}}')
    Put (Join-Path $D 'signins.json') ('[{"id":"' + $ME + '","ip":"203.0.113.1"},{"id":"' + $YOU + '","ip":"203.0.113.2"},{"id":"' + $ME + '","ip":"203.0.113.3"}]')
    Put (Join-Path $D 'sessions.json') ('[{"session":"s1","who":"' + $ME + '","profile":' + $P1 + '},{"session":"s2","who":"' + $ME + '","profile":' + $P1 + ',"keep":true},{"session":"s3","who":"' + $YOU + '","profile":' + $PY + '},{"session":"s4","who":"' + $THEM + '","profile":' + $PT + '}]')
    Put (Join-Path $D 'session-logs\s1.json') ('{"session":"s1","who":"' + $ME + '","logs":{"launcher.log":"x"}}')
    Put (Join-Path $D 'session-logs\s2.json') ('{"session":"s2","who":"' + $ME + '","logs":{"launcher.log":"kept"}}')
    Put (Join-Path $D 'session-logs\s3.json') ('{"session":"s3","who":"' + $YOU + '","logs":{"launcher.log":"y"}}')
    Put (Join-Path $D 'session-logs\s4.json') ('{"session":"s4","who":"' + $THEM + '","logs":{"launcher.log":"t"}}')
    Put (Join-Path $D 'for-bot\trouble.json') ('[{"session":"s1","who":"' + $ME + '","profile":' + $P1 + '},{"session":"s2","who":"' + $ME + '","profile":' + $P1 + '},{"session":"s3","who":"' + $YOU + '","profile":' + $PY + '}]')
    Put (Join-Path $D 'for-bot\inbox.json') ('[{"kind":"ticket","ticket":"apply","discordId":"' + $ME + '"},{"kind":"help","profileId":' + $P1 + '},{"kind":"report","profileId":' + $P1 + ',"aboutProfileId":' + $PY + '},{"kind":"report","profileId":' + $PY + ',"aboutProfileId":' + $P1 + '},{"kind":"ticket","discordId":"' + $YOU + '"},{"kind":"help","profileId":' + $P2 + '}]')
    Put (Join-Path $D 'for-bot\moderation.log') ('{"what":"note","pid":' + $P1 + '}' + "`n" + '{"what":"ban","pid":' + $PY + '}' + "`n")
    Put (Join-Path $D 'roster.json') ('{"who":{"' + $P1 + '":{"name":"Mine"},"' + $P2 + '":{"name":"Shared"},"' + $PY + '":{"name":"Yours"}},"servers":{"main":{"checked":[' + $P1 + ',' + $PY + '],"held":[' + $P1 + ']}}}')
    Put (Join-Path $D 'gallery-pending.json') ('[{"name":"20261001-mine.png","by":"Me","discordId":"' + $ME + '"},{"name":"20261001-yours.png","by":"You","discordId":"' + $YOU + '"}]')
    # Approved: one of theirs, one of theirs with an open report, one from
    # before the uploads note kept an account, and one of somebody else's.
    Put (Join-Path $D 'gallery.json') '[{"name":"20260901-old.png","url":"/shot/20260901-old.png","by":"Me"},{"name":"20261002-approved.png","url":"/shot/20261002-approved.png","by":"Me"},{"name":"20261003-reported.png","url":"/shot/20261003-reported.png","by":"Me"},{"name":"20261004-yours.png","url":"/shot/20261004-yours.png","by":"You"}]'
    Put (Join-Path $D 'gallery-reports.json') ('[{"name":"20260901-old.png","why":"x","discordId":"' + $ME + '"},{"name":"20261003-reported.png","why":"y","discordId":"' + $YOU + '"}]')
    foreach ($n in '20261001-mine.png', '20261001-yours.png', '20260901-old.png', '20261002-approved.png', '20261003-reported.png', '20261004-yours.png') { Put (Join-Path $Site ('uploads\' + $n)) $n }
    Put (Join-Path $Site 'uploads\uploads.json') ('{"20261001-mine.png":{"by":"Me","discordId":"' + $ME + '"},"20261001-yours.png":{"by":"You","discordId":"' + $YOU + '"},"20260901-old.png":{"by":"Me"},"20261002-approved.png":{"by":"Me","discordId":"' + $ME + '"},"20261003-reported.png":{"by":"Me","discordId":"' + $ME + '"},"20261004-yours.png":{"by":"You","discordId":"' + $YOU + '"}}')
    Put (Join-Path $D 'bans.json') ('{"' + $ME + '":{"why":"x"}}')
    Put (Join-Path $D 'notes.json') ('{"p:' + $P1 + '":[{"text":"a"},{"text":"b"}]}')
    Put (Join-Path $D 'pk.json') ('{"' + $P1 + '":{"why":"x"}}')
    # A copy of the site's data a restore set aside.
    $A = Join-Path $Site 'data-before-restore-20261001-010101'
    Put (Join-Path $A 'linked.json') ('{"' + $ME + '":{"name":"Me","profiles":[' + $P1 + ']}}')
    Put (Join-Path $A 'signins.json') ('[{"id":"' + $ME + '","ip":"203.0.113.1"}]')

    foreach ($g in @(@{ R = $Live; Tag = 'live' }, @{ R = $Dev; Tag = 'dev' })) {
        $R = $g.R
        $CF = Join-Path $R 'world\changeForms'
        Put (Join-Path $CF 'ff000a01.json') ('{"formDesc":"ff000a01","profileId":' + $P1 + ',"isDeleted":false}')
        Put (Join-Path $CF 'ff000a02.json') ('{"formDesc":"ff000a02","profileId":' + $PY + '}')
        Put (Join-Path $CF 'ff000a03.json') ('{"formDesc":"ff000a03","profileId":' + $P2 + '}')
        Put (Join-Path $CF 'ff000a04.json') ('{"formDesc":"ff000a04","profileId":' + $PT + '}')
        Put (Join-Path $CF '1a2b3.json') '{"formDesc":"1a2b3:Skyrim.esm","profileId":-1}'
        Put (Join-Path $CF '_discarded-20261002-000000\ff000a05.json') ('{"profileId":' + $P1 + '}')
        Put (Join-Path $R 'world-before-20260930-000000\changeForms\ff000a06.json') ('{"profileId":' + $P1 + '}')
        $PV = Join-Path $R 'private'
        Put (Join-Path $PV 'characters.json') ('{"who":{"' + $P1 + '":{"name":"Mine"},"' + $PY + '":{"name":"Yours"},"' + $PT + '":{"name":"Theirs"}}}')
        Put (Join-Path $PV 'characters-before-20260930-000000.json') ('{"who":{"' + $P1 + '":{"name":"Mine"}}}')
        Put (Join-Path $PV 'mod-settings.json') ('{"who":{"' + $P1 + '":{"a":1},"' + $PY + '":{"a":2}}}')
        Put (Join-Path $PV 'take-limit.json') ('{"counts":{"' + $P1 + '|1a2b3":{"n":1},"' + $PY + '|1a2b3":{"n":2}}}')
        Put (Join-Path $PV 'property.json') ('{"houses":[{"id":"h1","owner":' + $P1 + '},{"id":"h2","owner":' + $PY + '}]}')
        Put (Join-Path $PV 'moderation.log') ('{"what":"stuck","pid":' + $P1 + '}' + "`n")
        Put (Join-Path $PV 'door.log') ("2026-10-01 WOULD TURN AWAY profile $P1`n")
        Put (Join-Path $R 'data\last-left.json') ('{"' + $P1 + '":1790000000000,"' + $PY + '":1790000000001}')
        Put (Join-Path $R 'data\online.json') '{"now":0}'
    }
    Put (Join-Path $Box 'Thornswood-Server.prev-20261001-000000\world\changeForms\ff000a07.json') ('{"profileId":' + $P1 + '}')

    $mine = '{"at":1,"kind":"say","profileId":' + $P1 + ',"name":"Mine","text":"hello"}'
    $yours = '{"at":2,"kind":"say","profileId":' + $PY + ',"name":"Yours","text":"hi"}'
    $shared = '{"at":3,"kind":"say","profileId":' + $P2 + ',"name":"Shared","text":"hey"}'
    Put (Join-Path $Vl 'chat\2026-10-01.jsonl') ($mine + "`n" + $yours + "`n" + $mine + "`n" + $shared + "`n")
    Put (Join-Path $Vl 'chat\2026-10-02.jsonl') ($yours + "`n")
    Put (Join-Path $Vd 'chat\2026-10-01.jsonl') ($mine + "`n")
    Put (Join-Path $Bot 'data\joins.json') ('{"900":{"last":40,"members":{"' + $ME + '":39,"' + $YOU + '":40}}}')
    Put (Join-Path $Bot 'data\open-tickets.json') ('{"900:' + $ME + '":123,"900:' + $YOU + '":456}')
}

try {
    Build
    $before = Hashes $Box

    # ---- refusals ---------------------------------------------------------------
    $c = Run (@('-DiscordId', '12345') + $roots)
    Yes 'a Discord id that is not 17 to 20 digits is refused' ($c -eq 1 -and (Said 'REFUSED: -DiscordId takes a Discord id'))
    $c = Run (@('-DiscordId', $ME, '-Delete') + $roots)
    Yes '-Delete without -By is refused' ($c -eq 1 -and (Said 'REFUSED: -Delete needs -By'))
    $c = Run (@('-DiscordId', $ME, '-Merge', 'x.jsonl') + $roots)
    Yes '-Merge without -Reapply is refused' ($c -eq 1 -and (Said 'REFUSED: -Merge goes with -Reapply'))
    if (Test-Path -LiteralPath 'C:\Thornswood\Game\SkyrimSE.exe') {
        $c = Run (@('-DiscordId', $ME) + ($roots | Where-Object { $_ -ne '-AllowGamingPc' }))
        Yes 'on a gaming PC it refuses without -AllowGamingPc' ($c -eq 1 -and (Said 'this is a gaming PC'))
    }
    $roster = Join-Path $Site 'data\roster.json'
    $keepRoster = Get $roster
    Put $roster '{"who":'
    $c = Run (@('-DiscordId', $ME, '-Delete', '-By', 'Tester') + $roots)
    Yes 'a store that will not parse refuses the run' ($c -eq 1 -and (Said 'roster\.json will not parse, so nothing was changed'))
    Put $roster $keepRoster
    $pend = Join-Path $Dev 'world\changeForms\.pending-batch'
    Put $pend '{}'
    $c = Run (@('-DiscordId', $ME, '-Delete', '-By', 'Tester') + $roots)
    Yes 'an unfinished save in a game server refuses the run' ($c -eq 1 -and (Said '\.pending-batch is an unfinished save'))
    Remove-Item -LiteralPath $pend -Force
    Yes '  and none of the refusals changed a byte or wrote a record' ((Same $before (Hashes $Box)) -and -not (Test-Path -LiteralPath $Rec))

    # ---- the dry run --------------------------------------------------------------
    $c = Run (@('-DiscordId', $ME) + $roots)
    $dry = $script:last
    Yes 'the dry run ends 0 and says it changed nothing' ($c -eq 0 -and (Said 'DRY RUN: nothing was changed'))
    Yes '  and changed no byte and wrote no record' ((Same $before (Hashes $Box)) -and -not (Test-Path -LiteralPath $Rec))
    Yes '  it finds one character of theirs and leaves the one another account holds' (
        (Said 'Discord id 111111111111111111: 1 character') -and (Said "left\s+profile $P2`: another account holds it too"))
    Yes '  it counts what goes: the link, sign-ins, sessions, characters, chat' (
        (Said 'remove\s+1\s+site: Discord link') -and (Said 'remove\s+2\s+site: sign-in rows') -and
        (Said 'remove\s+1\s+site: session rows') -and (Said 'remove\s+1\s+live game server: characters\s*$') -and
        (Said 'remove\s+2\s+live voice: chat lines'))
    Yes '  and what stays: bans, notes, PK, reports, the kept session' (
        (Said 'kept\s+1\s+site: bans') -and (Said 'kept\s+2\s+site: staff notes') -and (Said 'kept\s+1\s+site: PK records') -and
        (Said 'kept\s+1\s+site: reports they made') -and (Said 'kept\s+1\s+site: reports about them') -and
        (Said 'kept\s+1\s+site: session rows staff marked kept'))
    Yes '  and counts their approved gallery picture, and leaves the one a report is about' (
        (Said 'remove\s+1\s+site: approved gallery pictures') -and (Said 'kept\s+1\s+site: gallery pictures held while a report about them is looked into'))
    Yes '  and counts the game registers naming their character without changing them' (Said 'left\s+1\s+live game server: places in private\\property\.json naming their character')
    if (-not (Said 'A real run stops these')) { Show }
    Yes '  and names the services a real run would stop' (Said 'A real run stops these while it changes their files, then starts them again: the site, the live game server, the dev game server, live voice, dev voice, the bot\.')
    Yes '  and never prints an address or what a record says' (-not (Said '203\.0\.113') -and -not (Said 'hello'))

    # ---- the real run -------------------------------------------------------------
    $c = Run (@('-DiscordId', $ME, '-Delete', '-By', 'Tester') + $roots)
    if ($c -ne 0) { Show }
    Yes 'the real run ends 0 and says it is written down' ($c -eq 0 -and (Said 'DELETED, and written down in'))
    $D = Join-Path $Site 'data'
    $lk = J (Join-Path $D 'linked.json')
    Yes 'their Discord link is gone, the others stay' ($null -eq $lk.$ME -and $null -ne $lk.$YOU -and $null -ne $lk.$THEM)
    Yes 'their answer to the rules is gone' ($null -eq (J (Join-Path $D 'rules-accepted.json')).$ME)
    $si = @(J (Join-Path $D 'signins.json'))
    Yes 'their sign-in rows are gone, with the addresses in them' ($si.Count -eq 1 -and $si[0].id -eq $YOU)
    $ss = @(J (Join-Path $D 'sessions.json'))
    Yes 'their session row is gone and the one staff kept stays' (@($ss | Where-Object { $_.session -eq 's1' }).Count -eq 0 -and @($ss | Where-Object { $_.session -eq 's2' }).Count -eq 1 -and $ss.Count -eq 3)
    Yes 'their launcher logs are gone, the kept session''s stay' (-not (Test-Path (Join-Path $D 'session-logs\s1.json')) -and (Test-Path (Join-Path $D 'session-logs\s2.json')) -and (Test-Path (Join-Path $D 'session-logs\s3.json')))
    $tr = @(J (Join-Path $D 'for-bot\trouble.json'))
    Yes 'their failed-session alert is gone, the kept session''s stays' (@($tr | ForEach-Object { $_.session }) -join ',' -eq 's2,s3')
    $ib = @(J (Join-Path $D 'for-bot\inbox.json'))
    Yes 'their ticket and call for help are gone; reports by and about them and the shared character''s stay' (
        $ib.Count -eq 4 -and @($ib | Where-Object { $_.kind -eq 'report' }).Count -eq 2 -and @($ib | Where-Object { $_.discordId -eq $ME }).Count -eq 0 -and
        @($ib | Where-Object { $_.profileId -eq $P2 }).Count -eq 1)
    $ro = J $roster
    Yes 'their roster row is gone from who and from each server''s lists' (
        $null -eq $ro.who."$P1" -and $null -ne $ro.who."$P2" -and $null -ne $ro.who."$PY" -and
        (@($ro.servers.main.checked) -join ',') -eq "$PY" -and @($ro.servers.main.held).Count -eq 0)
    $gp = @(J (Join-Path $D 'gallery-pending.json'))
    $um = J (Join-Path $Site 'uploads\uploads.json')
    Yes 'their waiting gallery submission is gone, file and note too' (
        $gp.Count -eq 1 -and $gp[0].discordId -eq $YOU -and -not (Test-Path (Join-Path $Site 'uploads\20261001-mine.png')) -and
        $null -eq $um.'20261001-mine.png' -and (Test-Path (Join-Path $Site 'uploads\20261001-yours.png')))
    $gl = @(J (Join-Path $D 'gallery.json'))
    Yes 'their approved gallery picture is gone, file and note too' (
        @($gl | Where-Object { $_.name -eq '20261002-approved.png' }).Count -eq 0 -and -not (Test-Path (Join-Path $Site 'uploads\20261002-approved.png')) -and
        $null -eq $um.'20261002-approved.png')
    Yes '  the one a report is about stays, and so do the old one with no account and somebody else''s' (
        (@($gl | ForEach-Object { $_.name }) -join ',') -eq '20260901-old.png,20261003-reported.png,20261004-yours.png' -and
        (Test-Path (Join-Path $Site 'uploads\20261003-reported.png')) -and $null -ne $um.'20261003-reported.png' -and
        (Test-Path (Join-Path $Site 'uploads\20260901-old.png')) -and (Test-Path (Join-Path $Site 'uploads\20261004-yours.png')))
    Yes 'bans, notes, PK, gallery reports and the staff log are as they were' (
        $before['\Thornswood-Docs\data\bans.json'] -eq (Get-FileHash (Join-Path $D 'bans.json')).Hash -and
        $before['\Thornswood-Docs\data\notes.json'] -eq (Get-FileHash (Join-Path $D 'notes.json')).Hash -and
        $before['\Thornswood-Docs\data\pk.json'] -eq (Get-FileHash (Join-Path $D 'pk.json')).Hash -and
        $before['\Thornswood-Docs\data\gallery-reports.json'] -eq (Get-FileHash (Join-Path $D 'gallery-reports.json')).Hash -and
        $before['\Thornswood-Docs\data\for-bot\moderation.log'] -eq (Get-FileHash (Join-Path $D 'for-bot\moderation.log')).Hash)
    $A = Join-Path $Site 'data-before-restore-20261001-010101'
    Yes 'the copy of the site''s data a restore set aside loses them too' ($null -eq (J (Join-Path $A 'linked.json')).$ME -and @(J (Join-Path $A 'signins.json')).Count -eq 0)

    foreach ($g in @(@{ R = $Live; Tag = 'live' }, @{ R = $Dev; Tag = 'dev' })) {
        $R = $g.R; $tag = $g.Tag
        $CF = Join-Path $R 'world\changeForms'
        Yes "$tag`: their character's change form is gone, whatever its name" (-not (Test-Path (Join-Path $CF 'ff000a01.json')))
        Yes "$tag`:   and the shared one, the other people's and the world's stay" ((Test-Path (Join-Path $CF 'ff000a03.json')) -and (Test-Path (Join-Path $CF 'ff000a02.json')) -and (Test-Path (Join-Path $CF 'ff000a04.json')) -and (Test-Path (Join-Path $CF '1a2b3.json')))
        Yes "$tag`:   and the copies a reset and a wipe set aside are gone" (-not (Test-Path (Join-Path $CF '_discarded-20261002-000000\ff000a05.json')) -and -not (Test-Path (Join-Path $R 'world-before-20260930-000000\changeForms\ff000a06.json')))
        $PV = Join-Path $R 'private'
        $ch = J (Join-Path $PV 'characters.json')
        Yes "$tag`: their card is gone, in characters.json and its wipe copy" ($null -eq $ch.who."$P1" -and $null -ne $ch.who."$PY" -and $null -eq (J (Join-Path $PV 'characters-before-20260930-000000.json')).who."$P1")
        Yes "$tag`: their mod menu choices, take counts and last-left time are gone" (
            $null -eq (J (Join-Path $PV 'mod-settings.json')).who."$P1" -and $null -ne (J (Join-Path $PV 'mod-settings.json')).who."$PY" -and
            $null -eq (J (Join-Path $PV 'take-limit.json')).counts."$P1|1a2b3" -and $null -ne (J (Join-Path $PV 'take-limit.json')).counts."$PY|1a2b3" -and
            $null -eq (J (Join-Path $R 'data\last-left.json'))."$P1" -and $null -ne (J (Join-Path $R 'data\last-left.json'))."$PY")
        $rel = $R.Substring($Box.Length)
        Yes "$tag`: the property register, the staff log and the door log are as they were" (
            $before["$rel\private\property.json"] -eq (Get-FileHash (Join-Path $PV 'property.json')).Hash -and
            $before["$rel\private\moderation.log"] -eq (Get-FileHash (Join-Path $PV 'moderation.log')).Hash -and
            $before["$rel\private\door.log"] -eq (Get-FileHash (Join-Path $PV 'door.log')).Hash)
    }
    Yes 'the live server''s folder an install set aside loses their change form too' (-not (Test-Path (Join-Path $Box 'Thornswood-Server.prev-20261001-000000\world\changeForms\ff000a07.json')))

    $day = Get (Join-Path $Vl 'chat\2026-10-01.jsonl')
    Yes 'their chat lines are gone from the day, the other lines stay byte for byte' (
        $day -eq ('{"at":2,"kind":"say","profileId":' + $PY + ',"name":"Yours","text":"hi"}' + "`n" + '{"at":3,"kind":"say","profileId":' + $P2 + ',"name":"Shared","text":"hey"}' + "`n"))
    Yes '  a day with none of theirs is not touched' ($before['\Thornswood-Voice\chat\2026-10-02.jsonl'] -eq (Get-FileHash (Join-Path $Vl 'chat\2026-10-02.jsonl')).Hash)
    Yes '  and a dev day of only theirs is left empty, not deleted' ((Get (Join-Path $Vd 'chat\2026-10-01.jsonl')) -eq '')
    Yes '  and the run says each edited day with its line count before and after' (Said 'chat\s+live 2026-10-01\.jsonl: 4 lines before, 2 after')
    $jn = J (Join-Path $Bot 'data\joins.json')
    Yes 'their join number is gone and the last number given out stays' ($null -eq $jn.'900'.members.$ME -and $jn.'900'.members.$YOU -eq 40 -and $jn.'900'.last -eq 40)
    $ot = J (Join-Path $Bot 'data\open-tickets.json')
    Yes 'their open ticket is forgotten' ($null -eq $ot."900:$ME" -and $null -ne $ot."900:$YOU")

    # ---- the record ---------------------------------------------------------------
    $recFile = Join-Path $Rec 'requests.jsonl'
    $lines = @(if (Test-Path $recFile) { [IO.File]::ReadAllLines($recFile) | Where-Object { $_.Trim() } })
    Yes 'one line went into the record' ($lines.Count -eq 1)
    if ($lines.Count -eq 1) {
        $row = $lines[0] | ConvertFrom-Json
        Yes '  with the Discord id, the character, who ran it and when' ($row.discordId -eq $ME -and (@($row.profiles) -join ',') -eq "$P1" -and $row.by -eq 'Tester' -and $lines[0] -match '"at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"')
        Yes '  and the counts, with each edited chat day' ($row.removed.'site: Discord link' -eq 1 -and @($row.chat).Count -ge 2)
        Yes '  and no name, no address and nothing a record said' ($lines[0] -notmatch '203\.0\.113' -and $lines[0] -notmatch 'hello' -and $lines[0] -notmatch '"Me"' -and $lines[0] -notmatch 'Mine')
    }
    $acl = Get-Acl -LiteralPath $Rec
    $who = @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value })
    $mySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Yes 'the record''s folder inherits nothing and lets in only SYSTEM, Administrators and whoever made it' (
        $acl.AreAccessRulesProtected -and @($who | Where-Object { @('S-1-5-18', 'S-1-5-32-544', $mySid) -notcontains $_ }).Count -eq 0)

    # ---- a restore, and the reapply -------------------------------------------------
    $after = Hashes $Box
    Build
    $c = Run (@('-Reapply') + $roots)
    if ($c -ne 0 -or -not (Said 'DRY RUN')) { Show }
    Yes 'after a restore, -Reapply alone is a dry run that names what would go again' ($c -eq 0 -and (Said 'record\s+1 completed request') -and (Said 'remove\s+1\s+site: Discord link') -and (Said 'DRY RUN'))
    Yes '  and changed nothing' (Same $before (Hashes $Box))
    $c = Run (@('-Reapply', '-Delete') + $roots)
    if ($c -ne 0) { Show }
    Yes '-Reapply -Delete removes it all again' ($c -eq 0 -and (Said 'REAPPLIED') -and (Same $after (Hashes $Box)))
    Yes '  and adds no line to the record' (@([IO.File]::ReadAllLines($recFile) | Where-Object { $_.Trim() }).Count -eq 1)
    $c = Run (@('-Reapply', '-DiscordId', $ME) + $roots)
    Yes '-Reapply with a Discord id is refused' ($c -eq 1 -and (Said 'REFUSED: -Reapply takes every request in the record'))

    # A request in another copy of the record: the backup being put back.
    $other = Join-Path $T 'backup-requests.jsonl'
    Put $other ('{"at":"2026-10-02T00:00:00Z","discordId":"' + $THEM + '","profiles":[' + $PT + '],"by":"Tester"}' + "`n")
    $c = Run (@('-Reapply', '-Delete', '-Merge', $other) + $roots)
    if ($c -ne 0) { Show }
    Yes '-Merge adds the request the box''s record did not have, and removes that person too' (
        $c -eq 0 -and (Said 'merged\s+1 request') -and $null -eq (J (Join-Path $Site 'data\linked.json')).$THEM -and
        -not (Test-Path (Join-Path $Live 'world\changeForms\ff000a04.json')) -and @([IO.File]::ReadAllLines($recFile) | Where-Object { $_.Trim() }).Count -eq 2)
    $c = Run (@('-Reapply', '-Delete', '-Merge', $other) + $roots)
    Yes '  and merging the same copy again adds nothing' ($c -eq 0 -and -not (Said 'merged') -and @([IO.File]::ReadAllLines($recFile) | Where-Object { $_.Trim() }).Count -eq 2)
    Put $other "not json`n"
    $c = Run (@('-Reapply', '-Delete', '-Merge', $other) + $roots)
    Yes 'a copy of the record with a line that will not parse is refused' ($c -eq 1 -and (Said 'will not parse. Nothing was changed'))
}
catch {
    Yes ('the harness ran to the end: ' + $_.Exception.Message) $false
}
finally {
    if (Test-Path -LiteralPath $T) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}
Done
