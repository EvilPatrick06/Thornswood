<#
  test-2460-winps-module-path.ps1

  The Developer Guide says to start a PowerShell harness with
  `pwsh -NoProfile -File` (#2460). Windows PowerShell 5.1 started straight from
  a shell whose PSModulePath is PowerShell 7's (Git Bash opened from a pwsh
  terminal) finds PowerShell 7's Utility module first and loses Get-FileHash.
  PowerShell 7 started with pwsh rewrites the path when it starts 5.1, so the
  harnesses that need 5.1 keep working. This proves both sides, so a pwsh that
  stopped rewriting the path goes red here instead of breaking every harness
  that starts 5.1.

  Read only. Needs pwsh and Windows PowerShell 5.1; skips without them.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# The guide names the safe command, whatever machine this runs on.
$guide = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Developer-Guide.md'))
Yes 'the Developer Guide says to start a harness with pwsh -NoProfile -File' ($guide.Contains('pwsh -NoProfile -File .\tests\'))
Yes 'and names the Git Bash failure (#2460)' ($guide.Contains('#2460') -and $guide.Contains('Get-FileHash'))
Yes 'and how to clear the path for 5.1 from Git Bash' ($guide.Contains('env -u PSModulePath powershell.exe'))

. (Join-Path $PSScriptRoot 'Windows.ps1')
$pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $OnWindows) {
    Write-Host 'SKIP  the module path runs: they are between pwsh and Windows PowerShell 5.1, and this is not Windows, which is the only place 5.1 runs'
} elseif (-not $pwsh) {
    Write-Host 'SKIP  the module path runs need pwsh as well as Windows PowerShell 5.1, and this machine has no pwsh'
} else {
    $ps51 = Get-WindowsPowerShell
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-2460-' + [Guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($tmp)
    $utf8 = New-Object Text.UTF8Encoding($false)
    try {
        $probe = Join-Path $tmp 'probe.ps1'
        [IO.File]::WriteAllText($probe, (@(
            '$p = @(Get-Module Microsoft.PowerShell.Utility -ListAvailable | ForEach-Object { $_.Path })',
            'if ($p.Count) { "FIRST=" + $p[0] } else { "FIRST=" }',
            'if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) { "HASH=yes" } else { "HASH=no" }'
        ) -join "`r`n"), $utf8)
        $outer = Join-Path $tmp 'outer.ps1'
        [IO.File]::WriteAllText($outer, (@(
            'param([string]$Probe)',
            ('& ''' + $ps51.Replace("'", "''") + ''' -NoProfile -File $Probe')
        ) -join "`r`n"), $utf8)

        # A PowerShell 7 module path, the shape Git Bash passes on from a pwsh terminal.
        $home7 = ([string](& $pwsh.Source -NoProfile -Command '$PSHOME')).Trim()
        $polluted = @(
            (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'),
            (Join-Path $env:ProgramFiles 'PowerShell\Modules'),
            (Join-Path $home7 'Modules'),
            (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
            (Get-WindowsPath 'System32\WindowsPowerShell\v1.0\Modules')
        ) -join ';'

        function Read-Probe([string]$exe, [string]$argLine) {
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = $exe
            $psi.Arguments = $argLine
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $psi.EnvironmentVariables['PSModulePath'] = $polluted
            $p = [Diagnostics.Process]::Start($psi)
            $out = $p.StandardOutput.ReadToEnd()
            $null = $p.StandardError.ReadToEnd()
            $null = $p.WaitForExit(60000)
            $r = @{ First = ''; Hash = '' }
            foreach ($line in ($out -split "`r?`n")) {
                if ($line.StartsWith('FIRST=')) { $r.First = $line.Substring(6) }
                if ($line.StartsWith('HASH=')) { $r.Hash = $line.Substring(5) }
            }
            return $r
        }

        $sys = Get-WindowsPath 'System32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Utility'
        $via = Read-Probe $pwsh.Source ('-NoProfile -File "' + $outer + '" -Probe "' + $probe + '"')
        Yes 'the guide route (pwsh started with that path, then 5.1) keeps Get-FileHash' ($via.Hash -eq 'yes')
        Yes 'and that 5.1 loads Windows PowerShell''s own Utility module' ($via.First.StartsWith($sys, [StringComparison]::OrdinalIgnoreCase))

        $direct = Read-Probe $ps51 ('-NoProfile -File "' + $probe + '"')
        Yes '5.1 started straight with a PowerShell 7 module path loses Get-FileHash (the failure the guide warns of)' ($direct.Hash -eq 'no')
        Yes 'because it finds PowerShell 7''s Utility module first' ($direct.First.StartsWith((Join-Path $home7 'Modules'), [StringComparison]::OrdinalIgnoreCase))
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
