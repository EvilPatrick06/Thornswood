<#
  test-backup-restore.ps1

      pwsh -NoProfile -File .\tests\test-backup-restore.ps1

  Issue #401: nothing backed up the world, and the only two backups there were
  had no characters in them. This takes a backup of a scratch live server and
  a scratch dev server with the real vps-nightly-backup.ps1, puts it back into
  other scratch folders with the real Restore-Server.ps1, and checks the world
  and a character came back and the load order resolves.

  It proves:
    - the nightly backup takes world, private (characters.json,
      mod-settings.json, take-limit.json, door.json, allowed.json) and data
      from both the live and the dev server, encrypted, and the zip lists
      entries under game/world and is far larger than the 195 KB of the
      15 September pair
    - retention keeps seven daily and leaves a file put there by hand alone
    - Restore-Backup.ps1 -CheckOnly opens it, refuses a wrong passphrase, and
      calls a backup with nothing under game/world a failure
    - Restore-Server.ps1 puts a character back byte for byte into a folder
      whose load order pointed at another server's plugins, points it at its
      own, and says RESTORE OK, with the original server folder deleted first
      so nothing can resolve against it
    - a folder missing one plugin is refused and the plugin is named
    - -Which dev restores the dev character and not the live one
    - a second restore keeps what it replaced, and a running server is refused
    - Fetch-Backups.ps1 -PruneOnly keeps the last -KeepDays days and never
      fewer than the newest seven

  The scripts run under Windows PowerShell 5.1, which is what runs them on the
  VPS. Touches nothing but a scratch folder under the temp folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Vps = Join-Path (Split-Path -Parent $Here) 'scripts\vps'
$Nightly  = Join-Path $Vps 'vps-nightly-backup.ps1'
$Unpack   = Join-Path $Vps 'Restore-Backup.ps1'
$Restore  = Join-Path $Vps 'Restore-Server.ps1'
$Fetch    = Join-Path $Vps 'Fetch-Backups.ps1'

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

foreach ($f in $Nightly, $Unpack, $Restore, $Fetch) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    Yes ((Split-Path -Leaf $f) + ' parses') ($errors.Count -eq 0)
}

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $env:SystemRoot -or -not (Test-Path -LiteralPath $ps51)) {
    Write-Host 'SKIP  the runs need Windows PowerShell 5.1, which runs these on the VPS'
    Done
}

$utf8 = New-Object Text.UTF8Encoding($false)
function Put([string]$path, [string]$text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
$script:last = @()
function Run([string]$file, [string[]]$argv) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $script:last = @(& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file @argv 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $eap }
    return $LASTEXITCODE
}
function Show { foreach ($l in $script:last | Select-Object -Last 40) { Write-Host ('        ' + $l) } }
function Said([string]$pattern) { return (($script:last -join "`n") -match $pattern) }

$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
function Noise([int]$n) { $b = New-Object byte[] $n; $rng.GetBytes($b); return [Convert]::ToBase64String($b) }

$plugins = @('Skyrim.esm', 'Update.esm', "Bob's Armour.esp", 'Thornswood.esp')
function Plugins([string]$root, [string[]]$names) {
    foreach ($n in $names) { Put (Join-Path $root "plugins\$n") ("plugin " + $n) }
}
function Settings([string]$root, [string]$pluginRoot, [int]$port) {
    $far = ($pluginRoot -replace '\\', '/') + '/plugins/'
    Put (Join-Path $root 'server-settings.json') (
        ([ordered]@{ port = $port; name = 'Thornswood Test'; loadOrder = @($plugins | ForEach-Object { $far + $_ }) } |
         ConvertTo-Json -Depth 5))
}
# A server as the box has it: plugins, settings, a world of change forms (the
# characters are the ones named with a bare number), private and data.
function Server([string]$root, [int]$port, [string]$who, [int]$worldFiles) {
    Plugins $root $plugins
    Settings $root $root $port
    Put (Join-Path $root 'gamemode.js') '// gamemode'
    Put (Join-Path $root 'data\keep.txt') 'the online count'
    Put (Join-Path $root 'private\characters.json') ('{"at":1,"who":{"' + $who + '":{"name":"Brynja","race":"Nord"}}}')
    Put (Join-Path $root 'private\mod-settings.json') '{"menus":{}}'
    Put (Join-Path $root 'private\take-limit.json') '{"counts":{}}'
    Put (Join-Path $root 'private\door.json') '{"key":"not-a-real-key"}'
    Put (Join-Path $root 'private\allowed.json') '{"allowed":[]}'
    $forms = Join-Path $root 'world\changeForms'
    Put (Join-Path $forms "$who.json") ('{"formId":' + $who + ',"marker":"' + [Guid]::NewGuid().ToString('N') + '","inv":"' + (Noise 900) + '"}')
    foreach ($i in 1..4) { Put (Join-Path $forms ("{0}.json" -f (1000 + $i))) ('{"formId":' + (1000 + $i) + ',"x":"' + (Noise 600) + '"}') }
    foreach ($i in 1..$worldFiles) { Put (Join-Path $forms ("ff{0:x6}.json" -f $i)) ('{"ref":' + $i + ',"x":"' + (Noise 1100) + '"}') }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-backup-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
$live = Join-Path $work 'live'
$dev  = Join-Path $work 'dev'
$out  = Join-Path $work 'box-backups'
$key  = Join-Path $work 'key.txt'
$liveWho = '1234567'
$devWho  = '7654321'

try {
    Server $live 45777 $liveWho 1420
    Server $dev  45787 $devWho 30
    Put $key (Noise 48)
    Put (Join-Path $work 'wrong-key.txt') (Noise 48)
    $keep = [IO.File]::ReadAllBytes((Join-Path $live "world\changeForms\$liveWho.json"))
    $keepBook = [IO.File]::ReadAllText((Join-Path $live 'private\characters.json'))
    $worldCount = @(Get-ChildItem -LiteralPath (Join-Path $live 'world') -Recurse -File).Count

    # Ten old nightlies, none on a Sunday, and one file a person put there.
    [void](New-Item -ItemType Directory -Path $out -Force)
    $d = [datetime]'2025-03-03'; $seeded = @()
    while ($seeded.Count -lt 10) {
        if ($d.DayOfWeek -ne 'Sunday') {
            $n = 'thornswood-' + $d.ToString('yyyyMMdd') + '-031500.zip.enc'
            Put (Join-Path $out $n) 'old'
            $seeded += $n
        }
        $d = $d.AddDays(1)
    }
    Put (Join-Path $out 'put-here-by-hand.zip') 'mine'

    # ---- the nightly backup --------------------------------------------------
    $common = @('-GameRoot', $live, '-DevGameRoot', $dev,
                '-SiteRoot', (Join-Path $work 'no-site'), '-BotRoot', (Join-Path $work 'no-bot'),
                '-CaddyRoot', (Join-Path $work 'no-caddy'), '-VoiceRoot', (Join-Path $work 'no-voice'))
    $code = Run $Nightly ($common + @('-Out', $out, '-KeyFile', $key))
    Yes "vps-nightly-backup.ps1 runs (exit $code)" ($code -eq 0)
    if ($code -ne 0) { Show }
    $enc = @(Get-ChildItem -LiteralPath $out -File | Where-Object { $_.Name -match '^thornswood-\d{8}-\d{6}\.zip\.enc$' -and $seeded -notcontains $_.Name })
    Yes 'and leaves one new encrypted backup' ($enc.Count -eq 1)
    Yes '  with no zip left in the clear beside it' (@(Get-ChildItem -LiteralPath $out -Filter 'thornswood-*.zip').Count -eq 0)
    $encPath = if ($enc.Count) { $enc[0].FullName } else { '' }
    $encKB = if ($enc.Count) { [math]::Round($enc[0].Length / 1KB) } else { 0 }
    Yes "  far larger than the 195 KB of the 15 September pair ($encKB KB)" ($encKB -gt 5 * 195)
    Yes '  and the log counts the characters in each world' (
        (Said 'game\\world\s+5 character') -and (Said 'game-dev\\world\s+5 character'))

    $daily = @(Get-ChildItem -LiteralPath $out -File | Where-Object { $_.Name -match '^thornswood-(\d{8})-\d{6}\.zip(\.enc)?$' } |
               Where-Object { ([datetime]::ParseExact($_.Name.Substring(11, 8), 'yyyyMMdd', $null)).DayOfWeek -ne 'Sunday' })
    Yes "retention keeps seven daily ($($daily.Count))" ($daily.Count -eq 7)
    Yes '  dropping the oldest' (-not (Test-Path -LiteralPath (Join-Path $out $seeded[0])))
    Yes '  and leaves the file put there by hand' (Test-Path -LiteralPath (Join-Path $out 'put-here-by-hand.zip'))

    # The same run in the clear, to read the zip itself.
    $plainOut = Join-Path $work 'plain'
    $code = Run $Nightly ($common + @('-Out', $plainOut, '-KeyFile', $key, '-Plain'))
    $zip = @(Get-ChildItem -LiteralPath $plainOut -Filter 'thornswood-*.zip' -File -EA SilentlyContinue)
    Yes "-Plain makes a zip to read (exit $code)" ($code -eq 0 -and $zip.Count -eq 1)
    if ($zip.Count) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
        $names = @($z.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        $z.Dispose()
        $gw = @($names | Where-Object { $_ -like 'game/world/*' })
        Yes ("the zip lists entries under game/world ({0} of {1})" -f $gw.Count, $worldCount) ($gw.Count -eq $worldCount)
        Yes '  including the character' ($names -contains "game/world/changeForms/$liveWho.json")
        $want = 'characters.json', 'mod-settings.json', 'take-limit.json', 'door.json', 'allowed.json'
        Yes '  and every private file of the live server' (@($want | Where-Object { $names -notcontains "game/private/$_" }).Count -eq 0)
        Yes '  and of the dev server, with its world' (
            @($want | Where-Object { $names -notcontains "game-dev/private/$_" }).Count -eq 0 -and
            $names -contains "game-dev/world/changeForms/$devWho.json")
        Yes '  and data and the settings from both' (
            $names -contains 'game/data/keep.txt' -and $names -contains 'game-dev/server-settings.json')
        Yes ("  and the zip is far larger than 195 KB ({0} KB)" -f [math]::Round($zip[0].Length / 1KB)) ($zip[0].Length -gt 5 * 195KB)
    }

    # ---- opening it ----------------------------------------------------------
    $code = Run $Unpack @('-Backup', $encPath, '-KeyFile', $key, '-CheckOnly', '-NoPause')
    Yes "Restore-Backup.ps1 -CheckOnly opens it (exit $code)" ($code -eq 0 -and (Said 'signature matches'))
    Yes '  and prints what the box wrote in NOTES.txt' (Said 'game\s+5 character\(s\), 0 torn')
    $code = Run $Unpack @('-Backup', $encPath, '-KeyFile', (Join-Path $work 'wrong-key.txt'), '-CheckOnly', '-NoPause')
    Yes '  and refuses the wrong passphrase before decrypting anything' ($code -ne 0 -and (Said 'Nothing was decrypted'))

    $emptyOut = Join-Path $work 'empty'
    Put (Join-Path $work 'bot-only\bot.env.json') '{}'
    $code = Run $Nightly @('-GameRoot', (Join-Path $work 'gone'), '-DevGameRoot', (Join-Path $work 'gone-dev'),
                           '-SiteRoot', (Join-Path $work 'no-site'), '-BotRoot', (Join-Path $work 'bot-only'),
                           '-CaddyRoot', (Join-Path $work 'no-caddy'), '-VoiceRoot', (Join-Path $work 'no-voice'),
                           '-Out', $emptyOut, '-KeyFile', $key, '-Plain')
    $empty = @(Get-ChildItem -LiteralPath $emptyOut -Filter 'thornswood-*.zip' -File -EA SilentlyContinue)
    if ($empty.Count) {
        $code = Run $Unpack @('-Backup', $empty[0].FullName, '-CheckOnly', '-NoPause')
        Yes 'a backup with nothing under game/world fails -CheckOnly, as the 15 September pair would have' (
            $code -ne 0 -and (Said 'nothing under game/world'))
    } else { Yes 'a backup of a box with no world is still made, to be refused' $false }

    # ---- putting it back -----------------------------------------------------
    # As Install-ThornswoodServer leaves a new folder: the plugins, and settings
    # that name the live server's folder. The live folder is then deleted, so
    # nothing can resolve against it.
    $restored = Join-Path $work 'restore-test'
    Plugins $restored $plugins
    Settings $restored $live 45797
    Remove-Item -LiteralPath $live -Recurse -Force
    Yes 'the original server folder is gone before the restore' (-not (Test-Path -LiteralPath $live))

    $code = Run $Restore @('-Backup', $encPath, '-KeyFile', $key, '-Root', $restored, '-Expect', $liveWho, '-NoPause')
    Yes "Restore-Server.ps1 puts it back (exit $code)" ($code -eq 0 -and (Said 'RESTORE OK: 5 character'))
    if ($code -ne 0) { Show }
    $back = Join-Path $restored "world\changeForms\$liveWho.json"
    Yes '  the character is there, byte for byte' (
        (Test-Path -LiteralPath $back) -and ([Convert]::ToBase64String([IO.File]::ReadAllBytes($back)) -eq [Convert]::ToBase64String($keep)))
    Yes ("  and the whole world ({0} files)" -f $worldCount) (
        @(Get-ChildItem -LiteralPath (Join-Path $restored 'world') -Recurse -File).Count -eq $worldCount)
    Yes '  and characters.json, the take limits and the door' (
        ([IO.File]::ReadAllText((Join-Path $restored 'private\characters.json')) -eq $keepBook) -and
        (Test-Path -LiteralPath (Join-Path $restored 'private\take-limit.json')) -and
        (Test-Path -LiteralPath (Join-Path $restored 'private\door.json')))
    Yes '  and data' (Test-Path -LiteralPath (Join-Path $restored 'data\keep.txt'))
    $s = Get-Content -LiteralPath (Join-Path $restored 'server-settings.json') -Raw | ConvertFrom-Json
    $mine = ($restored -replace '\\', '/') + '/plugins/'
    Yes '  and the load order names this folder, not the one the backup came from' (
        @($s.loadOrder).Count -eq $plugins.Count -and @($s.loadOrder | Where-Object { -not $_.StartsWith($mine) }).Count -eq 0)
    Yes '  in the same order' ((@($s.loadOrder | ForEach-Object { Split-Path -Leaf $_ }) -join '|') -eq ($plugins -join '|'))
    Yes '  and the decrypted copy is not left in the temp folder' (
        @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'thornswood-restore-*' -EA SilentlyContinue |
          Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) }).Count -eq 0)

    $code = Run $Restore @('-Backup', $encPath, '-KeyFile', $key, '-Root', $restored, '-NoPause')
    $aside = @(Get-ChildItem -LiteralPath $restored -Directory -Filter 'world-before-restore-*')
    Yes 'a second restore keeps the world it replaced' (
        $code -eq 0 -and $aside.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $aside[0].FullName "world\changeForms\$liveWho.json")))

    $broken = Join-Path $work 'restore-broken'
    Plugins $broken ($plugins | Where-Object { $_ -ne 'Thornswood.esp' })
    Settings $broken $broken 45807
    $code = Run $Restore @('-Backup', $encPath, '-KeyFile', $key, '-Root', $broken, '-NoPause')
    Yes 'a folder missing a plugin is refused' ($code -ne 0 -and (Said 'load order does not resolve'))
    Yes '  and the missing plugin is named' (Said 'not on disk:[\s\S]*Thornswood\.esp')

    $devBack = Join-Path $work 'restore-dev'
    Plugins $devBack $plugins
    Settings $devBack $dev 45817
    $code = Run $Restore @('-Backup', $encPath, '-KeyFile', $key, '-Root', $devBack, '-Which', 'dev', '-Expect', $devWho, '-NoPause')
    Yes "-Which dev puts the dev world back (exit $code)" ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $devBack "world\changeForms\$devWho.json")))
    Yes '  and not the live one' (-not (Test-Path -LiteralPath (Join-Path $devBack "world\changeForms\$liveWho.json")))

    $code = Run $Restore @('-Backup', $encPath, '-KeyFile', $key, '-Root', $devBack, '-Expect', '999', '-NoPause')
    Yes '-Expect names a character that is not there and refuses' ($code -ne 0 -and (Said 'Character 999 is not in the restored world'))

    $node = Get-Command node -EA SilentlyContinue
    if ($node) {
        $p = Start-Process -FilePath $node.Source -WindowStyle Hidden -PassThru -ArgumentList @('-e', '"setTimeout(function(){},60000)"', ('"' + $devBack + '"'))
        try {
            Start-Sleep -Milliseconds 500
            $code = Run $Restore @('-Backup', $encPath, '-KeyFile', $key, '-Root', $devBack, '-Which', 'dev', '-NoPause')
            Yes 'a folder whose server is running is refused' ($code -ne 0 -and (Said 'is running'))
        } finally { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
    } else { Write-Host 'SKIP  no node here to stand in for a running server' }

    # ---- the copy on this machine --------------------------------------------
    $here = Join-Path $work 'fetched'
    $today = Get-Date
    $names = @()
    foreach ($i in 0..2) { $names += 'thornswood-' + $today.AddDays(-$i).ToString('yyyyMMdd') + '-031500.zip.enc' }
    foreach ($i in 0..8) { $names += 'thornswood-' + $today.AddDays(-60 - $i).ToString('yyyyMMdd') + '-031500.zip.enc' }
    foreach ($n in $names) { Put (Join-Path $here $n) 'x' }
    Put (Join-Path $here 'mine.zip.enc') 'mine'
    $code = Run $Fetch @('-To', $here, '-KeepDays', '30', '-PruneOnly', '-NoPause')
    $left = @(Get-ChildItem -LiteralPath $here -Filter 'thornswood-*' -File | ForEach-Object { $_.Name } | Sort-Object -Descending)
    Yes "Fetch-Backups.ps1 -PruneOnly keeps the newest seven when only three are recent (exit $code, $($left.Count) left)" (
        $code -eq 0 -and $left.Count -eq 7 -and (($left -join '|') -eq ((@($names | Sort-Object -Descending) | Select-Object -First 7) -join '|')))
    Yes '  and leaves a file put there by hand' (Test-Path -LiteralPath (Join-Path $here 'mine.zip.enc'))
    Yes '  and says what it did in fetch.log' (
        (Test-Path -LiteralPath (Join-Path $here 'fetch.log')) -and
        ([IO.File]::ReadAllText((Join-Path $here 'fetch.log')) -match 'dropped thornswood-'))
}
catch {
    Yes ('the runs finished without an error: ' + $_.Exception.Message) $false
    Show
}
finally {
    $rng.Dispose()
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
