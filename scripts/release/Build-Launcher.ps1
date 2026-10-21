<#
  Build-Launcher.ps1
  Compiles the launcher into a real Thornswood.exe, and the setup program into
  out\setup-stub.exe.

  It runs MSBuild on the two project files, launcher\app\Thornswood.csproj and
  installer\setup\Setup.csproj, with the MSBuild of Visual Studio 2022 or its
  free Build Tools (Find-MSBuild.ps1 says whether this machine has it;
  Developer-Guide.md "Setting up a machine" has the one install line). Your
  friends never compile anything - they get the finished exe in the bundle.

  THE SWITCH (#498, Patrick's option C, 11 Oct; done 15 Oct). Until then this
  script called the .NET Framework csc that ships inside Windows directly,
  with sixty lines finding framework assemblies by hand, and held the launcher
  to C# 5, because that compiler knows nothing newer and was the only one every
  machine that built the launcher had. The project files were added on 12 Oct
  (#2362) and built the same exe both ways (the figures are on #498); what
  kept the old build was the VPS build runners, which had no MSBuild until
  Bootstrap-VPS.ps1 -IncludeBuildTools put it there. Now there is one build:
  what goes into each exe (sources, references, resources, icon, stamped
  manifest, file details, LangVersion) is written in the project files and
  nowhere else, and this script is the two build lines, the checks the project
  files cannot make, and the signing.

  It builds into the DEV install by default, not the one you play on. Running
  this by hand used to overwrite C:\Thornswood\Launcher, so a build nobody had
  tried yet became the launcher in front of you, and on 17 Sep one did exactly
  that and wrote a broken setting into the game folder on the next Play. A
  build you ran to see whether it compiles should never be able to do that.

  Ship.ps1 passes -Root itself, so a real release still builds where it should.
  Pass -Root 'C:\Thornswood' if you genuinely mean the one you play on.

  IT BUILDS AND DOES NOTHING ELSE. It writes Thornswood.exe into -OutDir, which
  is <Root>\Launcher unless told otherwise, and the setup stub into out\. It
  closes no game and no launcher, and it does not touch the Desktop, the icon
  cache or Explorer. Those are Install-Launcher.ps1, which Ship.ps1 runs after
  a build that worked. Until 24 September this script did both, so every
  compile check and every hand build closed whatever Skyrim was running on the
  machine. That was To Do List entry 243: "A build produces files in an output
  folder and does not kill processes or write to the Desktop."
#>
[CmdletBinding()]
param(
    [string]$Src,
    # The dev install, Where.ps1 InstallDev, unless told otherwise (#3031).
    [string]$Root,
    # Where Thornswood.exe goes. Ship builds into a folder of its own and lets
    # Install-Launcher put the exe in place, so the build never meets a
    # launcher that is still running from the install.
    [string]$OutDir,
    [switch]$NoPause,
    # Where the setup program goes, out\setup-stub.exe unless told otherwise.
    # tests\test-498-msbuild.ps1 builds into scratch so a test build never
    # replaces the stub a clone's packaging copies from.
    [string]$StubOut,
    # Leaves the launcher unsigned even on a machine with records\signing\signing.json.
    # For a test build that never ships, so it spends no signing; Ship never
    # passes it, and Ship and Publish-Installer refuse an unsigned exe.
    [switch]$NoSign
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $MyInvocation is not usable from inside a param block, so the script folder
# is worked out here instead.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Src)  { $Src  = Join-Path $Here '..\..\launcher\app' }
if (-not $Root) { $Root = [string](& (Join-Path $Here 'Where.ps1') InstallDev) }
if (-not $OutDir) { $OutDir = Join-Path $Root 'Launcher' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Head 'Thornswood - launcher build'
Say ("  building into $OutDir") 'DarkGray'
if ($Root.TrimEnd('\\') -ieq [string](& (Join-Path $Here 'Where.ps1') Install)) {
    Say '  this is the install you play on, not the dev one' 'Yellow'
}

# ------------------------------------------------------------ MSBuild
. (Join-Path $Here 'Find-MSBuild.ps1') -Load
$found = Find-ThornswoodMSBuild
if (-not $found.MSBuild) { Die 'MSBuild was not found on this machine. The launcher builds with Visual Studio 2022 or its Build Tools with the MSBuild component; Developer-Guide.md "Setting up a machine" has the install line. On a VPS runner: .\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments ''-IncludeBuildTools -SkipFirewall''.' }
if (-not $found.RefAssemblies) { Die 'The .NET Framework 4.8.1 reference assemblies are not on this machine. They are the Build Tools component Microsoft.Net.Component.4.8.1.TargetingPack; Developer-Guide.md "Setting up a machine" has the install line.' }
Say "  $($found.MSBuild)" 'DarkGray'
$proj = Join-Path $Src 'Thornswood.csproj'
$stubProj = Join-Path $Here '..\..\installer\setup\Setup.csproj'
foreach ($p in @($proj, $stubProj)) {
    if (-not (Test-Path -LiteralPath $p)) { Die "$([IO.Path]::GetFileName($p)) is not at $p. It is in the repository, so the path is wrong; nothing was built." }
}

# ------------------------------------------- the records compiled into it
# RecordShape.ps1 (#2180): the two records compiled into the launcher must be
# a version this checkout knows with every field OwnGame reads, or the build
# stops here; a launcher with a half-read list in it is worse than none. The
# project file embeds them; it cannot read their shape, so this does.
. (Join-Path $Here 'RecordShape.ps1')
foreach ($embedded in @(@{ Path = (Join-Path $Here '..\..\records\skyrim-files.json'); Kind = 'skyrim-files' },
                        @{ Path = (Join-Path $Here '..\..\records\ui-gone.json'); Kind = 'ui-gone' })) {
    if (Test-Path -LiteralPath $embedded.Path) {
        try { $null = Read-ThornswoodRecord -Path $embedded.Path -Kind $embedded.Kind } catch { Die ($_.Exception.Message + ' Nothing was built.') }
    }
}

$null = New-Item -ItemType Directory -Force -Path $outDir
$exe = Join-Path $outDir 'Thornswood.exe'

# Nothing is closed here; Install-Launcher.ps1 does that, after a build that
# worked. So a launcher still running from this folder holds its own exe and
# the build cannot replace it. That is said plainly here, before any work,
# rather than left to a file-in-use error at the end of a compile.
if (Test-Path -LiteralPath $exe) {
    try { $held = [IO.File]::Open($exe, 'Open', 'ReadWrite', 'None'); $held.Close() }
    catch { Die ("$exe is in use, most likely by the launcher running from that folder. A build closes nothing. " +
                 "Close it, or build somewhere else with -OutDir. Ship builds into a folder of its own and closes it for you.") }
}

Head 'Compiling'
# -nr:false: without it MSBuild leaves its worker processes running after the
# build, holding files under out\obj, and a runner names them as left behind.
$msbArgs = @('-nologo', '-v:minimal', '-nr:false', '-p:Configuration=Release')
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $found.MSBuild (Resolve-Path -LiteralPath $proj).Path @msbArgs ('-p:OutDir=' + $outDir.TrimEnd('\') + '\')
$rc = $LASTEXITCODE
$ErrorActionPreference = $old
if ($rc -ne 0 -or -not (Test-Path $exe)) { Die "MSBuild exited with $rc" }
Say ("  Thornswood.exe  {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'
$pdb = [IO.Path]::ChangeExtension($exe, '.pdb')
if (Test-Path -LiteralPath $pdb) {
    Say ("  Thornswood.pdb  {0:n0} KB (kept beside the exe; packs and the installer leave it out)" -f ((Get-Item $pdb).Length / 1KB)) 'DarkGray'
} else {
    Say '  Thornswood.pdb did not appear beside the exe' 'Yellow'
}

# ------------------------------------------------------------ setup stub
Head 'Setup stub'
# Built under the name it ships as (the project's AssemblyName is
# Thornswood-Setup, because Windows reads OriginalFilename and InternalName
# from the name it was built as), into a scratch folder, then moved onto
# out\setup-stub.exe, which packaging copies from. Deleting the old one up
# front meant a failed build left no installer at all, and the only sign of
# it was a red STOP an hour before anyone noticed the package had no exe in
# it, so a failed build leaves the last working copy. out\ is the build
# output, the folder Where.ps1 calls Out, ignored by git.
$stub = Join-Path (Join-Path $Here '..\..\out') 'setup-stub.exe'
if ($StubOut) { $stub = $StubOut }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stub) | Out-Null
$stubBuild = Join-Path ([IO.Path]::GetTempPath()) 'ThornswoodSetupBuild'
if (Test-Path -LiteralPath $stubBuild) { Remove-Item -LiteralPath $stubBuild -Recurse -Force }
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $found.MSBuild (Resolve-Path -LiteralPath $stubProj).Path @msbArgs ('-p:OutDir=' + $stubBuild + '\')
$rc2 = $LASTEXITCODE
$ErrorActionPreference = $old
$stubNew = Join-Path $stubBuild 'Thornswood-Setup.exe'
if ($rc2 -ne 0 -or -not (Test-Path -LiteralPath $stubNew)) {
    Write-Host ''
    Say "  MSBuild exited with $rc2. The installer program did NOT build." 'Red'
    if (Test-Path $stub) {
        Die 'setup-stub.exe did not rebuild. The last working copy is still here, but a release must not ship on a failed stub build. Fix the compile error above and run Build-Launcher again.'
    } else {
        Die 'There is no setup-stub.exe at all. A package built now would have no installer in it. Fix the compile error above and run Build-Launcher again.'
    }
}
if (Test-Path $stub) { Remove-Item $stub -Force }
Move-Item -LiteralPath $stubNew -Destination $stub
Say ("  setup-stub.exe  {0:n0} KB" -f ((Get-Item $stub).Length / 1KB)) 'Green'
$stubPdb = [IO.Path]::ChangeExtension($stub, '.pdb')
if (Test-Path -LiteralPath $stubPdb) { Remove-Item -LiteralPath $stubPdb -Force }
Move-Item -LiteralPath ([IO.Path]::ChangeExtension($stubNew, '.pdb')) -Destination $stubPdb
Remove-Item -LiteralPath $stubBuild -Recurse -Force

# ------------------------------------------------------------ signing
#
# Sign the launcher here. Do NOT sign setup-stub.exe.
#
# Package-Thornswood.ps1 -OneFile copies the stub, appends the payload and a
# trailer, then signs Thornswood-Setup.exe. Authenticode cannot survive that
# append: a pre-signed stub makes the combined file un-signable (signtool
# 0x800700C1). Measured 27 September on Main Package. The stub stays unsigned
# on disk; Package signs the final Setup after attach, and the two-file path
# signs the copied Setup the same way. A stranger still gets a signed installer
# from the site; this machine's out\setup-stub.exe is only a build input.
#
# This does nothing at all unless records\signing\signing.json exists, so Djinn's machine
# and the pull request build carry on exactly as before. See the header of
# Sign-Artifact.ps1 for what that file holds, and Bootstrap.cs:112-121 for why
# any of this matters.
$signer = Join-Path $Here 'Sign-Artifact.ps1'
if ($NoSign) {
    Say '  not signing: -NoSign, a test build that never ships' 'DarkGray'
} elseif (Test-Path -LiteralPath $signer) {
    Head 'Signing'
    & $signer -Path $exe
    if ($LASTEXITCODE -ne 0) { Die 'Signing failed. Nothing was published.' }
}

# The shortcut, the icon file beside the exe, Explorer's redraw and its icon
# cache used to follow here. They are Install-Launcher.ps1 now, with the
# closing of a running game and launcher, because they are what an install
# does and a build has no business doing them.

Head 'Done'
Say $exe 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }

# Said out loud rather than left to chance.
#
# A PowerShell script that runs off the end does not reset $LASTEXITCODE: the
# caller sees whatever the last native command left behind, and this script runs
# MSBuild and signtool. Ship.ps1 reads that code to decide whether a release may
# go out, so a stray value here would either hide a failure or stop a good build
# for no reason.
exit 0
