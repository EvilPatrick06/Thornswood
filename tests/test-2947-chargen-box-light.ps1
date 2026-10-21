<#
  test-2947-chargen-box-light.ps1

      pwsh -NoProfile -File .\tests\test-2947-chargen-box-light.ps1
      powershell -NoProfile -File .\tests\test-2947-chargen-box-light.ps1

  Check-Chargen.ps1 -From dev and -From live read which plugins are light on
  the box, from the files the server loads, and whether its engine loads
  them from the server's own server-build.json (#2947).

  WHY. Until #2947 both came from the machine running the check: the headers
  in -Data (C:\Thornswood\Game\Data) and this checkout's record. On a machine
  with no game folder, a cloud one, Get-ThornswoodLightTest threw on the
  first plugin it could not find, so the check stopped before it said
  anything; and a game folder holding another copy of a plugin answered for
  a file the server does not load.

  HOW. The script the check sends is lifted out of Check-Chargen.ps1,
  expanded here with the values the check would give it (the server root and
  Test-ThornswoodPluginLight from ServerOrder.ps1), and run in Windows
  PowerShell, what sshd runs on the box, against a server folder made in a
  temp folder: a server-settings.json, a server-build.json and plugin files
  whose TES4 headers say light or not. Nothing connects to anything.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Windows.ps1')
# What this runs, the box runs in Windows PowerShell 5.1; off Windows, this shell.
if ($OnWindows) { $winPs = Get-WindowsPowerShell }
else {
    $winPs = (Get-Process -Id $PID).Path
    Write-Host 'NOTE  the far side runs in this shell, not in Windows PowerShell 5.1 as on the box: this is not Windows'
}

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$check = Join-Path $repo 'scripts\ops\Check-Chargen.ps1'
. (Join-Path $repo 'scripts\deploy\ServerOrder.ps1')

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$text = [IO.File]::ReadAllText($check)
$open = $text.IndexOf('$remote = @"')
$close = -1
$m = [regex]::Match($text.Substring([Math]::Max($open, 0)), '\r?\n"@')
if ($open -ge 0 -and $m.Success) { $close = $open + $m.Index }
Yes 'the script the check sends is where it was' ($open -ge 0 -and $close -gt $open)
$body = $text.Substring($open + '$remote = @"'.Length, $close - $open - '$remote = @"'.Length).Trim("`r", "`n")
Yes 'it reads each plugin with Test-ThornswoodPluginLight, sent up with it' ($body.Contains('$lightDef') -and $body.Contains('Test-ThornswoodPluginLight `$f'))
Yes '  and the server''s own server-build.json' ($body.Contains('$root\server-build.json'))
# Only the build on this machine reads -Data and this checkout's record.
$build = [regex]::IsMatch($text, "if \(\`$From -eq 'build'\) \{\s*\`$lightTest = Get-ThornswoodLightTest")
Yes 'a server''s light plugins are not read from -Data' ($build -and ([regex]::Matches($text, 'Get-ThornswoodLightTest')).Count -eq 1)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-chargen-light-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $tmp 'plugins') -Force | Out-Null

function Write-Plugin([string]$name, [bool]$light) {
    $b = New-Object byte[] 24
    [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($b, 0)
    $flags = [uint32]0
    if ($light) { $flags = [uint32]0x200 }
    [BitConverter]::GetBytes($flags).CopyTo($b, 8)
    [IO.File]::WriteAllBytes((Join-Path (Join-Path $tmp 'plugins') $name), $b)
}

# $engine is the server-build.json text, or $null for none.
function Run-Remote([string[]]$order, $engine) {
    $root = $tmp
    $settingsPath = Join-Path $tmp 'server-settings.json'
    $settings = [ordered]@{ port = 7787; loadOrder = @($order | ForEach-Object { (Join-Path (Join-Path $tmp 'plugins') $_).Replace('\', '/') }) }
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
    $rp = Join-Path $tmp 'server-build.json'
    if ($null -eq $engine) { Remove-Item -LiteralPath $rp -Force -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllText($rp, $engine, (New-Object Text.UTF8Encoding $false)) }
    $lightDef = 'function Test-ThornswoodPluginLight {' + "`n" + (Get-Command Test-ThornswoodPluginLight).Definition + "`n}"
    $expanded = $ExecutionContext.InvokeCommand.ExpandString($body)
    $file = Join-Path $tmp 'remote.ps1'
    [IO.File]::WriteAllText($file, $expanded, (New-Object Text.UTF8Encoding $true))
    return @(& $winPs -NoProfile -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { "$_" })
}

try {
    Write-Plugin 'Skyrim.esm' $false
    Write-Plugin 'Light One.esp' $true
    Write-Plugin 'Skyrim Unbound.esp' $false
    $order = @('Skyrim.esm', 'Light One.esp', '_ResourcePack.esl', 'Skyrim Unbound.esp')

    $said = Run-Remote $order '{ "lightPlugins": true }'
    Yes 'each plugin the order names is read on the box' (
        ($said -contains 'LIGHT 0 Skyrim.esm') -and ($said -contains 'LIGHT 1 Light One.esp') -and
        ($said -contains 'LIGHT 1 _ResourcePack.esl') -and ($said -contains 'LIGHT 0 Skyrim Unbound.esp'))
    Yes '  and the engine is the server''s record: ENGINE True' ($said -contains 'ENGINE True')
    $at = [Array]::IndexOf([string[]]$said, 'SETTINGS')
    $json = (@($said | Select-Object -Skip ($at + 1)) -join "`n")
    Yes '  and the settings follow SETTINGS whole' ($at -ge 0 -and @(($json | ConvertFrom-Json).loadOrder).Count -eq 4)

    $said = Run-Remote $order '{ "lightPlugins": false }'
    Yes 'a record that says its engine does not load them: ENGINE False' ($said -contains 'ENGINE False')
    $said = Run-Remote $order $null
    Yes 'no record on the server: ENGINE none, which the check refuses' ($said -contains 'ENGINE none' -and $text.Contains("so it is not known whether its engine loads light plugins"))
    $said = Run-Remote $order '{ not json'
    Yes 'a record that does not read: ENGINE unreadable' ($said -contains 'ENGINE unreadable')

    $said = Run-Remote @('Skyrim.esm', 'Mystery.esp', 'Skyrim Unbound.esp') '{ "lightPlugins": true }'
    Yes 'a plugin the server does not have is named, not guessed' ($said -contains 'UNREAD Mystery.esp' -and -not @($said | Where-Object { $_ -like 'LIGHT * Mystery.esp' }).Count)
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
