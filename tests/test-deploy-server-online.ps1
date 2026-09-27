<#
  test-deploy-server-online.ps1

  Deploy-Server.ps1 treats a server with nothing listening as nobody online,
  and removes a leftover restart.json when it stops. Issue #524: the live
  half of the same two gaps Deploy-DevGamemode closed.

  HOW. OnlineNow is taken out of the deploy and driven with Remote replaced
  by a local run against a temp folder, with a real UDP socket on loopback
  standing in for the server, and with none. StopOurs is taken out of the
  swap block and run against the same temp folder, with everything in it
  that stops a task or a process replaced by a stand-in.

  Never connects to the VPS.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$tools = Join-Path (Split-Path -Parent $Here) 'tools'
$deployPath = Join-Path $tools '..\scripts\deploy\Deploy-Server.ps1'
$shimPath   = Join-Path $tools 'Deploy-Server.ps1'

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

Yes 'OnlineNow asks whether anything is on the game port' (
    $src -match 'function OnlineNow' -and $src -match 'Get-NetUDPEndpoint -EA Stop')
Yes 'OnlineNow zeroes the count when nothing is listening' (
    $src -match 'if \(-not `\$up\) \{ 0 \}')
Yes 'StopOurs removes a leftover restart.json' (
    $src -match "removed a restart\.json the old process never read")
Yes 'tools\Deploy-Server.ps1 still forwards to scripts\deploy' (
    (Test-Path -LiteralPath $shimPath) -and
    ((Get-Content -LiteralPath $shimPath -Raw) -match 'scripts\\deploy\\Deploy-Server\.ps1'))

$ast = [System.Management.Automation.Language.Parser]::ParseFile($deployPath, [ref]$null, [ref]$null)
$onlineAst = @($ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'OnlineNow'
}, $true))
Yes 'Deploy-Server.ps1 defines OnlineNow once' ($onlineAst.Count -eq 1)
if ($onlineAst.Count -ne 1) { Done }

$winPs = 'powershell'
if (-not (Get-Command powershell -ErrorAction SilentlyContinue)) { $winPs = 'pwsh' }
function RunHere($text) {
    $ErrorActionPreference = 'Continue'
    $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
    return @(& $winPs -NoProfile -NonInteractive -EncodedCommand $e 2>&1 | ForEach-Object { [string]$_ })
}
function Remote($text) { return RunHere $text }

Invoke-Expression $onlineAst[0].Extent.Text

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-online-' + [Guid]::NewGuid().ToString('N'))
$box = Join-Path $work 'Thornswood-Server'
$boxData = Join-Path $box 'data'
New-Item -ItemType Directory -Path $boxData -Force | Out-Null
$Root = $box.Replace('\', '/')
$settings = Join-Path $box 'server-settings.json'
$online = Join-Path $boxData 'online.json'
$udp = $null

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

        $elsewhere = Join-Path $work 'elsewhere'
        New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $elsewhere 'online.json'), '{"now":5}')
        [IO.File]::WriteAllText($settings, ((@{ port = $upPort; dataDir = $elsewhere } | ConvertTo-Json -Compress)))
        $n = OnlineNow
        Yes 'a dataDir written as a full path is read where it points' ($n -eq 5)
    }

    $a = $src.IndexOf('# ==== deploy-server remote blocks ====')
    $b = $src.IndexOf('# ==== end deploy-server remote blocks ====')
    Yes 'the remote blocks are still between their markers' ($a -ge 0 -and $b -gt $a)
    if ($a -ge 0 -and $b -gt $a) {
        $checkBlock = $null
        $swapBlock = $null
        Invoke-Expression $src.Substring($a, $b - $a)
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