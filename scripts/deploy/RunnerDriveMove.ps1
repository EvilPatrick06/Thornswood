# Shared runner-drive move preflight. Defining these functions changes nothing.
function Assert-MoveAdministrator {
  $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this command as administrator on THIS PC; nothing was installed.'
  }
}

function Get-RunnerMovePlan {
  param(
    [string]$Drive,
    [int]$PerformanceMode,
    [int[]]$Numbers,
    [object[]]$Accounts,
    [object[]]$Services,
    [object[]]$Workers,
    [object[]]$Profiles
  )
  if ($Drive -notmatch '^[D-Z]:$') { throw 'The runner drive must be a drive other than C:.' }
  # Get-MpPreference's PerformanceModeStatus is not used as a gate: on One on
  # 29 Oct 2026 it read 1 while Windows Security listed R: with asynchronous
  # scanning on (#4048). The drive's trust, its attached filter and real-time
  # protection are checked instead; a Defender recording proves the speed.
  $plan = @()
  foreach ($number in $Numbers) {
    $suffix = $(if ($number -gt 1) { [string]$number } else { '' })
    $account = 'thornswood-pr' + $suffix
    $exists = @($Accounts | Where-Object { $_.Name -eq $account }).Count -gt 0
    if (-not $exists) {
      $loaded = @($Profiles | Where-Object {
        $leaf = (('' + $_.LocalPath) -split '[\\/]')[-1]
        $_.Loaded -and ($leaf -eq $account -or $leaf -like ($account + '.*'))
      })
      if ($loaded.Count) {
        throw ("Windows still holds the removed account's profile for " + $account + '; restart this PC to release it. No runner has changed.')
      }
    }
    $identity = @($Accounts | Where-Object { $_.Name -eq $account })
    $service = @($Services | Where-Object { $_.Account -eq $account })
    $source = $(if ($service.Count) { [string]$service[0].Root } else { '' })
    $target = $Drive + '\Thornswood-RunnerPR' + $suffix
    if ($service.Count -gt 1) { throw ($account + ' has more than one runner service; no runner has changed.') }
    if ($source -and $source -ne ('C:\Thornswood-RunnerPR' + $suffix) -and $source -ne $target) {
      throw ($account + ' uses an unexpected folder: ' + $source + '. No runner has changed.')
    }
    foreach ($worker in $Workers) {
      $path = ('' + $worker.ExecutablePath).Replace('/', '\')
      if (-not $path) { throw 'A runner is building but its process folder cannot be read. No runner has changed.' }
      if ($source -and $source -ne $target -and $path.StartsWith($source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw ($account + ' is building. Let that job finish before moving it. No runner has changed.')
      }
    }
    $plan += [pscustomobject]@{
      Number = $number
      Account = $account
      AccountSid = $(if ($identity.Count) { [string]$identity[0].SID } else { '' })
      SourceRoot = $source
      TargetRoot = $target
      ServiceName = $(if ($service.Count) { [string]$service[0].Name } else { '' })
    }
  }
  $plan
}

function Invoke-RunnerMovePlan {
  param([object[]]$Plan, [scriptblock]$Install, [scriptblock]$Verify)
  foreach ($move in $Plan) {
    if ($move.SourceRoot -ne $move.TargetRoot) {
      $code = & $Install $move
      if ($code -isnot [int] -or $code -ne 0) {
        throw ('Runner ' + $move.Number + ' install stopped (exit ' + $code + '). No later runner was attempted; source folders were not deleted.')
      }
    }
    $verified = & $Verify $move
    if ($verified -isnot [bool] -or -not $verified) {
      throw ('Runner ' + $move.Number + ' did not pass verification. No later runner was attempted; source folders were not deleted.')
    }
    $move
  }
}

function Get-RunnerDriveReadiness {
  param(
    [object[]]$Volumes,
    [Nullable[int]]$PerformanceMode,
    [bool]$AntivirusEnabled,
    [bool]$RealTimeProtectionEnabled,
    [string]$DevDriveQuery,
    [bool]$StartupReady
  )
  if (@($Volumes).Count -ne 1) { throw 'Exactly one attached Thornswood Runners drive is required.' }
  if ($Volumes[0].FileSystem -ne 'ReFS') { throw 'The runner drive must use ReFS.' }
  if (-not $AntivirusEnabled -or -not $RealTimeProtectionEnabled) {
    throw 'Microsoft Defender and real-time protection must both be active.'
  }
  if ($DevDriveQuery -notmatch '(?im)^\s*This is a trusted developer volume\.\s*$' -or
      $DevDriveQuery -notmatch '(?im)^\s*Developer volumes are protected by antivirus filter\.\s*$' -or
      $DevDriveQuery -notmatch '(?im)^\s*WdFilter\s*$') {
    throw 'The drive must be a trusted developer volume with its antivirus filter and WdFilter attached. Unrecognized status is not treated as ready.'
  }
  if (-not $StartupReady) { throw 'The Thornswood Runner Drive startup task must be enabled and run its protected startup script as SYSTEM.' }
  ([string]$Volumes[0].DriveLetter + ':')
}

function Confirm-RunnerMove {
  param(
    $Move,
    $Account,
    [object[]]$Services,
    [object[]]$Listeners,
    [object[]]$Profiles,
    [object[]]$Registrations,
    [string]$RunnerName,
    [bool]$NeedsBuildLabel,
    [bool]$NeedsPrBuildLabel
  )
  if (-not $Account -or $Account.Name -ne $Move.Account -or -not ('' + $Account.SID) -or
      ($Move.AccountSid -and ('' + $Account.SID) -ne $Move.AccountSid)) {
    throw ('Runner ' + $Move.Number + ' account or SID did not match.')
  }
  $mine = @($Services | Where-Object { $_.Account -eq $Move.Account })
  if ($mine.Count -ne 1 -or $mine[0].Name -ne $Move.ServiceName -or
      $mine[0].Root -ne $Move.TargetRoot -or $mine[0].State -ne 'Running' -or $mine[0].StartMode -ne 'Manual') {
    throw ('Runner ' + $Move.Number + ' service must run from its target folder, as its own account, with manual start.')
  }
  $expectedListener = $Move.TargetRoot + '\bin\Runner.Listener.exe'
  $listenersHere = @($Listeners | Where-Object { ('' + $_.ExecutablePath).Replace('/', '\') -eq $expectedListener })
  if ($listenersHere.Count -ne 1) { throw ('Runner ' + $Move.Number + ' needs exactly one listener in its target folder.') }
  $related = @($Profiles | Where-Object {
    $leaf = (('' + $_.LocalPath) -split '[\\/]')[-1]
    $leaf -eq $Move.Account -or $leaf -like ($Move.Account + '.*')
  })
  if ($related.Count -gt 1 -or @($related | Where-Object { ('' + $_.SID) -ne ('' + $Account.SID) }).Count) {
    throw ('Runner ' + $Move.Number + ' has a duplicate or mismatched profile.')
  }
  $registered = @($Registrations | Where-Object { $_.name -eq $RunnerName })
  if ($registered.Count -ne 1) { throw ($RunnerName + ' needs exactly one GitHub registration.') }
  if ($registered[0].status -ne 'online') { throw ($RunnerName + ' is not online on GitHub.') }
  $labels = @($registered[0].labels | ForEach-Object { $_.name })
  if ($labels -notcontains 'thornswood-pr' -or $labels -contains 'thornswood-vps' -or
      $NeedsBuildLabel -ne ($labels -contains 'thornswood-build') -or
      $NeedsPrBuildLabel -ne ($labels -contains 'thornswood-pr-build')) {
    throw ($RunnerName + ' labels do not match this off-box runner and the build-runner records.')
  }
  return $true
}
