<#
  test-3059-long-stdin.ps1

  A measurement for #3059, run on a VPS Windows runner, not a pass or fail.

  Since #3036 a script over 6,000 characters goes to the box as one base64
  line on ssh's standard input, read by [Console]::In.ReadLine(). On the box
  Install-Runner's firewall script never arrived. The box's sshd starts the
  command as `powershell.exe -c "<command>"` (pid 440 on 21 Oct), so the
  reader is a child of an outer Windows PowerShell whose standard input is
  the session's. This runs the same reader on this machine in each shape,
  with no sshd, and prints what arrived, for line sizes from 4 KB to 330 KB:

    direct     the reader alone, standard input a pipe
    ps-outer   inside powershell.exe -c, as the box's sshd starts it
    cmd-outer  inside cmd.exe /d /c, the other shell sshd can use

  and for each, standard input closed after the write (what `$input | & ssh`
  does) or held open (what #2912 saw: the end never reaches the box), and the
  write made at once or three seconds late. Every case has a 15 second limit
  and its process tree is ended at the limit, so nothing is left running.
#>
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') { Write-Host 'SKIP  Windows PowerShell 5.1 is the shell measured, and only Windows has it'; exit 0 }

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'

$lineReader = ". ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((('' + [Console]::In.ReadLine()) -replace '[^A-Za-z0-9+/=]', '')))))"
$chunkReader = "`$b = New-Object Text.StringBuilder; while (`$null -ne (`$l = [Console]::In.ReadLine()) -and `$l -ne '.') { [void]`$b.Append(`$l) }; . ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((`$b.ToString() -replace '[^A-Za-z0-9+/=]', '')))))"

function Enc([string]$s) { [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s)) }

function Run-Case([string]$wrapper, [string]$reader, [int]$size, [bool]$close, [int]$delayMs) {
    $script = '# ' + ('x' * $size) + "`n'ARRIVED ' + " + $size
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    if ($reader -eq 'line') { $wire = $b64 + "`r`n"; $run = 'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + (Enc $lineReader) }
    else {
        $parts = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $b64.Length; $i += 1000) { $parts.Add($b64.Substring($i, [Math]::Min(1000, $b64.Length - $i))) }
        $parts.Add('.')
        $wire = ($parts -join "`r`n") + "`r`n"
        $run = 'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + (Enc $chunkReader)
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    switch ($wrapper) {
        'direct'    { $psi.FileName = $ps; $psi.Arguments = $run.Substring('powershell '.Length) }
        'ps-outer'  { $psi.FileName = $ps; $psi.Arguments = '-c "' + $run + '"' }
        'cmd-outer' { $psi.FileName = $cmdExe; $psi.Arguments = '/d /c "' + $run + '"' }
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if ($delayMs) { Start-Sleep -Milliseconds $delayMs }
    $bytes = [Text.Encoding]::ASCII.GetBytes($wire)
    $writeTask = $p.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
    $wrote = $writeTask.Wait(15000)
    if ($wrote) { try { $p.StandardInput.BaseStream.Flush() } catch { } }
    if ($wrote -and $close) { try { $p.StandardInput.Close() } catch { } }
    $left = [Math]::Max(1000, 15000 - [int]$clock.ElapsedMilliseconds)
    $ended = $p.WaitForExit($left)
    $ms = [int]$clock.ElapsedMilliseconds
    if (-not $ended) {
        & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
        [void]$p.WaitForExit(5000)
    }
    $out = ''; $err = ''
    if ($outTask.Wait(3000)) { $out = $outTask.Result }
    if ($errTask.Wait(1000)) { $err = $errTask.Result }
    $got = $out -match ('ARRIVED ' + $size)
    $verdict = if ($got -and $ended) { 'ARRIVED' } elseif ($got) { 'ARRIVED-BUT-HUNG' } elseif ($ended) { 'ENDED-WITHOUT' } else { 'HUNG' }
    $o = (($out + ' ' + $err) -replace '\s+', ' ').Trim()
    if ($o.Length -gt 160) { $o = $o.Substring(0, 160) + '...' }
    '{0,-17} {1,-9} {2,-5} script={3,7} wire={4,7} close={5,-3} delay={6,4} wrote={7,-3} code={8,-4} {9,6} ms  {10}' -f $verdict, $wrapper, $reader, $size, $wire.Length, $(if ($close) { 'yes' } else { 'no' }), $delayMs, $(if ($wrote) { 'yes' } else { 'no' }), $(if ($ended) { $p.ExitCode } else { '-' }), $ms, $o
}

Write-Host ('Windows PowerShell ' + (& $ps -NoProfile -c '$PSVersionTable.PSVersion.ToString()') + ' on ' + $env:COMPUTERNAME + ' as ' + [Environment]::UserName)
$sizes = 3000, 10000, 30000, 60000, 120000, 250000
foreach ($s in $sizes) { Run-Case 'direct' 'line' $s $true 0 }
foreach ($s in $sizes) { Run-Case 'cmd-outer' 'line' $s $true 0 }
foreach ($s in $sizes) { Run-Case 'ps-outer' 'line' $s $true 0 }
foreach ($s in $sizes) { Run-Case 'ps-outer' 'line' $s $false 0 }
foreach ($s in $sizes) { Run-Case 'ps-outer' 'chunk' $s $true 0 }
foreach ($s in $sizes) { Run-Case 'ps-outer' 'chunk' $s $false 0 }
Run-Case 'direct' 'line' 3000 $false 3000
Run-Case 'cmd-outer' 'line' 3000 $false 3000
Run-Case 'ps-outer' 'line' 3000 $false 3000
Run-Case 'ps-outer' 'line' 60000 $true 3000
exit 0
