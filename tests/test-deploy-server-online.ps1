<#
  test-deploy-server-online.ps1

  Deploy-Server.ps1 treats a server with nothing listening as nobody online,
  and removes a leftover restart.json when it stops. Issue #524: the live
  half of the same two gaps Deploy-DevGamemode closed. Issue #520 keeps the
  same OnlineNow listen check and puts the warn/refuse path beside it.

  HOW. The live warning block (Read-LiveOnline / Get-LiveOnline / OnlineNow)
  is taken out of the deploy and driven with Remote replaced by a local run
  against a temp folder, with a real UDP socket on loopback standing in for
  the server, and with none. StopOurs is taken out of the swap block and run
  against the same temp folder, with everything in it that stops a task or
  a process replaced by a stand-in.

  Never connects to the VPS.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$tools = Split-Path -Parent $Here
$deployPath = Join-Path $tools 'scripts\deploy\Deploy-Server.ps1'

$script:pass = 0
$script:fail = 0
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

$src = Get-Content -LiteralPath $deployPath -Raw
# The stage check and the swap moved into Swap.ps1 beside it for issue #446.
$lib = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $deployPath) 'Swap.ps1') -Raw

Yes 'OnlineNow asks whether anything is on the game port' (
    $src -match 'function OnlineNow' -and $src -match 'Get-NetUDPEndpoint -EA Stop')
Yes 'OnlineNow zeroes the count when nothing is listening' (
    $src -match "if \(-not ``\`$up\) \{ 'ONLINE 0' \}" -or
    $src -match "if \(-not ``\$up\) \{ 'ONLINE 0' \}" -or
    ($src -match "if \(-not ``\`$up\)" -and $src -match "'ONLINE 0'"))
Yes 'StopOurs removes a leftover restart.json' (
    $lib -match "removed a restart\.json the old process never read")

$open  = '# ==== thornswood live deploy warning ===='
$close = '# ==== end thornswood live deploy warning ===='
$a = $src.IndexOf($open)
$b = $src.IndexOf($close)
Yes 'Deploy-Server.ps1 carries the live warning block between its markers' ($a -ge 0 -and $b -gt $a)
if (-not ($a -ge 0 -and $b -gt $a)) { Done }

$winPs = 'powershell'
if (-not (Get-Command powershell -ErrorAction SilentlyContinue)) { $winPs = 'pwsh' }
function RunHere($text) {
    $ErrorActionPreference = 'Continue'
    $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
    return @(& $winPs -NoProfile -NonInteractive -EncodedCommand $e 2>&1 | ForEach-Object { [string]$_ })
}
function Remote($text) { return RunHere $text }

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-online-' + [Guid]::NewGuid().ToString('N'))
$box = Join-Path $work 'Thornswood-Server'
$boxData = Join-Path $box 'data'
New-Item -ItemType Directory -Path $boxData -Force | Out-Null
$Root = $box.Replace('\', '/')
$settings = Join-Path $box 'server-settings.json'
$online = Join-Path $boxData 'online.json'
$udp = $null

# Reload the block so '$Root' inside the remote here-string captures the temp path.
# Get-LiveOnline closes over $Root when the remote script is built at call time
# (single-quoted here-string uses '$Root' which expands when Get-LiveOnline runs).
# Actually looking at the code: Remote @" ... '$Root' ... "@ - double-quote here-string
# so $Root expands when Get-LiveOnline is *defined*? No - the function body is parsed
# when Invoke-Expression runs, and @" "@ expands $Root at that moment.
# So we must Invoke-Expression AFTER setting $Root to the temp box.
Remove-Item Function:Read-LiveOnline -ErrorAction SilentlyContinue
Remove-Item Function:Get-LiveOnline -ErrorAction SilentlyContinue
Remove-Item Function:OnlineNow -ErrorAction SilentlyContinue
Remove-Item Function:Warn-LiveRoom -ErrorAction SilentlyContinue
Invoke-Expression $src.Substring($a, $b - $a)

try {
    if (-not (Get-Command Get-NetUDPEndpoint -EA SilentlyContinue)) {
        Write-Host 'SKIP  OnlineNow runs need Get-NetUDPEndpoint'
    } else {
        $loop = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, 0)
        $udp = New-Object System.Net.Sockets.UdpClient($loop)
        $upPort = $udp.Client.LocalEndPoint.Port
        $gone = New-Object System.Net.Sockets.UdpClient($loop)
        $downPort = $gone.Client.LocalEndPoint.Port
        $gone.Close()

        [IO.File]::WriteAllText($settings, ('{"port":' + $upPort + ',"name":"Thornswood","dataDir":"data"}'))
        [IO.File]::WriteAllText($online, '{"now":3,"at":1790000000000,"restarting":false}')
        $n = OnlineNow
        Yes "a server on its port gives the online.json count (got $n)" ($n -eq 3)

        $room = Get-LiveOnline
        Yes 'Get-LiveOnline names the data folder the gamemode uses' (
            $room.Data -replace '\\','/' -match '/data$')
        Yes 'a gamemode older than the names file gives no names' (@($room.Names).Count -eq 0)

        # Issue #520: who, from the private folder, never the served one.
        $priv = Join-Path $box 'private'
        New-Item -ItemType Directory -Path $priv -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $priv 'online-names.json'),
            '{"at":1790000000000,"names":["Ahlam","Brynjolf","Camilla"]}')
        $room = Get-LiveOnline
        Yes "the private online-names.json gives who is on (got $(@($room.Names) -join ', '))" (
            (@($room.Names) -join ',') -eq 'Ahlam,Brynjolf,Camilla')
        Yes 'and the warning line carries them' ((Format-Names $room.Names) -eq ': Ahlam, Brynjolf, Camilla')
        Yes 'and no names adds nothing to it' ((Format-Names @()) -eq '')

        Remove-Item -LiteralPath $online -Force
        $n = OnlineNow
        Yes 'no online.json with the server up is nobody' ($n -eq 0)

        [IO.File]::WriteAllText($online, '{"now":3,"at')
        $n = OnlineNow
        Yes 'a half written online.json with the server up is nobody (courtesy check)' ($n -eq 0)

        [IO.File]::WriteAllText($online, '{"now":1,"at":1790000000000,"restarting":false}')
        [IO.File]::WriteAllText($settings, ('{"port":' + $downPort + ',"dataDir":"data"}'))
        $n = OnlineNow
        Yes "nothing on the port is nobody, whatever online.json says (got $n)" ($n -eq 0)
        Yes 'and whatever names it left behind' (@((Get-LiveOnline).Names).Count -eq 0)

        $elsewhere = Join-Path $work 'elsewhere'
        New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $elsewhere 'online.json'), '{"now":5}')
        [IO.File]::WriteAllText($settings, ((@{ port = $upPort; dataDir = $elsewhere } | ConvertTo-Json -Compress)))
        $n = OnlineNow
        Yes 'a dataDir written as a full path is read where it points' ($n -eq 5)
        $room = Get-LiveOnline
        Yes 'and Get-LiveOnline reports that same full data path' (
            ($room.Data -replace '\\','/') -eq ($elsewhere -replace '\\','/'))
    }

    $a2 = $lib.IndexOf('# ==== deploy-server remote blocks ====')
    $b2 = $lib.IndexOf('# ==== end deploy-server remote blocks ====')
    Yes 'the remote blocks are still between their markers' ($a2 -ge 0 -and $b2 -gt $a2)
    if ($a2 -ge 0 -and $b2 -gt $a2) {
        $checkBlock = $null
        $swapBlock = $null
        Invoke-Expression $lib.Substring($a2, $b2 - $a2)
        Yes 'the swap block defines StopOurs' ($swapBlock -match 'function StopOurs')

        $standIns = "function Stop-ScheduledTask { }`r`n" +
                    "function Stop-Process { 'stand-in asked to stop ' + (`$args -join ' ') }`r`n" +
                    "function Get-NetUDPEndpoint { }`r`n" +
                    "function Start-Sleep { }`r`n" +
                    "function Held { `$false }`r`n"

        $stopMatch = [regex]::Match($swapBlock, '(?ms)^function StopOurs \{.*?^\}\r?$')
        Yes 'the swap block carries one StopOurs to run' ($stopMatch.Success)
        if ($stopMatch.Success) {
            Invoke-Expression ($standIns + $stopMatch.Value)
            $Task = 'thornswood-test-no-such-task'
            $port = 7777
            $Root = $box
            [IO.File]::WriteAllText($settings, '{"port":7777,"name":"Thornswood","dataDir":"data"}')
            [IO.File]::WriteAllText($online, '{"now":1}')
            $request = Join-Path $boxData 'restart.json'
            [IO.File]::WriteAllText($request, '{"seconds":60,"mode":"notice","why":"a server update"}')
            $said = @(StopOurs)
            Yes 'the stop removes a restart.json the old process never read' (-not (Test-Path -LiteralPath $request))
            Yes 'and says it did' (@($said | Where-Object { $_ -match 'removed a restart.json' }).Count -eq 1)
            Yes 'and leaves the rest of the data folder alone' (Test-Path -LiteralPath $online)
            Yes 'with nothing on this machine stopped' (@($said | Where-Object { $_ -match 'stand-in asked' }).Count -eq 0)

            $said = @(StopOurs)
            Yes 'with no restart.json there it says nothing about one' (
                @($said | Where-Object { $_ -match 'restart.json' }).Count -eq 0)

            $elseData = Join-Path $work 'else-data'
            New-Item -ItemType Directory -Path $elseData -Force | Out-Null
            $elseReq = Join-Path $elseData 'restart.json'
            [IO.File]::WriteAllText($elseReq, '{"seconds":60}')
            [IO.File]::WriteAllText($settings, ((@{ port = 7777; dataDir = $elseData } | ConvertTo-Json -Compress)))
            $said = @(StopOurs)
            Yes 'a dataDir full path is where restart.json is removed from' (
                -not (Test-Path -LiteralPath $elseReq) -and
                (@($said | Where-Object { $_ -match 'removed a restart.json' }).Count -eq 1))
        }
    }
}
finally {
    if ($udp) { $udp.Close() }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done

