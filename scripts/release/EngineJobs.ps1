<#
  EngineJobs.ps1

  How many projects an engine build compiles at once, and whether a compile
  that failed ran the machine out of memory. Dot-sourced by Build-Engine.ps1
  and Build-Server.ps1, which both hand MSBuild what Get-EngineMSBuildArgs
  gives.

  WHY THIS EXISTS, issue #1203. Both scripts gave MSBuild a bare /m, which
  starts one project per core (22 on the shipping machine), and the fork
  compiles every C++ target with /MP (cmake\apply_default_settings.cmake),
  which starts one compiler per core inside each of those projects. On
  29 September, with 23.9 of 31.4 GB in use and other builds running, every
  skyrim_platform source failed at once with C3859 (Failed to create virtual
  memory for PCH) and C1076 (internal heap limit reached), and Build-Engine
  said the first error was the real one. Nothing was wrong with the code: the
  same build, continued with /m:2 /p:CL_MPCount=2, finished. The #1200 build
  ran /m:4 /p:CL_MPCount=2 with about 16 GB free and finished too.

  HOW MANY. Each project runs two compilers (CL_MPCount is the count MSBuild
  gives the fork's /MP), and each project is given 4 GB of the memory free
  when the build starts. Against the two builds measured: 16 GB free gives 4,
  the number the #1200 build ran; 7.5 GB free gives 1, one under the 2 that
  finished on 29 September, because the other builds on a busy machine grow
  while this one runs. Never fewer than one project, and never more
  compilers than the machine has cores. -Jobs on either script sets the
  number by hand.

  WHEN IT RUNS OUT ANYWAY. Get-EngineOutOfMemoryCode knows the compiler's and the
  linker's out of memory errors (C3859, C1076, C1060, LNK1102), so a build
  that failed with one says the machine ran out of memory and how to build
  with fewer at once, instead of pointing at the first error.
#>

# Compilers in each project, through CL_MPCount, and the memory each project
# is given. The header says where both numbers come from.
$EngineCompilersPerJob = 2
$EngineBytesPerJob = 4GB

# Projects at once for this much free memory on this many cores.
function Get-EngineJobs([double]$FreeBytes, [int]$Cores) {
    $byMemory = [int][Math]::Floor($FreeBytes / $EngineBytesPerJob)
    $byCores = [int][Math]::Floor($Cores / $EngineCompilersPerJob)
    $jobs = [Math]::Min($byMemory, $byCores)
    if ($jobs -lt 1) { $jobs = 1 }
    return [int]$jobs
}

# The physical memory free right now, in bytes (Windows reports kilobytes).
function Get-EngineFreeBytes {
    return [double](Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory * 1KB
}

# What MSBuild is given: this many projects at once, two compilers each.
function Get-EngineMSBuildArgs([int]$Jobs) {
    return @(('/m:' + $Jobs), ('/p:CL_MPCount=' + $EngineCompilersPerJob))
}

# The error code when a line of build output says the compiler or the
# linker ran out of memory, and '' for any other line.
function Get-EngineOutOfMemoryCode([string]$Line) {
    $m = [regex]::Match($Line, '\b(C3859|C1076|C1060|LNK1102)\b')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# The line that runs this script again as it was run, without -Jobs, for a
# build that ran out of memory to say with fewer at once.
function Get-EngineAgainLine([string]$Script, [System.Collections.IDictionary]$Bound) {
    $line = $Script
    foreach ($k in @($Bound.Keys | Sort-Object)) {
        if ($k -eq 'Jobs' -or $k -eq 'NoPause') { continue }
        $v = $Bound[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $line += ' -' + $k }; continue }
        $line += ' -' + $k + " '" + ([string]$v).Replace("'", "''") + "'"
    }
    return $line
}

# What a build that ran out of memory says, and the line to run again with.
function Get-EngineOutOfMemoryAdvice([string]$Code, [int]$Jobs, [double]$FreeBytes, [string]$Script) {
    $free = '{0:N1} GB' -f ($FreeBytes / 1GB)
    $said = 'the machine ran out of memory, not the code: the build said ' + $Code + ', which is the compiler or the linker running out. '
    if ($Jobs -le 1) {
        return ($said + 'This build compiled one project at a time, ' + $EngineCompilersPerJob +
                ' compilers, with ' + $free + ' free when it started. Close what else is building or running and run ' +
                $Script + ' again; what finished is not built again.')
    }
    $fewer = [int][Math]::Max(1, [Math]::Floor($Jobs / 2))
    return ($said + 'This build compiled ' + $Jobs + ' projects at once, ' + $EngineCompilersPerJob +
            ' compilers each, with ' + $free + ' free when it started. Close what else is building, or build with fewer at once: ' +
            $Script + ' -Jobs ' + $fewer + '  (what finished is not built again).')
}
