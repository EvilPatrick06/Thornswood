# Expand the roster seed here-string exactly as Publish-Server would and parse
# the text that would actually be sent. Same idea as Check-VoiceInstall.ps1:
# a mistake in a remote block parses perfectly here and fails on the box.
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$src = Get-Content (Join-Path $here '..\release\Publish-Server.ps1') -Raw
$m = [regex]::Match($src, "(?s)\`$seed = @'\r?\n(.*?)\r?\n'@")
if (-not $m.Success) { throw 'could not find the roster seed here-string' }

$seed = $m.Groups[1].Value.Replace('@@DEVROOT@@', 'C:\Thornswood-Server-Dev')
Write-Output ("seed script: {0} lines" -f ($seed -split "`n").Count)
if ($seed -match '@@') { throw 'a placeholder was left unreplaced' }
if ($seed -notmatch 'Thornswood-Server-Dev') { throw 'the dev root did not land' }
if ($seed -match "Thornswood-Server-Dev\\\\") { throw 'a doubled separator in the dev path' }

$e = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($seed, [ref]$null, [ref]$e)
if ($e.Count) { $e | ForEach-Object { $_.Message }; exit 1 }
Write-Output 'the remote seed script parses clean'
$seed -split "`n" | Select-Object -First 3
