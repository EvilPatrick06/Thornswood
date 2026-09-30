<#
  test-build-generated.ps1

      pwsh -NoProfile -File .\tests\test-build-generated.ps1

  scripts\mods\Build-Generated.ps1 builds Thornswood's animation and body
  files in Thornswood's own folder and nowhere else, records them as
  Thornswood's, refuses while the folder is in use, keeps the bodies covered
  and unshaped, and Ship stops when what it built is stale. Issue #1247.

  WHY THIS EXISTS. Patrick, 29 Sep: Nemesis (behavior files) and BodySlide
  (body meshes) output is made in Thornswood's own folder, as a scripted step
  on the shipping PC before a Ship; Steam's copy stays the person's own. Most
  of Thornswood's folder is hard links to Vortex's copies, which the Steam copy
  links too, and both tools write their files in place, so a tool run there
  without care writes into Vortex's copy and the Steam copy as well. And a
  build the launcher or the release does not know is Thornswood's is either
  put back to Vortex's at the next refresh or left out of the release.

  HOW. Stand-ins for the two tools, compiled here with the .NET Framework csc,
  do what the real ones do to a game folder: Nemesis reads its data folder
  from nemesis.ini (auto is the folder above its own), -update writes its cache
  of full paths, -generate writes every behavior file on that cache, FNIS.pex
  and the animation list IN PLACE (opened and truncated, which writes through
  a hard link); BodySlide reads Config.xml, the group, the slider set and the
  preset, builds each body as a nif with the set's shapes less any the preset
  zaps, into --targetdir, and writes its own settings file in place. A pretend
  Vortex staging folder, Steam copy and Thornswood install are built with
  every mod file hard linked into both game folders, the worst case, and
  Build-Generated.ps1 runs against the install as a child process.

    A  a build: the output is in Thornswood's folder, each file its own copy,
       the Steam copy and Vortex's staging byte and time identical; the bodies
       are covered; the preset names every slider at its default and no morph
       file is asked for; the record lists every file made and nothing of the
       tools' own folders; Ship-Rules lets the release carry them
    B  stale: the mod list, a file Nemesis reads, a file BodySlide reads, the
       build list, a built file changed, and no record, each make it stale,
       and Ship and Check-ShipReady stop on it
    C  in use: Skyrim or the launcher run from the install: refused, nothing written
    D  never the Steam copy: a folder with Vortex's record in it, or the one the
       launcher made the folder from: refused, nothing written
    E  the body rules: a breast slider moved, the bra zapped: refused before
       BodySlide runs; a nude slider set: built, read, refused, nothing placed
    F  a write through a link the script did not foresee: refused, not recorded
    G  Nemesis' cache naming a path outside the folder: refused before -generate
    H  BodySlide writing into the game folder itself: refused
    I  what the last build made and this one did not: Vortex's copy put back
    J  a dry run writes nothing

  Writes only under its own scratch folder.
#>
[CmdletBinding()]
param([string]$Scratch)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Scratch) { $Scratch = [IO.Path]::GetTempPath() }
$Build = Join-Path $Repo 'scripts\mods\Build-Generated.ps1'
$Lib = Join-Path $Repo 'scripts\mods\Generated.ps1'
$Ship = Join-Path $Repo 'scripts\release\Ship.ps1'
$Ready = Join-Path $Repo 'scripts\release\Check-ShipReady.ps1'
$pwsh = (Get-Process -Id $PID).Path

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

foreach ($f in $Build, $Lib, (Join-Path $Repo 'scripts\release\Ship-Rules.ps1'), $Ship, $Ready) {
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
    Yes ("$(Split-Path -Leaf $f) parses") (@($e).Count -eq 0)
}

$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework csc is here to build the stand-ins' ([bool]$csc)
if (-not $csc) { Done }

# ------------------------------------------------------------ the stand-ins
$common = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Xml;

static class Standin
{
    // Opens an existing file and truncates it, the way the tools write: the
    // same file under every name it has, so through a hard link too.
    public static void InPlace(string path, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
        {
            byte[] b = Encoding.ASCII.GetBytes(text);
            fs.Write(b, 0, b.Length);
        }
    }
    public static void Log(string what)
    {
        string log = Environment.GetEnvironmentVariable("STANDIN_LOG");
        if (!string.IsNullOrEmpty(log)) File.AppendAllText(log, what + "\r\n");
    }
    public static string Dir() { return AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\'); }
}
'@

$nemesis = $common + @'
static class Nemesis
{
    static int Main(string[] args)
    {
        string dir = Standin.Dir();
        Standin.Log("nemesis " + string.Join(" ", args));
        string data = null;
        string ini = Path.Combine(dir, "nemesis.ini");
        if (File.Exists(ini))
            foreach (string line in File.ReadAllLines(ini))
                if (line.StartsWith("SkyrimDataDirectory=")) data = line.Substring(20);
        if (data == null || data == "auto") data = Path.GetDirectoryName(dir) + "\\";
        string cache = Path.Combine(dir, "cache");
        if (args.Length > 0 && args[0] == "-update")
        {
            var lines = new List<string>();
            lines.Add("0_master=" + data + "meshes\\actors\\character\\behaviors\\0_master");
            lines.Add("_1stperson\\firstperson=" + data + "meshes\\actors\\character\\_1stperson\\behaviors\\firstperson");
            if (Environment.GetEnvironmentVariable("STANDIN_NEMESIS_OUTSIDE") != null)
                lines.Add("mt_behavior=" + Environment.GetEnvironmentVariable("STANDIN_NEMESIS_OUTSIDE"));
            Standin.InPlace(Path.Combine(cache, "behavior_path"), string.Join("\r\n", lines.ToArray()) + "\r\n");
            Standin.InPlace(Path.Combine(cache, "engine_update"), "0.84\r\n" + data + "Nemesis_Engine\\behavior templates\\a.txt>>Fri Mar 27 05:49:39 2020\r\n");
            Standin.InPlace(Path.Combine(cache, "mod settings"), "updated\r\n");
            return 0;
        }
        if (args.Length > 0 && args[0] == "-generate")
        {
            var codes = new List<string>();
            for (int i = 1; i < args.Length; i++) codes.Add(args[i]);
            string said = "NEMESIS " + string.Join(" ", codes.ToArray());
            foreach (string line in File.ReadAllLines(Path.Combine(cache, "behavior_path")))
            {
                int eq = line.IndexOf('=');
                if (eq > 0) Standin.InPlace(line.Substring(eq + 1) + ".hkx", said);
            }
            Standin.InPlace(data + "scripts\\FNIS.pex", "FNIS " + said);
            Standin.InPlace(data + "meshes\\animationdatasinglefile.txt", "ANIMATIONS " + said);
            Standin.InPlace(Path.Combine(dir, "PatchLog.txt"), "done");
            string rogue = Environment.GetEnvironmentVariable("STANDIN_ROGUE");
            if (!string.IsNullOrEmpty(rogue)) Standin.InPlace(data + rogue, "ROGUE");
            return 0;
        }
        return 9;
    }
}
'@

$bodyslide = $common + @'
static class BodySlide
{
    static string Arg(string[] args, string name)
    {
        for (int i = 0; i + 1 < args.Length; i++) if (args[i] == name) return args[i + 1];
        return null;
    }

    static void Nif(string path, List<string> shapes)
    {
        var names = new List<string>();
        names.Add("Scene Root");
        names.AddRange(shapes);
        int longest = 0;
        foreach (string n in names) longest = Math.Max(longest, n.Length);
        using (var ms = new MemoryStream())
        using (var w = new BinaryWriter(ms))
        {
            w.Write(Encoding.ASCII.GetBytes("Gamebryo File Format, Version 20.2.0.7\n"));
            w.Write((uint)0x14020007); w.Write((byte)1); w.Write((uint)12);
            w.Write((uint)names.Count); w.Write((uint)100);
            for (int k = 0; k < 3; k++) { w.Write((byte)1); w.Write((byte)0); }
            string[] types = { "NiNode", "BSTriShape" };
            w.Write((ushort)types.Length);
            foreach (string t in types) { w.Write((uint)t.Length); w.Write(Encoding.ASCII.GetBytes(t)); }
            for (int i = 0; i < names.Count; i++) w.Write((ushort)(i == 0 ? 0 : 1));
            for (int i = 0; i < names.Count; i++) w.Write((uint)12);
            w.Write((uint)names.Count); w.Write((uint)longest);
            foreach (string n in names) { w.Write((uint)n.Length); w.Write(Encoding.ASCII.GetBytes(n)); }
            w.Write((uint)0);
            for (int k = 0; k < names.Count; k++) { w.Write((int)k); w.Write((ulong)0); }
            w.Flush();
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, ms.ToArray());
        }
    }

    static int Main(string[] args)
    {
        string dir = Standin.Dir();
        Standin.Log("bodyslide " + string.Join(" ", args));
        var cfg = new XmlDocument();
        cfg.Load(Path.Combine(dir, "Config.xml"));
        XmlNode game = cfg.SelectSingleNode("/Config/TargetGame");
        XmlNode dataPath = cfg.SelectSingleNode("/Config/GameDataPath");
        // Unset, the real one asks which game on its first start.
        if (game == null || game.InnerText != "4" || dataPath == null || dataPath.InnerText.Length == 0) return 5;
        string group = Arg(args, "--groupbuild"), target = Arg(args, "--targetdir"), preset = Arg(args, "--preset");
        if (Environment.GetEnvironmentVariable("STANDIN_BS_INTO_GAME") != null) target = dataPath.InnerText.TrimEnd('\\');
        Standin.InPlace(Path.Combine(dir, "BodySlide.xml"), "<BodySlideConfig><LastPreset>" + preset + "</LastPreset></BodySlideConfig>");

        var members = new List<string>();
        foreach (string f in Directory.GetFiles(Path.Combine(dir, "SliderGroups"), "*.xml"))
        {
            var x = new XmlDocument(); x.Load(f);
            foreach (XmlElement g in x.SelectNodes("/SliderGroups/Group"))
                if (g.GetAttribute("name") == group)
                    foreach (XmlElement m in g.SelectNodes("Member")) members.Add(m.GetAttribute("name"));
        }
        var values = new Dictionary<string, double>();
        foreach (string f in Directory.GetFiles(Path.Combine(dir, "SliderPresets"), "*.xml"))
        {
            var x = new XmlDocument(); x.Load(f);
            foreach (XmlElement p in x.SelectNodes("/SliderPresets/Preset"))
                if (p.GetAttribute("name") == preset)
                    foreach (XmlElement s in p.SelectNodes("SetSlider"))
                        if (s.GetAttribute("size") == "big") values[s.GetAttribute("name")] = double.Parse(s.GetAttribute("value"), System.Globalization.CultureInfo.InvariantCulture);
        }
        int built = 0;
        foreach (string f in Directory.GetFiles(Path.Combine(dir, "SliderSets"), "*.osp"))
        {
            var x = new XmlDocument(); x.Load(f);
            foreach (XmlElement set in x.SelectNodes("/SliderSetInfo/SliderSet"))
            {
                if (!members.Contains(set.GetAttribute("name"))) continue;
                var shapes = new List<string>();
                foreach (XmlElement sh in set.SelectNodes("Shape")) shapes.Add(sh.InnerText);
                // A zap at anything above 0 takes its shape off the mesh.
                foreach (XmlElement sl in set.SelectNodes("Slider"))
                {
                    double v;
                    if (sl.GetAttribute("zap") == "true" && values.TryGetValue(sl.GetAttribute("name"), out v) && v > 0) shapes.Remove(sl.GetAttribute("name"));
                }
                XmlElement outFile = (XmlElement)set.SelectSingleNode("OutputFile");
                string baseName = Path.Combine(Path.Combine(target, set.SelectSingleNode("OutputPath").InnerText), outFile.InnerText);
                if (outFile.GetAttribute("GenWeights") == "true") { Nif(baseName + "_0.nif", shapes); Nif(baseName + "_1.nif", shapes); }
                else Nif(baseName + ".nif", shapes);
                if (Array.IndexOf(args, "--trimorphs") >= 0) File.WriteAllText(baseName + ".tri", "morphs");
                built++;
            }
        }
        return built > 0 ? 0 : 7;
    }
}
'@

$sleeper = @'
static class Sleeper { static void Main() { System.Threading.Thread.Sleep(120000); } }
'@

$work = Join-Path $Scratch ('thornswood-build-generated-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$fw = Split-Path -Parent $csc
$bin = Join-Path $work 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
function Compile([string]$name, [string]$source) {
    $src = Join-Path $bin ($name + '.cs')
    [IO.File]::WriteAllText($src, $source, $utf8)
    $out = Join-Path $bin ($name + '.exe')
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $said = & $csc /noconfig /nologo /target:exe /warn:0 "/out:$out" "/reference:$(Join-Path $fw 'System.dll')" "/reference:$(Join-Path $fw 'System.Xml.dll')" $src 2>&1
    $ErrorActionPreference = $old
    $ok = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $out)
    if (-not $ok) { foreach ($l in @($said)) { Write-Host "      $l" } }
    return $ok
}

# ------------------------------------------------------------ a nif, the same shape Check-CoveredBodies reads
function New-Nif([string]$Path, [string[]]$Shapes) {
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $w.Write([Text.Encoding]::ASCII.GetBytes("Gamebryo File Format, Version 20.2.0.7`n"))
    $w.Write([uint32]0x14020007); $w.Write([byte]1); $w.Write([uint32]12)
    $names = @('Scene Root') + $Shapes
    $w.Write([uint32]$names.Count); $w.Write([uint32]100)
    for ($k = 0; $k -lt 3; $k++) { $w.Write([byte]1); $w.Write([byte]0) }
    $types = @('NiNode', 'BSTriShape')
    $w.Write([uint16]$types.Count)
    foreach ($t in $types) { $w.Write([uint32]$t.Length); $w.Write([Text.Encoding]::ASCII.GetBytes($t)) }
    for ($i = 0; $i -lt $names.Count; $i++) { if ($i -eq 0) { $w.Write([uint16]0) } else { $w.Write([uint16]1) } }
    foreach ($n in $names) { $w.Write([uint32]12) }
    $w.Write([uint32]$names.Count)
    $w.Write([uint32](($names | Measure-Object -Property Length -Maximum).Maximum))
    foreach ($n in $names) { $w.Write([uint32]$n.Length); $w.Write([Text.Encoding]::ASCII.GetBytes($n)) }
    $w.Write([uint32]0)
    for ($k = 0; $k -lt $names.Count; $k++) { $w.Write([int32]$k); $w.Write([uint64]0) }
    $w.Flush()
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
}

function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function Text([string]$path) { if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) } return $null }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class GenTestIds
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
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateHardLink(string newName, string existing, IntPtr security);
    static Info Get(string path)
    {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            Info i; GetFileInformationByHandle(fs.SafeFileHandle, out i); return i;
        }
    }
    public static string Id(string path) { Info i = Get(path); return i.Volume + ":" + i.IndexHigh + ":" + i.IndexLow; }
    public static int Links(string path) { return (int)Get(path).Links; }
}
'@

# Every file under a folder with its bytes and its write time.
function Snap([string]$dir) {
    $d = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
        # The time from the file itself: a folder's listing keeps the time a
        # hard linked file had when it was last opened by that name.
        $d[$f.FullName.Substring($dir.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash + '|' + [IO.File]::GetLastWriteTimeUtc($f.FullName).Ticks
    }
    return $d
}
function Same($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k) -or $b[$k] -ne $a[$k]) { Write-Host "      differs: $k"; return $false } }
    return $true
}

try {
    $okN = Compile 'nemesis' $nemesis
    $okB = Compile 'bodyslide' $bodyslide
    $okS = Compile 'sleeper' $sleeper
    Yes 'the stand-ins for Nemesis, BodySlide and a running game compile' ($okN -and $okB -and $okS)
    if (-not ($okN -and $okB -and $okS)) { Done }

    # -------------------------------------------------------- the machine
    $staging = Join-Path $work 'vortex\mods'
    $steam = Join-Path $work 'steam\steamapps\common\Skyrim Special Edition'
    $root = Join-Path $work 'Thornswood-DevBuild'
    $game = Join-Path $root 'Game'
    $own = Join-Path $root 'Profile\OwnGame'
    $log = Join-Path $work 'tools.log'
    $env:STANDIN_LOG = $log

    $osp = @'
<SliderSetInfo version="1">
    <SliderSet name="CBBE 3BBB Amazing NeverNude">
        <OutputPath>meshes\actors\character\character assets</OutputPath>
        <OutputFile GenWeights="true">femalebody</OutputFile>
        <Shape target="3BA">3BA</Shape>
        <Shape target="3BA_Anus">3BA_Anus</Shape>
        <Shape target="3BA_Vagina">3BA_Vagina</Shape>
        <Shape target="Bra">Bra</Shape>
        <Shape target="Panty">Panty</Shape>
        <Slider name="Breasts" invert="false" small="0" big="0"/>
        <Slider name="ButtShape2" invert="false" small="0" big="0"/>
        <Slider name="AnkleSize" invert="false" small="100" big="0"/>
        <Slider name="NippleZap" invert="false" small="100" big="100" hidden="true" zap="true"/>
        <Slider name="Bra" invert="false" small="0" big="0" zap="true"/>
        <Slider name="Panty" invert="false" small="0" big="0" zap="true"/>
    </SliderSet>
    <SliderSet name="CBBE 3BBB Body Amazing">
        <OutputPath>meshes\actors\character\character assets</OutputPath>
        <OutputFile GenWeights="true">femalebody</OutputFile>
        <Shape target="3BA">3BA</Shape>
        <Shape target="3BA_Anus">3BA_Anus</Shape>
        <Shape target="3BA_Vagina">3BA_Vagina</Shape>
        <Slider name="Breasts" invert="false" small="0" big="0"/>
    </SliderSet>
    <SliderSet name="HIMBO Body - Vanilla Nevernude">
        <OutputPath>meshes\actors\character\character assets</OutputPath>
        <OutputFile GenWeights="true">malebody</OutputFile>
        <Shape target="HIMBO - Body">HIMBO - Body</Shape>
        <Shape target="HIMBO - Boxers">HIMBO - Boxers</Shape>
        <Slider name="ButtBooty" invert="false" small="0" big="0"/>
        <Slider name="Weight 0 to 1" invert="false" small="0" big="100" hidden="true"/>
    </SliderSet>
</SliderSetInfo>
'@
    # What Vortex has, mod by mod: path under Data, then the bytes (a
    # string, or a script block that writes the file).
    $mods = [ordered]@{
        'Nemesis' = @(
            @('Nemesis_Engine\Nemesis Unlimited Behavior Engine.exe', { param($p) Copy-Item -LiteralPath (Join-Path $bin 'nemesis.exe') -Destination $p }),
            @('Nemesis_Engine\nemesis.ini', "SkyrimDataDirectory=auto`r`nfirst=false`r`n"),
            # The cache it came with names the Steam copy's files, as the real one did.
            @('Nemesis_Engine\cache\behavior_path', ("0_master=" + $steam + "\Data\meshes\actors\character\behaviors\0_master`r`n")),
            @('Nemesis_Engine\cache\engine_update', ("0.84`r`n" + $steam + "\Data\Nemesis_Engine\x>>date`r`n")),
            @('Nemesis_Engine\cache\mod settings', "Precision`r`n"),
            @('Nemesis_Engine\mod\colis\info.ini', "name=Precision`r`n"),
            @('Nemesis_Engine\mod\tdmh\info.ini', "name=TDM Horse`r`n"),
            @('Nemesis_Engine\mod\tdmlen\info.ini', "name=TDM Leaning`r`n"),
            @('Nemesis_Engine\mod\tdmv\info.ini', "name=TDM Headtracking`r`n")
        )
        'TDM' = @(
            @('meshes\actors\character\behaviors\0_master.hkx', 'VORTEX-TDM-BEHAVIOR'),
            @('scripts\FNIS.pex', 'VORTEX-FNIS'),
            @('meshes\ts\bench.nif', 'VORTEX-BENCH')
        )
        'BodySlide' = @(
            @('CalienteTools\BodySlide\BodySlide.exe', { param($p) Copy-Item -LiteralPath (Join-Path $bin 'bodyslide.exe') -Destination $p }),
            @('CalienteTools\BodySlide\Config.xml', "<Config>`r`n    <TargetGame>-1</TargetGame>`r`n    <GameDataPath></GameDataPath>`r`n</Config>`r`n"),
            @('CalienteTools\BodySlide\SliderSets\Test.osp', $osp),
            @('CalienteTools\BodySlide\SliderGroups\CBBE.xml', "<SliderGroups><Group name=`"CBBE`"><Member name=`"CBBE 3BBB Amazing NeverNude`"/></Group></SliderGroups>"),
            # The preset the person last used, which a build must not pick up.
            @('CalienteTools\BodySlide\SliderPresets\CBBE.xml', "<SliderPresets><Preset name=`"CBBE Curvy`" set=`"CBBE Body`"><Group name=`"CBBE`"/><SetSlider name=`"Breasts`" size=`"big`" value=`"80`"/></Preset></SliderPresets>")
        )
        '3BA' = @(
            @('meshes\actors\character\character assets\femalebody_0.nif', { param($p) New-Nif $p @('3BA', '3BA_Vagina', '3BA_Anus') }),
            @('meshes\actors\character\character assets\femalebody_1.nif', { param($p) New-Nif $p @('3BA', '3BA_Vagina', '3BA_Anus') })
        )
        'HIMBO' = @(
            @('meshes\actors\character\character assets\malebody_0.nif', { param($p) New-Nif $p @('HIMBO - Body', 'HIMBO - Boxers', 'VORTEX') }),
            @('meshes\actors\character\character assets\malebody_1.nif', { param($p) New-Nif $p @('HIMBO - Body', 'HIMBO - Boxers', 'VORTEX') })
        )
    }
    Put (Join-Path $steam 'SkyrimSE.exe') 'STEAM-EXE'
    Copy-Item -LiteralPath (Join-Path $bin 'sleeper.exe') -Destination (New-Item -ItemType Directory -Force -Path $game).FullName
    Rename-Item -LiteralPath (Join-Path $game 'sleeper.exe') -NewName 'SkyrimSE.exe'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'Launcher') | Out-Null
    Copy-Item -LiteralPath (Join-Path $bin 'sleeper.exe') -Destination (Join-Path $root 'Launcher\Thornswood.exe')
    $filesTxt = New-Object Collections.Generic.List[string]
    $deploy = New-Object Collections.Generic.List[string]
    foreach ($mod in $mods.Keys) {
        foreach ($f in $mods[$mod]) {
            $rel = $f[0]
            $st = Join-Path $staging "$mod\$rel"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $st) | Out-Null
            if ($f[1] -is [scriptblock]) { & $f[1] $st } else { Put $st $f[1] }
            foreach ($into in (Join-Path $steam "Data\$rel"), (Join-Path $game "Data\$rel")) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $into) | Out-Null
                [void][GenTestIds]::CreateHardLink($into, $st, [IntPtr]::Zero)
            }
            $fi = Get-Item -LiteralPath $st
            $filesTxt.Add(('L|V|{0}|{1}|Data\{2}' -f $fi.Length, $fi.LastWriteTimeUtc.Ticks, $rel))
            $deploy.Add(('{{ "relPath": "{0}", "source": "{1}" }}' -f $rel.Replace('\', '\\'), $mod))
        }
    }
    Put (Join-Path $steam 'Data\vortex.deployment.json') ('{ "stagingPath": "' + $staging.Replace('\', '\\') + '", "files": [ ' + ($deploy -join ', ') + ' ] }')
    $filesTxt.Add('C|O|9|1|SkyrimSE.exe')
    Put (Join-Path $own 'files.txt') (($filesTxt -join "`r`n") + "`r`n")
    Put (Join-Path $own 'made.txt') ("source=$steam`r`ngame=$steam`r`nrules=13`r`nkinds=1`r`n")
    Put (Join-Path $own 'plugins.txt') "*TsOne.esp`r`n*Precision.esp`r`n"
    $list = Join-Path $work 'generated.json'
    $listText = '{ "nemesis": { "patches": ["colis", "tdmh", "tdmlen", "tdmv"] }, "bodyslide": { "sets": ["CBBE 3BBB Amazing NeverNude", "HIMBO Body - Vanilla Nevernude"], "sliders": {} } }'
    Put $list $listText
    Yes '(every mod file is one file under three names: Vortex''s, the Steam copy''s and Thornswood''s)' (
        [GenTestIds]::Links((Join-Path $game 'Data\meshes\actors\character\character assets\femalebody_1.nif')) -eq 3 -and
        [GenTestIds]::Links((Join-Path $game 'Data\Nemesis_Engine\cache\mod settings')) -eq 3)

    function Invoke-Build([string[]]$more) {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Build, '-Root', $root, '-BuildList', $list, '-NoPause') + $more
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & $pwsh @a 2>&1 | Out-String
        $code = $LASTEXITCODE
        $ErrorActionPreference = $old
        return [pscustomobject]@{ Code = $code; Out = $out }
    }
    function Log { if (Test-Path -LiteralPath $log) { return [IO.File]::ReadAllText($log) } return '' }
    $record = Join-Path $own 'generated.txt'
    $A = 'Data\meshes\actors\character\character assets\'

    # ======================================================== J: a dry run
    $gameBefore = Snap $game; $ownBefore = Snap $own
    $r = Invoke-Build @('-DryRun')
    Yes ('J: a dry run exits 0 (got {0})' -f $r.Code) ($r.Code -eq 0)
    Yes 'J: and says what it would run, both tools' ($r.Out -match '-update' -and $r.Out -match '-generate colis tdmh tdmlen tdmv' -and $r.Out -match '--groupbuild "Thornswood 1"')
    Yes 'J: and writes nothing: not the game folder, not the records, no tool started' ((Same $gameBefore (Snap $game)) -and (Same $ownBefore (Snap $own)) -and -not (Log))

    # ======================================================== A: a build
    $steamBefore = Snap $steam; $stagingBefore = Snap $staging
    $r = Invoke-Build @()
    if ($r.Code -ne 0) { Write-Host $r.Out }
    Yes ('A: the build works (exit {0})' -f $r.Code) ($r.Code -eq 0)
    Yes 'A: the Steam copy is byte for byte and time for time what it was' (Same $steamBefore (Snap $steam))
    Yes 'A: and so is Vortex''s staging folder, the tools'' own files in it included' (Same $stagingBefore (Snap $staging))
    $beh = Join-Path $game 'Data\meshes\actors\character\behaviors\0_master.hkx'
    Yes 'A: Nemesis wrote the behavior files in Thornswood''s folder, with the patches the list names' (
        (Text $beh) -eq 'NEMESIS colis tdmh tdmlen tdmv' -and
        (Text (Join-Path $game 'Data\meshes\actors\character\_1stperson\behaviors\firstperson.hkx')) -eq 'NEMESIS colis tdmh tdmlen tdmv' -and
        (Text (Join-Path $game 'Data\scripts\FNIS.pex')) -eq 'FNIS NEMESIS colis tdmh tdmlen tdmv')
    Yes 'A: into this folder''s own copies, not Vortex''s' ([GenTestIds]::Links($beh) -eq 1 -and (Text (Join-Path $staging 'TDM\meshes\actors\character\behaviors\0_master.hkx')) -eq 'VORTEX-TDM-BEHAVIOR')
    Yes 'A: it ran -update, then -generate' ((Log) -match '(?s)nemesis -update.*nemesis -generate colis tdmh tdmlen tdmv')
    $ini = Text (Join-Path $game 'Data\Nemesis_Engine\nemesis.ini')
    Yes 'A: Nemesis was pointed at this folder''s Data by name, not left to find the game itself' ($ini -match [regex]::Escape('SkyrimDataDirectory=' + $game + '\Data\'))
    Yes 'A: and its cache names only this folder''s files now' (
        (Text (Join-Path $game 'Data\Nemesis_Engine\cache\behavior_path')) -notmatch [regex]::Escape($steam) -and
        (Text (Join-Path $staging 'Nemesis\Nemesis_Engine\cache\behavior_path')) -match [regex]::Escape($steam))
    $cov = & $pwsh -NoProfile -File (Join-Path $Repo 'scripts\mods\Check-CoveredBodies.ps1') -Game $game 2>&1 | Out-String
    Yes ('A: every body in Thornswood''s folder is covered now (Check-CoveredBodies exit {0})' -f $LASTEXITCODE) ($LASTEXITCODE -eq 0 -and $cov -match 'covered\s+femalebody_1\.nif\s+shapes: 3BA, 3BA_Anus, 3BA_Vagina, Bra, Panty')
    Yes 'A: the bodies are new files of this folder''s own; Vortex''s nude 3BA body is as it was' (
        [GenTestIds]::Links((Join-Path $game ($A + 'femalebody_1.nif'))) -eq 1 -and
        [GenTestIds]::Links((Join-Path $staging ('3BA\' + $A.Substring(5) + 'femalebody_1.nif'))) -eq 2)
    $bsLog = @((Log) -split "`r?`n" | Where-Object { $_ -like 'bodyslide *' })
    Yes 'A: BodySlide built each set with the preset made for it, and was never asked for morph files' (
        $bsLog.Count -eq 2 -and ($bsLog -join "`n") -match '--preset Thornswood 1' -and ($bsLog -join "`n") -notmatch 'trimorphs')
    Yes 'A: into a folder of its own, not the game folder' (($bsLog -join "`n") -notmatch [regex]::Escape('--targetdir ' + $game))
    $preset = [xml](Text (Join-Path $game 'Data\CalienteTools\BodySlide\SliderPresets\Thornswood.xml'))
    $p1 = @($preset.SliderPresets.Preset | Where-Object { $_.name -eq 'Thornswood 1' })[0]
    $val = { param($n, $s) @($p1.SetSlider | Where-Object { $_.name -eq $n -and $_.size -eq $s })[0].value }
    Yes 'A: the preset names every slider of the set at its default: Breasts 0, AnkleSize small 100, NippleZap 100, Bra and Panty 0' (
        (& $val 'Breasts' 'big') -eq '0' -and (& $val 'AnkleSize' 'small') -eq '100' -and (& $val 'NippleZap' 'big') -eq '100' -and
        (& $val 'Bra' 'big') -eq '0' -and (& $val 'Panty' 'small') -eq '0' -and @($p1.SetSlider).Count -eq 12)
    Yes 'A: BodySlide was set to Skyrim Special Edition and this folder''s Data, in this folder''s own copy of its settings' (
        (Text (Join-Path $game 'Data\CalienteTools\BodySlide\Config.xml')) -match '<TargetGame>4</TargetGame>' -and
        (Text (Join-Path $staging 'BodySlide\CalienteTools\BodySlide\Config.xml')) -match '<TargetGame>-1</TargetGame>')

    . $Lib
    $rec = Read-GeneratedRecord $record
    $want = @('Data\meshes\actors\character\behaviors\0_master.hkx', 'Data\meshes\actors\character\_1stperson\behaviors\firstperson.hkx',
              'Data\scripts\FNIS.pex', 'Data\meshes\animationdatasinglefile.txt',
              ($A + 'femalebody_0.nif'), ($A + 'femalebody_1.nif'), ($A + 'malebody_0.nif'), ($A + 'malebody_1.nif'))
    $got = @($rec.Files | ForEach-Object { $_.Rel })
    Yes ('A: the record lists every file made, and nothing of the tools'' own folders ({0})' -f $got.Count) (
        $got.Count -eq $want.Count -and @($want | Where-Object { $got -notcontains $_ }).Count -eq 0)
    $shaOk = $true
    foreach ($f in $rec.Files) { if ((Get-FileHash -LiteralPath (Join-Path $game $f.Rel) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $f.Sha) { $shaOk = $false } }
    Yes 'A: each with the sha256 of what is in the folder' $shaOk
    Yes 'A: and what it was built from: the build list, the mod list, Nemesis'' files, BodySlide''s' (
        $rec.Parts.Contains('list') -and $rec.Parts.Contains('plugins') -and $rec.Parts.Contains('nemesis') -and $rec.Parts.Contains('bodyslide') -and $rec.Game -eq $game)
    Yes 'A: its work folder is gone' (-not (Test-Path -LiteralPath (Join-Path $own 'build-generated')))
    $state = Get-GeneratedState $root $list
    Yes 'A: and it reads back as current' ($state.Current)

    . (Join-Path $Repo 'scripts\release\Ship-Rules.ps1')
    $col = Get-ShipOwnGameCollection (Join-Path $root 'Profile')
    Yes 'A: a release carries them: Ship-Rules no longer counts the body or the behavior file as the collection''s, though Vortex deploys those names' (
        -not $col.Contains($A + 'femalebody_1.nif') -and -not $col.Contains('Data\meshes\actors\character\behaviors\0_master.hkx') -and -not $col.Contains('Data\scripts\FNIS.pex'))
    Yes 'A: and still counts the rest of Vortex''s files as the collection''s, the tools among them' (
        $col.Contains('Data\meshes\ts\bench.nif') -and $col.Contains('Data\Nemesis_Engine\Nemesis Unlimited Behavior Engine.exe') -and $col.Contains('Data\CalienteTools\BodySlide\BodySlide.exe'))
    Yes 'A: Get-ShipGeneratedFiles reads the same files the record has' ((Get-ShipGeneratedFiles (Join-Path $root 'Profile')).Count -eq $want.Count)

    # ======================================================== B: stale
    $plugins = Join-Path $own 'plugins.txt'
    $keep = Text $plugins
    Put $plugins ($keep + "*NewMod.esp`r`n")
    $s = Get-GeneratedState $root $list
    Yes 'B: a changed mod list makes it stale, and says so' (-not $s.Current -and ($s.Why -join ';') -match 'the mod list changed')
    $says = Get-GeneratedStaleSays $s 'dev'
    Yes 'B: the sentence says what to run, with the channel' ($says -match [regex]::Escape('.\scripts\mods\Build-Generated.ps1 -Channel dev') -and $says -notmatch [char]0x2014 -and $says -notmatch '(?i)player')
    Put $plugins $keep
    Yes 'B: put back, it is current again' ((Get-GeneratedState $root $list).Current)

    $ft = Text (Join-Path $own 'files.txt')
    $line = @($ft -split "`r`n" | Where-Object { $_ -like '*|Data\Nemesis_Engine\mod\colis\info.ini' })[0]
    Put (Join-Path $own 'files.txt') ($ft.Replace($line, ($line -replace '\|(\d+)\|Data', '|999|Data')))
    $s = Get-GeneratedState $root $list
    Yes 'B: Vortex changing a file Nemesis reads (a patch) makes it stale, and says Nemesis' (-not $s.Current -and ($s.Why -join ';') -match 'Nemesis reads')
    $line2 = @($ft -split "`r`n" | Where-Object { $_ -like '*|Data\CalienteTools\BodySlide\SliderSets\Test.osp' })[0]
    Put (Join-Path $own 'files.txt') ($ft.Replace($line2, ($line2 -replace '\|(\d+)\|Data', '|999|Data')))
    $s = Get-GeneratedState $root $list
    Yes 'B: Vortex changing a slider set makes it stale, and says BodySlide' (-not $s.Current -and ($s.Why -join ';') -match 'BodySlide builds from' -and ($s.Why -join ';') -notmatch 'Nemesis reads')
    Put (Join-Path $own 'files.txt') $ft
    Put $list ($listText.Replace('"tdmv"', '"tdmv", "gender"'))
    $s = Get-GeneratedState $root $list
    Yes 'B: a changed build list makes it stale' (-not $s.Current -and ($s.Why -join ';') -match 'records\\generated\.json')
    Put $list $listText
    $bodyBytes = [IO.File]::ReadAllBytes((Join-Path $game ($A + 'femalebody_1.nif')))
    [IO.File]::WriteAllText((Join-Path $game ($A + 'femalebody_1.nif')), 'put back by somebody')
    $s = Get-GeneratedState $root $list
    Yes 'B: a built file not as built makes it stale, and names it' (-not $s.Current -and ($s.Why -join ';') -match 'femalebody_1\.nif is not as built')
    [IO.File]::WriteAllBytes((Join-Path $game ($A + 'femalebody_1.nif')), $bodyBytes)
    Yes 'B: put back, current again' ((Get-GeneratedState $root $list).Current)
    Move-Item -LiteralPath $record -Destination ($record + '.aside')
    $s = Get-GeneratedState $root $list
    Yes 'B: no record at all is stale: never built' (-not $s.Current -and ($s.Why -join ';') -match 'never been built')

    # Check-ShipReady's row, lifted out of the script and run.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Ready, [ref]$null, [ref]$null)
    foreach ($n in 'New-Row', 'Get-GeneratedRows') {
        $fn = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        Yes "Check-ShipReady.ps1 has $n" ($null -ne $fn)
        if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
    }
    $row = @(Get-GeneratedRows $root $list 'dev')[0]
    Yes 'B: Check-ShipReady says NO on it, a gap that stops a Ship, with the command that closes it' (
        -not $row.Ok -and $row.Level -eq 'need' -and $row.Fix -match 'Build-Generated\.ps1 -Channel dev')
    Move-Item -LiteralPath ($record + '.aside') -Destination $record
    $row = @(Get-GeneratedRows $root $list 'dev')[0]
    Yes 'B: and yes once it is current' ($row.Ok)
    $readyText = [IO.File]::ReadAllText($Ready)
    Yes 'B: Check-ShipReady asks it whenever there is a game folder' ($readyText -match "if \(\`$hasGame\) \{\s*foreach \(\`$r in @\(Get-GeneratedRows \`$Root \(Join-Path \`$RepoDir 'records\\generated\.json'\) \`$Channel\)\) \{ Show-Row \`$r \}")

    # Ship's step, read out of Ship.ps1.
    $shipText = [IO.File]::ReadAllText($Ship)
    $at = $shipText.IndexOf("Head 'Generated files'")
    $bodies = $shipText.IndexOf("Head 'Covered bodies'")
    Yes 'B: Ship.ps1 has a Generated files step' ($at -gt 0)
    $step = if ($at -gt 0 -and $bodies -gt $at) { $shipText.Substring($at, $bodies - $at) } else { '' }
    Yes 'B: it reads the state of this install''s folder against records\generated.json' (
        $step -match "\. \(Join-Path \`$Here '\.\.\\mods\\Generated\.ps1'\)" -and $step -match "Get-GeneratedState \`$Root \(Join-Path \`$RepoDir 'records\\generated\.json'\)")
    Yes 'B: and stops, on both channels, with the sentence that says what to run, putting the version back' (
        $step -match "if \(-not \`$genState\.Current\) \{\s*Unbump '[^']+'\s*Die \(Get-GeneratedStaleSays \`$genState \`$Channel\)" -and $step -notmatch '\$Dev')
    $client = $shipText.IndexOf("Head 'Client build'")
    $publish = $shipText.IndexOf("Publish-Update.ps1", $at + 1)
    Yes 'B: after the client check, before the covered bodies (which read what it built) and before anything is published' (
        $client -gt 0 -and $at -gt $client -and $bodies -gt $at -and ($publish -lt 0 -or $publish -gt $at))

    # ======================================================== C: in use
    $recBefore = Text $record
    $gameBefore = Snap $game
    foreach ($who in @(@('Skyrim', (Join-Path $game 'SkyrimSE.exe')), @('the launcher', (Join-Path $root 'Launcher\Thornswood.exe')))) {
        $p = Start-Process -FilePath $who[1] -PassThru -WindowStyle Hidden
        try {
            Start-Sleep -Milliseconds 400
            $r = Invoke-Build @()
            Yes ('C: with ' + $who[0] + ' run from the install, it refuses: exit 3 (got ' + $r.Code + ')') ($r.Code -eq 3)
            Yes ('C: and says the folder is in use and what to close') ($r.Out -match 'is in use' -and $r.Out -match 'Close Skyrim and the Thornswood launcher')
        } finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $p.WaitForExit() }
    }
    Yes 'C: and nothing was written: the game folder and the record are as they were' ((Same $gameBefore (Snap $game)) -and (Text $record) -eq $recBefore)

    # ======================================================== D: never the Steam copy
    Put (Join-Path $game 'Data\vortex.deployment.json') '{}'
    $gameBefore = Snap $game
    $r = Invoke-Build @()
    Yes 'D: a folder with Vortex''s own record in it is refused as not Thornswood''s own' ($r.Code -eq 1 -and $r.Out -match 'folder Vortex deploys into')
    Yes 'D: and nothing is written' ((Same $gameBefore (Snap $game)) -and (Text $record) -eq $recBefore)
    Remove-Item -LiteralPath (Join-Path $game 'Data\vortex.deployment.json')
    $madeTxt = Text (Join-Path $own 'made.txt')
    Put (Join-Path $own 'made.txt') ($madeTxt.Replace("source=$steam", "source=$game"))
    $r = Invoke-Build @()
    Yes 'D: the folder the launcher made Thornswood''s from is refused' ($r.Code -eq 1 -and $r.Out -match 'the Steam copy\. Nothing is built there')
    Put (Join-Path $own 'made.txt') $madeTxt

    # ======================================================== E: the body rules
    [IO.File]::Delete($log)
    foreach ($case in @(
        @('a breast slider moved', '{ "CBBE 3BBB Amazing NeverNude": { "Breasts": { "big": 60 } } }', "'Breasts' in CBBE 3BBB Amazing NeverNude shapes the body at 60"),
        @('the seat shaped on the men''s body', '{ "HIMBO Body - Vanilla Nevernude": { "ButtBooty": { "small": 30 } } }', "'ButtBooty' in HIMBO Body - Vanilla Nevernude shapes the body at 30"),
        @('the bra zapped', '{ "CBBE 3BBB Amazing NeverNude": { "Bra": { "big": 100, "small": 100 } } }', "'Bra' in CBBE 3BBB Amazing NeverNude takes the underwear off"),
        @('another zap moved from its default', '{ "CBBE 3BBB Amazing NeverNude": { "NippleZap": { "big": 0 } } }', "'NippleZap' in CBBE 3BBB Amazing NeverNude is a zap moved from its default"),
        @('a slider the set does not have', '{ "CBBE 3BBB Amazing NeverNude": { "NoSuch": { "big": 1 } } }', "moves 'NoSuch'"))) {
        Put $list ($listText.Replace('"sliders": {}', '"sliders": ' + $case[1]))
        $gameBefore = Snap $game
        $r = Invoke-Build @()
        Yes ('E: ' + $case[0] + ': refused, and the line names it') ($r.Code -eq 1 -and $r.Out.Contains($case[2]) -and $r.Out -match 'against the body rules')
        Yes ('E: ' + $case[0] + ': before anything was written or run') ((Same $gameBefore (Snap $game)) -and -not (Log) -and (Text $record) -eq $recBefore)
    }
    Put $list ($listText.Replace('"CBBE 3BBB Amazing NeverNude"', '"CBBE 3BBB Body Amazing"'))
    $bodyBefore = (Get-FileHash -LiteralPath (Join-Path $game ($A + 'femalebody_1.nif'))).Hash
    $r = Invoke-Build @()
    Yes 'E: a slider set with nothing over the body is built, read and refused as nude' ($r.Code -eq 1 -and $r.Out -match 'NUDE\s+femalebody_1\.nif' -and $r.Out -match 'is not covered')
    Yes 'E: and nothing it built was put in the folder, nor recorded' ((Get-FileHash -LiteralPath (Join-Path $game ($A + 'femalebody_1.nif'))).Hash -eq $bodyBefore -and (Text $record) -eq $recBefore)
    Put $list $listText

    # ======================================================== F: a write it did not foresee
    $steamBefore = Snap $steam
    $env:STANDIN_ROGUE = 'meshes\ts\bench.nif'
    $r = Invoke-Build @()
    Remove-Item Env:\STANDIN_ROGUE
    Yes 'F: a tool writing a shared file in place is caught and refused' ($r.Code -eq 1 -and $r.Out -match 'Nemesis wrote into 1 file\(s\) this folder shares with another \(Data\\meshes\\ts\\bench\.nif\)')
    Yes 'F: and nothing is recorded' ((Text $record) -eq $recBefore)
    Yes '(F: the stand-in really did write through: the Steam copy''s file changed with it)' ((Text (Join-Path $steam 'Data\meshes\ts\bench.nif')) -eq 'ROGUE')
    foreach ($p in (Join-Path $staging 'TDM\meshes\ts\bench.nif')) { [IO.File]::WriteAllText($p, 'VORTEX-BENCH') }

    # ======================================================== G: Nemesis aimed outside
    [IO.File]::Delete($log)
    $env:STANDIN_NEMESIS_OUTSIDE = $steam + '\Data\meshes\actors\character\behaviors\mt_behavior'
    $steamBefore = Snap $steam
    $r = Invoke-Build @()
    Remove-Item Env:\STANDIN_NEMESIS_OUTSIDE
    Yes 'G: Nemesis'' cache naming a file outside this folder stops it before -generate' ($r.Code -eq 1 -and $r.Out -match 'which is not in' -and (Log) -notmatch '-generate')
    Yes 'G: and the Steam copy is untouched' (Same $steamBefore (Snap $steam))

    # ======================================================== H: BodySlide aimed at the game
    $env:STANDIN_BS_INTO_GAME = '1'
    $r = Invoke-Build @()
    Remove-Item Env:\STANDIN_BS_INTO_GAME
    Yes 'H: BodySlide writing into the game folder itself is refused and not recorded' ($r.Code -eq 1 -and $r.Out -match 'BodySlide wrote into the game folder itself' -and (Text $record) -eq $recBefore)

    # ======================================================== I: no longer made
    Put $list ($listText.Replace(', "HIMBO Body - Vanilla Nevernude"', ''))
    $steamBefore = Snap $steam
    $r = Invoke-Build @()
    if ($r.Code -ne 0) { Write-Host $r.Out }
    $male = Join-Path $game ($A + 'malebody_1.nif')
    Yes 'I: a build that no longer makes the men''s body works' ($r.Code -eq 0)
    Yes 'I: and the men''s body in the folder is Vortex''s again, as its own copy' (
        (Get-FileHash -LiteralPath $male).Hash -eq (Get-FileHash -LiteralPath (Join-Path $staging ('HIMBO\' + $A.Substring(5) + 'malebody_1.nif'))).Hash -and [GenTestIds]::Links($male) -eq 1)
    $rec = Read-GeneratedRecord $record
    Yes 'I: and the record no longer lists it' (@($rec.Files | Where-Object { $_.Rel -like '*\malebody*' }).Count -eq 0 -and $rec.Files.Count -eq 6)
    Yes 'I: the Steam copy is untouched' (Same $steamBefore (Snap $steam))
    Put $list $listText
} finally {
    Remove-Item Env:\STANDIN_LOG -ErrorAction SilentlyContinue
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($work, [StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================ the real build list
. $Lib
$real = Get-GeneratedBuildList (Join-Path $Repo 'records\generated.json')
Yes 'records\generated.json builds the women''s NeverNude body and the men''s body with boxers (issue #405)' (
    $real.Sets -contains 'CBBE 3BBB Amazing NeverNude' -and $real.Sets -contains 'HIMBO Body - Vanilla Nevernude')
Yes 'and moves no slider, so every body is its set''s own default shape (issue #1004)' ($real.Sliders.Count -eq 0)
Yes 'and generates with the four Nemesis patches the releases were made with' (($real.Patches -join ',') -eq 'colis,tdmh,tdmlen,tdmv')
$buildText = [IO.File]::ReadAllText($Build)
Yes 'Build-Generated.ps1 never asks BodySlide for RaceMenu morph files' ($buildText -notmatch '--trimorphs''|"--trimorphs"|''-tri''')

Done
