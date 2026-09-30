<#
.SYNOPSIS
  Builds Thornswood's animation and body files (Nemesis behavior files and
  BodySlide body meshes) in Thornswood's own game folder, and records them as
  Thornswood's, so the next Ship carries them. Never writes into the Steam copy.

.DESCRIPTION
  Issue #1247. Patrick, 29 Sep: "make it in Thornswood's own folder, as a
  scripted step on the shipping PC before a Ship. Steam's copy stays the
  person's own."

  WHY. Every release carries Nemesis behavior files (the animation graphs for
  the mod list) and body meshes BodySlide builds. Until #1232 both were run
  into the Steam copy of Skyrim and Thornswood's folder took the output from
  there. Since then Thornswood's folder takes only Skyrim's own files, Vortex's
  and Thornswood's, so anything run into the Steam copy stops there, and the
  Steam copy is the person's own Skyrim to mod as they like.

  WHAT IT DOES, in <Root>\Game (C:\Thornswood\Game, or the dev build's
  C:\Thornswood-DevBuild\Game with -Channel dev):
    1. Refuses while Skyrim, the launcher or anything else run from <Root> is
       open, when the folder is not one the launcher made, and when it could
       be the Steam copy or any folder Vortex deploys into.
    2. Checks records\generated.json: the Nemesis patches are installed, and
       every BodySlide set it names keeps to the body rules. Each set is
       built at its own slider defaults, written out as a preset that names
       every slider, and nothing that shapes the breasts, the seat, the
       genitals or the nipples may do anything (issue #1004), no zap may take
       the underwear off (issue #405), and no RaceMenu morph file is built
       (BodySlide is never given --trimorphs).
    3. Gives the folder its own copy of every file the tools write in place
       (Nemesis' own folder, the behavior files, the character files,
       FNIS.pex, BodySlide's settings). The folder holds most of the collection
       as hard links to Vortex's copies, and a file written through a link is
       written in Vortex's copy and the Steam copy too.
    4. Nemesis: points it at this folder's Data (nemesis.ini) and clears its
       cache of paths, which named the Steam copy's, runs -update, refuses if
       the paths it cached are anywhere but this folder, then runs -generate
       with the patches.
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
  main or dev: which install's folder to build in, the same way Ship.ps1
  finds it. dev is the main install's folder with -DevBuild on the end.
  Required unless -Root is given, so the folder is always chosen.

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
function Find-Root {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}
if (-not $Root) {
    if (-not $Channel) { Die 'Say which folder: -Channel dev (C:\Thornswood-DevBuild) or -Channel main (C:\Thornswood).' }
    $Root = Find-Root
    if ($Channel -eq 'dev') { $Root = $Root + '-DevBuild' }
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

# What is new or changed between two snapshots.
function Get-Changed($before, $after) {
    $l = New-Object 'System.Collections.Generic.List[string]'
    foreach ($kv in $after.GetEnumerator()) {
        $was = $null
        if (-not $before.TryGetValue($kv.Key, [ref]$was) -or $was -ne $kv.Value) { $l.Add($kv.Key) }
    }
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
# the tools themselves. A game or launcher whose path cannot be read counts as
# in use, because which folder it has open cannot be told.
function Get-FolderUsers([string]$root) {
    $prefix = $root.TrimEnd('\') + '\'
    $users = @()
    foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
        $exe = [string]$p.ExecutablePath
        if ($exe) {
            if ($exe.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $users += ($p.Name + ' (' + $p.ProcessId + ', ' + $exe + ')') }
        } elseif ($p.Name -match '^(SkyrimSE|skse64_loader|Thornswood|Thornswood Dev)\.exe$') {
            $users += ($p.Name + ' (' + $p.ProcessId + ', whose folder Windows does not say)')
        }
    }
    return , $users
}
function Assert-NotInUse {
    $users = Get-FolderUsers $Root
    if ($users.Count) {
        foreach ($u in $users) { Say "  in use by $u" 'Red' }
        Die ("Thornswood's folder at $Root is in use. Close Skyrim and the Thornswood launcher (and any Nemesis or BodySlide started from it), then run this again. " +
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

$nemDir = Join-Path $Data 'Nemesis_Engine'
$nemExe = Join-Path $nemDir 'Nemesis Unlimited Behavior Engine.exe'
$bsDir = Join-Path $Data 'CalienteTools\BodySlide'
$bsExe = Join-Path $bsDir 'BodySlide.exe'

if ($list.Patches.Count) {
    if (-not (Test-Path -LiteralPath $nemExe)) {
        Die "Nemesis is not in this folder ($nemExe). It comes with the collection: deploy it in Vortex and bring the folder up to date in the launcher (Settings, Maintenance)."
    }
    foreach ($p in $list.Patches) {
        if (-not (Test-Path -LiteralPath (Join-Path $nemDir "mod\$p"))) {
            Die "The Nemesis patch '$p' that records\generated.json names is not installed (no $nemDir\mod\$p). Is the mod that carries it deployed?"
        }
    }
    Say ("  Nemesis, with the patches " + ($list.Patches -join ', ')) 'Green'
}

$sets = @()
if ($list.Sets.Count) {
    if (-not (Test-Path -LiteralPath $bsExe)) {
        Die "BodySlide is not in this folder ($bsExe). It comes with the collection: deploy it in Vortex and bring the folder up to date in the launcher."
    }
    $bad = @()
    foreach ($name in $list.Sets) {
        try { $set = Get-BodySlideSet (Join-Path $bsDir 'SliderSets') $name } catch { Die $_.Exception.Message }
        $moves = $null
        if ($list.Sliders.ContainsKey($name)) { $moves = $list.Sliders[$name] }
        $values = Get-BodySlideValues $set $moves
        $bad += (Test-BodySlideRules $set $values $moves)
        $sets += [pscustomobject]@{ Set = $set; Values = $values }
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
Say ("  built from {0:n0} of Vortex's files for Nemesis and {1:n0} for BodySlide, and the mod list" -f $inputs.NemesisFiles, $inputs.BodySlideFiles) 'DarkGray'

$quote = { param($a) if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
$groupOf = { param($i) 'Thornswood ' + ($i + 1) }
if ($DryRun) {
    Head 'Would run'
    if ($list.Patches.Count) {
        Say ("  " + (& $quote $nemExe) + ' -update') 'White'
        Say ("  " + (& $quote $nemExe) + ' -generate ' + ($list.Patches -join ' ')) 'White'
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

function Invoke-Tool([string]$exe, [string[]]$arguments, [string]$who) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = (@($arguments | ForEach-Object { & $quote $_ }) -join ' ')
    $psi.WorkingDirectory = Split-Path -Parent $exe
    $psi.UseShellExecute = $false
    Say ("  " + $who + ': ' + (Split-Path -Leaf $exe) + ' ' + $psi.Arguments) 'DarkGray'
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($Minutes * 60 * 1000)) {
        $p.Kill()
        $p.WaitForExit()
        Die "$who was still running after $Minutes minutes, so it was stopped and nothing was recorded. Run it by hand from $(Split-Path -Parent $exe) to see what it is waiting on."
    }
    if ($p.ExitCode -ne 0) { Die "$who stopped with exit code $($p.ExitCode). Nothing was recorded. Its own log is in $(Split-Path -Parent $exe)." }
}

# ------------------------------------------------------------ its own copies
Head 'This folder''s own copies'
$listed = Get-Snap
$split = 0
$toSplit = New-Object 'System.Collections.Generic.List[string]'
foreach ($rel in $listed.Keys) {
    if ($list.Patches.Count) {
        if ($rel.StartsWith('Data\Nemesis_Engine\', [StringComparison]::OrdinalIgnoreCase)) { $toSplit.Add($rel); continue }
        if ($rel -match '(?i)^Data\\meshes\\.*\\behaviors\\[^\\]+\.hkx$' -or
            $rel -match '(?i)^Data\\meshes\\.*\\characters( female)?\\[^\\]+\.hkx$' -or
            $rel -match '(?i)^Data\\meshes\\actors\\[^\\]+\\[^\\]+\.hkx$' -or
            $rel -match '(?i)^Data\\meshes\\([^\\]+\\)*animation(set)?datasinglefile\.txt$' -or
            $rel -match '(?i)^Data\\scripts\\(fnis|fnbe|nemesis)[^\\]*\.pex$') { $toSplit.Add($rel); continue }
    }
    if ($sets.Count -and $rel -match '(?i)^Data\\CalienteTools\\BodySlide\\([^\\]+|SliderPresets\\[^\\]+|SliderGroups\\[^\\]+)$') { $toSplit.Add($rel) }
}
foreach ($rel in $toSplit) { if (Split-Link (Join-Path $Game $rel)) { $split++ } }
Say ("  {0:n0} file(s) the tools write in place were shared with another folder and are this folder's own copies now; {1:n0} already were" -f $split, ($toSplit.Count - $split)) 'Green'

# ------------------------------------------------------------ Nemesis
$outputs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
if ($list.Patches.Count) {
    Head 'Nemesis'
    # Its data folder is this one, by name. Left at auto it looks for the
    # game by its own path and then by the registry, which names the Steam copy.
    $ini = Join-Path $nemDir 'nemesis.ini'
    $iniLines = New-Object 'System.Collections.Generic.List[string]'
    $iniLines.Add('SkyrimDataDirectory=' + $Data + '\')
    if (Test-Path -LiteralPath $ini) {
        foreach ($line in [IO.File]::ReadAllLines($ini)) { if ($line -notmatch '^\s*SkyrimDataDirectory\s*=') { $iniLines.Add($line) } }
    }
    [IO.File]::WriteAllLines($ini, $iniLines.ToArray())
    # Its cache names every behavior file by its full path, and the one it
    # came with names the Steam copy's. -update writes it again for this folder.
    foreach ($c in 'behavior_path', 'engine_update') {
        $cp = Join-Path $nemDir "cache\$c"
        if (Test-Path -LiteralPath $cp) { [IO.File]::Delete($cp) }
    }
    $before = Get-Snap
    Invoke-Tool $nemExe @('-update') 'Nemesis (-update)'
    Assert-NoWriteThrough (Get-Changed $before (Get-Snap)) 'Nemesis -update'
    $bp = Join-Path $nemDir 'cache\behavior_path'
    if (-not (Test-Path -LiteralPath $bp)) { Die "Nemesis -update did not write $bp, so where it would write the behavior files cannot be checked. Nothing was generated." }
    $targets = @()
    foreach ($c in 'behavior_path', 'engine_update') {
        $cp = Join-Path $nemDir "cache\$c"
        if (-not (Test-Path -LiteralPath $cp)) { continue }
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($cp), '(?i)[a-z]:\\[^\r\n=>|"]+')) {
            $abs = $m.Value.Trim()
            if (-not $abs.StartsWith($Data + '\', [StringComparison]::OrdinalIgnoreCase)) {
                Die ("Nemesis would write to $abs, which is not in $Data (cache\$c). It was not run. Check SkyrimDataDirectory in $ini.")
            }
            if ($c -eq 'behavior_path') { $targets += ($abs + '.hkx') }
        }
    }
    foreach ($t in $targets) { if ((Test-Path -LiteralPath $t) -and (Split-Link $t)) { $split++ } }
    Say ("  it writes {0} behavior file(s), all in this folder" -f $targets.Count) 'Green'

    $before = Get-Snap
    Invoke-Tool $nemExe (@('-generate') + $list.Patches) 'Nemesis (-generate)'
    $changed = Get-Changed $before (Get-Snap)
    Assert-NoWriteThrough $changed 'Nemesis'
    $nemMade = @($changed | Where-Object { -not (Test-InTool $_) })
    if (-not $nemMade.Count) { Die 'Nemesis finished and changed no file outside its own folder, so it built nothing. Nothing was recorded. Its log is PatchLog.txt beside it.' }
    foreach ($r in $nemMade) { [void]$outputs.Add($r) }
    Say ("  made {0} file(s)" -f $nemMade.Count) 'Green'
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

    # The bodies it built, read before any is put in place.
    $global:LASTEXITCODE = 0
    & (Join-Path $Here 'Check-CoveredBodies.ps1') -Game $stageRoot
    if ($LASTEXITCODE -ne 0) {
        Die ('A body BodySlide built is not covered, or cannot be read (see above). Nothing was put in the folder (issue #405).')
    }

    foreach ($f in $built) {
        $rel = 'Data\' + $f.FullName.Substring($stageData.Length + 1)
        $dest = Join-Path $Game $rel
        # A new file of this folder's own. Deleting the name first drops only
        # this folder's link; Vortex's copy and the Steam copy keep theirs.
        if (Test-Path -LiteralPath $dest) { [IO.File]::Delete($dest) }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        [IO.File]::Copy($f.FullName, $dest)
        [void]$outputs.Add($rel)
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
