<#
  Prove-SecretOffCommandLines.ps1

  Proves, on one real run, that a secret-sending script keeps the value off
  every command line on the VPS (issue #1212, the person check of #451).

      .\scripts\vps\Prove-SecretOffCommandLines.ps1 -Run { .\scripts\deploy\Deploy-Docs.ps1 -Password }

  It asks for the value the run is about to send, hidden as it is typed. It
  starts a watcher on the VPS and waits for it to say it is watching, runs the
  script block, and stops the watcher when the run is over. It ends with one
  of:

      NOT FOUND  no command line on the VPS held the value during the run
      FOUND      that many processes on the VPS had it in their command line

  and a count of the process command lines it read. Exit code 0 for NOT FOUND,
  1 for FOUND, 2 when the watcher could not say. A NOT FOUND over no command
  lines at all proves nothing, so it is not one (#1263): that is a 2 as well.

  WHY THIS EXISTS. #1068's person check was a hand-run Get-CimInstance on the
  VPS during the call. That is one snapshot of a remote powershell that lives
  for about a second, and the person reading it does not know the value, so
  the only way to see it is to print every command line, which prints the
  secret on the day the check fails.

  HOW. The watcher goes up the way every secret does (Send-Secret.ps1): the
  value on ssh's standard input, only the watcher's own script on the command
  line. On the VPS it reads Win32_Process about ten times a second until this
  machine closes its standard input, and looks in every command line for the
  value, its UTF-8 base64 and its UTF-16 base64, with any -EncodedCommand
  decoded first. It writes nothing to disk and prints only counts: never a
  command line and never the value, whichever way it comes out.

  The harness is tests\test-prove-secret.ps1: it runs this against a fake ssh,
  once the way Send-Secret sends (NOT FOUND) and once the old way, the value
  base64'd into the command line (FOUND).

  Never prints the value. Reads nothing on the VPS but the process list.
#>
[CmdletBinding()]
param(
    # The real secret-sending run, as it would be typed.
    [Parameter(Mandatory = $true)][scriptblock]$Run,

    # The value the run sends. Asked for, hidden, when not given; otherwise
    # only from another script, as a SecureString nobody can type.
    [System.Security.SecureString]$Secret,

    [string]$VpsHost = '',
    [string]$VpsUser = '',

    # The watcher stops on its own after this long, whatever happens here.
    [int]$MaxSeconds = 900,

    # The ssh to start the watcher with, and any arguments in front of the
    # usual ones. Only the harness changes it.
    [string[]]$SshCommand = @('ssh')
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
. (Join-Path $Here 'Send-Secret.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

# What runs on the VPS, after Send-Secret's prelude has read the value.
function Get-ThornswoodSecretWatcher([int]$Seconds) {
    $body = @'
$v = $ThornswoodSecret; $ThornswoodSecret = $null
if (-not $v) { 'WATCHER EMPTY'; exit 2 }
$forms = @($v, [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($v)), [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($v)))
$v = $null
$hit = @{}; $read = @{}
function Look {
  foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, CommandLine)) {
    $c = [string]$p.CommandLine
    if (-not $c) { continue }
    $read[[string]$p.ProcessId + '|' + $c.Length] = 1
    $m = [regex]::Match($c, '-EncodedCommand\s+"?([A-Za-z0-9+/=]+)')
    if ($m.Success) { try { $c += "`n" + [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } catch { } }
    foreach ($f in $forms) { if ($c.Contains($f)) { $hit[[string]$p.ProcessId] = 1 } }
  }
}
# The stop signal: this machine closing standard input. Read on a runspace of
# its own, because Console.In's ReadLineAsync does not return until it is read.
$stop = [powershell]::Create().AddScript('[void][Console]::In.ReadLine()').BeginInvoke()
$end = (Get-Date).AddSeconds(SECONDS)
'WATCHER READY'
do { Look; Start-Sleep -Milliseconds 100 } while (-not $stop.IsCompleted -and (Get-Date) -lt $end)
Look
if ($hit.Count) { 'WATCHER FOUND ' + $hit.Count } else { 'WATCHER NOT FOUND' }
'WATCHER READ ' + $read.Count
'@
    return (Get-ThornswoodSecretPrelude) + "`r`n" + $body.Replace('SECONDS', [string]$Seconds)
}

function ConvertTo-ThornswoodArg([string]$a) {
    if ($a -match '[\s"]') { return '"' + $a.Replace('"', '\"') + '"' }
    return $a
}

if ($PSBoundParameters.ContainsKey('Secret')) { $value = ConvertFrom-ThornswoodSecureString $Secret }
else { $value = Read-ThornswoodSecret 'The value the run will send (hidden)' }
$Secret = $null
if (-not $value) { throw 'No value given, so there is nothing to look for. Nothing was started.' }
$wire = ConvertTo-ThornswoodSecretWire $value
$value = $null

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-ThornswoodSecretWatcher $MaxSeconds)))
$sshArgs = @($SshCommand | Select-Object -Skip 1) + @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', "$VpsUser@$VpsHost", "powershell -NoProfile -EncodedCommand $encoded")

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $SshCommand[0]
$psi.Arguments = (@($sshArgs | ForEach-Object { ConvertTo-ThornswoodArg $_ }) -join ' ')
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$proc = [Diagnostics.Process]::Start($psi)
# Read and dropped: an ssh error line is not the verdict, and is not shown in
# case anything in it came from the far side.
$null = $proc.StandardError.ReadToEndAsync()
$verdict = 2
try {
    # The value first, alone on its line, then wait for the watcher to say it
    # is reading the process list before anything is run.
    $proc.StandardInput.WriteLine($wire)
    $proc.StandardInput.Flush()
    $wire = $null
    $lines = New-Object Collections.Generic.List[string]
    $ready = $false
    while ($true) {
        $l = $proc.StandardOutput.ReadLine()
        if ($null -eq $l) { break }
        $lines.Add($l)
        if ($l.Trim() -eq 'WATCHER READY') { $ready = $true; break }
    }
    if (-not $ready) {
        Write-Host 'The watcher on the VPS did not start, so nothing was run and nothing is proved.' -ForegroundColor Red
    } else {
        Write-Host "Watching the command lines on $VpsHost. Running it now."
        # The run sees its own variables, not this script's: a $Secret or a
        # $wire of the caller's is not hidden by an empty one here.
        Remove-Variable -Name Secret, value, wire -ErrorAction SilentlyContinue
        try { & $Run }
        finally {
            # Closing standard input is the watcher's signal to take one more
            # look and answer.
            $proc.StandardInput.Close()
        }
        while ($true) {
            $l = $proc.StandardOutput.ReadLine()
            if ($null -eq $l) { break }
            $lines.Add($l)
        }
        $proc.WaitForExit()
        $said = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'WATCHER *' })
        $read = @($said | Where-Object { $_ -like 'WATCHER READ *' } | ForEach-Object { $_.Substring(13) }) | Select-Object -First 1
        $found = @($said | Where-Object { $_ -like 'WATCHER FOUND *' } | ForEach-Object { $_.Substring(14) }) | Select-Object -First 1
        $readCount = 0
        if (-not [int]::TryParse([string]$read, [ref]$readCount)) { $readCount = 0 }
        if ($said -contains 'WATCHER NOT FOUND' -and $readCount -le 0) {
            Write-Host "The watcher read no command lines on $VpsHost, so nothing is proved." -ForegroundColor Red
        } elseif ($said -contains 'WATCHER NOT FOUND') {
            Write-Host "NOT FOUND  no command line on $VpsHost held the value during the run ($read process command lines read)" -ForegroundColor Green
            $verdict = 0
        } elseif ($found) {
            Write-Host "FOUND  $found processes on $VpsHost had the value or its base64 in their command line ($read read)" -ForegroundColor Red
            $verdict = 1
        } else {
            Write-Host 'The watcher on the VPS did not answer, so nothing is proved.' -ForegroundColor Red
        }
    }
}
finally {
    $wire = $null
    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
}
exit $verdict
