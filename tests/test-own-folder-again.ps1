<#
  test-own-folder-again.ps1

      pwsh -NoProfile -File .\tests\test-own-folder-again.ps1

  A second run of Setup-Thornswood.ps1 over a folder the launcher already
  made. That folder is Root\Game with Profile\OwnGame\files.txt beside it.
  The setup updates Thornswood's own files in it. It does not park the
  folder as Game-old-<date>, and it does not write through a hard link.
  Issue #1233.

  A Game folder with no such record is still the pre-collection leftover
  and is still parked.

  The real Setup-Thornswood.ps1 runs in Windows PowerShell on a pretend
  Steam copy in a temp folder. Get-Process is answered empty, so no real
  Skyrim is closed. The live install folder is never the root.
#>
[CmdletBinding()]
param([string]$Repo, [string]$Scratch)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Repo) { $Repo = Split-Path -Parent $Here }
if (-not $Scratch) { $Scratch = [IO.Path]::GetTempPath() }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { exit 1 }
    exit 0
}

$SetupScript = Join-Path $Repo 'installer\Setup-Thornswood.ps1'
. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $OnWindows) { Write-Host 'NOT RUN  Setup-Thornswood.ps1 runs only on Windows, in Windows PowerShell, over hard links into the game folder'; exit 0 }
$winps = Get-WindowsPowerShell
Yes 'installer\Setup-Thornswood.ps1 is there' (Test-Path -LiteralPath $SetupScript)
if ($script:fail) { Done }

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class TsLinkProbe {
    [StructLayout(LayoutKind.Sequential)]
    struct Info {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle h, out Info info);
    static bool Read(string path, out Info info) {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
            return GetFileInformationByHandle(fs.SafeFileHandle, out info);
        }
    }
    public static int Count(string path) {
        Info info;
        if (!Read(path, out info)) return 1;
        return (int)info.NumberOfLinks;
    }
    public static bool Same(string a, string b) {
        Info ia, ib;
        if (!Read(a, out ia) || !Read(b, out ib)) return false;
        return ia.VolumeSerialNumber == ib.VolumeSerialNumber
            && ia.FileIndexHigh == ib.FileIndexHigh
            && ia.FileIndexLow == ib.FileIndexLow;
    }
}
"@

function Put([string]$path, [string]$text) {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
function ReadText([string]$path) { return [IO.File]::ReadAllText($path) }
function Snap([string]$dir) {
    $d = @{}
    $pfx = $dir.TrimEnd('\') + '\'
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
        $d[$f.FullName.Substring($pfx.Length)] = [IO.File]::ReadAllText($f.FullName)
    }
    return $d
}
function SameSnap($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k) -or $b[$k] -ne $a[$k]) { return $false } }
    return $true
}

$T = Join-Path $Scratch ('own-folder-again-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $T
$runner = Join-Path $T 'run-setup.ps1'
$runnerLines = @(
    'param([string]$Setup, [string]$Root, [string]$Game, [string]$Local, [switch]$Own)'
    'function Get-Process { param([string]$Name, $ErrorAction) }'
    '$env:LOCALAPPDATA = $Local'
    '$a = @{ Root = $Root; SteamGamePath = $Game; NonInteractive = $true; NoOpen = $true }'
    'if ($Own) { $a.MakeOwnGame = $true }'
    '& $Setup @a'
    'exit $LASTEXITCODE'
)
[IO.File]::WriteAllLines($runner, $runnerLines)

function New-Fixture([string]$name, [bool]$made) {
    $dir = Join-Path $T $name
    $steam = Join-Path $dir 'steam\steamapps\common\Skyrim Special Edition'
    Put (Join-Path $steam 'SkyrimSE.exe') 'PIN-EXE'
    Put (Join-Path $steam 'Data\Skyrim - Textures0.bsa') 'ARCHIVE-BYTES'
    Put (Join-Path $steam 'Data\Thornswood-Content.esp') 'OLD-ESP'
    Put (Join-Path $steam 'Data\meshes\vortex\armor.nif') 'ARMOR'
    $root = Join-Path $dir 'Thornswood'
    $game = Join-Path $root 'Game'
    Put (Join-Path $game 'SkyrimSE.exe') 'OWN-EXE'
    Put (Join-Path $game 'kept.txt') 'KEPT'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $game 'Data\Skyrim - Textures0.bsa'))
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $game 'Data\meshes\vortex\armor.nif'))
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $game 'Data\Thornswood-Content.esp'))
    $null = New-Item -ItemType HardLink -Path (Join-Path $game 'Data\Skyrim - Textures0.bsa') -Target (Join-Path $steam 'Data\Skyrim - Textures0.bsa')
    $null = New-Item -ItemType HardLink -Path (Join-Path $game 'Data\meshes\vortex\armor.nif') -Target (Join-Path $steam 'Data\meshes\vortex\armor.nif')
    $null = New-Item -ItemType HardLink -Path (Join-Path $game 'Data\Thornswood-Content.esp') -Target (Join-Path $steam 'Data\Thornswood-Content.esp')
    Put (Join-Path $game 'Data\Platform\Plugins\thornswood-front.js') 'OLD-FRONT'
    if ($made) {
        Put (Join-Path $root 'Profile\OwnGame\files.txt') ("L|O|13|0|Data\Skyrim - Textures0.bsa`r`n" +
            "L|T|7|0|Data\Thornswood-Content.esp`r`n" +
            "C|T|9|0|Data\Platform\Plugins\thornswood-front.js`r`n" +
            "L|V|5|0|Data\meshes\vortex\armor.nif`r`n")
    }
    Put (Join-Path $root 'Profile\accepted.json') '{ "accepted": "2026-09-29T00:00:00Z" }'
    $setup = Join-Path $dir 'setup'
    $null = New-Item -ItemType Directory -Force -Path $setup
    Copy-Item -LiteralPath $SetupScript -Destination (Join-Path $setup 'Setup-Thornswood.ps1')
    Put (Join-Path $setup 'collection.txt') 'This build leaves out everything the Nexus collection provides.'
    $pay = Join-Path $setup 'payload'
    Put (Join-Path $pay 'Data\Thornswood-Content.esp') 'NEW-ESP'
    Put (Join-Path $pay 'Data\Platform\Plugins\thornswood-front.js') 'NEW-FRONT'
    Put (Join-Path $pay 'Data\Platform\UI\index.html') 'NEW-INDEX'
    Put (Join-Path $pay 'Data\SKSE\Plugins\MpClientPlugin.dll') 'MP'
    $local = Join-Path $dir 'windows\LocalAppData'
    Put (Join-Path $local 'Skyrim Special Edition\plugins.txt') "*TsOne.esp`r`n"
    return [pscustomobject]@{ Dir = $dir; Steam = $steam; Root = $root; Game = $game; Setup = (Join-Path $setup 'Setup-Thornswood.ps1'); Local = $local }
}

function Invoke-Setup($fx, [bool]$own) {
    $before = Snap $fx.Steam
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-Setup', $fx.Setup, '-Root', $fx.Root, '-Game', $fx.Steam, '-Local', $fx.Local)
    if ($own) { $args2 += '-Own' }
    $out = @(& $winps @args2 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Out = $out; Before = $before; After = (Snap $fx.Steam) }
}

$made = New-Fixture 'made' $true
Yes 'the content plugin starts as one file with the Steam copy' ([TsLinkProbe]::Same((Join-Path $made.Game 'Data\Thornswood-Content.esp'), (Join-Path $made.Steam 'Data\Thornswood-Content.esp')))
# Same size and the same timestamp is the case robocopy leaves alone. The
# repair still has to put the payload's bytes down.
$frontThere = Join-Path $made.Game 'Data\Platform\Plugins\thornswood-front.js'
$frontPay = Join-Path (Split-Path -Parent $made.Setup) 'payload\Data\Platform\Plugins\thornswood-front.js'
(Get-Item -LiteralPath $frontThere).LastWriteTimeUtc = (Get-Item -LiteralPath $frontPay).LastWriteTimeUtc
$r = Invoke-Setup $made $false
$misses = @($r.Out | Where-Object { $_ -match '\[MISS\]' })
$onlyLauncher = ($misses.Count -eq 1 -and $misses[0] -match 'Launcher')
Yes 'made folder: the only miss is the launcher this pretend payload leaves out' $onlyLauncher
$parked = @(Get-ChildItem -LiteralPath $made.Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Game-old-*' })
Yes 'made folder: it was not parked' ($parked.Count -eq 0 -and (Test-Path -LiteralPath $made.Game))
Yes 'made folder: the run said the folder was already here' (@($r.Out | Where-Object { $_ -match 'already here' }).Count -ge 1)
Yes 'made folder: a linked name was separated before the copy' (@($r.Out | Where-Object { $_ -match 'linked file\(s\) separated' }).Count -ge 1)
$esp = Join-Path $made.Game 'Data\Thornswood-Content.esp'
$front = Join-Path $made.Game 'Data\Platform\Plugins\thornswood-front.js'
$index = Join-Path $made.Game 'Data\Platform\UI\index.html'
Yes 'made folder: Thornswood''s plugin in the folder is the new bytes' ((Test-Path -LiteralPath $esp) -and (ReadText $esp) -eq 'NEW-ESP')
Yes 'made folder: that plugin is no longer a hard link' ([TsLinkProbe]::Count($esp) -eq 1)
Yes 'made folder: the Steam copy of that plugin is still the old bytes' ((ReadText (Join-Path $made.Steam 'Data\Thornswood-Content.esp')) -eq 'OLD-ESP')
Yes 'made folder: the folder and the Steam copy are no longer the same file' (-not [TsLinkProbe]::Same($esp, (Join-Path $made.Steam 'Data\Thornswood-Content.esp')))
Yes 'made folder: an own file that was already a copy is updated' ((ReadText $front) -eq 'NEW-FRONT')
Yes 'made folder: a new own file is written into the folder' ((ReadText $index) -eq 'NEW-INDEX')
Yes 'made folder: the archive hard link still reaches the Steam copy' ([TsLinkProbe]::Same((Join-Path $made.Game 'Data\Skyrim - Textures0.bsa'), (Join-Path $made.Steam 'Data\Skyrim - Textures0.bsa')))
Yes 'made folder: a collection file that was not in the payload is still linked' ([TsLinkProbe]::Same((Join-Path $made.Game 'Data\meshes\vortex\armor.nif'), (Join-Path $made.Steam 'Data\meshes\vortex\armor.nif')) -and (ReadText (Join-Path $made.Steam 'Data\meshes\vortex\armor.nif')) -eq 'ARMOR')
Yes 'made folder: the Steam copy is otherwise untouched' (SameSnap $r.Before $r.After)
Yes 'made folder: the payload was not diverted to Profile\Payload' (-not (Test-Path -LiteralPath (Join-Path $made.Root 'Profile\Payload')))
Yes 'made folder: nothing was recorded as written into the Steam copy' (-not (Test-Path -LiteralPath (Join-Path $made.Root 'Profile\installed-into-game.txt')))
Yes 'made folder: the record that made it is still there' (Test-Path -LiteralPath (Join-Path $made.Root 'Profile\OwnGame\files.txt'))
Yes 'made folder: a file that was already in the folder and not in the payload stays' ((ReadText (Join-Path $made.Game 'kept.txt')) -eq 'KEPT')

$old = New-Fixture 'old' $false
$r2 = Invoke-Setup $old $true
$misses2 = @($r2.Out | Where-Object { $_ -match '\[MISS\]' })
Yes 'no record: the only miss is the launcher' ($misses2.Count -eq 1 -and $misses2[0] -match 'Launcher')
$parked2 = @(Get-ChildItem -LiteralPath $old.Root -Directory | Where-Object { $_.Name -like 'Game-old-*' })
Yes 'no record: the Game folder was parked' ($parked2.Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $old.Root 'Game')))
Yes 'no record: the parked folder still has what was in it' ((ReadText (Join-Path $parked2[0].FullName 'kept.txt')) -eq 'KEPT')
Yes 'no record: the run said it was an old Game folder' (@($r2.Out | Where-Object { $_ -match 'old Game folder' }).Count -ge 1)
$payEsp = Join-Path $old.Root 'Profile\Payload\Data\Thornswood-Content.esp'
Yes 'no record: with the own folder chosen, the payload went to Profile\Payload' ((Test-Path -LiteralPath $payEsp) -and (ReadText $payEsp) -eq 'NEW-ESP')
Yes 'no record: the Steam copy was not written' (SameSnap $r2.Before $r2.After)
Yes 'no record: the parked plugin is still the old bytes, linked to Steam' ([TsLinkProbe]::Same((Join-Path $parked2[0].FullName 'Data\Thornswood-Content.esp'), (Join-Path $old.Steam 'Data\Thornswood-Content.esp')) -and (ReadText (Join-Path $old.Steam 'Data\Thornswood-Content.esp')) -eq 'OLD-ESP')

Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
Done
