<#
  Roll-Log.ps1

  Rolls a log just before the service that writes it starts. It goes up beside
  the voice service as roll-log.ps1, and its scheduled task runs it in front of
  the service. The game server stopped using it on 15 Oct 2026 (#2349): its
  log is written by Server-Log.js, which rolls by day and keeps nothing past
  30 days, because the engine writes every connecting address there. The bot
  rolls its own (BotService.cs). The shape, as the server's line used to be:

      cmd /c "powershell ... -File roll-log.ps1 -Path server.log & node ... >> server.log 2>&1"

      .\Roll-Log.ps1 -Path C:\Thornswood-Voice\voice.log          at 4 MB
      .\Roll-Log.ps1 -Path C:\Thornswood-Voice\voice.log -Force   whatever the size

  WHY AT START AND NOT ON A TIMER. server.log, voice.log and bot.log are
  written by cmd's >> log 2>&1, and cmd holds that file open for as long as
  the service runs. Measured on 23 September with cmd /c "ping ... >> held.log"
  running: Rename-Item, Clear-Content and FileStream.SetLength(0) were all
  refused, "being used by another process", and Rename-Item worked the moment
  the holder exited. So a roll on a timer cannot work against a running
  service, copy then truncate included, because the truncate is the half that
  is refused. The one moment the file is free is just before the service opens
  it, and that is every start: a crash, the watcher, a deploy, an install.

  THE RULE IS THE SITE'S (site.log, entry 64). At 4 MB the log becomes .1, what
  was .1 becomes .2, and so on, five kept, so a crash on Saturday night is
  still readable on Monday. The oldest past five is the only thing that ever
  goes. Rolled, never deleted: deleting a log is how the evidence for the last
  crash disappeared in the first place. -Force rolls whatever the size, which
  is what an install wants, so the run it starts has a file of its own.

  IT NEVER STOPS THE SERVICE. It always exits 0, and the task runs the service
  after it with & rather than &&, so a log that could not be rolled is appended
  to as it always was. A log something still holds is left exactly as it is,
  older ones included, rather than shuffled around a file that cannot move.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [long]$MaxBytes = 4MB,
    [int]$Keep = 5,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { exit 0 }
    # Absolute, because [IO.File] resolves a relative path against the
    # process's own directory rather than PowerShell's.
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    if ($Keep -lt 1) { $Keep = 1 }
    $name = Split-Path -Leaf $Path
    $size = (Get-Item -LiteralPath $Path).Length

    # An empty log is not worth one of the five places.
    if ($size -eq 0) { exit 0 }
    if (-not $Force -and $size -lt $MaxBytes) { exit 0 }

    # Asked first, so a file that cannot move leaves the older ones where they
    # are. Anything holding it, cmd's redirect or somebody reading it over ssh,
    # would refuse the rename below anyway.
    try {
        $h = [IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $h.Close()
    } catch {
        Write-Output ('{0} is held by another process, so it was left as it is' -f $name)
        exit 0
    }

    $oldest = $Path + '.' + $Keep
    if (Test-Path -LiteralPath $oldest) { Remove-Item -LiteralPath $oldest -Force }
    for ($i = $Keep - 1; $i -ge 1; $i--) {
        $from = $Path + '.' + $i
        if (Test-Path -LiteralPath $from) { [IO.File]::Move($from, $Path + '.' + ($i + 1)) }
    }
    [IO.File]::Move($Path, $Path + '.1')
    Write-Output ('rolled {0} at {1:N1} MB to {0}.1, {2} kept' -f $name, ($size / 1MB), $Keep)
} catch {
    Write-Output ('could not roll {0}: {1}' -f $Path, $_.Exception.Message)
}
exit 0
