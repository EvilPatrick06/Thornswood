<#
  test-publish-server-channel.ps1

  A dev Publish-Server packs the dev ports without leaving them in the local
  build, and a live one packs 7777 or nothing (#1114).

  WHY THIS EXISTS. A dev publish (-Channel dev) rewrote the build's own
  server-settings.json in place, to port 7787, voice 7789 and the name
  Thornswood Dev, with Set-Content -Encoding UTF8 (a byte order mark under
  Windows PowerShell), and never put it back. The next live publish without
  Deploy-Gamemode.ps1 in between packed those for the live server, and the run
  said only that the server did not come up.

  HOW. The real Publish-Server.ps1 and Export-ServerPayload.ps1 run in a child
  PowerShell against a scratch build, with ssh and scp stand-ins first on PATH
  (they write down what they were asked and say INSTALL OK), and a listener on
  this machine standing in for the resources port the run probes afterwards:

    1. a dev publish: the zip starts the server on 7787, voice 7789, named
       Thornswood Dev, with no byte order mark, and the build's own settings
       are byte for byte what they were
    2. a live publish straight after: the zip starts it on 7777
    3. a build left on the dev ports by an older dev publish: the live publish
       refuses before anything is sent
    4. -SkipBuild with a dev zip on the live channel: refused, nothing sent
    5. Export-ServerPayload.ps1 by itself, the same way round
    6. a binary that is not the build the record names (#1214): refused
       before anything is sent, by a publish on either channel, by -SkipBuild
       with a zip made from it, and by Export-ServerPayload by itself; a good
       zip carries the record, for the installer to hold it again
    7. a build whose npcSettings has a "default" key, which refuses every NPC
       (#1222): refused on either channel before anything is sent; a dev zip
       says thornswoodServer dev, and a live export of one that says dev is
       refused; ServerSettings.ps1 goes up beside the installer

  Run under whichever PowerShell runs this file, so running it under both
  checks both. Nothing here connects to the VPS.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$publish = Join-Path $repo 'scripts\release\Publish-Server.ps1'
$export = Join-Path $repo 'scripts\release\Export-ServerPayload.ps1'
Yes 'Publish-Server.ps1 and Export-ServerPayload.ps1 are there' ((Test-Path -LiteralPath $publish) -and (Test-Path -LiteralPath $export))

$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-pubserver-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$dist = Join-Path $T 'dist'
$bin = Join-Path $T 'bin'
$zip = Join-Path $T 'out\thornswood-server.zip'
$log = Join-Path $T 'calls.log'
$utf8 = New-Object Text.UTF8Encoding($false)
$shell = (Get-Process -Id $PID).Path
$oldPath = $env:PATH; $oldCalls = $env:TS_PUB_CALLS
$listeners = @()

$record = Join-Path $T 'server-build.json'
function Write-Live {
    param([int]$Port = 7777, [string]$Name = 'Thornswood', [int]$Voice = 7778, [string]$Server = '', [switch]$NpcDefault)
    $esp = (Join-Path $T 'plugins\ours.esp').Replace('\', '/')
    $s = [ordered]@{
        name = $Name; port = $Port; thornswoodVoicePort = $Voice; maxPlayers = 100
        loadOrder = @($esp); startPoints = @(@{ worldOrCell = '0x3C'; pos = @(0, 0, 0); angleZ = 0 })
    }
    if ($Server) { $s.thornswoodServer = $Server }
    if ($NpcDefault) { $s.npcSettings = @{ default = @{ spawnInInterior = $true; spawnInExterior = $true } } }
    [IO.File]::WriteAllText((Join-Path $dist 'server-settings.json'), ($s | ConvertTo-Json -Depth 6), $utf8)
}
function Hash([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
# The binary in the build, and a record naming a build: -For says which.
function Write-Binary([string]$text) { [IO.File]::WriteAllText((Join-Path $dist 'scam_native.node'), $text, $utf8) }
function Write-Record([string]$for, [string]$path = $record) {
    $h = [Security.Cryptography.SHA256]::Create()
    $sum = (-join ($h.ComputeHash($utf8.GetBytes($for)) | ForEach-Object { $_.ToString('x2') }))
    $h.Dispose()
    [IO.File]::WriteAllText($path, ('{ "binary": "scam_native.node", "sha256": "' + $sum + '" }'), $utf8)
    return $sum
}
# What the zip starts the server with, and whether its settings start with a BOM.
function Read-Zip([string]$path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $e = $z.GetEntry('server-settings.json')
        $ms = New-Object IO.MemoryStream
        $st = $e.Open(); try { $st.CopyTo($ms) } finally { $st.Dispose() }
        $b = $ms.ToArray()
        $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
        $j = ($utf8.GetString($b) -replace '^\uFEFF', '') | ConvertFrom-Json
        $rec = ''
        $re = $z.GetEntry('server-build.json')
        if ($re) {
            $rr = New-Object IO.StreamReader($re.Open())
            try { $rec = [string]($rr.ReadToEnd() | ConvertFrom-Json).sha256 } finally { $rr.Dispose() }
        }
        $server = ''
        if ($j.PSObject.Properties['thornswoodServer']) { $server = [string]$j.thornswoodServer }
        return [pscustomobject]@{ Port = [string]$j.port; Voice = [string]$j.thornswoodVoicePort; Name = [string]$j.name; Bom = $bom; Rec = $rec; Server = $server }
    } finally { $z.Dispose() }
}
function Run([string]$script, [string[]]$more) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = (& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script @more 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $calls = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Where-Object { $_ } })
    # PowerShell 7 prints an error wrapped to the window, each piece on a line
    # of its own after a '|', so a message can break in the middle of the
    # words matched below. Joined back up.
    $out = $out -replace '\r?\n\s+\|\s+', ' '
    return [pscustomobject]@{ Code = $code; Out = $out; Calls = $calls }
}
function Publish([string[]]$more) {
    return Run $publish (@('-Dist', $dist, '-Zip', $zip, '-Record', $record, '-VpsHost', '127.0.0.1', '-VpsUser', 'test', '-NoPause', '-NoNews', '-NoPush', '-Wait', '1') + @($more))
}
function Tail($r, [bool]$ok) { if (-not $ok) { Write-Host (($r.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 12) -join "`n") -ForegroundColor DarkGray } }
function Sent($r) { return @($r.Calls | Where-Object { $_ -match '^scp .*thornswood-server\.zip' }).Count }

try {
    foreach ($d in $dist, $bin, (Join-Path $T 'plugins'), (Split-Path -Parent $zip)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText((Join-Path $T 'plugins\ours.esp'), 'a plugin', $utf8)
    [IO.File]::WriteAllText((Join-Path $dist 'skymp5-server.js'), '// the server', $utf8)
    Write-Binary 'the recorded binary'
    $recSum = Write-Record 'the recorded binary'
    # PowerShell scripts rather than .cmd files: a .cmd runs through cmd.exe,
    # which splits an unquoted argument at an ampersand, and a temp folder can
    # have one in its path. The real ssh and scp are programs and take it whole.
    foreach ($n in 'ssh', 'scp') {
        [IO.File]::WriteAllText((Join-Path $bin ($n + '.ps1')),
            "[IO.File]::AppendAllText(`$env:TS_PUB_CALLS, ('$n ' + (`$args -join ' ') + [Environment]::NewLine))`r`n'INSTALL OK'`r`nexit 0`r`n")
    }
    $env:PATH = $bin + ';' + $oldPath
    $env:TS_PUB_CALLS = $log
    # The resources ports the run probes afterwards, dev's and live's. The
    # operating system answers a connect for a started listener by itself.
    foreach ($p in 7788, 3000) {
        try { $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p); $l.Start(); $listeners += $l } catch { }
    }

    # ---- 1. a dev publish ---------------------------------------------------------
    Write-Host ''; Write-Host 'a dev publish'
    Write-Live
    $settings = Join-Path $dist 'server-settings.json'
    $r = Publish @('-Channel', 'dev')
    $ok = $r.Code -eq 0 -and (Sent $r) -eq 1
    Yes ("a dev publish runs through and sends its zip (exit {0})" -f $r.Code) $ok; Tail $r $ok
    $z = Read-Zip $zip
    Yes ("  the zip starts the dev server: port {0}, voice {1}, name {2}" -f $z.Port, $z.Voice, $z.Name) ($z.Port -eq '7787' -and $z.Voice -eq '7789' -and $z.Name -eq 'Thornswood Dev')
    Yes '  its settings have no byte order mark' (-not $z.Bom)
    Yes ("  it says thornswoodServer {0}, for a first install into an empty dev root" -f $z.Server) ($z.Server -eq 'dev')
    Yes '  and it carries the build record, for the installer to hold the binary to (#1214)' ($z.Rec -eq $recSum)
    Yes '  and ServerSettings.ps1 went up beside the installer (#1222)' (@($r.Calls | Where-Object { $_ -match '^scp .*ServerSettings\.ps1 .*C:/ServerSettings\.ps1' }).Count -eq 1)
    $local = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    Yes ("  and the build's own settings are the live ones still (port {0}, name {1})" -f $local.port, $local.name) ([int]$local.port -eq 7777 -and $local.name -eq 'Thornswood' -and [int]$local.thornswoodVoicePort -eq 7778)
    # The gamemode and the number of seats are the build's, written the same on
    # any channel; the ports and the name are all that must not have moved.
    $ports = @('port', 'name', 'thornswoodVoicePort' | ForEach-Object { [string]$local.$_ })
    Yes '  byte for byte where a channel is concerned' (($ports -join '|') -eq '7777|Thornswood|7778')
    $b = [IO.File]::ReadAllBytes($settings)
    Yes '  and no byte order mark was written into it' (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB))

    # ---- 2. the live publish straight after -----------------------------------------
    Write-Host ''; Write-Host 'a live publish after it'
    $r = Publish @('-Channel', 'main')
    $ok = $r.Code -eq 0 -and (Sent $r) -eq 1
    Yes ("a live publish after the dev one runs through (exit {0})" -f $r.Code) $ok; Tail $r $ok
    $z = Read-Zip $zip
    Yes ("  and packs port {0}, voice {1}, name {2}" -f $z.Port, $z.Voice, $z.Name) ($z.Port -eq '7777' -and $z.Voice -eq '7778' -and $z.Name -eq 'Thornswood')

    # ---- 3. a build an older dev publish left on the dev ports ------------------------
    Write-Host ''; Write-Host 'a build left on the dev ports'
    $devZip = Join-Path $T 'dev.zip'
    [void](Publish @('-Channel', 'dev')); Copy-Item -LiteralPath $zip -Destination $devZip -Force
    Write-Live -Port 7787 -Name 'Thornswood Dev' -Voice 7789
    $r = Publish @('-Channel', 'main')
    $ok = $r.Code -ne 0 -and (Sent $r) -eq 0 -and $r.Out -match 'not the live server''s' -and $r.Out -match 'port 7787'
    Yes ("a live publish refuses them, and sends nothing (exit {0})" -f $r.Code) $ok; Tail $r $ok
    Yes '  and says what to run' ($r.Out -match 'Deploy-Gamemode\.ps1')

    # ---- 4. -SkipBuild with the other channel's zip ------------------------------------
    Write-Host ''; Write-Host '-SkipBuild'
    Write-Live
    Copy-Item -LiteralPath $devZip -Destination $zip -Force
    $r = Publish @('-Channel', 'main', '-SkipBuild')
    $ok = $r.Code -ne 0 -and (Sent $r) -eq 0 -and $r.Out -match 'port 7787, and the main server is 7777'
    Yes ("a live publish of a dev zip is refused before it is sent (exit {0})" -f $r.Code) $ok; Tail $r $ok
    $r = Publish @('-Channel', 'dev', '-SkipBuild')
    $ok = $r.Code -eq 0 -and (Sent $r) -eq 1
    Yes ("  and the same zip goes to dev (exit {0})" -f $r.Code) $ok; Tail $r $ok

    # ---- 5. Export-ServerPayload.ps1 by itself -------------------------------------------
    Write-Host ''; Write-Host 'Export-ServerPayload.ps1'
    $ex = @('-Dist', $dist, '-Zip', $zip, '-OutDir', (Join-Path $T 'out\_payload'), '-Record', $record)
    $x = Run $export ($ex + @('-Channel', 'dev'))
    $z = Read-Zip $zip
    Yes ("-Channel dev packs 7787 into the payload only (exit {0})" -f $x.Code) ($x.Code -eq 0 -and $z.Port -eq '7787' -and [int](Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).port -eq 7777)
    $x = Run $export $ex
    $z = Read-Zip $zip
    Yes ("no channel is live, and packs 7777 (exit {0})" -f $x.Code) ($x.Code -eq 0 -and $z.Port -eq '7777')
    Yes '  with the build record in it' ($z.Rec -eq $recSum)
    Write-Live -Port 7777 -Name 'Thornswood' -Voice 7789
    $x = Run $export $ex
    Yes ("a live export of the dev voice port is refused (exit {0})" -f $x.Code) ($x.Code -ne 0 -and $x.Out -match 'dev voice port 7789')
    Write-Live -Server 'dev'
    $x = Run $export $ex
    Yes ("a live export of settings that say thornswoodServer dev is refused (exit {0})" -f $x.Code) ($x.Code -ne 0 -and $x.Out -match 'thornswoodServer dev')

    # ---- 6. a binary that is not the recorded build (#1214) ---------------------------
    Write-Host ''; Write-Host 'a binary that is not the recorded build'
    Write-Live
    Write-Binary 'some other binary'
    foreach ($ch in 'dev', 'main') {
        $r = Publish @('-Channel', $ch)
        $ok = $r.Code -ne 0 -and (Sent $r) -eq 0 -and @($r.Calls | Where-Object { $_ -match '^(ssh|scp) ' }).Count -eq 0 -and $r.Out -match 'not the build'
        Yes ("a $ch publish of it is refused before anything is sent (exit {0})" -f $r.Code) $ok; Tail $r $ok
    }
    $x = Run $export $ex
    Yes ("Export-ServerPayload by itself refuses it too (exit {0})" -f $x.Code) ($x.Code -ne 0 -and $x.Out -match 'not the build' -and $x.Out -match 'Nothing was packed')
    # A zip made from it against a record that names it, sent with -SkipBuild
    # against the real record: refused from what is in the zip.
    $other = Join-Path $T 'other-record.json'
    [void](Write-Record 'some other binary' $other)
    $x = Run $export @('-Dist', $dist, '-Zip', $zip, '-OutDir', (Join-Path $T 'out\_payload'), '-Record', $other, '-Channel', 'dev')
    Yes ("  (a zip made from it, against a record naming it, exit {0})" -f $x.Code) ($x.Code -eq 0)
    $r = Publish @('-Channel', 'dev', '-SkipBuild')
    $ok = $r.Code -ne 0 -and (Sent $r) -eq 0 -and $r.Out -match 'not the recorded build'
    Yes ("-SkipBuild with that zip is refused before it is sent (exit {0})" -f $r.Code) $ok; Tail $r $ok
    Write-Binary 'the recorded binary'
    $r = Publish @('-Channel', 'dev')
    $ok = $r.Code -eq 0 -and (Sent $r) -eq 1 -and $r.Out -match 'payload binary is the recorded build'
    Yes ("  and the recorded binary goes again (exit {0})" -f $r.Code) $ok; Tail $r $ok

    # ---- 7. an npcSettings "default" key (#1222) -----------------------------------------
    Write-Host ''; Write-Host 'an npcSettings default key'
    Write-Live -NpcDefault
    foreach ($ch in 'dev', 'main') {
        $r = Publish @('-Channel', $ch)
        $ok = $r.Code -ne 0 -and (Sent $r) -eq 0 -and $r.Out -match 'refuses every NPC'
        Yes ("a $ch publish of a build whose npcSettings has a default key is refused, nothing sent (exit {0})" -f $r.Code) $ok; Tail $r $ok
    }
    Write-Live
}
finally {
    foreach ($l in $listeners) { try { $l.Stop() } catch { } }
    $env:PATH = $oldPath; $env:TS_PUB_CALLS = $oldCalls
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}
Done
