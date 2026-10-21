<#
  test-setup-game-files.ps1

  The parts of installer\Setup-Thornswood.ps1 that decide which files in a
  player's game get read, replaced or deleted, run for real against stand-in
  folders under %TEMP%. No Steam, no network, no install.

  What this holds the setup script to:
    - Get-Libraries: Steam's own folder first, then every "path" in
      steamapps\libraryfolders.vdf with Valve's doubled backslashes undone,
      a library that is gone is left out, nothing listed twice, and a
      library whose folder name has [ ] in it is still found (a Skyrim on
      D:\Games [SSD]\Steam must not read as "not installed");
    - Resolve-Depot: finds a downloaded depot in each of the four layouts
      Steam has used, and says nothing when it is not there;
    - Get-Mismatched: a file that matches vanilla.json is clean, a changed
      one is named, the hash is compared without caring about case, and a
      file the game does not have is not reported;
    - Remove-SharedNames: every name the payload is about to replace comes
      off first. A hard-linked name goes and its other name (the Steam copy
      or Vortex staging) keeps its bytes; a plain or read-only file goes too;
      anything the payload does not carry is left alone; the payload itself
      is not touched; names with [ ] in them are handled.

  HOW. The functions are lifted out of the real script with the PowerShell
  parser, so this tests the shipped code, not a copy of it.
#>
[CmdletBinding()]
param([string]$SetupPath, [string]$Scratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repoRoot = Split-Path -Parent $Here
if (-not $SetupPath) { $SetupPath = Join-Path $repoRoot 'installer\Setup-Thornswood.ps1' }
if (-not $Scratch) { $Scratch = [IO.Path]::GetTempPath() }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

. (Join-Path $PSScriptRoot 'Windows.ps1')

# ---- lift the functions out of the real script -----------------------------
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($SetupPath, [ref]$tokens, [ref]$errors)
Yes 'Setup-Thornswood.ps1 parses' ($errors.Count -eq 0)
$want = 'Get-Libraries', 'Resolve-Depot', 'Get-Sha256', 'Get-Mismatched', 'Remove-SharedNames'
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($want -contains $f.Name -and -not $fns.ContainsKey($f.Name)) { $fns[$f.Name] = $f.Extent.Text }
}
foreach ($n in $want) { Yes "the script still defines $n" ($fns.ContainsKey($n)) }
if ($script:fail) { Write-Host "$($script:pass) passed, $($script:fail) failed"; exit 1 }

function Say($m, $c = 'Gray') { $script:said += , [string]$m }
foreach ($n in $want) { . ([scriptblock]::Create($fns[$n])) }

$root = Join-Path $Scratch ('ts-setup-files-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
function Put([string]$p, [string]$text) {
    $d = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Force -Path $d }
    [IO.File]::WriteAllText($p, $text)
}
function ReadOf([string]$p) { [IO.File]::ReadAllText($p) }

try {
    # ---- 1. Get-Libraries -----------------------------------------------------
    $steam = Join-Path $root 'Steam'
    $libA  = Join-Path $root 'LibA'
    $libB  = Join-Path $root 'Games [SSD]\SteamLibrary'
    $gone  = Join-Path $root 'Unplugged'
    $null = New-Item -ItemType Directory -Force -Path $libA, $libB, (Join-Path $steam 'steamapps')
    $esc = { param($p) $p.Replace('\', '\\') }
    $vdf = @(
        '"libraryfolders"', '{',
        '  "0"', '  {', ('    "path"		"' + (& $esc $steam) + '"'), '  }',
        '  "1"', '  {', ('    "path"		"' + (& $esc $libA) + '"'), '    "label"		""', '  }',
        '  "2"', '  {', ('    "path"		"' + (& $esc $gone) + '"'), '  }',
        '  "3"', '  {', ('    "path"		"' + (& $esc $libB) + '"'), '  }',
        '}')
    [IO.File]::WriteAllLines((Join-Path $steam 'steamapps\libraryfolders.vdf'), $vdf)
    $libs = @(Get-Libraries $steam)
    Yes 'Steam''s own folder is the first library' ($libs.Count -gt 0 -and $libs[0] -eq $steam)
    Yes 'a second library is read out of libraryfolders.vdf, backslashes undone' ($libs -contains $libA)
    Yes 'Steam''s folder, listed again in the file, is not listed twice' (@($libs | Where-Object { $_ -eq $steam }).Count -eq 1)
    Yes 'a library whose folder is gone is left out' (-not ($libs -contains $gone))
    Yes 'a library with [ ] in its folder name is still found' ($libs -contains $libB)
    $bare = Join-Path $root 'BareSteam'; $null = New-Item -ItemType Directory -Force -Path $bare
    $only = @(Get-Libraries $bare)
    Yes 'with no libraryfolders.vdf, Steam''s own folder is the only library' ($only.Count -eq 1 -and $only[0] -eq $bare)

    # ---- 2. Resolve-Depot -----------------------------------------------------
    $AppId = 489830
    $content = Join-Path $root 'content'
    $layouts = @{
        '111' = "app_$AppId\depot_111"
        '222' = "$AppId\222"
        '333' = 'depot_333'
        '444' = '444'
    }
    foreach ($k in $layouts.Keys) { $null = New-Item -ItemType Directory -Force -Path (Join-Path $content $layouts[$k]) }
    foreach ($k in $layouts.Keys) {
        Yes "a depot downloaded as $($layouts[$k]) is found" ((Resolve-Depot $k) -eq (Join-Path $content $layouts[$k]))
    }
    Yes 'a depot that is not downloaded comes back empty' ($null -eq (Resolve-Depot '999'))

    # ---- 3. Get-Mismatched ----------------------------------------------------
    $GameDir = Join-Path $root 'Game'
    Put (Join-Path $GameDir 'SkyrimSE.exe') 'clean exe'
    Put (Join-Path $GameDir 'steam_api64.dll') 'clean dll'
    Put (Join-Path $GameDir 'skse64_loader.exe') 'clean loader'
    $doc = [pscustomobject]@{
        'SkyrimSE.exe'      = (Get-Sha256 (Join-Path $GameDir 'SkyrimSE.exe')).ToUpper()
        'steam_api64.dll'   = (Get-Sha256 (Join-Path $GameDir 'steam_api64.dll'))
        'skse64_loader.exe' = (Get-Sha256 (Join-Path $GameDir 'skse64_loader.exe'))
        'NotThere.dll'      = ('0' * 64)
    }
    $off = @(Get-Mismatched $doc)
    Yes 'a clean game has nothing mismatched (upper-case hash in the list too)' ($off.Count -eq 0)
    Yes 'a file the game does not have is not reported' (-not ($off -contains 'NotThere.dll'))
    Put (Join-Path $GameDir 'skse64_loader.exe') 'patched by some other setup'
    $off = @(Get-Mismatched $doc)
    Yes 'a patched file is named' ($off.Count -eq 1 -and $off[0] -eq 'skse64_loader.exe')
    Put (Join-Path $GameDir 'SkyrimSE.exe') 'patched exe'
    $off = @(Get-Mismatched $doc)
    Yes 'a patched SkyrimSE.exe is named, which is what sends setup to the depot repair' ($off -contains 'SkyrimSE.exe')

    # ---- 4. Remove-SharedNames ------------------------------------------------
    if (-not $OnWindows) {
        Write-Host 'SKIP  4. Remove-SharedNames: its linked names are NTFS hard links made with cmd.exe''s mklink, which only Windows has'
    } else {
        $steamCopy = Join-Path $root 'SteamCopy'
        $made      = Join-Path $root 'Made'
        $payload   = Join-Path $root 'Payload'
        Put (Join-Path $steamCopy 'Data\Skyrim.esm') 'STEAM MASTER'
        Put (Join-Path $steamCopy 'Data\Shared [x].bsa') 'STEAM BRACKET'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $made 'Data')
        $null = New-Item -ItemType HardLink -Path (Join-Path $made 'Data\Skyrim.esm') -Target (Join-Path $steamCopy 'Data\Skyrim.esm')
        $lb = Join-Path $made 'Data\Shared [x].bsa'
        & (Get-WindowsPath 'System32\cmd.exe') /c mklink /H "$lb" "$(Join-Path $steamCopy 'Data\Shared [x].bsa')" | Out-Null
        Put (Join-Path $made 'Data\Plain.esp') 'OLD PLAIN'
        Put (Join-Path $made 'Data\Locked.esp') 'OLD LOCKED'
        [IO.File]::SetAttributes((Join-Path $made 'Data\Locked.esp'), [IO.FileAttributes]::ReadOnly)
        Put (Join-Path $made 'Data\Keep.esp') 'NOT IN PAYLOAD'
        foreach ($n in 'Skyrim.esm', 'Shared [x].bsa', 'Plain.esp', 'Locked.esp', 'New.esp') { Put (Join-Path $payload "Data\$n") "PAYLOAD $n" }
        Yes 'stand-in: the made folder''s master is a hard link to the Steam copy' ((Get-Item -LiteralPath (Join-Path $made 'Data\Skyrim.esm')).LinkType -eq 'HardLink')
        $script:said = @()
        Remove-SharedNames $payload $made
        Yes 'the linked master is gone from the made folder' (-not (Test-Path -LiteralPath (Join-Path $made 'Data\Skyrim.esm')))
        Yes 'and the Steam copy keeps its own bytes' ((ReadOf (Join-Path $steamCopy 'Data\Skyrim.esm')) -eq 'STEAM MASTER')
        Yes 'a linked name with [ ] in it is gone too' (-not (Test-Path -LiteralPath $lb))
        Yes 'and its Steam name keeps its bytes' ((ReadOf (Join-Path $steamCopy 'Data\Shared [x].bsa')) -eq 'STEAM BRACKET')
        Yes 'a plain file the payload replaces is gone' (-not (Test-Path -LiteralPath (Join-Path $made 'Data\Plain.esp')))
        Yes 'a read-only file the payload replaces is gone' (-not (Test-Path -LiteralPath (Join-Path $made 'Data\Locked.esp')))
        Yes 'a file the payload does not carry is left alone' ((ReadOf (Join-Path $made 'Data\Keep.esp')) -eq 'NOT IN PAYLOAD')
        Yes 'the payload itself is untouched' (@(Get-ChildItem -LiteralPath (Join-Path $payload 'Data') -File).Count -eq 5)
        Yes 'it says two linked files were separated' (@($script:said | Where-Object { $_ -match '\b2 linked file' }).Count -eq 1)
        $script:said = @()
        Remove-SharedNames $payload (Join-Path $root 'EmptyDest')
        Yes 'into a folder with none of the names, nothing is said and nothing fails' ($script:said.Count -eq 0)
    }
}
finally {
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -EA SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
    Remove-Item -LiteralPath $root -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
exit 0
