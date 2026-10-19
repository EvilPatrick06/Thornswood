<#
  test-2459-artifact-unpack-race.ps1

      pwsh -NoProfile -File .\tests\test-2459-artifact-unpack-race.ps1

  Issue #2459: New-ThornswoodArtifact used to Remove-Item the shared unpacked
  folder under out\deploys\<component> on every call, so two runs from one
  checkout failed each other while one read game\gamemode.js. This proves:

    1. A second call for an already-unpacked artifact leaves the folder alone
       (same path, same mtime on a held file) with a reader open - no delete.
    2. Two near-simultaneous builds of one artifact in one checkout both
       finish with the same sha256 and a ready shared folder.
    3. No .unpacking-* staging dirs are left behind.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param()
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

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

$helper = Join-Path $Repo 'scripts\deploy\Artifact.ps1'
Yes 'scripts\deploy\Artifact.ps1 is there' (Test-Path -LiteralPath $helper)
if (-not (Test-Path -LiteralPath $helper)) { Done }
. $helper
Add-Type -AssemblyName System.IO.Compression.FileSystem

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-2459-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$src = Join-Path $tmp 'repo'
$out = Join-Path $tmp 'out'
$utf8 = New-Object Text.UTF8Encoding($false)
function Put([string]$path, [string]$text) {
    $d = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function Run-Git { $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; & git @args 2>&1 | Out-Null; $ErrorActionPreference = $old }

$oldCeiling = $env:GIT_CEILING_DIRECTORIES
$env:GIT_CEILING_DIRECTORIES = $tmp
$pwsh = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell -CommandType Application | Select-Object -First 1).Source }

try {
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    Put (Join-Path $src 'game\gamemode.js') ("'use strict';`nconsole.log('gamemode-2459');`n")
    Put (Join-Path $src 'game\extra.js') ("'use strict';`nconsole.log('extra');`n")
    Run-Git -C $src init -q
    Run-Git -C $src config core.autocrlf false
    Run-Git -C $src add -A
    Run-Git -C $src -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q -m one

    # ---- 1. second call while a reader holds a file in the shared folder ----
    $a1 = New-ThornswoodArtifact -Component gamemode -RepoDir $src -Paths 'game' -OutDir $out
    $held = Join-Path $a1.Folder 'game\gamemode.js'
    Yes 'first build unpacked game\gamemode.js' (Test-Path -LiteralPath $held)
    $beforeWrite = (Get-Item -LiteralPath $held).LastWriteTimeUtc
    $stream = [IO.File]::Open($held, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $a2 = $null
        $secondErr = $null
        try {
            $a2 = New-ThornswoodArtifact -Component gamemode -RepoDir $src -Paths 'game' -OutDir $out
        } catch {
            $secondErr = $_
        }
        Yes 'second call with a reader open does not throw' ($null -eq $secondErr)
        if ($secondErr) { Write-Host ("  " + $secondErr.Exception.Message) }
        Yes 'second call returns the same folder path' ($null -ne $a2 -and $a2.Folder -eq $a1.Folder)
        Yes 'second call returns the same sha256' ($null -ne $a2 -and $a2.Sha256 -eq $a1.Sha256)
        Yes 'the held file was not rewritten (mtime unchanged)' (
            (Test-Path -LiteralPath $held) -and ((Get-Item -LiteralPath $held).LastWriteTimeUtc -eq $beforeWrite))
        Yes 'the reader can still read the bytes' (
            $stream.CanRead -and ($stream.ReadByte() -ge 0))
    } finally {
        $stream.Dispose()
    }

    # ---- 2. two near-simultaneous builds in one checkout --------------------
    $out2 = Join-Path $tmp 'out-concurrent'
    $worker = Join-Path $tmp 'worker.ps1'
    $resultA = Join-Path $tmp 'result-a.txt'
    $resultB = Join-Path $tmp 'result-b.txt'
    $workerBody = @"
param([string]`$Helper, [string]`$RepoDir, [string]`$OutDir, [string]`$Result, [int]`$DelayMs = 0)
`$ErrorActionPreference = 'Stop'
`$env:THORNSWOOD_HARNESS = '1'
if (`$DelayMs -gt 0) { Start-Sleep -Milliseconds `$DelayMs }
. `$Helper
try {
  `$a = New-ThornswoodArtifact -Component gamemode -RepoDir `$RepoDir -Paths 'game' -OutDir `$OutDir
  [IO.File]::WriteAllText(`$Result, ('OK|' + `$a.Sha256 + '|' + `$a.Folder + '|' + `$a.Name))
  exit 0
} catch {
  [IO.File]::WriteAllText(`$Result, ('ERR|' + `$_.Exception.Message))
  exit 1
}
"@
    [IO.File]::WriteAllText($worker, $workerBody, $utf8)

    $argA = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $worker,
        '-Helper', $helper, '-RepoDir', $src, '-OutDir', $out2, '-Result', $resultA, '-DelayMs', '0')
    $argB = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $worker,
        '-Helper', $helper, '-RepoDir', $src, '-OutDir', $out2, '-Result', $resultB, '-DelayMs', '50')
    # Each worker is started by .NET's Process.Start, whose process object
    # holds the worker's handle from the moment it starts, so its exit code is
    # there once the worker has ended. Windows PowerShell 5.1's Start-Process
    # -PassThru hands back one that holds no handle, and its ExitCode read
    # empty once the worker had gone, so both workers failed there (#2739).
    function Start-Worker([string[]]$a) {
        $si = New-Object Diagnostics.ProcessStartInfo
        $si.FileName = $pwsh
        # Each argument quoted whole: the temp paths may hold a space, and
        # none of them holds a quote or ends in a backslash.
        $si.Arguments = (@($a | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        $si.UseShellExecute = $false
        $si.RedirectStandardOutput = $true
        $si.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($si)
        [pscustomobject]@{ P = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
    }
    # The exit code once the worker ends, or -1 when it is still going at the
    # two minutes both are given, which ends it.
    function Wait-Worker($w, [DateTime]$by) {
        $ms = [int][Math]::Max(0, ($by - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $w.P.WaitForExit($ms)) { $w.P.Kill(); $w.P.WaitForExit(); return -1 }
        # Without a timeout it also waits for the worker's output to be read to its end.
        $w.P.WaitForExit()
        return $w.P.ExitCode
    }
    $wA = Start-Worker $argA
    $wB = Start-Worker $argB
    $by = [DateTime]::UtcNow.AddSeconds(120)
    $codeA = Wait-Worker $wA $by
    $codeB = Wait-Worker $wB $by
    $textA = if (Test-Path -LiteralPath $resultA) { (Get-Content -LiteralPath $resultA -Raw).Trim() } else { 'MISSING' }
    $textB = if (Test-Path -LiteralPath $resultB) { (Get-Content -LiteralPath $resultB -Raw).Trim() } else { 'MISSING' }
    Yes ("worker A finished (exit $codeA)") ($codeA -eq 0 -and $textA.StartsWith('OK|'))
    Yes ("worker B finished (exit $codeB)") ($codeB -eq 0 -and $textB.StartsWith('OK|'))
    if ($codeA -eq 0 -and $codeB -eq 0 -and $textA.StartsWith('OK|') -and $textB.StartsWith('OK|')) {
        $partsA = $textA.Split('|')
        $partsB = $textB.Split('|')
        Yes 'both workers built the same sha256' ($partsA[1] -eq $partsB[1])
        Yes 'both workers point at the same folder' ($partsA[2] -eq $partsB[2])
        $folder = $partsA[2]
        $gm = Join-Path $folder 'game\gamemode.js'
        Yes 'the shared folder still has game\gamemode.js' (Test-Path -LiteralPath $gm)
        $left = @(Get-ChildItem -LiteralPath $out2 -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '.unpacking-*' })
        Yes 'no .unpacking-* staging dirs left behind' ($left.Count -eq 0)
    } else {
        Yes 'both workers built the same sha256' $false
        Yes 'both workers point at the same folder' $false
        Yes 'the shared folder still has game\gamemode.js' $false
        Yes 'no .unpacking-* staging dirs left behind' $false
        Write-Host ("  A result: $textA")
        Write-Host ("  B result: $textB")
        @($wA.Err.Result -split "`r?`n" | Where-Object { $_ }) | Select-Object -Last 5 | ForEach-Object { Write-Host "  A stderr: $_" }
        @($wB.Err.Result -split "`r?`n" | Where-Object { $_ }) | Select-Object -Last 5 | ForEach-Object { Write-Host "  B stderr: $_" }
    }

    # ---- 3. source still never Remove-Items the shared folder name ----------
    $srcText = Get-Content -LiteralPath $helper -Raw
    Yes 'Artifact.ps1 no longer Remove-Items the shared unpack folder' (
        $srcText -notmatch 'if \(Test-Path -LiteralPath \$folder\) \{ Remove-Item -LiteralPath \$folder -Recurse -Force \}')
    Yes 'Artifact.ps1 unpacks to a unique .unpacking- staging dir' (
        $srcText -match '\.unpacking-')
} finally {
    $env:GIT_CEILING_DIRECTORIES = $oldCeiling
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Done
