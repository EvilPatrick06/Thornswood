<#
  Align-LoadOrder.ps1

  The client counts its own plugins with Game.GetModCount, which skips every
  ESL-flagged one because Skyrim gives those no normal index. The server counts
  the list in server-settings.json. Those two numbers have to be identical, and
  every entry has to line up position for position, because SkyMP resolves a
  form as fileIdx * 0x01000000 + shortFormId and nothing translates between the
  two sides. One extra plugin on either side and forms silently resolve to the
  wrong objects.

  The yellow LOAD ORDER WARNING on screen is that mismatch. It does not
  disconnect you, which is worse: it means you play with wrong indices.

  The usual cause on this setup: a plugin that is not itself light but masters
  to one that is. Deploy-Gamemode has to drop it server side, because libespm
  will not load a plugin whose master is absent. The game has no such problem,
  so it keeps it and gets an extra index. This finds those and, with -Fix,
  switches them off client side so the two lists match exactly.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Data     = 'C:\Thornswood\Game\Data',
    [string]$Plugins  = 'C:\Thornswood\Profile\Default\plugins.txt',
    [string]$Settings = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerSettings),
    [switch]$Fix,
    # Other plugin lists -Fix also edits, beside the two names next to -Plugins.
    # The launcher's LocalAppData copy by default; a test passes @() so nothing
    # outside its scratch folder is written.
    [string[]]$AlsoFix = @('C:\Thornswood\Profile\LocalAppData\Plugins.txt')
)
. (Join-Path $PSScriptRoot '..\release\Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named

$ErrorActionPreference = 'Stop'
foreach ($p in @($Data, $Plugins, $Settings)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}

function Test-Light([string]$path) {
    if ($path -match '\.esl$') { return $true }
    try {
        $fs = [IO.File]::OpenRead($path)
        $b = New-Object byte[] 12
        [void]$fs.Read($b, 0, 12)
        $fs.Close()
        if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { return $false }
        return ([BitConverter]::ToUInt32($b, 8) -band 0x200) -ne 0
    } catch { return $false }
}

$implicit = 'Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm'
$fromFile = Get-Content -LiteralPath $Plugins |
            Where-Object { $_ -match '^\*' } |
            ForEach-Object { $_.TrimStart('*').Trim() }
$wanted = @($implicit | Where-Object { $fromFile -notcontains $_ }) + $fromFile

# What the game will give a normal index to, in order.
$gameList = @()
foreach ($p in $wanted) {
    $full = Join-Path $Data $p
    if (-not (Test-Path -LiteralPath $full)) { continue }
    if (Test-Light $full) { continue }
    $gameList += $p
}

$server = @((ConvertFrom-ThornswoodJson (Get-Content -LiteralPath $Settings -Raw) $Settings).loadOrder |
            ForEach-Object { [IO.Path]::GetFileName($_) })

Write-Host ''
Write-Host ("game will index : {0} plugins" -f $gameList.Count) -ForegroundColor Cyan
Write-Host ("server lists    : {0} plugins" -f $server.Count) -ForegroundColor Cyan

# Walk both in step and name the first place they part company.
$extra = @()
$si = 0
for ($gi = 0; $gi -lt $gameList.Count; $gi++) {
    # A server entry the game will not index is reported as missing below; it
    # is stepped over here, or every plugin after it would read as extra and
    # -Fix would switch them all off.
    while ($si -lt $server.Count -and $gameList -notcontains $server[$si]) { $si++ }
    if ($si -lt $server.Count -and $gameList[$gi] -ieq $server[$si]) { $si++; continue }
    $extra += $gameList[$gi]
}

$missing = @($server | Where-Object { $gameList -notcontains $_ })

if ($extra.Count -eq 0 -and $missing.Count -eq 0) {
    Write-Host ''
    Write-Host 'The two lists match exactly. No warning should appear in game.' -ForegroundColor Green
    return
}

if ($missing.Count) {
    Write-Host ''
    Write-Host 'The server lists these and the game will not index them:' -ForegroundColor Red
    foreach ($m in $missing) { Write-Host ("  {0}" -f $m) -ForegroundColor Red }
    Write-Host '  Run Deploy-Gamemode.ps1 to rebuild the server list from this machine.' -ForegroundColor DarkGray
}

if ($extra.Count) {
    Write-Host ''
    Write-Host 'The game will index these and the server does not have them:' -ForegroundColor Yellow
    foreach ($e in $extra) {
        $masters = @()
        try {
            $fs = [IO.File]::OpenRead((Join-Path $Data $e))
            $len = [Math]::Min(16384, $fs.Length); $b = New-Object byte[] $len
            [void]$fs.Read($b, 0, $len); $fs.Close()
            for ($i = 0; $i -lt $b.Length - 6; $i++) {
                if ($b[$i] -eq 0x4D -and $b[$i+1] -eq 0x41 -and $b[$i+2] -eq 0x53 -and $b[$i+3] -eq 0x54) {
                    $sz = [BitConverter]::ToUInt16($b, $i+4)
                    if ($sz -gt 0 -and $sz -lt 260 -and ($i+6+$sz) -le $b.Length) {
                        $s = [Text.Encoding]::GetEncoding(1252).GetString($b, $i+6, $sz).TrimEnd([char]0)
                        if ($s -match '\.es[pml]$') { $masters += $s }
                    }
                }
            }
        } catch { }
        $lightMasters = @($masters | Select-Object -Unique | Where-Object {
            $mp = Join-Path $Data $_
            (Test-Path -LiteralPath $mp) -and (Test-Light $mp)
        })
        if ($lightMasters.Count) {
            Write-Host ("  {0}   masters to a light plugin: {1}" -f $e, ($lightMasters -join ', ')) -ForegroundColor Yellow
        } else {
            Write-Host ("  {0}" -f $e) -ForegroundColor Yellow
        }
    }

    if (-not $Fix) {
        Write-Host ''
        Write-Host 'Run again with -Fix to switch those off client side so the lists match.' -ForegroundColor DarkGray
        return
    }

    $targets = @('plugins.txt','Plugins.txt' | ForEach-Object {
        Join-Path (Split-Path $Plugins -Parent) $_
    }) + @($AlsoFix | Where-Object { $_ })
    $seen = @{}
    foreach ($t in ($targets | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        if ($seen[$t.ToLower()]) { continue }
        $seen[$t.ToLower()] = $true
        $lines = Get-Content -LiteralPath $t
        $out = @()
        $off = 0
        foreach ($line in $lines) {
            $name = $line.TrimStart('*').Trim()
            if ($line -match '^\*' -and ($extra -contains $name)) {
                if ($PSCmdlet.ShouldProcess("$name in $(Split-Path $t -Leaf)", 'disable')) {
                    $out += $name; $off++
                    continue
                }
            }
            $out += $line
        }
        if ($off) {
            # WriteAllLines, not Set-Content -Encoding UTF8: that adds a byte order mark
            # under Windows PowerShell 5.1 and not under 7, so the same line produces a
            # different file depending on who runs it. The game and SkyrimPlatform both
            # stop on a BOM, and the .cmd wrappers use 5.1.
            [IO.File]::WriteAllLines($t, $out, (New-Object Text.UTF8Encoding($false)))
            Write-Host ("  {0,-46} {1} switched off" -f (Split-Path $t -Leaf), $off) -ForegroundColor Cyan
        }
    }
    Write-Host ''
    Write-Host 'Now run Deploy-Gamemode.ps1 so the server list is rebuilt from the new plugins.txt.' -ForegroundColor Green
}
