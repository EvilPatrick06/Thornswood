# Expand Check-Roster's here-string exactly as the script does and parse the
# text that would actually be sent. Same check as Check-VoiceInstall.ps1 and
# Check-DevRosterSeed.ps1: a mistake in a remote block parses perfectly here
# and fails on the box.
$src = Get-Content 'C:\Users\you\Downloads\Thornswood-Repo\scripts\ops\Check-Roster.ps1' -Raw
$m = [regex]::Match($src, "(?s)\`$script = @'\r?\n(.*?)\r?\n'@")
if (-not $m.Success) { throw 'could not find the remote here-string' }

$script = $m.Groups[1].Value.Replace('@@ROOT@@', 'C:\Thornswood-Server-Dev')
if ($script -match '@@') { throw 'a placeholder was left unreplaced' }
if ($script -notmatch 'Thornswood-Server-Dev\\private') { throw 'the root did not land' }
if ($script -match 'Thornswood-Server-Dev\\\\') { throw 'a doubled separator' }
if ($script -notmatch "ProgressPreference") { throw 'the progress stream is not silenced' }

$e = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$e)
if ($e.Count) { $e | ForEach-Object { $_.Message }; exit 1 }
Write-Output ("remote script: {0} lines, parses clean" -f ($script -split "`n").Count)
$script -split "`n" | Select-Object -First 3
