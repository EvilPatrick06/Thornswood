<#
  test-3561-setup-unpack-fence.ps1

      pwsh -NoProfile -File .\tests\test-3561-setup-unpack-fence.ps1

  The setup program unpacks its payload only inside its scratch folder, by the
  same rule the launcher fences its packs with.

  Issue #3561. Bootstrap.cs unpacked each zip entry after
  `full.StartsWith(temp, ...)`, where temp is the scratch folder with no
  separator on its end (C:\Thornswood-setup). An entry that resolved to
  C:\Thornswood-setup2\x passed that test, so a payload could write into a
  neighbouring folder whose name only starts the same. The launcher already
  had the right rule, Updater.Inside: compare against the folder plus its
  separator. The cause was two copies of the fence, one of them wrong. Now
  there is one, launcher\app\PathFence.cs, which the launcher compiles with
  launcher\app\*.cs and Setup.csproj links in beside WindowFit.cs and
  Themes.cs.

  What this holds the files to:
    1. Setup.csproj compiles PathFence.cs into the setup program;
    2. Bootstrap's unpack takes an entry only when PathFence.Inside says it is
       inside temp, and nothing in Bootstrap compares a path to temp with a
       bare StartsWith;
    3. there is one Inside: no other `static bool Inside(` in launcher\app or
       installer\setup;
    4. PathFence.cs leans on nothing else in launcher\app, so the setup
       program can compile it alone;
    5. on Windows, PathFence.cs compiled with the compiler the build runs: the
       neighbouring folder stays out, a file under the folder is let in, and
       the unpack's own path, Combine then GetFullPath, keeps a ..\ entry out.
       Off Windows that part says SKIP, as every harness that compiles
       launcher code does (tests\Launcher-Csc.ps1).

  It fails on the old line: check 2 finds `StartsWith(temp` there, and the
  old rule is shown letting the neighbour in below.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Root) { $Root = Split-Path -Parent $Here }
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#2821)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bsPath    = Join-Path $Root 'installer\setup\Bootstrap.cs'
$projPath  = Join-Path $Root 'installer\setup\Setup.csproj'
$fencePath = Join-Path $Root 'launcher\app\PathFence.cs'
$bs    = [IO.File]::ReadAllText($bsPath)
$proj  = [IO.File]::ReadAllText($projPath)
$fence = if (Test-Path -LiteralPath $fencePath) { [IO.File]::ReadAllText($fencePath) } else { '' }

# ---- 1. the setup program compiles the shared fence --------------------------
Yes 'launcher\app\PathFence.cs is there' ($fence.Length -gt 0)
Yes 'Setup.csproj compiles PathFence.cs into the setup program' (
    $proj.Contains('<Compile Include="..\..\launcher\app\PathFence.cs"><Link>PathFence.cs</Link></Compile>'))

# ---- 2. the unpack is held to it ---------------------------------------------
$unpack = [regex]::Match($bs, '(?s)string full = Path\.GetFullPath\(dest\);\s*(?<check>[^\r\n]*)\r?\n\s*Directory\.CreateDirectory\(Path\.GetDirectoryName\(full\)\);\s*e\.ExtractToFile\(full, true\);')
Yes 'Bootstrap''s unpack is where this expects it: resolve, check, extract' ($unpack.Success)
$check = if ($unpack.Success) { $unpack.Groups['check'].Value.Trim() } else { '' }
Yes ('the unpack checks the resolved entry with PathFence.Inside(full, temp), got: ' + $check) (
    $check -eq 'if (!Thornswood.PathFence.Inside(full, temp)) continue;')
Yes 'nothing in Bootstrap compares a path to temp with a bare StartsWith' (
    -not [regex]::IsMatch($bs, 'StartsWith\(\s*temp\b'))

# ---- 3. one copy of the rule -------------------------------------------------
$copies = @(Get-ChildItem -LiteralPath (Join-Path $Root 'launcher\app'), (Join-Path $Root 'installer\setup') -Filter *.cs -File |
    Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'static\s+bool\s+Inside\s*\(' } |
    ForEach-Object { $_.Name })
Yes ('PathFence.cs holds the only Inside, found in: ' + ($copies -join ', ')) (
    $copies.Count -eq 1 -and $copies[0] -eq 'PathFence.cs')

# ---- 4. it stands alone ------------------------------------------------------
$usings = @([regex]::Matches($fence, '(?m)^using\s+([\w.]+);') | ForEach-Object { $_.Groups[1].Value })
Yes ('PathFence.cs uses only System and System.IO, got: ' + ($usings -join ', ')) (
    $usings.Count -eq 2 -and $usings -contains 'System' -and $usings -contains 'System.IO')
foreach ($w in 'Paths.', 'Swallow', 'Log(', 'Updater.') {
    Yes ('PathFence.cs leans on nothing else in launcher\app: no ' + $w) (-not $fence.Contains($w))
}

# The old rule, as Bootstrap had it, lets the neighbour in. This is the hole.
Yes 'the old bare prefix lets C:\Thornswood-setup2\x in, which is why it went' (
    'C:\Thornswood-setup2\x'.StartsWith('C:\Thornswood-setup', [StringComparison]::OrdinalIgnoreCase))

# ---- 5. compiled and asked ---------------------------------------------------
if (-not $OnWindows) {
    Write-Host 'SKIP  5. PathFence.Inside, compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'
}
else {
    $asm = $null
    try { $asm = Add-LauncherType -Source $fence }
    catch { Write-Host ('      ' + $_.Exception.Message) }
    Yes 'PathFence.cs compiles on its own, with the compiler the build runs' ($null -ne $asm)
    if ($null -ne $asm) {
        $m = $asm.GetType('Thornswood.PathFence').GetMethod('Inside', [Reflection.BindingFlags]'Static, Public, NonPublic')
        function Within([string]$full, [string]$folder) { return [bool]$m.Invoke($null, [object[]]@($full, $folder)) }

        $temp = 'C:\Thornswood-setup'
        Yes 'a file under the scratch folder is let in' (Within 'C:\Thornswood-setup\Data\Skyrim.ini' $temp)
        Yes 'C:\Thornswood-setup2\x stays out, the case #3561 found' (-not (Within 'C:\Thornswood-setup2\x' $temp))
        Yes 'C:\Thornswood-setup-old\x stays out too' (-not (Within 'C:\Thornswood-setup-old\x' $temp))
        Yes 'the folder itself is not inside itself' (-not (Within $temp $temp))
        Yes 'a scratch folder given with its separator on the end' (Within 'C:\Thornswood-setup\x' ($temp + '\'))
        Yes 'the case of the letters does not matter' (Within 'c:\thornswood-setup\x' $temp)
        Yes 'nothing given is inside nothing' (-not (Within '' $temp) -and -not (Within 'C:\x' ''))

        # The unpack's own steps: Combine with the entry's name, then GetFullPath.
        foreach ($entry in '..\Thornswood-setup2\x.dll', '..\..\Windows\x.dll', 'Data\..\..\Thornswood-setup2\x') {
            $full = [IO.Path]::GetFullPath([IO.Path]::Combine($temp, $entry))
            Yes ("an entry named '$entry' resolves to $full and stays out") (-not (Within $full $temp))
        }
        foreach ($entry in 'Data\Skyrim.ini', 'Data\..\Data\x.esp') {
            $full = [IO.Path]::GetFullPath([IO.Path]::Combine($temp, $entry))
            Yes ("an entry named '$entry' resolves to $full and is let in") (Within $full $temp)
        }
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
