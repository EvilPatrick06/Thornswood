<#
  test-max-online.ps1

  One number for how many a server seats, entry 281.

  WHAT WAS WRONG. The engine's slot count is maxPlayers in
  server-settings.json, and nothing in this repo ever wrote it, so it stayed
  at the 100 the skymp build puts there. The launcher's Play page says a
  different number, MaxOnline out of the launcher's config.json, 25, which
  Publish-Update.ps1 puts in the feed. People were told 25 and the engine
  seated 100.

  WHAT THIS PROVES.
    1. MaxOnline.ps1 reads MaxOnline by the same rule the feed does, number
       for number, over every shape of config.json worth trying. The feed
       half is Publish-Update.ps1's own block, lifted by text.
    2. It never quotes config.json in what it says, because that file
       carries the server password.
    3. It refuses a number the engine will not start with (above 1000).
    4. Deploy-Gamemode.ps1's settings section, lifted by text and run against
       a scratch build folder, writes the number as maxPlayers and keeps
       every other key.
    5. Deploy-DevGamemode.ps1's block that edits the dev settings on the VPS,
       lifted by text and run by Windows PowerShell against a scratch file,
       sets maxPlayers, keeps the dev port and name, and treats an unknown
       number as nothing to change.

  Nothing here reaches the VPS or reads a real config.json. Read only apart
  from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ToolsDir)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $ToolsDir) { $ToolsDir = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-maxonline-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Done {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# By name and by brace match, so a rename fails loudly rather than silently
# testing nothing.
function Get-BlockText([string]$text, [string]$start) {
    $at = $text.IndexOf($start)
    if ($at -lt 0) { return $null }
    $b = $text.IndexOf('{', $at)
    if ($b -lt 0) { return $null }
    $depth = 0
    for ($i = $b; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) } }
    }
    return $null
}

$secret = 'NOT-A-REAL-PASSWORD-281'
$utf8 = New-Object Text.UTF8Encoding($false)

# A launcher folder holding the config.json given, or none when $json is null.
function New-Root([string]$name, $json, [bool]$bom) {
    $d = Join-Path $tmp $name
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    if ($null -ne $json) {
        [IO.File]::WriteAllText((Join-Path $d 'config.json'), [string]$json, (New-Object Text.UTF8Encoding($bom)))
    }
    return $d
}

# ---- 1. the helper ----------------------------------------------------------
$helper = Join-Path $ToolsDir '..\scripts\deploy\MaxOnline.ps1'
Yes 'MaxOnline.ps1 is in tools' (Test-Path -LiteralPath $helper)
if (-not (Test-Path -LiteralPath $helper)) { Done }
. $helper
Yes 'it gives Get-MaxOnline, Set-MaxPlayers and Find-LauncherRoot' (
    [bool](Get-Command Get-MaxOnline -ErrorAction SilentlyContinue) -and
    [bool](Get-Command Set-MaxPlayers -ErrorAction SilentlyContinue) -and
    [bool](Get-Command Find-LauncherRoot -ErrorAction SilentlyContinue))

# name, config.json text (null for no file), byte order mark, the number wanted
$cases = @(
    @('plain',    ('{"MaxOnline":25,"ServerPassword":"' + $secret + '"}'), $false, 25),
    @('bom',      '{"MaxOnline":40}',                                      $true,  40),
    @('quoted',   '{"MaxOnline":"12"}',                                    $false, 12),
    @('nokey',    ('{"ServerPassword":"' + $secret + '"}'),                $false, 0),
    @('zero',     '{"MaxOnline":0}',                                       $false, 0),
    @('negative', '{"MaxOnline":-3}',                                      $false, 0),
    @('words',    '{"MaxOnline":"lots"}',                                  $false, 0),
    @('fraction', '{"MaxOnline":2.5}',                                     $false, 0),
    @('broken',   ('{"ServerPassword":"' + $secret + '", "MaxOnline": 25,,'), $false, 0),
    @('nofile',   $null,                                                   $false, 0),
    @('ceiling',  '{"MaxOnline":1000}',                                    $false, 1000)
)
$roots = @{}
foreach ($c in $cases) {
    $root = New-Root $c[0] $c[1] $c[2]
    $roots[$c[0]] = $root
    $got = $null
    try { $got = Get-MaxOnline $root } catch { $got = $null }
    Yes ("{0}: reads {1}" -f $c[0], $c[3]) ($null -ne $got -and $got.Value -eq $c[3])
    if ($null -ne $got) {
        Yes ("{0}: says which file" -f $c[0]) ($got.From -eq (Join-Path $root 'config.json'))
        if ($c[3] -eq 0) { Yes ("{0}: says why there is no number" -f $c[0]) ([string]$got.Why -ne '') }
        Yes ("{0}: never quotes the file" -f $c[0]) (-not ([string]$got.Why).Contains($secret))
    }
}

# Above the engine's ceiling is a stop, and the stop names the ceiling.
$over = New-Root 'over' ('{"MaxOnline":1001,"ServerPassword":"' + $secret + '"}') $false
$threw = $null
try { [void](Get-MaxOnline $over) } catch { $threw = $_.Exception.Message }
Yes 'above 1000 is refused rather than written' ($null -ne $threw)
Yes 'the refusal names the engine ceiling' ($null -ne $threw -and $threw.Contains('1000'))
Yes 'the refusal never quotes the file' ($null -ne $threw -and -not $threw.Contains($secret))

# ---- the feed reads the same number ----------------------------------------
#
# Publish-Update.ps1's own MaxOnline block, lifted by text with its own
# Set-Prop, run over the same files after the same parse it does. Every case
# the deploy writes, the feed announces, and every case the deploy leaves
# alone, the feed says nothing about. That is what "one number" means here.
$pu = Get-Content -LiteralPath (Join-Path $ToolsDir '..\scripts\release\Publish-Update.ps1') -Raw
$feedBlock = Get-BlockText $pu "if (`$cfg.PSObject.Properties.Name -contains 'MaxOnline')"
$setProp = Get-BlockText $pu 'function Set-Prop'
Yes 'the feed''s MaxOnline block is in Publish-Update.ps1' ($null -ne $feedBlock -and $null -ne $setProp)
if ($null -ne $feedBlock -and $null -ne $setProp) {
    . ([scriptblock]::Create($setProp))
    foreach ($c in $cases) {
        $doc = [pscustomobject]@{ version = '1.0.0' }
        $path = Join-Path $roots[$c[0]] 'config.json'
        if (Test-Path -LiteralPath $path) {
            try {
                $raw = [IO.File]::ReadAllBytes($path)
                $skip = 0
                if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $skip = 3 }
                $cfg = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
                . ([scriptblock]::Create($feedBlock))
            } catch { }
        }
        $feed = 0
        if ($doc.PSObject.Properties.Name -contains 'maxOnline') { $feed = [int]$doc.maxOnline }
        $deploy = (Get-MaxOnline $roots[$c[0]]).Value
        Yes ("{0}: the feed announces {1} and the deploy writes {2}" -f $c[0], $feed, $deploy) ($feed -eq $deploy)
    }
}

# ---- Set-MaxPlayers on its own ---------------------------------------------
$s = [pscustomobject]@{ port = 7777; maxPlayers = 100; keep = 'yes' }
Set-MaxPlayers $s ([pscustomobject]@{ Value = 25; From = 'x'; Why = '' }) 6>$null
Yes 'Set-MaxPlayers writes the number' ($s.maxPlayers -eq 25)
Yes 'and keeps every other key' ($s.port -eq 7777 -and $s.keep -eq 'yes')
$s = [pscustomobject]@{ port = 7777; maxPlayers = 100 }
Set-MaxPlayers $s ([pscustomobject]@{ Value = 0; From = 'x'; Why = 'none' }) 6>$null
Yes 'with no number it leaves maxPlayers as it was' ($s.maxPlayers -eq 100)
$s = [pscustomobject]@{ port = 7777 }
Set-MaxPlayers $s ([pscustomobject]@{ Value = 25; From = 'x'; Why = '' }) 6>$null
Yes 'it adds the key when the file had none' ($s.maxPlayers -eq 25)

# ---- 4. Deploy-Gamemode.ps1 --------------------------------------------------
$dg = Get-Content -LiteralPath (Join-Path $ToolsDir '..\scripts\deploy\Deploy-Gamemode.ps1') -Raw
$read = $dg.IndexOf('Get-MaxOnline')
$copy = $dg.IndexOf('Copy-Item -LiteralPath $Gamemode')
Yes 'Deploy-Gamemode.ps1 dot-sources MaxOnline.ps1' ($dg.Contains("Join-Path `$Here 'MaxOnline.ps1'"))
Yes 'it reads the number before it writes anything into the build' ($read -ge 0 -and $copy -gt $read)

$from = $dg.IndexOf('# ---- rewrite server-settings.json')
$to = -1
if ($from -ge 0) { $to = $dg.IndexOf('[IO.File]::WriteAllText($settingsPath', $from) }
if ($to -ge 0) { $to = $dg.IndexOf("`n", $to) }
Yes 'the settings section is in Deploy-Gamemode.ps1' ($from -ge 0 -and $to -gt $from)
if ($from -ge 0 -and $to -gt $from) {
    $section = $dg.Substring($from, $to - $from)

    function Invoke-Section([string]$dist, $maxOnline) {
        $Dist = $dist
        $paths = @('C:/Data/Skyrim.esm', 'C:/Data/Skyrim Unbound.esp')
        $ServerName = 'Thornswood'; $Port = 7777; $VoicePort = 7778; $Npcs = 'all'
        $HitsOnPeople = 1.0; $HitsOnNpcs = 2.0; $Devs = @(); $Playtesters = @()
        . ([scriptblock]::Create($section)) 6>$null
    }
    function Seed-Built([string]$dist) {
        New-Item -ItemType Directory -Force -Path $dist | Out-Null
        [IO.File]::WriteAllText((Join-Path $dist 'server-settings.json'),
            '{"port":7777,"name":"Thornswood","maxPlayers":100,"keepMe":"yes","loadOrder":[]}', $utf8)
    }

    $dist = Join-Path $tmp 'dist'
    Seed-Built $dist
    $ok = $true
    try { Invoke-Section $dist (Get-MaxOnline $roots['plain']) } catch { $ok = $false; Write-Host ("      " + $_.Exception.Message) }
    Yes 'the lifted settings section runs against a scratch build' $ok
    $w = Get-Content -LiteralPath (Join-Path $dist 'server-settings.json') -Raw | ConvertFrom-Json
    Yes 'the built settings carry maxPlayers 25, from MaxOnline' ([int]$w.maxPlayers -eq 25)
    Yes 'a key nobody sets there survives' ($w.keepMe -eq 'yes')
    Yes 'the file has no byte order mark' ([IO.File]::ReadAllBytes((Join-Path $dist 'server-settings.json'))[0] -ne 0xEF)

    Seed-Built $dist
    $ok = $true
    try { Invoke-Section $dist (Get-MaxOnline $roots['nokey']) } catch { $ok = $false; Write-Host ("      " + $_.Exception.Message) }
    $w = Get-Content -LiteralPath (Join-Path $dist 'server-settings.json') -Raw | ConvertFrom-Json
    Yes 'with no number the build keeps its 100' ($ok -and [int]$w.maxPlayers -eq 100)
}

# ---- 5. Deploy-DevGamemode.ps1 ----------------------------------------------
$dd = Get-Content -LiteralPath (Join-Path $ToolsDir '..\scripts\deploy\Deploy-DevGamemode.ps1') -Raw
$read = $dd.IndexOf('Get-MaxOnline')
$stop = $dd.IndexOf("Write-Host 'Stopping the dev server...'")
Yes 'Deploy-DevGamemode.ps1 dot-sources MaxOnline.ps1' ($dd.Contains("Join-Path `$Here 'MaxOnline.ps1'"))
Yes 'it reads the number before the dev server is stopped' ($read -ge 0 -and $stop -gt $read)
Yes 'its number comes from the dev launcher, the one the dev feed reads' ($dd.Contains("(Find-LauncherRoot) + '-DevBuild'"))

$marker = $dd.IndexOf('`$p = ''$rootWin\server-settings.json''')
$open = -1; $close = -1
if ($marker -ge 0) {
    $open = $dd.LastIndexOf('Remote @"', $marker)
    $close = $dd.IndexOf("`n" + '"@', $marker)
}
Yes 'the block that edits the dev settings is in Deploy-DevGamemode.ps1' ($open -ge 0 -and $close -gt $marker)
if ($open -ge 0 -and $close -gt $marker) {
    $bodyAt = $dd.IndexOf("`n", $open) + 1
    $body = ($dd.Substring($bodyAt, $close - $bodyAt) -replace "`r`n", "`n").TrimEnd("`r", "`n")

    # Expanded the way the real script expands it, as the here-string it is,
    # with the values the script would put in.
    function Expand-Remote([string]$rootWin, $maxOnline) {
        $farOrder = ''
        $remotePlugins = 'C:/Thornswood-Server-Dev/plugins'
        $VoicePort = 7789
        return & ([scriptblock]::Create('@"' + "`n" + $body + "`n" + '"@'))
    }

    # The far end is Windows PowerShell 5.1, so that is what runs it.
    $ps = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $psExe = if ($ps) { $ps.Source } else { (Get-Process -Id $PID).Path }

    function Invoke-Remote([string]$rootWin, $maxOnline) {
        $text = Expand-Remote $rootWin $maxOnline
        $file = Join-Path $tmp ('remote-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($true)))
        # Continue, so a line on stderr is output to read rather than a stop
        # under Windows PowerShell.
        $ErrorActionPreference = 'Continue'
        return @(& $psExe -NoProfile -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { [string]$_ })
    }
    function Seed-Dev([string]$root, [bool]$withMax) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $max = ''
        if ($withMax) { $max = '"maxPlayers":100,' }
        [IO.File]::WriteAllText((Join-Path $root 'server-settings.json'),
            ('{"port":7787,"name":"Thornswood Dev",' + $max + '"thornswoodVoicePort":7789,' +
             '"equipmentSlotCheckEnabled":false,"equipmentSpellCheckEnabled":false,' +
             '"equipmentInventoryCheckEnabled":false,"dataDir":"data",' +
             '"npcAllowCrimeFaction":true,"npcAllowEssential":true,"thornswoodServer":"dev",' +
             '"loadOrder":["C:/Thornswood-Server-Dev/plugins/Skyrim.esm"]}'), $utf8)
    }
    function Read-Dev([string]$root) { Get-Content -LiteralPath (Join-Path $root 'server-settings.json') -Raw | ConvertFrom-Json }

    $dev = Join-Path $tmp 'dev-root'
    Seed-Dev $dev $true
    $out = Invoke-Remote $dev 25
    $w = Read-Dev $dev
    Yes 'the dev block sets maxPlayers to 25' ([int]$w.maxPlayers -eq 25)
    Yes 'and says it moved from 100' (($out -join "`n").Contains('the most online moves from 100 to 25'))
    Yes 'the dev port and name are untouched' ([int]$w.port -eq 7787 -and $w.name -eq 'Thornswood Dev')
    Yes 'the read back names the number' (($out -join "`n").Contains('most online 25'))
    Yes 'the dev file has no byte order mark' ([IO.File]::ReadAllBytes((Join-Path $dev 'server-settings.json'))[0] -ne 0xEF)
    if ([int]$w.maxPlayers -ne 25) { foreach ($l in $out) { Write-Host ("      " + $l) } }

    $out = Invoke-Remote $dev 25
    Yes 'a second run finds nothing to change' ((($out -join "`n").Contains('already')) -and [int](Read-Dev $dev).maxPlayers -eq 25)

    Seed-Dev $dev $true
    $out = Invoke-Remote $dev 0
    Yes 'with no number the dev server keeps its 100' ([int](Read-Dev $dev).maxPlayers -eq 100)
    Yes 'and an unknown number is not a reason to rewrite' (($out -join "`n").Contains('already'))

    Seed-Dev $dev $false
    $out = Invoke-Remote $dev 25
    Yes 'a dev file with no maxPlayers gets one' ([int](Read-Dev $dev).maxPlayers -eq 25)
}

Done
