<#
  test-check-serena.ps1

      pwsh -NoProfile -File .\tests\test-check-serena.ps1

  scripts\dev\Check-Serena.ps1 times a Serena start the way Claude Code
  makes it, and says when it is too slow or never answers. Here it is
  pointed at a stand-in server instead of Serena: a small pwsh script that
  speaks the same three messages, after a delay the test chooses, or not at
  all. The check has to read a Claude Code config with no Serena in it, time
  a quick answer and count its tools, fail one slower than -Within, and stop
  waiting at -Limit for one that never answers, leaving no process behind.

  Why: #2935. A check that only ever ran against a real Serena would pass on
  a fast machine whatever its timing code did.

  Writes only into a temp folder, which it removes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# $OnWindows, for the one Windows-only step: how a leftover process is found.
. (Join-Path $PSScriptRoot 'Windows.ps1')
$Repo = Split-Path -Parent $PSScriptRoot
$Check = Join-Path $Repo 'scripts' 'dev' 'Check-Serena.ps1'
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-serena-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

# The stand-in. It waits -Delay seconds before its first log line and its
# answer, or with -Silent never answers, and it ends when stdin closes, as
# Serena does.
$fake = Join-Path $work 'fake-serena.ps1'
Set-Content -LiteralPath $fake -Encoding utf8NoBOM -Value @'
param([double]$Delay = 0, [switch]$Silent)
Start-Sleep -Milliseconds ([int]($Delay * 1000))
[Console]::Error.WriteLine('INFO  [MainThread] serena.cli:start_mcp_server:432 - Initializing Serena MCP server')
while ($null -ne ($line = [Console]::In.ReadLine())) {
    if ($Silent) { continue }
    $m = $line | ConvertFrom-Json
    if ($m.method -eq 'initialize') {
        [Console]::Out.WriteLine((@{ jsonrpc = '2.0'; id = $m.id; result = @{ protocolVersion = '2025-06-18'; capabilities = @{}; serverInfo = @{ name = 'fake'; version = '0' } } } | ConvertTo-Json -Depth 6 -Compress))
    } elseif ($m.method -eq 'tools/list') {
        [Console]::Out.WriteLine((@{ jsonrpc = '2.0'; id = $m.id; result = @{ tools = @(@{ name = 'a' }, @{ name = 'b' }, @{ name = 'c' }) } } | ConvertTo-Json -Depth 6 -Compress))
    }
    [Console]::Out.Flush()
}
'@
$pwsh = (Get-Process -Id $PID).Path

function Config([string]$name, [string[]]$fakeArgs) {
    $p = Join-Path $work "$name.json"
    $servers = @{}
    if ($null -ne $fakeArgs) {
        $servers.serena = @{ type = 'stdio'; command = $pwsh; args = @('-NoProfile', '-File', $fake) + $fakeArgs; env = @{} }
    }
    Set-Content -LiteralPath $p -Encoding utf8NoBOM -Value (@{ mcpServers = $servers } | ConvertTo-Json -Depth 6)
    return $p
}
function Run([string]$config, [string[]]$more) {
    $out = & $pwsh -NoProfile -File $Check -Config $config -Folder $work @more 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $out }
}

try {
    $r = Run (Config 'none' $null) @()
    Yes 'no Serena in the config fails and says so' ($r.Code -eq 1 -and $r.Out -match 'has no Serena')

    $r = Run (Config 'quick' @()) @()
    Yes 'a quick start is timed to its answer' ($r.Out -match 'answered initialize')
    Yes 'its first log line is timed' ($r.Out -match "Serena's first log line")
    Yes 'its tools are counted' ($r.Out -match 'listed 3 tools')
    Yes 'a program that is neither uvx nor the installed Serena fails' ($r.Code -eq 1 -and $r.Out -match 'neither uvx nor the installed program')

    $r = Run (Config 'slow' @('-Delay', '3')) @('-Within', '1')
    Yes 'a start slower than -Within fails with its time' ($r.Code -eq 1 -and $r.Out -match 'more than the 1 s')

    $t = [Diagnostics.Stopwatch]::StartNew()
    $r = Run (Config 'silent' @('-Silent')) @('-Limit', '4')
    $t.Stop()
    Yes 'a start that never answers fails' ($r.Code -eq 1 -and $r.Out -match 'never answered initialize')
    Yes 'and the check stops waiting at -Limit' ($t.Elapsed.TotalSeconds -lt 30)
    $left = if ($OnWindows) { @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$fake*" }) } else { @(& pgrep -f $fake) }
    Yes 'no stand-in is left running' ($left.Count -eq 0)
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}

Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
