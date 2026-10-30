<#
  test-3582-manual-backup.ps1

      pwsh -NoProfile -File .\tests\test-3582-manual-backup.ps1

  Issue #3582: Backup-Server.ps1, the whole-server copy taken by hand, brought
  down a plain zip of the site's sign-ins, the bot's and voice's folders whole
  (voice chat included) and every character, into local\backups, and nothing
  ever deleted it: Fetch-Backups.ps1's prune matched only the nightly names.

  What it proves, in a scratch folder:
    - Protect-BackupZip.ps1 writes the nightly's TSBK1 format: Restore-Backup.ps1
      -CheckOnly opens what it writes, finds the character in it, and a wrong
      passphrase is refused; no .partial is left behind
    - Backup-Server.ps1 sends that function to the box with its own script,
      encrypts there with the box's backup passphrase before anything comes
      down, stops with none, and brings down and names only
      thornswood-backup-<stamp>.zip.enc; the plain zip stays in the run's
      folder on the box, which its keeper removes (#3035)
    - its header says the bot and voice folders are taken whole, voice chat
      included
    - Fetch-Backups.ps1 -PruneOnly deletes a copy taken by hand, encrypted or
      the old plain kind, 31 days after the day in its name, keeps one taken
      29 days ago, counts none of them among the newest seven nightlies, and
      touches nothing else in the folder
    - the privacy page says a copy taken by hand is encrypted and kept 30 days
  Touches nothing but a scratch folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$Vps = Join-Path $Repo 'scripts\vps'
$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-3582-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work -Force)
try {
    foreach ($n in 'Protect-BackupZip.ps1', 'Backup-Server.ps1', 'Fetch-Backups.ps1') {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Vps $n), [ref]$tokens, [ref]$errors)
        Yes "$n parses" ($errors.Count -eq 0)
    }

    # ---- the format: Restore-Backup.ps1 opens it ---------------------------------
    . (Join-Path $Vps 'Protect-BackupZip.ps1')
    $stage = Join-Path $work 'stage'
    $forms = Join-Path $stage 'game\world\changeForms'
    [void](New-Item -ItemType Directory -Path $forms -Force)
    [IO.File]::WriteAllText((Join-Path $forms '0.json'), '{"formDesc":"ff000a01","profileId":5001,"isDeleted":false}')
    $zip = Join-Path $work 'thornswood-backup-20261026-1700.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
    $key = Join-Path $work 'key.txt'
    [IO.File]::WriteAllText($key, 'a passphrase for the test only')
    Protect-ThornswoodBackupZip -Zip $zip -Enc ($zip + '.enc') -Pass 'a passphrase for the test only'
    $bytes = [IO.File]::ReadAllBytes($zip + '.enc')
    Yes 'it writes the TSBK1 header the nightly writes' ([Text.Encoding]::ASCII.GetString($bytes, 0, 5) -eq 'TSBK1')
    Yes '  and leaves no .partial behind' (@(Get-ChildItem -LiteralPath $work -Filter '*.partial').Count -eq 0)
    $restore = Join-Path $Vps 'Restore-Backup.ps1'
    $pw = (Get-Process -Id $PID).Path
    $out = & $pw -NoProfile -File $restore -Backup ($zip + '.enc') -KeyFile $key -Work (Join-Path $work 'r') -CheckOnly -NoPause 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { $out | Select-Object -Last 15 | ForEach-Object { Write-Host "        $_" } }
    Yes "Restore-Backup.ps1 -CheckOnly opens it and finds the character (exit $code)" ($code -eq 0)
    $bad = Join-Path $work 'bad.txt'
    [IO.File]::WriteAllText($bad, 'not the passphrase')
    $null = & $pw -NoProfile -File $restore -Backup ($zip + '.enc') -KeyFile $bad -Work (Join-Path $work 'r') -CheckOnly -NoPause 2>&1
    Yes "  and refuses it with the wrong passphrase (exit $LASTEXITCODE)" ($LASTEXITCODE -ne 0)
    $threw = $false
    try { Protect-ThornswoodBackupZip -Zip $zip -Enc ($zip + '.enc') -Pass 'x' } catch { $threw = $true }
    Yes '  and never writes over a copy already there' ($threw -and ([IO.File]::ReadAllBytes($zip + '.enc').Length -eq $bytes.Length))

    # ---- Backup-Server.ps1 ----------------------------------------------------------
    $bs = [IO.File]::ReadAllText((Join-Path $Vps 'Backup-Server.ps1'))
    Yes 'Backup-Server.ps1 sends the function to the box ahead of its own script' (
        $bs -match [regex]::Escape("ReadAllText((Join-Path `$Here 'Protect-BackupZip.ps1'))") -and
        $bs -match [regex]::Escape('+ $protect + "`r`n" + $gather'))
    Yes '  encrypts there with the box''s backup passphrase, and stops with none before zipping' (
        $bs -match [regex]::Escape("`$keyFile = 'C:\Thornswood-Backup\key.txt'") -and
        $bs -match "if \(-not ``\`$pass\) \{ 'STOP" -and
        $bs.IndexOf("if (-not ```$pass)") -lt $bs.IndexOf('CreateFromDirectory(`$stage, `$zip)'))
    Yes '  and the zip line, which the side that asked waits for, comes only after it is encrypted' (
        $bs -match [regex]::Escape('Protect-ThornswoodBackupZip -Zip `$zip -Enc (`$zip + ''.enc'') -Pass `$pass') -and
        $bs.IndexOf('Protect-ThornswoodBackupZip -Zip') -lt $bs.IndexOf("'zip       ' +"))
    Yes '  and brings down and names only the .zip.enc' (
        $bs -match [regex]::Escape("`$remoteZip = `$box.Far + '/' + `$name + '.enc'") -and
        $bs -match [regex]::Escape("`$localZip  = Join-Path `$Out (`$name + '.enc')"))
    Yes 'its header says the bot and voice folders are taken whole, voice chat included' (
        $bs -match 'the bot folder\s+whole' -and $bs -match 'the voice server folder\s+whole: its config, voice\.log and the chat' -and
        $bs -notmatch 'the bot folder\s+its config and its log')

    # ---- Fetch-Backups.ps1 ages them -----------------------------------------------
    $here = Join-Path $work 'fetched'
    [void](New-Item -ItemType Directory -Path $here -Force)
    $today = Get-Date
    $old = 'thornswood-backup-' + $today.AddDays(-31).ToString('yyyyMMdd') + '-1200.zip.enc'
    $oldPlain = 'thornswood-backup-' + $today.AddDays(-400).ToString('yyyyMMdd') + '-0116.zip'
    $young = 'thornswood-backup-' + $today.AddDays(-29).ToString('yyyyMMdd') + '-1200.zip.enc'
    $nightly = @()
    foreach ($i in 0..6) { $nightly += 'thornswood-' + $today.AddDays(-60 - $i).ToString('yyyyMMdd') + '-031500.zip.enc' }
    $other = 'notes-by-hand.txt'
    foreach ($n in @($old, $oldPlain, $young, $other) + $nightly) { [IO.File]::WriteAllText((Join-Path $here $n), 'x') }
    $out = & $pw -NoProfile -File (Join-Path $Vps 'Fetch-Backups.ps1') -To $here -KeepDays 30 -PruneOnly -NoPause 2>&1
    $code = $LASTEXITCODE
    $has = { param($n) Test-Path -LiteralPath (Join-Path $here $n) }
    Yes "Fetch-Backups.ps1 -PruneOnly ends 0 (exit $code)" ($code -eq 0)
    Yes '  and deletes a copy taken by hand 31 days ago, and the old plain kind' (-not (& $has $old) -and -not (& $has $oldPlain))
    Yes '  keeps one taken 29 days ago' (& $has $young)
    Yes '  keeps the newest seven nightlies, which the copies by hand are not counted among' (@($nightly | Where-Object { & $has $_ }).Count -eq 7)
    Yes '  and touches nothing else in the folder' (& $has $other)
    $log = [IO.File]::ReadAllText((Join-Path $here 'fetch.log'))
    Yes '  and says each one it dropped' ($log -match ('dropped ' + [regex]::Escape($old) + ', a copy taken by hand') -and $log -match ('dropped ' + [regex]::Escape($oldPlain)))

    # ---- the privacy page ----------------------------------------------------------
    $page = ([IO.File]::ReadAllText((Join-Path $Repo 'site\data\site\privacy.md')) -split '\s+') -join ' '
    Yes 'the privacy page says a copy taken by hand is encrypted and kept 30 days' (
        $page -match 'A whole copy of the server taken by hand, before moving it to a new machine, is encrypted the same way and kept on the operator''s computer for 30 days')
}
catch {
    Yes ('the harness ran to the end: ' + $_.Exception.Message) $false
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
