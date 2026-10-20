<#
.SYNOPSIS
  Builds Thornswood's animation and body files (the behavior files, with
  Pandora Behaviour Engine+, and BodySlide's body meshes) in Thornswood's own
  game folder, and records them as Thornswood's, so the next Ship carries them.
  Never writes into the Steam copy.

.DESCRIPTION
  Issue #1247. Patrick, 29 Sep: "make it in Thornswood's own folder, as a
  scripted step on the shipping PC before a Ship. Steam's copy stays the
  person's own."

  WHY. Every release carries behavior files (the animation graphs for the mod
  list) and body meshes BodySlide builds. Until #1232 both were run into the
  Steam copy of Skyrim and Thornswood's folder took the output from there.
  Since then Thornswood's folder takes only Skyrim's own files, Vortex's and
  Thornswood's, so anything run into the Steam copy stops there, and the Steam
  copy is the person's own Skyrim to mod as they like.

  WHY PANDORA AND NOT NEMESIS. Measured 29 Sep on the shipping machine:
  Nemesis -generate sat for seven minutes on 0.09 s of processor time, with no
  window and no file written. In its own source, v0.84 and since, -generate
  connects its worker to a slot named GenerateBehavior(), which does not
  exist (the slot is InitializeGeneration()), so no Nemesis release can
  generate from a command line. Pandora Behaviour Engine+ reads the same
  patches, runs from a command line (--auto_run --auto_close), and was
  compared with Nemesis' output for the current dev release the same day: the
  same 20 behavior and character files with the same names in them. The
  collection carries Pandora from revision 2 (docs\COLLECTION-REVISION-2.md).

  WHAT IT DOES, in <Root>\Game (C:\Thornswood\Game, or the dev build's
  C:\Thornswood-DevBuild\Game with -Channel dev):
    1. Refuses while Skyrim, the launcher or anything else run from <Root> is
       open, when the folder is not one the launcher made, and when it could
       be the Steam copy or any folder Vortex deploys into.
    2. Checks records\generated.json: Pandora and the patches are in this
       folder, and every BodySlide set it names keeps to the body rules. Each
       set is built at its own slider defaults, written out as a preset that
       names every slider, and nothing that shapes the breasts, the seat, the
       genitals or the nipples may do anything (issue #1004), no zap may take
       the underwear off (issue #405), and no RaceMenu morph file is built
       (BodySlide is never given --trimorphs).
    3. Gives the folder its own copy of every file BodySlide writes in place
       (its settings, its presets and groups). The folder holds most of the
       collection as hard links to Vortex's copies, and a file written
       through a link is written in Vortex's copy and the Steam copy too.
    4. Pandora: runs a copy of it in the work folder, never the one in the
       game folder: its own folder, or, where Vortex deployed it loose into
       Data, the files Vortex's record lists for its mod. Its Settings.json names this folder's Data and a work
       output folder and nothing else: Pandora reads its folders from there,
       not from -o (v4.4.0 parses -o and never uses it), and without it falls
       back to the registry's Skyrim, the Steam copy. Its ActiveMods.json turns
       on exactly the patches the list names and every other patch off. It
       refuses if Pandora changed anything in the game folder, if its log has
       an error or names other patches, then puts each file it made in place
       as a new file of this folder's own, in the letter case the folder
       already uses.
    5. BodySlide: sets it to Skyrim Special Edition and this folder's Data,
       builds each set into a folder of its own (--targetdir), reads the
       bodies it built (Check-CoveredBodies.ps1) and refuses a nude one, then
       puts each file in place as a new file of this folder's own.
    6. Refuses, and records nothing, if any file the tools changed is shared
       with another folder (written through a link), or if BodySlide wrote
       anywhere but where it was told.
    7. Files the last build made that this one did not are put back: Vortex's
       own copy where Vortex deploys that path, otherwise taken out.
    8. Writes Profile\OwnGame\generated.txt: each file it made, with its
       sha256, and what it was built from (Generated.ps1). The launcher keeps
       those files as Thornswood's (OwnGameKinds.cs), and Ship-Rules.ps1 lets
       a release carry them.

  Ship and Check-ShipReady stop when the record is missing or stale: the mod
  list, the files the tools read, records\generated.json or a built file
  changed since.

  Exit 0 when built and recorded (or a dry run found nothing in the way),
  1 when it stopped, 3 when the folder is in use.

.PARAMETER Channel
  main or dev: which install's folder to build in, the one Ship.ps1 builds
  that channel's release from: Where.ps1 ShipRoot or ShipRootDev (#1692),
  the folder Setup-ShipMachine.ps1 -Root recorded, or else the launcher
  install, and for dev that with -DevBuild on the end. Required unless -Root
  is given, so the folder is always chosen.

.PARAMETER Root
  The Thornswood install to build in (the folder with Game, Launcher and
  Profile in it), in place of the one -Channel finds.

.PARAMETER BuildList
  What to build. records\generated.json in this repository by default.

.PARAMETER DryRun
  Checks everything and says what it would run, and writes nothing: no copy,
  no setting, no tool started, no record.

.PARAMETER Minutes
  How long each tool may run before it is stopped and the build refused.
  30 by default.

.PARAMETER StallSeconds
  How long a tool may sit using almost no processor time (under a second of
  it) while no file changes in the game folder or the work folder, before it
  is taken as waiting on something nobody can answer, stopped, and the build
  refused. 180 by default.

.PARAMETER NoPause
  Exits without waiting for Enter.

.EXAMPLE
  .\scripts\mods\Build-Generated.ps1 -Channel dev
  Builds them in C:\Thornswood-DevBuild\Game, before a dev Ship.

.EXAMPLE
  .\scripts\mods\Build-Generated.ps1 -Channel main -DryRun
  Says what it would do in C:\Thornswood\Game, and changes nothing.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel,
    [string]$Root,
    [string]$BuildList,
    [switch]$DryRun,
    [int]$Minutes = 30,
    [int]$StallSeconds = 180,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)
. (Join-Path $Here 'Generated.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Leave([int]$code) { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit $code }
function Die([string]$m, [int]$code = 1) {
    Write-Host ''
    Write-Host "STOP. $m" -ForegroundColor Red
    if ($script:WorkDir -and (Test-Path -LiteralPath $script:WorkDir)) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force }
    Leave $code
}
$script:WorkDir = ''

# ------------------------------------------------------------ which folder
# The one Ship builds the channel's release from, which Where.ps1 answers for
# Ship, Check-ShipReady, Setup-ShipMachine and this alike (#1692).
if (-not $Root) {
    if (-not $Channel) { Die 'Say which folder: -Channel dev or -Channel main (the folder Ship builds that channel from), or -Root.' }
    try { $Root = [string](& (Join-Path $RepoDir 'scripts\release\Where.ps1') $(if ($Channel -eq 'dev') { 'ShipRootDev' } else { 'ShipRoot' })) }
    catch { Die $_.Exception.Message }
}
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if (-not $Channel) { $Channel = $(if ($Root -match '-DevBuild$') { 'dev' } else { 'main' }) }
if (-not $BuildList) { $BuildList = Join-Path $RepoDir 'records\generated.json' }
$Game = Join-Path $Root 'Game'
$Data = Join-Path $Game 'Data'
$OwnDir = Join-Path $Root 'Profile\OwnGame'

Write-Host ''
Write-Host '  BUILD THORNSWOOD''S ANIMATION AND BODY FILES' -ForegroundColor White
Say ("  in " + $Game + $(if ($DryRun) { '  (dry run: nothing is written)' } else { '' })) 'DarkGray'

# ------------------------------------------------------------ links
if (-not ('Thornswood.GeneratedLinks' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Thornswood
{
    public static class GeneratedLinks
    {
        [StructLayout(LayoutKind.Sequential)]
        struct Info
        {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME C, A, W;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle h, out Info info);
        // How many names the file has: more than one is a hard link shared
        // with another folder (Vortex's copy, the Steam copy).
        public static int Count(string path)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                Info i;
                if (!GetFileInformationByHandle(fs.SafeFileHandle, out i)) throw new IOException("the link count of " + path + " cannot be read");
                return (int)i.Links;
            }
        }
    }

    // Counts every file created, changed, deleted or renamed under the
    // folders it is given, so a tool that writes is known to be working.
    public sealed class GeneratedActivity : IDisposable
    {
        long events;
        readonly System.Collections.Generic.List<FileSystemWatcher> watchers = new System.Collections.Generic.List<FileSystemWatcher>();
        public GeneratedActivity(string[] dirs)
        {
            foreach (string d in dirs)
            {
                if (string.IsNullOrEmpty(d) || !Directory.Exists(d)) continue;
                var w = new FileSystemWatcher(d);
                w.IncludeSubdirectories = true;
                w.InternalBufferSize = 65536;
                w.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size;
                FileSystemEventHandler seen = delegate { System.Threading.Interlocked.Increment(ref events); };
                w.Changed += seen; w.Created += seen; w.Deleted += seen;
                w.Renamed += delegate { System.Threading.Interlocked.Increment(ref events); };
                // Too much at once to list is a great deal of work, not none.
                w.Error += delegate { System.Threading.Interlocked.Increment(ref events); };
                w.EnableRaisingEvents = true;
                watchers.Add(w);
            }
        }
        public long Events { get { return System.Threading.Interlocked.Read(ref events); } }
        public void Dispose() { foreach (var w in watchers) w.Dispose(); }
    }
}
'@
}

# Gives this folder's name for a file a copy of its own, as it is now, so a
# tool writing it in place writes only here. The other names keep their file.
# Returns $true when there was a link to undo.
function Split-Link([string]$path) {
    if ([Thornswood.GeneratedLinks]::Count($path) -le 1) { return $false }
    if (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReadOnly) -ne 0) {
        # Clearing it would change the attribute of every name, the Steam
        # copy's included, so this stops instead.
        Die ("$path is read only and shared with another folder, so this folder cannot be given its own copy without changing the other one. " +
             'Clear read only on it in Vortex''s own copy, deploy, and run this again.')
    }
    $tmp = $path + '.thornswood-own'
    [IO.File]::Copy($path, $tmp, $true)
    [IO.File]::Delete($path)
    [IO.File]::Move($tmp, $path)
    return $true
}

# Every file under Game\Data as "bytes|write time", without following a folder
# link out of the folder.
function Get-Snap {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Data)
    $cut = $Game.Length + 1
    while ($stack.Count) {
        $dir = $stack.Pop()
        foreach ($f in [IO.Directory]::GetFiles($dir)) {
            $fi = New-Object IO.FileInfo $f
            $d[$f.Substring($cut)] = '' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks
        }
        foreach ($sub in [IO.Directory]::GetDirectories($dir)) {
            if (([IO.File]::GetAttributes($sub) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $stack.Push($sub)
        }
    }
    return , $d
}

# What is new, changed or deleted between two snapshots.
function Get-Changed($before, $after) {
    $l = New-Object 'System.Collections.Generic.List[string]'
    foreach ($kv in $after.GetEnumerator()) {
        $was = $null
        if (-not $before.TryGetValue($kv.Key, [ref]$was) -or $was -ne $kv.Value) { $l.Add($kv.Key) }
    }
    foreach ($rel in $before.Keys) { if (-not $after.ContainsKey($rel)) { $l.Add($rel) } }
    return , $l
}

function Test-InTool([string]$rel) {
    foreach ($t in $GeneratedToolDirs) { if ($rel.StartsWith($t, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

# Stops when a file the tools changed is shared with another folder: the
# change is in Vortex's copy or the Steam copy as well.
function Assert-NoWriteThrough($changed, [string]$who) {
    $through = @($changed | Where-Object { (Test-Path -LiteralPath (Join-Path $Game $_)) -and [Thornswood.GeneratedLinks]::Count((Join-Path $Game $_)) -gt 1 })
    if ($through.Count) {
        Die ("$who wrote into " + $through.Count + " file(s) this folder shares with another (" + (($through | Select-Object -First 5) -join ', ') +
             "), so the same change is in Vortex's copy or the Steam copy of it. Nothing was recorded. Put Vortex's copies back (Vortex, Deploy), " +
             "tell staff which files these were, and do not Ship until this script gives this folder its own copy of them first.")
    }
}

# ------------------------------------------------------------ in use
# Anything run from the install: its Skyrim, script extender, launcher, or
# the tools themselves.
#
# A game or launcher whose path cannot be read is another account's process.
# Until 11 Oct every one of those counted as in use, because which folder it
# had open could not be told. On the VPS four build runners are four accounts,
# and the harness starts a stand-in SkyrimSE.exe, so one runner's stand-in
# stopped another runner's build of a folder it never touched (#2233). Which
# folder it has open can be told, from the folder's side: a running program's
# file cannot be opened for writing (Windows answers with a sharing
# violation), whoever runs it. So such a process counts only when one of this
# install's own programs is running.
function Test-ImageRunning([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try {
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        $fs.Dispose()
        return $false
    } catch {
        $e = $_.Exception
        while ($e -and $e -isnot [IO.IOException] -and $e.InnerException) { $e = $e.InnerException }
        # ERROR_SHARING_VIOLATION (32): the image is mapped by a running process.
        return ($e -is [IO.IOException] -and ($e.HResult -band 0xFFFF) -eq 32)
    }
}
function Get-RunningInstallImages([string]$root) {
    $running = @()
    foreach ($dir in @((Join-Path $root 'Game'), (Join-Path $root 'Launcher'))) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File -ErrorAction SilentlyContinue)) {
            if (Test-ImageRunning $f.FullName) { $running += $f.FullName }
        }
    }
    return , $running
}
function Get-FolderUsers([string]$root) {
    $prefix = $root.TrimEnd('\') + '\'
    $users = @()
    $unreadable = @()
    foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
        $exe = [string]$p.ExecutablePath
        if ($exe) {
            if ($exe.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $users += ($p.Name + ' (' + $p.ProcessId + ', ' + $exe + ')') }
        } elseif ($p.Name -match '^(SkyrimSE|skse64_loader|Thornswood|Thornswood Dev)\.exe$') {
            $unreadable += $p
        }
    }
    if ($unreadable.Count) {
        $images = Get-RunningInstallImages $root
        if ($images.Count) {
            foreach ($p in $unreadable) {
                $users += ($p.Name + ' (' + $p.ProcessId + ', another account''s, while ' + (($images | ForEach-Object { Split-Path -Leaf $_ }) -join ', ') + ' from this folder is running)')
            }
        }
    }
    return , $users
}
function Assert-NotInUse {
    $users = Get-FolderUsers $Root
    if ($users.Count) {
        foreach ($u in $users) { Say "  in use by $u" 'Red' }
        Die ("Thornswood's folder at $Root is in use. Close Skyrim and the Thornswood launcher (and any Pandora or BodySlide started from it), then run this again. " +
             'The launcher brings the folder up to date while it runs, and the game holds its files open.') 3
    }
}

# ------------------------------------------------------------ the folder
Head 'The folder'
if (-not (Test-Path -LiteralPath (Join-Path $Game 'SkyrimSE.exe'))) {
    Die "There is no Skyrim in $Game. Open the launcher once; it makes Thornswood's own folder there."
}
if (-not (Test-Path -LiteralPath (Join-Path $OwnDir 'files.txt'))) {
    Die "$Game is not a folder the launcher made (there is no $OwnDir\files.txt), so it cannot be told which files are Vortex's. Open the launcher once to make it."
}
# Never the Steam copy, and never a folder Vortex deploys into: Vortex's record
# in Data is how a folder Vortex manages is known, and the launcher's record
# names the folder it was made from.
if (Test-Path -LiteralPath (Join-Path $Data 'vortex.deployment.json')) {
    Die "$Game has Vortex's own record in it (Data\vortex.deployment.json), so it is a folder Vortex deploys into, not Thornswood's own. Nothing is built there."
}
$madeFrom = @()
$made = Join-Path $OwnDir 'made.txt'
if (Test-Path -LiteralPath $made) {
    foreach ($line in [IO.File]::ReadAllLines($made)) {
        $m = [regex]::Match($line, '^(source|game)=(.+)$')
        if ($m.Success) { $madeFrom += $m.Groups[2].Value.Trim().TrimEnd('\') }
    }
}
foreach ($src in $madeFrom) {
    if ([string]::Equals([IO.Path]::GetFullPath($src).TrimEnd('\'), $Game, [StringComparison]::OrdinalIgnoreCase)) {
        Die "$Game is the folder Thornswood's own folder was made from, the Steam copy. Nothing is built there."
    }
}
Say "  $Game is Thornswood's own folder, made by the launcher" 'Green'
Assert-NotInUse
Say '  nothing has it open' 'Green'

# ------------------------------------------------------------ what to build
Head 'What to build'
try { $list = Get-GeneratedBuildList $BuildList } catch { Die $_.Exception.Message }
Say ("  " + $BuildList) 'DarkGray'

$bsDir = Join-Path $Data 'CalienteTools\BodySlide'
$bsExe = Join-Path $bsDir 'BodySlide.exe'
$patchDirs = @((Join-Path $Data 'Nemesis_Engine\mod'), (Join-Path $Data 'Pandora_Engine\mod'))

# A patch's name as its own record gives it, which is how Pandora's log names
# the patches it ran with: info.ini's name= (Nemesis' format) or info.xml's
# <name> (Pandora's).
function Get-PatchName([string]$code) {
    foreach ($d in $patchDirs) {
        $ini = Join-Path $d "$code\info.ini"
        if (Test-Path -LiteralPath $ini) {
            $m = [regex]::Match([IO.File]::ReadAllText($ini), '(?m)^name=(.+?)\s*$')
            if ($m.Success) { return $m.Groups[1].Value }
        }
        $xml = Join-Path $d "$code\info.xml"
        if (Test-Path -LiteralPath $xml) {
            $m = [regex]::Match([IO.File]::ReadAllText($xml), '<name>\s*(.+?)\s*</name>')
            if ($m.Success) { return $m.Groups[1].Value }
        }
    }
    return $null
}

$pandoraExe = ''
if ($list.Patches.Count) {
    # Pandora as the collection deployed it into this folder, in a folder of
    # its own: it runs from a copy of that folder, so it has to be one.
    $found = @(Get-ChildItem -LiteralPath $Data -Filter 'Pandora Behaviour Engine+.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)
    if (-not $found.Count) {
        Die "Pandora Behaviour Engine+ is not in this folder. It comes with the collection from revision 2 (docs\COLLECTION-REVISION-2.md): install it in Vortex, deploy, and bring the folder up to date in the launcher (Settings, Maintenance)."
    }
    if ($found.Count -gt 1) { Die ("Pandora is in this folder more than once (" + (($found | ForEach-Object { $_.FullName }) -join ', ') + "), so which one runs cannot be told. Keep one in Vortex.") }
    $pandoraExe = $found[0].FullName
    # Its files, to copy into the work folder: its own folder, or, when Vortex
    # deployed it loose into Data (its archive has no folder at the top), the
    # files Vortex's own record lists for the same mod as the exe.
    $pandoraFiles = @()
    if ([string]::Equals((Split-Path -Parent $pandoraExe), $Data, [StringComparison]::OrdinalIgnoreCase)) {
        try { $pandoraFiles = @(Get-GeneratedLoosePandoraFiles $Root) } catch { Die $_.Exception.Message }
    } else {
        $pFolder = Split-Path -Parent $pandoraExe
        $pandoraFiles = @([IO.Directory]::GetFiles($pFolder, '*', 'AllDirectories') | ForEach-Object { $_.Substring($pFolder.Length + 1) })
    }
    $patchNames = @()
    foreach ($p in $list.Patches) {
        $n = Get-PatchName $p
        if (-not $n) {
            Die "The behavior patch '$p' that records\generated.json names is not installed (no $($patchDirs -join ' or ') entry with an info.ini or info.xml). Is the mod that carries it deployed?"
        }
        $patchNames += $n
    }
    Say ("  Pandora, " + $pandoraExe) 'Green'
    Say ("  with the patches " + (@(for ($i = 0; $i -lt $list.Patches.Count; $i++) { $list.Patches[$i] + ' (' + $patchNames[$i] + ')' }) -join ', ') + '; every other patch off') 'Green'
}

$sets = @()
# The bodies first, then the outfits fitted to them (#2454): one group each,
# every one at its defaults and under the same rules.
$wanted = @(@($list.Sets | ForEach-Object { [pscustomobject]@{ Name = $_; Outfit = $false } }) + @($list.Outfits | ForEach-Object { [pscustomobject]@{ Name = $_; Outfit = $true } }))
if ($wanted.Count) {
    if (-not (Test-Path -LiteralPath $bsExe)) {
        Die "BodySlide is not in this folder ($bsExe). It comes with the collection: deploy it in Vortex and bring the folder up to date in the launcher."
    }
    $bad = @()
    foreach ($w in $wanted) {
        $name = $w.Name
        try { $set = Get-BodySlideSet (Join-Path $bsDir 'SliderSets') $name } catch { Die $_.Exception.Message }
        try { $expect = Get-BodySlideSetOutputs $set } catch { Die $_.Exception.Message }
        if ($w.Outfit) {
            $body = @($expect | Where-Object { Test-GeneratedBodyPath $_ })
            if ($body.Count) { Die "The outfit set '$name' writes a body ($($body[0])). Bodies are built from bodyslide.sets only. Nothing was built." }
        }
        $moves = $null
        if ($list.Sliders.ContainsKey($name)) { $moves = $list.Sliders[$name] }
        $values = Get-BodySlideValues $set $moves
        $bad += (Test-BodySlideRules $set $values $moves)
        $sets += [pscustomobject]@{ Set = $set; Values = $values; Outfit = $w.Outfit; Expect = $expect }
        $zaps = @($set.Sliders | Where-Object { $_.Zap } | ForEach-Object { $_.Name })
        Say ("  BodySlide, '{0}' ({1}): shapes {2}; {3} sliders at their defaults{4}" -f $name, (Split-Path -Leaf $set.File), ($set.Shapes -join ', '),
            $set.Sliders.Count, $(if ($zaps.Count) { '; zaps ' + ($zaps -join ', ') + ' as the set has them' } else { '' })) 'Green'
    }
    if ($bad.Count) {
        foreach ($b in $bad) { Say "  $b" 'Red' }
        Die 'A body would be built against the body rules (no shaping of the breasts, the seat, the genitals or the nipples, issue #1004; the underwear stays on, issue #405). Nothing was built. Change records\generated.json.'
    }
    Say '  every body keeps to the rules: nothing shapes the breasts, the seat, the genitals or the nipples, the underwear stays on, and no morph file is built' 'Green'
}

try { $inputs = Get-GeneratedInputs $Root $BuildList } catch { Die $_.Exception.Message }
Say ("  built from {0:n0} of Vortex's files for Pandora and {1:n0} for BodySlide, and the mod list" -f $inputs.BehaviorFiles, $inputs.BodySlideFiles) 'DarkGray'

$quote = { param($a) if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
$groupOf = { param($i) 'Thornswood ' + ($i + 1) }
if ($DryRun) {
    Head 'Would run'
    if ($list.Patches.Count) {
        Say ("  a copy of " + (Split-Path -Parent $pandoraExe) + " in the work folder: " + (& $quote (Split-Path -Leaf $pandoraExe)) +
             ' --tesv ' + (& $quote $Game) + ' -o <a folder of its own> --auto_run --auto_close, with the patches ' + ($list.Patches -join ' ')) 'White'
    }
    for ($i = 0; $i -lt $sets.Count; $i++) {
        Say ("  " + (& $quote $bsExe) + ' --groupbuild ' + (& $quote (& $groupOf $i)) + ' --targetdir <a folder of its own> --preset ' + (& $quote (& $groupOf $i))) 'White'
    }
    $state = Get-GeneratedState $Root $BuildList
    if ($state.Current) { Say '  the files in the folder are already current' 'Green' }
    else { foreach ($w in $state.Why) { Say "  out of date: $w" 'Yellow' } }
    Say '  dry run: nothing was copied, set, started or recorded' 'Yellow'
    Leave 0
}

$script:WorkDir = Join-Path $OwnDir 'build-generated'
if (Test-Path -LiteralPath $script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $script:WorkDir | Out-Null

# Runs a tool and waits for it, watching that it is working: it uses the
# processor, or a file changes in the game folder or the work folder. A tool
# that does neither for -StallSeconds is waiting on something nobody here can
# answer (a window, a prompt, an argument it did not take), and is stopped.
# Measured 29 Sep: Nemesis -generate sat for seven minutes on 0.09 s of
# processor time with no window and no file written.
function Invoke-Tool([string]$exe, [string[]]$arguments, [string]$who) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = (@($arguments | ForEach-Object { & $quote $_ }) -join ' ')
    $psi.WorkingDirectory = Split-Path -Parent $exe
    $psi.UseShellExecute = $false
    # What a tool prints (Pandora prints its whole trace) is drained, not
    # shown: each tool keeps its own log, which is what is checked.
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    Say ("  " + $who + ': ' + (Split-Path -Leaf $exe) + ' ' + $psi.Arguments) 'DarkGray'
    $watch = New-Object Thornswood.GeneratedActivity (, [string[]]@($Game, $script:WorkDir))
    try {
        $p = [Diagnostics.Process]::Start($psi)
        $drain = @($p.StandardOutput.ReadToEndAsync(), $p.StandardError.ReadToEndAsync())
        $deadline = (Get-Date).AddMinutes($Minutes)
        $quietSince = Get-Date
        $cpuThen = [TimeSpan]::Zero
        $eventsThen = [long]0
        while (-not $p.WaitForExit(2000)) {
            $p.Refresh()
            $cpu = $p.TotalProcessorTime
            $events = $watch.Events
            # More than a second of work, or any file, since it last did anything.
            if (($cpu - $cpuThen).TotalMilliseconds -gt 1000 -or $events -ne $eventsThen) {
                $quietSince = Get-Date; $cpuThen = $cpu; $eventsThen = $events
            }
            $quiet = ((Get-Date) - $quietSince).TotalSeconds
            if ($quiet -ge $StallSeconds -or (Get-Date) -gt $deadline) {
                $p.Kill()
                $p.WaitForExit()
                if ($quiet -ge $StallSeconds) {
                    Die ("$who used almost no processor time and changed no file for $StallSeconds seconds, so it was waiting on something nobody here can answer " +
                         "(a window, a prompt, or an argument it did not take). It was stopped and nothing was recorded. Run it by hand from $(Split-Path -Parent $exe) to see what it waits on.")
                }
                Die "$who was still working after $Minutes minutes, so it was stopped and nothing was recorded."
            }
        }
        [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$drain, 10000)
        if ($p.ExitCode -ne 0) { Die "$who stopped with exit code $($p.ExitCode). Nothing was recorded. Its own log is in $(Split-Path -Parent $exe)." }
    } finally { $watch.Dispose() }
}

# The path under the game folder in the letter case the folder already uses,
# so a tool that writes Behaviors\0_Master.hkx puts its file where
# behaviors\0_master.hkx is, under that name, and the release's list keeps
# one name for it.
function Resolve-Rel([string]$rel) {
    $cur = $Game
    $out = @()
    foreach ($seg in $rel.Split('\')) {
        $name = $seg
        if ([IO.Directory]::Exists($cur)) {
            foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($cur)) {
                $leaf = [IO.Path]::GetFileName($e)
                if ([string]::Equals($leaf, $seg, [StringComparison]::OrdinalIgnoreCase)) { $name = $leaf; break }
            }
        }
        $out += $name
        $cur = Join-Path $cur $name
    }
    return ($out -join '\')
}

# Puts a file a tool made in a work folder into the game folder as a new file
# of this folder's own. Deleting the name first drops only this folder's link;
# Vortex's copy and the Steam copy keep theirs. Returns the path it went to.
function Put-Output([string]$from, [string]$rel) {
    $rel = Resolve-Rel $rel
    $dest = Join-Path $Game $rel
    if (Test-Path -LiteralPath $dest) { [IO.File]::Delete($dest) }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    [IO.File]::Copy($from, $dest)
    return $rel
}

# ------------------------------------------------------------ its own copies
# What BodySlide writes in place in its own folder: its settings, and the
# presets and groups. Pandora runs from a copy and writes nothing here.
Head 'This folder''s own copies'
$split = 0
$toSplit = New-Object 'System.Collections.Generic.List[string]'
if ($sets.Count) {
    foreach ($rel in (Get-Snap).Keys) {
        if ($rel -match '(?i)^Data\\CalienteTools\\BodySlide\\([^\\]+|SliderPresets\\[^\\]+|SliderGroups\\[^\\]+)$') { $toSplit.Add($rel) }
    }
}
foreach ($rel in $toSplit) { if (Split-Link (Join-Path $Game $rel)) { $split++ } }
Say ("  {0:n0} file(s) BodySlide writes in place were shared with another folder and are this folder's own copies now; {1:n0} already were" -f $split, ($toSplit.Count - $split)) 'Green'

# ------------------------------------------------------------ Pandora
$outputs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
if ($list.Patches.Count) {
    Head 'Pandora'
    # A copy of Pandora's folder in the work folder, so what it writes beside
    # itself (its settings, its caches) never lands in the game folder.
    $pFrom = Split-Path -Parent $pandoraExe
    $pRun = Join-Path $script:WorkDir 'pandora'
    foreach ($rel in $pandoraFiles) {
        $f = Join-Path $pFrom $rel
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $to = Join-Path $pRun $rel
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
        [IO.File]::Copy($f, $to, $true)
    }
    $pExe = Join-Path $pRun (Split-Path -Leaf $pandoraExe)
    $pOut = Join-Path $script:WorkDir 'pandora-out'
    New-Item -ItemType Directory -Force -Path (Join-Path $pOut 'Pandora_Engine') | Out-Null
    # Its folders, by name: this folder's Data to read and the work output
    # folder to write. It reads them from here and nowhere else; -o is parsed
    # and never used in v4.4.0, and with no game folder here it would take the
    # registry's Skyrim, the Steam copy.
    $settings = [ordered]@{ app = [ordered]@{}; games = [ordered]@{ SkyrimSE = [ordered]@{ gameDataPath = $Data; outputPath = $pOut } } }
    [IO.File]::WriteAllText((Join-Path $pRun 'Settings.json'), (ConvertTo-Json $settings -Depth 5), (New-Object Text.UTF8Encoding($false)))
    # Exactly the patches the list names on, in its order, and every other
    # patch in this folder off. A patch left off this list would keep
    # Pandora's own default, which for an FNIS list is on: those are what
    # Nemesis always read as well.
    $entries = @()
    $prio = 1
    foreach ($p in $list.Patches) { $entries += [ordered]@{ code = $p; active = $true; priority = $prio++ } }
    foreach ($d in $patchDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($sub in [IO.Directory]::GetDirectories($d)) {
            $code = [IO.Path]::GetFileName($sub)
            if ($list.Patches -contains $code) { continue }
            $entries += [ordered]@{ code = $code; active = $false; priority = $prio++ }
        }
    }
    [IO.File]::WriteAllText((Join-Path $pOut 'Pandora_Engine\ActiveMods.json'), (ConvertTo-Json @($entries) -Depth 3), (New-Object Text.UTF8Encoding($false)))

    $before = Get-Snap
    Invoke-Tool $pExe @('--tesv', $Game, '-o', $pOut, '--auto_run', '--auto_close') 'Pandora'
    $changed = Get-Changed $before (Get-Snap)
    if ($changed.Count) {
        Die ("Pandora wrote into the game folder itself (" + (($changed | Select-Object -First 5) -join ', ') + ") and not only into the folder it was given. Nothing was recorded.")
    }
    $crash = @(Get-ChildItem -LiteralPath $pOut -Filter 'Pandora_CriticalCrash*' -File -ErrorAction SilentlyContinue)
    if ($crash.Count) { Die ("Pandora crashed (" + $crash[0].FullName + "). Nothing was recorded.") }
    $engineLog = Join-Path $pOut 'Engine.log'
    if (-not (Test-Path -LiteralPath $engineLog)) { Die "Pandora finished without writing its log ($engineLog), so what it did cannot be checked. Nothing was recorded." }
    $logText = [IO.File]::ReadAllText($engineLog)
    $errors = @([regex]::Matches($logText, '(?m)^(ERROR|FATAL) : .*$') | ForEach-Object { $_.Value.Trim() })
    if ($errors.Count) {
        foreach ($e in ($errors | Select-Object -First 8)) { Say "  $e" 'Red' }
        Die "Pandora's log has errors (above). Nothing was recorded. Run this again after putting right what they name."
    }
    $ran = @([regex]::Matches($logText, '(?m)Pandora Mod \d+ : (.+?) - v') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ -ne 'Pandora Base' } | Sort-Object -Unique)
    $want = @($patchNames | Sort-Object -Unique)
    if (($ran -join '|') -ne ($want -join '|')) {
        Die ("Pandora ran with the patches " + ($ran -join ', ') + ", and records\generated.json names " + ($want -join ', ') + ". Nothing was recorded.")
    }
    $pMade = @(Get-ChildItem -LiteralPath $pOut -Recurse -File | Where-Object {
        $r = $_.FullName.Substring($pOut.Length + 1)
        $r -ne 'Engine.log' -and -not $r.StartsWith('Pandora_Engine\', [StringComparison]::OrdinalIgnoreCase)
    })
    if (-not $pMade.Count) { Die "Pandora finished and made nothing. Nothing was recorded." }
    foreach ($f in $pMade) { [void]$outputs.Add((Put-Output $f.FullName ('Data\' + $f.FullName.Substring($pOut.Length + 1)))) }
    Say ("  made {0} file(s) with {1}, and they are in the folder" -f $pMade.Count, ($want -join ', ')) 'Green'
}

# ------------------------------------------------------------ BodySlide
if ($sets.Count) {
    Head 'BodySlide'
    # Skyrim Special Edition, this folder's Data. Left unset it asks which game
    # on its first start, which a build started from here cannot answer.
    $cfgPath = Join-Path $bsDir 'Config.xml'
    $cfg = New-Object Xml.XmlDocument
    if (Test-Path -LiteralPath $cfgPath) { $cfg.Load($cfgPath) } else { [void]$cfg.AppendChild($cfg.CreateElement('Config')) }
    $cfgRoot = $cfg.DocumentElement
    function Set-Node($parent, [string]$name, [string]$value) {
        $n = $parent.SelectSingleNode($name)
        if (-not $n) { $n = $parent.OwnerDocument.CreateElement($name); [void]$parent.AppendChild($n) }
        $n.InnerText = $value
        return $n
    }
    [void](Set-Node $cfgRoot 'TargetGame' '4')
    [void](Set-Node $cfgRoot 'GameDataPath' ($Data + '\'))
    $paths = $cfgRoot.SelectSingleNode('GameDataPaths')
    if (-not $paths) { $paths = $cfg.CreateElement('GameDataPaths'); [void]$cfgRoot.AppendChild($paths) }
    [void](Set-Node $paths 'SkyrimSpecialEdition' ($Data + '\'))
    $cfg.Save($cfgPath)

    # One group and one preset for each set, named for Thornswood, naming
    # every slider at the value it is built with.
    $groups = New-Object Xml.XmlDocument
    [void]$groups.AppendChild($groups.CreateXmlDeclaration('1.0', 'UTF-8', $null))
    $gRoot = $groups.AppendChild($groups.CreateElement('SliderGroups'))
    $presets = New-Object Xml.XmlDocument
    [void]$presets.AppendChild($presets.CreateXmlDeclaration('1.0', 'UTF-8', $null))
    $pRoot = $presets.AppendChild($presets.CreateElement('SliderPresets'))
    for ($i = 0; $i -lt $sets.Count; $i++) {
        $gname = & $groupOf $i
        $g = $groups.CreateElement('Group'); $g.SetAttribute('name', $gname); [void]$gRoot.AppendChild($g)
        $mem = $groups.CreateElement('Member'); $mem.SetAttribute('name', $sets[$i].Set.Name); [void]$g.AppendChild($mem)
        $p = $presets.CreateElement('Preset'); $p.SetAttribute('name', $gname); $p.SetAttribute('set', $sets[$i].Set.Name); [void]$pRoot.AppendChild($p)
        $pg = $presets.CreateElement('Group'); $pg.SetAttribute('name', $gname); [void]$p.AppendChild($pg)
        foreach ($v in $sets[$i].Values) {
            foreach ($size in 'big', 'small') {
                $ss = $presets.CreateElement('SetSlider')
                $ss.SetAttribute('name', $v.Name); $ss.SetAttribute('size', $size)
                $ss.SetAttribute('value', ([string]$(if ($size -eq 'big') { $v.Big } else { $v.Small })))
                [void]$p.AppendChild($ss)
            }
        }
    }
    $groups.Save((Join-Path $bsDir 'SliderGroups\Thornswood.xml'))
    $presets.Save((Join-Path $bsDir 'SliderPresets\Thornswood.xml'))

    $stageRoot = Join-Path $script:WorkDir 'bodyslide'
    $stageData = Join-Path $stageRoot 'Data'
    New-Item -ItemType Directory -Force -Path $stageData | Out-Null
    $before = Get-Snap
    for ($i = 0; $i -lt $sets.Count; $i++) {
        $gname = & $groupOf $i
        Invoke-Tool $bsExe @('--groupbuild', $gname, '--targetdir', $stageData, '--preset', $gname) ("BodySlide ('" + $sets[$i].Set.Name + "')")
    }
    $after = Get-Snap
    $changed = Get-Changed $before $after
    Assert-NoWriteThrough $changed 'BodySlide'
    $stray = @($changed | Where-Object { -not (Test-InTool $_) })
    if ($stray.Count) {
        Die ("BodySlide wrote into the game folder itself (" + (($stray | Select-Object -First 5) -join ', ') + ") and not only into the folder it was given. Nothing was recorded.")
    }
    $built = @(Get-ChildItem -LiteralPath $stageData -Recurse -File)
    if (-not $built.Count) { Die 'BodySlide finished and built nothing. Nothing was recorded. Its log is Log_BS.txt beside it.' }
    $tri = @($built | Where-Object { $_.Extension -ieq '.tri' })
    if ($tri.Count) { Die ('BodySlide built RaceMenu morph files (' + (($tri | ForEach-Object { $_.Name }) -join ', ') + '), which the body rules do not allow (issue #1004). Nothing was put in the folder.') }
    # Every outfit built exactly the files its set names, and nothing else
    # landed beside them (#2454): what Ship-Rules lists as ours is what was made.
    $builtRel = @($built | ForEach-Object { 'Data\' + $_.FullName.Substring($stageData.Length + 1) })
    $expectAll = @($sets | ForEach-Object { $_.Expect } | ForEach-Object { $_ })
    $missing = @($sets | Where-Object { $_.Outfit } | ForEach-Object { $_.Expect } | ForEach-Object { $_ } | Where-Object { $builtRel -inotcontains $_ })
    if ($missing.Count) { Die ('BodySlide did not build every outfit file its sets name (' + (($missing | Select-Object -First 5) -join ', ') + '). Nothing was put in the folder.') }
    $outfitDirs = @($sets | Where-Object { $_.Outfit } | ForEach-Object { $_.Expect } | ForEach-Object { Split-Path -Parent $_ } | Sort-Object -Unique)
    $extra = @($builtRel | Where-Object { $outfitDirs -icontains (Split-Path -Parent $_) -and $expectAll -inotcontains $_ })
    if ($extra.Count) { Die ('BodySlide built files no set names (' + (($extra | Select-Object -First 5) -join ', ') + '). Nothing was put in the folder.') }

    # The bodies it built, read before any is put in place.
    $global:LASTEXITCODE = 0
    & (Join-Path $Here 'Check-CoveredBodies.ps1') -Game $stageRoot
    if ($LASTEXITCODE -ne 0) {
        Die ('A body BodySlide built is not covered, or cannot be read (see above). Nothing was put in the folder (issue #405).')
    }

    foreach ($f in $built) {
        [void]$outputs.Add((Put-Output $f.FullName ('Data\' + $f.FullName.Substring($stageData.Length + 1))))
    }
    Say ("  built {0} file(s) and put them in the folder" -f $built.Count) 'Green'
}

# ------------------------------------------------------------ what the last one made
$recordPath = Get-GeneratedRecordPath $Root
$old = Read-GeneratedRecord $recordPath
if ($old) {
    $dropped = @($old.Files | Where-Object { -not $outputs.Contains($_.Rel) } | ForEach-Object { $_.Rel })
    if ($dropped.Count) {
        Head 'What the last build made and this one did not'
        # Vortex's own copy where Vortex deploys that path, by its record in
        # the folder it deploys into, which the launcher names in made.txt.
        $staged = @{}
        $src = ''
        foreach ($line in [IO.File]::ReadAllLines($made)) { $m = [regex]::Match($line, '^source=(.+)$'); if ($m.Success) { $src = $m.Groups[1].Value.Trim() } }
        $vm = Join-Path $src 'Data\vortex.deployment.json'
        if ($src -and (Test-Path -LiteralPath $vm)) {
            $vdoc = ([IO.File]::ReadAllText($vm) -replace '^\uFEFF', '') | ConvertFrom-Json
            foreach ($vf in @($vdoc.files)) { $staged['Data\' + ([string]$vf.relPath).TrimStart('\')] = Join-Path (Join-Path ([string]$vdoc.stagingPath) ([string]$vf.source)) ([string]$vf.relPath) }
        }
        foreach ($rel in $dropped) {
            $dest = Join-Path $Game $rel
            if (Test-Path -LiteralPath $dest) { [IO.File]::Delete($dest) }
            if ($staged.ContainsKey($rel) -and (Test-Path -LiteralPath $staged[$rel])) {
                [IO.File]::Copy($staged[$rel], $dest)
                Say "  $rel is Vortex's again" 'DarkGray'
            } else {
                Say "  $rel taken out" 'DarkGray'
            }
        }
    }
}

# ------------------------------------------------------------ the record
Head 'The record'
Assert-NotInUse
$files = @()
foreach ($rel in $outputs) { $files += [pscustomobject]@{ Rel = $rel; Sha = (Get-GeneratedFileSha (Join-Path $Game $rel)) } }
Write-GeneratedRecord $recordPath $Game $inputs $files
Say ("  {0} file(s) recorded as Thornswood's in {1}" -f $files.Count, $recordPath) 'Green'
Remove-Item -LiteralPath $script:WorkDir -Recurse -Force

$state = Get-GeneratedState $Root $BuildList
if (-not $state.Current) { Die ('The record was written and does not read back as current: ' + ($state.Why -join '; ')) }
if ($sets.Count) {
    $global:LASTEXITCODE = 0
    & (Join-Path $Here 'Check-CoveredBodies.ps1') -Game $Game -Quiet
    if ($LASTEXITCODE -eq 2) { Say '  another body in the folder is nude (see above); a main Ship refuses until it is covered (issue #405)' 'Yellow' }
}
Write-Host ''
Say ("  Done. The next Ship from this folder carries them: .\scripts\release\Ship.ps1 -Channel " + $Channel + ' "..."') 'Green'
Leave 0
