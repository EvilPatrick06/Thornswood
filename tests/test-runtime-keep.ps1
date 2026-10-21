<# Compile the real Keep and ClientRuntime classes with a recorded fixture.
   Only the download and install environment is replaced; no network or game
   installation is touched. Exercises the repair followed by Play sequence. #>
param([string]$Repo = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
if (-not $OnWindows) { Write-Host 'NOT RUN  this compiles Keep.cs and ClientRuntime.cs with the build''s compiler (the Build Tools'' csc) and runs them on .NET Framework, which only Windows has'; exit 0 }
$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-runtime-keep-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
try {
    $good = [Text.Encoding]::UTF8.GetBytes('recorded client')
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $sha = ([BitConverter]::ToString($hash.ComputeHash($good))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
    $record = @{ files = @{ 'Data\Platform\Plugins\skymp5-client.js' = [ordered]@{ sha256 = $sha; bytes = $good.Length } } } | ConvertTo-Json -Depth 5
    $recordPath = Join-Path $work 'client-build.json'
    [IO.File]::WriteAllText($recordPath, $record)
    $exe = Join-Path $work 'runtime-keep-test.exe'
    & $LauncherCsc /nologo /target:exe "/out:$exe" /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll "/resource:$recordPath,client-build.json" (Join-Path $Repo 'launcher\app\Keep.cs') (Join-Path $Repo 'launcher\app\ClientRuntime.cs') (Join-Path $Repo 'tests\fixtures\RuntimeKeepTest.cs')
    if ($LASTEXITCODE) { throw 'Runtime/Keep fixture did not compile' }
    & $exe $work
    if ($LASTEXITCODE) { throw 'Runtime/Keep regression failed' }
} finally {
    $target = [IO.Path]::GetFullPath($work)
    # This machine's separator: off Windows the temp folder ends in / (#2989).
    $sep = [IO.Path]::DirectorySeparatorChar
    $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd($sep) + $sep
    if (-not $target.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target) -notlike 'thornswood-runtime-keep-*') { throw 'Unsafe fixture cleanup target' }
    Remove-Item -LiteralPath $target -Recurse -Force
}
