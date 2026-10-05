# Expand Install-Voice's here-string exactly as the script does and look at the
# text that would actually be sent. Skipping this step is how '$log' silently
# became '**' and killed live voice twice.
$src = Get-Content (Join-Path $PSScriptRoot '..\deploy\Install-Voice.ps1') -Raw

# What the outer script would have set by the time the here-string is built.
$Root = 'C:\Thornswood-Voice-Dev'
$Port = 7789
$TaskName = 'Thornswood Dev Voice'
$Site = 'https://thornswood.net'
# Every parameter the here-string reads. Leave one out and it expands to
# nothing, which is the whole failure this script exists to catch, so a
# missing one here would hide the very thing being looked for.
$Bind = '0.0.0.0'
$ChatRange = 'on'
# The relay line, built before the here-string and empty when there is no
# relay, which is every box today. Empty is right here and not a missing
# value: with a relay it is "set THORNSWOOD_TURN_URL=<address>&& ", which
# tests\test-voice-turn-url.ps1 builds and runs.
$turnSet = ''

$m = [regex]::Match($src, '(?s)\$remote = @"\r?\n(.*?)\r?\n"@')
if (-not $m.Success) { throw 'could not find the install here-string' }
$expanded = $ExecutionContext.InvokeCommand.ExpandString($m.Groups[1].Value)
Write-Output ("expanded remote script: {0} lines" -f ($expanded -split "`n").Count)
Write-Output ""

# Any outer variable that expanded to nothing shows up as an empty pattern.
$problems = 0
foreach ($line in ($expanded -split "`n")) {
    $l = $line.Trim()
    if ($l -match "-like\s*\(\s*'\*'\s*\+\s*\+" -or $l -match "'\*'\s*\+\s*''\s*\+\s*'\*'" -or $l -match "-like\s*'\*\*'") {
        Write-Output ("  MATCHES EVERYTHING: " + $l); $problems++
    }
    # A quoted empty string where a path belongs.
    if ($l -match "Join-Path\s+''" -or $l -match "-LocalPort\s*$" -or $l -match "TaskName\s+''") {
        Write-Output ("  EMPTY VALUE: " + $l); $problems++
    }
    # set NAME=&& or set NAME=" : an environment variable handed nothing.
    # The service then falls back to its own default and the setting silently
    # does not apply, which is worse than failing, because everything looks
    # like it worked.
    foreach ($m in [regex]::Matches($l, 'set\s+([A-Z_]+)=(?=&&|")')) {
        Write-Output ("  EMPTY ENV VALUE: " + $m.Groups[1].Value + "  in: " + $l); $problems++
    }
}

Write-Output "--- the lines that decide what gets killed, as sent ---"
foreach ($line in ($expanded -split "`n")) {
    $l = $line.Trim()
    if ($l -match 'CommandLine -like' -or $l -like '$log =*' -or $l -match 'THORNSWOOD_VOICE_PORT' -or
        $l -match 'LocalPort' -or $l -match 'NetFirewallRule') {
        Write-Output ("  " + $l)
    }
}
Write-Output ""
Write-Output ("problems found: " + $problems)
if ($problems) { exit 1 }
