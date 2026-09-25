<#
  Watch-Foreground.ps1

  Which window Windows is giving the keyboard to, sampled from outside the game.

  Every keyboard lock in this build has the same shape in the client log: no
  menu open, nothing holding browser focus, player controls on, and not one key
  reaching the process. That is Windows having handed back a foreground acquired
  DirectInput device, which it does when the game stops being the foreground
  window. SkyrimPlatform's hook asks for it back on every read now, and Windows
  refuses while something else holds the foreground, so the question that is
  left is simply: what is holding it.

  Asking that from inside the game does not work. Two attempts froze the game
  outright, and the reason is structural rather than a bug to be fixed: the
  question has to be asked on the game's own thread, and answering it can mean
  waiting on a window owned by a thread that is busy. Waiting on the game's
  thread is a freeze by definition.

  From a separate process none of that matters. If this script blocks for a
  moment, this script blocks. Nothing is asked of the game at all.

      .\Watch-Foreground.ps1

  Leave it open, play until the keyboard goes, then close it. Every change of
  foreground window is one line with a timestamp, so the line written at the
  moment the microphone opened is the answer.

  Nothing is changed anywhere. This only looks.
#>
[CmdletBinding()]
param(
    [int]$IntervalMs = 200,
    [string]$Out = ''
)

$ErrorActionPreference = 'Continue'

if (-not $Out) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $logs = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'logs'
    if (-not (Test-Path -LiteralPath $logs)) { New-Item -ItemType Directory -Path $logs -Force | Out-Null }
    $Out = Join-Path $logs 'foreground.log'
}

Add-Type -Namespace Ts -Name Win -MemberDefinition @'
[DllImport("user32.dll")]
public static extern IntPtr GetForegroundWindow();

[DllImport("user32.dll")]
public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);

[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);
'@

Write-Host ''
Write-Host '  Watching which window has the keyboard' -ForegroundColor Cyan
Write-Host "  writing to $Out" -ForegroundColor DarkGray
Write-Host '  Leave this open, play, and close it when you are done.' -ForegroundColor DarkGray
Write-Host ''

"=== started $(Get-Date -Format 'HH:mm:ss.fff') ===" | Out-File -LiteralPath $Out -Encoding UTF8

$lastHandle = [IntPtr]::Zero
$names = @{}

while ($true) {
    $h = [Ts.Win]::GetForegroundWindow()

    if ($h -ne $lastHandle) {
        $lastHandle = $h

        # Not $pid. That is one of PowerShell's own automatic variables and
        # assigning to it fails, which is how this script managed to log its
        # own terminal and nothing else.
        $procId = 0
        [void][Ts.Win]::GetWindowThreadProcessId($h, [ref]$procId)

        # Cached, because a process that has gone away throws and there is no
        # reason to ask twice about the same id.
        if (-not $names.ContainsKey($procId)) {
            $n = '(gone)'
            try { $n = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
            $names[$procId] = $n
        }

        $sb = New-Object System.Text.StringBuilder 256
        [void][Ts.Win]::GetClassName($h, $sb, $sb.Capacity)

        $line = '{0}  {1,-22} pid {2,-7} class {3}' -f `
                (Get-Date -Format 'HH:mm:ss.fff'), $names[$procId], $procId, $sb.ToString()

        $line | Out-File -LiteralPath $Out -Encoding UTF8 -Append
        Write-Host ('  ' + $line) -ForegroundColor Gray
    }

    Start-Sleep -Milliseconds $IntervalMs
}
