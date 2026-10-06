<#
  test-swap-task-priority.ps1

      pwsh -NoProfile -File .\tests\test-swap-task-priority.ps1

  A server put up by Deploy-Server or Deploy-DevGamemode starts at normal
  priority (#2015).

  WHY. Only Install-ThornswoodServer.ps1 registered the game server's task at
  priority 4 (#1931, #1967); Swap.ps1's $swapBlock, which both deploys use to
  start the server, started whatever task the box had. On 5 Oct at 11:47 PM
  the live server's task was still Task Scheduler's default of 7 after the
  1.2.0 deploy, and its node ran BelowNormal.

  HOW. Swap.ps1 is dot-sourced for $swapBlock. Its NormalTask function is read
  out of it and run against a task registered for the person running this,
  at the default priority, with $Task set as SwapVars sets it. The task must
  come back at 4 with its action kept, and a second run must change nothing
  and say nothing. Every Start-ScheduledTask in the block must come straight
  after a NormalTask.

  Registers and removes one task named Thornswood swap priority harness <guid>
  (not 'Thornswood Test...', which test-deploy-swaps and test-install-server
  clear away, #1135). Nothing is started.
#>
[CmdletBinding()]
param([string]$Swap)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Swap) { $Swap = [IO.Path]::Combine($Repo, 'scripts', 'deploy', 'Swap.ps1') }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

. $Swap
Yes 'Swap.ps1 gives $swapBlock' ([bool]$swapBlock)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($swapBlock, [ref]$t, [ref]$e)
Yes 'the swap block parses' (-not $e -or $e.Count -eq 0)
$fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'NormalTask' }, $true))
Yes 'it has a NormalTask step' ($fn.Count -eq 1)
$lines = @($swapBlock -split "`r?`n" | ForEach-Object { $_.Trim() })
$starts = @(); for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -like 'Start-ScheduledTask -TaskName $Task*') { $starts += $i } }
Yes ('every start of the task comes straight after NormalTask (' + $starts.Count + ' start(s))') (
    $starts.Count -ge 2 -and @($starts | Where-Object { $_ -gt 0 -and $lines[$_ - 1] -eq 'NormalTask' }).Count -eq $starts.Count)
if ($fn.Count -ne 1) { Done }

$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $onWindows) { Write-Host 'SKIP  the task part needs Windows and its Task Scheduler'; Done }
Import-Module ScheduledTasks -ErrorAction SilentlyContinue
if (-not (Get-Module ScheduledTasks)) { Write-Host 'SKIP  the ScheduledTasks module did not load'; Done }

$Task = 'Thornswood swap priority harness ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
try {
    $a = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument '/c exit 0' -WorkingDirectory $env:TEMP
    $p = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive
    Register-ScheduledTask -TaskName $Task -Action $a -Principal $p -Settings (New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)) | Out-Null
    $before = Get-ScheduledTask -TaskName $Task
    Yes ('a task registered with no -Priority has Task Scheduler''s default, 7 (' + $before.Settings.Priority + ')') ($before.Settings.Priority -eq 7)

    $run = [scriptblock]::Create($fn[0].Extent.Text + "`nNormalTask")
    $said = @(& $run | ForEach-Object { "$_" })
    $said | ForEach-Object { Write-Host ('      ' + $_) }
    $after = Get-ScheduledTask -TaskName $Task
    Yes 'NormalTask sets it to 4' ($after.Settings.Priority -eq 4)
    Yes '  and says so, with what it was' (($said -join ' ') -match 'priority 4 now, not 7')
    Yes '  and keeps the rest of the task: its action and its restarts' (
        $after.Actions[0].Execute -eq $before.Actions[0].Execute -and $after.Actions[0].Arguments -eq $before.Actions[0].Arguments -and
        $after.Settings.RestartCount -eq 999)
    $again = @(& $run | ForEach-Object { "$_" })
    Yes 'run again on a task at 4, it changes nothing and says nothing' ($again.Count -eq 0 -and (Get-ScheduledTask -TaskName $Task).Settings.Priority -eq 4)
}
catch {
    Yes ('the harness ran to the end without an error: ' + $_.Exception.Message) $false
}
finally {
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
}
Done
