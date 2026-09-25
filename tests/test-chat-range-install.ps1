<#
  test-chat-range-install.ps1

  Install-Voice.ps1 can turn local chat on, and leaves it off unless told to.

  Entry 150 put local in-character chat into the voice service behind
  THORNSWOOD_CHAT_RANGE, shipped off (voice\test-local-chat.js drives
  the service itself). A setting only counts if the install hands it over, and
  the install builds the service's command line inside a here-string that is
  expanded on this machine and run on the VPS. That expansion is where '$log'
  once became '**' and killed live voice twice (Check-VoiceInstall.ps1), so
  this expands it the same way and reads the line that starts the service.

  It also checks the other direction. An install run later for some other
  reason, with no -ChatRange on it, must keep whatever range is running, the
  same as -Bind and -Auth already do. Otherwise the next voice fix quietly
  turns local chat back into global chat, and nobody notices until a scene on
  the Whiterun road is read in Markarth again.

  Read only. Never connects to anything.
#>
[CmdletBinding()]
param([string]$InstallPath, [string]$ServerPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $InstallPath) { $InstallPath = Join-Path $Here '..\scripts\deploy\Install-Voice.ps1' }
if (-not $ServerPath) { $ServerPath = Join-Path $Here '..\voice\voice-server.js' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$src = Get-Content -LiteralPath $InstallPath -Raw
$svc = Get-Content -LiteralPath $ServerPath -Raw

# ---- the parameter ------------------------------------------------------------
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($InstallPath, [ref]$tokens, [ref]$errors)
Yes 'Install-Voice.ps1 parses' ($errors.Count -eq 0)

$param = $null
if ($ast.ParamBlock) {
    $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ChatRange' }
}
Yes 'it has a -ChatRange parameter' ($null -ne $param)

$default = $null
if ($param -and $param.DefaultValue) { $default = $param.DefaultValue.SafeGetValue() }
Yes 'and it defaults to off, so an install that does not mention it changes nothing' ($default -eq 'off')

$pattern = $null
if ($param) {
    foreach ($a in $param.Attributes) {
        if ($a.TypeName.Name -eq 'ValidatePattern') { $pattern = $a.PositionalArguments[0].SafeGetValue() }
    }
}
Yes 'a value is checked on this machine before anything is sent' ($null -ne $pattern)
if ($pattern) {
    foreach ($v in @('off', 'on', '4000', '2500')) { Yes "  $v is accepted" ($v -match $pattern) }
    foreach ($v in @('', 'loud', '-1', 'on ')) { Yes ("  '" + $v + "' is refused") (-not ($v -match $pattern)) }
}

# ---- the command line the service is started with ----------------------------
$remote = [regex]::Match($src, '(?s)\$remote = @"\r?\n(.*?)\r?\n"@')
Yes 'the install here-string is there' $remote.Success

<# What the outer script has set by the time the here-string is built, as
   Check-VoiceInstall.ps1 sets them, with the range under test. #>
function Expand([string]$range) {
    $Root = 'C:\Thornswood-Voice-Dev'
    $Port = 7789
    $TaskName = 'Thornswood Dev Voice'
    $Site = 'https://thornswood.net'
    $Bind = '0.0.0.0'
    $Auth = 'log'
    $expectBuild = 'chat-local-1'
    $ChatRange = $range
    return $ExecutionContext.InvokeCommand.ExpandString($remote.Groups[1].Value)
}

function StartLine([string]$expanded) {
    foreach ($l in ($expanded -split "`n")) {
        if ($l -match 'THORNSWOOD_VOICE_AUTH=') { return $l.Trim() }
    }
    return ''
}

if ($remote.Success) {
    $off = StartLine (Expand 'off')
    Yes 'the line that starts the service sets THORNSWOOD_CHAT_RANGE' ($off -match 'set THORNSWOOD_CHAT_RANGE=')
    Yes 'and by default it hands it off' ($off.Contains('set THORNSWOOD_CHAT_RANGE=off&&'))
    $at = $off.IndexOf('THORNSWOOD_CHAT_RANGE')
    $node = $off.IndexOf('voice-server.js')
    Yes 'before node starts, so the service is there to read it' ($at -ge 0 -and $node -gt $at)
    Yes 'no setting on that line is handed nothing' (-not ([regex]::IsMatch($off, 'set\s+[A-Z_]+=(?=&&|")')))

    Yes '-ChatRange on hands it on' ((StartLine (Expand 'on')).Contains('set THORNSWOOD_CHAT_RANGE=on&&'))
    Yes 'a number is handed through as it is' ((StartLine (Expand '2500')).Contains('set THORNSWOOD_CHAT_RANGE=2500&&'))
}

Yes 'the name the install sets is the name the service reads' ($svc.Contains('process.env.THORNSWOOD_CHAT_RANGE'))
Yes 'and the service reports its range on /health, which is what keeping it reads' ($svc -match 'chatRange:\s*CHAT_RANGE')

# ---- a later install keeps what is running -----------------------------------
Yes 'whether -ChatRange was passed is noticed' ($src.Contains('$chatExplicit = $PSBoundParameters.ContainsKey(''ChatRange'')'))
Yes 'the running service is asked when it was not' ($src.Contains('-or -not $chatExplicit'))
Yes 'and the question asks for the range' ($src.Contains('+ '';chat='' + `$h.chatRange'))

$keepAt = [regex]::Match($src, '\$chatExplicit -and "\$current" -match ''([^'']+)''')
$bindAt = [regex]::Match($src, '"\$current" -match ''(bind=[^'']+)''')
Yes 'the answer is read for a range' $keepAt.Success
Yes 'and still read for the bind and the auth' $bindAt.Success

if ($keepAt.Success -and $bindAt.Success) {
    $keep = $keepAt.Groups[1].Value
    $both = $bindAt.Groups[1].Value
    function Kept([string]$answer) {
        if ($answer -match $keep) { return $Matches[1] }
        return 'off'
    }
    Yes 'a running range of 4000 is kept' ((Kept 'bind=0.0.0.0;auth=log;chat=4000') -eq '4000')
    Yes 'a running range of 0 stays off' ((Kept 'bind=0.0.0.0;auth=log;chat=0') -eq 'off')
    Yes 'a service older than the setting, which answers with nothing, stays off' ((Kept 'bind=0.0.0.0;auth=log;chat=') -eq 'off')
    Yes 'a service that did not answer at all stays off' ((Kept 'none') -eq 'off')
    $ok = 'bind=127.0.0.1;auth=on;chat=4000' -match $both
    Yes 'the longer answer still gives up the bind and the auth' ($ok -and $Matches[1] -eq '127.0.0.1' -and $Matches[2] -eq 'on')
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
