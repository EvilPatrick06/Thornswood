<#
  test-498-msbuild.ps1

      pwsh -NoProfile -File .\tests\test-498-msbuild.ps1
      pwsh -NoProfile -File .\tests\test-498-msbuild.ps1 -RequireMSBuild      (the build check)
      pwsh -NoProfile -File .\tests\test-498-msbuild.ps1 -Scratch <folder>    keeps the two builds there

  Issue #498, Patrick's option C on 11 Oct: the launcher moves from the
  in-box .NET Framework csc to MSBuild and a project file. Until the switch
  both builds have to make the same two exes, so this builds the launcher and
  the setup program both ways with scripts\release\Build-Launcher.ps1
  (-With csc and -With msbuild, unsigned, into scratch) and holds the two
  pairs to each other:

    1. the project files name the same resources and references as
       Build-Launcher.ps1's csc half, read as text (this part runs everywhere,
       MSBuild or not, so a resource added to one and not the other is caught
       on the VPS's nightly too);
    2. the same manifest resources under the same names with the same bytes;
    3. the same assembly references, names and versions;
    4. the same types, methods (by name and signature), fields, properties
       and events, leaving out what each compiler generates for itself
       (lambda classes, iterators, cached delegates: names with < in them),
       because the old csc and Roslyn name those differently;
    5. the same assembly attributes, the same file details Windows shows
       (FileVersion, ProductVersion, description, product, company,
       copyright, OriginalFilename), the same entry point, the same PE kind
       (AnyCPU, not 32 bit preferred, GUI subsystem 4.00, high entropy ASLR
       off) and no TargetFrameworkAttribute in either, so the runtime's
       compatibility defaults stay what they are;
    6. the same win32 icon bytes and the same application manifest, compared
       as XML without comments and spacing;
    7. tests\test-app-manifest.ps1 passes on both pairs, and
       scripts\dev\Check-Secrets.ps1 -Binary passes on the MSBuild pair;
    8. sizes within five percent, and nothing but the exe and its pdb in the
       MSBuild output folder (the update system ships one file).

  What it prints but does not hold the two to: the methods each compiler
  generates, and the outside members each one calls (Roslyn compiles a
  switch on strings to a hash, the old csc to a Dictionary).

  Without MSBuild on the machine (the VPS runners, 12 Oct) part 1 still runs
  and the rest says SKIP; -RequireMSBuild makes that a failure instead, which
  is how the build check on GitHub's runner calls it.

  Builds into scratch and nowhere else: never signs (-NoSign), never touches
  out\setup-stub.exe (-StubOut), closes nothing, starts nothing.
#>
[CmdletBinding()]
param(
    [switch]$RequireMSBuild,
    [string]$Scratch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
$script:skip = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Skip([string]$what) { $script:skip++; Write-Host "SKIP  $what" }
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed, {2} skipped" -f $script:pass, $script:fail, $script:skip)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- 1. the project files against Build-Launcher.ps1, as text -------------
$blPath = Join-Path $repo 'scripts\release\Build-Launcher.ps1'
$bl = [IO.File]::ReadAllText($blPath)
$appProjPath = Join-Path $repo 'launcher\app\Thornswood.csproj'
$setupProjPath = Join-Path $repo 'installer\setup\Setup.csproj'
Yes 'launcher\app\Thornswood.csproj is there' (Test-Path -LiteralPath $appProjPath)
Yes 'installer\setup\Setup.csproj is there' (Test-Path -LiteralPath $setupProjPath)
if (-not (Test-Path -LiteralPath $appProjPath) -or -not (Test-Path -LiteralPath $setupProjPath)) { Done }
$appProj = [xml][IO.File]::ReadAllText($appProjPath)
$setupProj = [xml][IO.File]::ReadAllText($setupProjPath)
$ns = @{ m = 'http://schemas.microsoft.com/developer/msbuild/2003' }
function Names($doc, [string]$xpath) { @(Select-Xml -Xml $doc -XPath $xpath -Namespace $ns | ForEach-Object { $_.Node.InnerText.Trim() }) }
function Attr($doc, [string]$xpath) { @(Select-Xml -Xml $doc -XPath $xpath -Namespace $ns | ForEach-Object { $_.Node.Value.Trim() }) }
function Same([object[]]$a, [object[]]$b) { (@($a | Sort-Object) -join '|') -eq (@($b | Sort-Object) -join '|') }

# The csc half's resources: each "/resource:<path>,<name>" it passes, and the
# WebView2 files it passes by loop.
$cscRes = @([regex]::Matches($bl, '/resource:\$\(\(Resolve-Path \$[A-Za-z]+\)\.Path\),([A-Za-z0-9.\-]+)"') | ForEach-Object { $_.Groups[1].Value })
$wvm = [regex]::Match($bl, '\$wv2Managed\s*=\s*@\(([^)]*)\)')
$wvl = [regex]::Match($bl, "\`$wv2Loader\s*=\s*'([^']+)'")
$wv2 = @()
if ($wvm.Success) { $wv2 += @([regex]::Matches($wvm.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) }
if ($wvl.Success) { $wv2 += $wvl.Groups[1].Value }
Yes 'Build-Launcher.ps1 still names the WebView2 files it embeds' ($wv2.Count -eq 3)
$cscRes = @($cscRes) + $wv2
# logo.png appears twice in the csc half: the launcher's, and the setup
# program's logo-192.png under the same name, so the list is taken once each.
$cscAppRes = @($cscRes | Select-Object -Unique)
$projAppRes = @(Names $appProj '//m:EmbeddedResource/m:LogicalName')
Yes ('the launcher project embeds the same resources as the csc build: ' + ($projAppRes -join ', ')) (Same $projAppRes $cscAppRes)
$projSetupRes = @(Names $setupProj '//m:EmbeddedResource/m:LogicalName')
Yes 'the setup project embeds logo-192.png as logo.png, as the csc build does' ((Same $projSetupRes @('logo.png')) -and
    ($bl.Contains('$stubArgs += "/resource:$((Resolve-Path $logoSml).Path),logo.png"')) -and
    (@(Attr $setupProj '//m:EmbeddedResource/@Include') -join '') -match 'logo-192\.png$')

$needed = [regex]::Match($bl, '(?s)\$needed\s*=\s*@\((.*?)\n\)')
$cscRefs = @()
if ($needed.Success) { $cscRefs = @([regex]::Matches($needed.Groups[1].Value, "'([A-Za-z0-9.]+)\.dll'") | ForEach-Object { $_.Groups[1].Value }) }
Yes 'Build-Launcher.ps1 still lists the framework assemblies it hands csc' ($cscRefs.Count -ge 10)
$projAppRefs = @(Attr $appProj '//m:Reference/@Include')
$wv2Managed = @($wv2 | Where-Object { $_ -like 'Microsoft.*.dll' } | ForEach-Object { $_ -replace '\.dll$', '' })
Yes ('the launcher project references the same assemblies: ' + ($projAppRefs -join ', ')) (Same $projAppRefs (@($cscRefs) + $wv2Managed))
Yes 'the setup project references the same framework assemblies' (Same @(Attr $setupProj '//m:Reference/@Include') $cscRefs)
Yes 'WebView2 is never copied beside the exe (Private false on both)' (
    @(Select-Xml -Xml $appProj -XPath "//m:Reference[starts-with(@Include,'Microsoft.Web.WebView2')]/m:Private" -Namespace $ns | Where-Object { $_.Node.InnerText -eq 'false' }).Count -eq 2)
foreach ($pair in @(@{ Doc = $appProj; Name = 'launcher' }, @{ Doc = $setupProj; Name = 'setup' })) {
    $d = $pair.Doc
    Yes "the $($pair.Name) project keeps LangVersion 5 until the switch" ((Names $d '//m:LangVersion') -join '' -eq '5')
    Yes "the $($pair.Name) project targets .NET Framework 4.8.1" ((Names $d '//m:TargetFrameworkVersion') -join '' -eq 'v4.8.1')
    Yes "the $($pair.Name) project writes no TargetFrameworkAttribute" ((Names $d '//m:GenerateTargetFrameworkAttribute') -join '' -eq 'false')
    Yes "the $($pair.Name) project has no PackageReference (nothing restored, nothing loose)" (@(Select-Xml -Xml $d -XPath '//m:PackageReference' -Namespace $ns).Count -eq 0)
}

$ship = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Ship.ps1'))
Yes 'Ship builds a dev launcher the way -LauncherWith says, csc unless told' (
    $ship.Contains("[ValidateSet('csc', 'msbuild')][string]`$LauncherWith = 'csc'") -and
    $ship.Contains("'Build-Launcher.ps1') -Root `$Root -OutDir `$buildOut -NoPause -With `$LauncherWith"))
Yes 'and refuses msbuild for main, which takes the exe CI built' ($ship.Contains("if (-not `$Dev -and `$LauncherWith -ne 'csc') { Die "))
Yes 'Build-Launcher.ps1 builds with csc unless told, until the switch' ($bl.Contains("[string]`$With = 'csc'"))

# ---- 2 to 8 need MSBuild --------------------------------------------------
. (Join-Path $repo 'scripts\release\Find-MSBuild.ps1') -Load
$found = Find-ThornswoodMSBuild
if (-not $found.MSBuild -or -not $found.RefAssemblies) {
    $why = 'no MSBuild from Visual Studio 2022 or its Build Tools with the .NET Framework 4.8.1 targeting pack on this machine'
    if ($RequireMSBuild) { Yes "MSBuild is here ($why)" $false }
    else { Skip "the two builds and their comparison: $why" }
    Done
}
Write-Host "      MSBuild $($found.MSBuild)"

$own = $false
if (-not $Scratch) { $Scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-498-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)); $own = $true }
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$pwsh = (Get-Process -Id $PID).Path
$builds = @{}
foreach ($way in 'csc', 'msbuild') {
    $root = Join-Path $Scratch $way
    $stub = Join-Path $root 'setup-stub.exe'
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    $said = & $pwsh -NoProfile -File $blPath -With $way -Root $root -StubOut $stub -NoSign -NoPause 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $exe = Join-Path $root 'Launcher\Thornswood.exe'
    Yes "Build-Launcher.ps1 -With $way built both exes (exit $rc)" ($rc -eq 0 -and (Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $stub))
    if ($rc -ne 0) { Write-Host $said }
    Yes "-With $way signed nothing (-NoSign)" ($said -match 'not signing: -NoSign')
    $builds[$way] = @{ Exe = $exe; Stub = $stub; Root = $root }
}
if (-not (Test-Path -LiteralPath $builds.csc.Exe) -or -not (Test-Path -LiteralPath $builds.msbuild.Exe)) { Done }

# ---- reading an exe -------------------------------------------------------
# System.Reflection.Metadata, which pwsh 7 carries. Written in C# 5 like the
# launcher, though pwsh's Add-Type would take newer.
if (-not ('Thornswood498.Describe' -as [type])) {
    Add-Type -ReferencedAssemblies @('System.Reflection.Metadata', 'System.Collections.Immutable', 'System.Collections', 'System.Linq', 'System.Security.Cryptography', 'System.Runtime', 'System.Text.Encoding.Extensions') -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text;

namespace Thornswood498 {
    public sealed class Names : ISignatureTypeProvider<string, object> {
        readonly MetadataReader r;
        public Names(MetadataReader r) { this.r = r; }
        public string GetPrimitiveType(PrimitiveTypeCode c) { return c.ToString(); }
        public string GetTypeFromDefinition(MetadataReader m, TypeDefinitionHandle h, byte k) { return Describe.TypeName(m, h); }
        public string GetTypeFromReference(MetadataReader m, TypeReferenceHandle h, byte k) { return Describe.RefName(m, h); }
        public string GetTypeFromSpecification(MetadataReader m, object c, TypeSpecificationHandle h, byte k) { return m.GetTypeSpecification(h).DecodeSignature(this, c); }
        public string GetSZArrayType(string e) { return e + "[]"; }
        public string GetArrayType(string e, ArrayShape s) { return e + "[" + s.Rank + "]"; }
        public string GetByReferenceType(string e) { return e + "&"; }
        public string GetPointerType(string e) { return e + "*"; }
        public string GetPinnedType(string e) { return e + " pinned"; }
        public string GetGenericInstantiation(string g, ImmutableArray<string> a) { return g + "<" + string.Join(",", a) + ">"; }
        public string GetGenericTypeParameter(object c, int i) { return "!" + i; }
        public string GetGenericMethodParameter(object c, int i) { return "!!" + i; }
        public string GetFunctionPointerType(MethodSignature<string> s) { return "fnptr"; }
        public string GetModifiedType(string m, string u, bool req) { return u; }
    }

    public static class Describe {
        public static string TypeName(MetadataReader r, TypeDefinitionHandle h) {
            TypeDefinition t = r.GetTypeDefinition(h);
            string n = r.GetString(t.Name);
            TypeDefinitionHandle outer = t.GetDeclaringType();
            if (!outer.IsNil) return TypeName(r, outer) + "/" + n;
            string ns = r.GetString(t.Namespace);
            return ns.Length > 0 ? ns + "." + n : n;
        }
        public static string RefName(MetadataReader r, TypeReferenceHandle h) {
            TypeReference t = r.GetTypeReference(h);
            string n = r.GetString(t.Name);
            if (t.ResolutionScope.Kind == HandleKind.TypeReference) return RefName(r, (TypeReferenceHandle)t.ResolutionScope) + "/" + n;
            string ns = r.GetString(t.Namespace);
            return ns.Length > 0 ? ns + "." + n : n;
        }
        static bool IsGen(string s) { return s.IndexOf('<') >= 0 || s.IndexOf('$') >= 0; }
        static string Sha(byte[] b) { using (var s = SHA256.Create()) { return BitConverter.ToString(s.ComputeHash(b)).Replace("-", "").ToLowerInvariant(); } }
        static string AttrType(MetadataReader r, CustomAttribute a) {
            if (a.Constructor.Kind == HandleKind.MemberReference) {
                MemberReference m = r.GetMemberReference((MemberReferenceHandle)a.Constructor);
                if (m.Parent.Kind == HandleKind.TypeReference) return RefName(r, (TypeReferenceHandle)m.Parent);
                if (m.Parent.Kind == HandleKind.TypeDefinition) return TypeName(r, (TypeDefinitionHandle)m.Parent);
            } else if (a.Constructor.Kind == HandleKind.MethodDefinition) {
                return TypeName(r, r.GetMethodDefinition((MethodDefinitionHandle)a.Constructor).GetDeclaringType());
            }
            return "?";
        }

        // What both compilers must agree on, one line each, sorted.
        public static string[] Surface(string path) {
            var lines = new List<string>();
            using (var fs = File.OpenRead(path))
            using (var pe = new PEReader(fs)) {
                MetadataReader r = pe.GetMetadataReader();
                var prov = new Names(r);
                PEHeaders hd = pe.PEHeaders;
                lines.Add("pe machine " + hd.CoffHeader.Machine);
                lines.Add("pe corflags " + hd.CorHeader.Flags);
                lines.Add("pe subsystem " + hd.PEHeader.Subsystem + " " + hd.PEHeader.MajorSubsystemVersion + "." + hd.PEHeader.MinorSubsystemVersion);
                lines.Add("pe highentropyva " + ((hd.PEHeader.DllCharacteristics & DllCharacteristics.HighEntropyVirtualAddressSpace) != 0));
                lines.Add("pe dynamicbase " + ((hd.PEHeader.DllCharacteristics & DllCharacteristics.DynamicBase) != 0));
                lines.Add("pe nxcompat " + ((hd.PEHeader.DllCharacteristics & DllCharacteristics.NxCompatible) != 0));
                lines.Add("pe terminalserveraware " + ((hd.PEHeader.DllCharacteristics & DllCharacteristics.TerminalServerAware) != 0));
                int ep = hd.CorHeader.EntryPointTokenOrRelativeVirtualAddress;
                if (ep != 0) {
                    var mh = (MethodDefinitionHandle)MetadataTokens.EntityHandle(ep);
                    MethodDefinition md = r.GetMethodDefinition(mh);
                    lines.Add("entrypoint " + TypeName(r, md.GetDeclaringType()) + "::" + r.GetString(md.Name));
                }
                AssemblyDefinition asm = r.GetAssemblyDefinition();
                lines.Add("assembly " + r.GetString(asm.Name) + " " + asm.Version);
                foreach (var h in asm.GetCustomAttributes()) {
                    CustomAttribute a = r.GetCustomAttribute(h);
                    string t = AttrType(r, a);
                    // What each compiler adds for itself: Debuggable's flags differ between the
                    // two and neither changes what the launcher does.
                    if (t == "System.Diagnostics.DebuggableAttribute") continue;
                    lines.Add("assembly-attr " + t + " " + BitConverter.ToString(r.GetBlobBytes(a.Value)));
                }
                foreach (var h in r.AssemblyReferences) {
                    AssemblyReference a = r.GetAssemblyReference(h);
                    lines.Add("asmref " + r.GetString(a.Name) + " " + a.Version + " " + BitConverter.ToString(r.GetBlobBytes(a.PublicKeyOrToken)));
                }
                foreach (var h in r.ManifestResources) {
                    ManifestResource m = r.GetManifestResource(h);
                    string name = r.GetString(m.Name);
                    byte[] bytes = null;
                    if (m.Implementation.IsNil) {
                        PEMemoryBlock block = pe.GetSectionData(hd.CorHeader.ResourcesDirectory.RelativeVirtualAddress);
                        BlobReader br = block.GetReader((int)m.Offset, block.Length - (int)m.Offset);
                        int len = br.ReadInt32();
                        bytes = br.ReadBytes(len);
                    }
                    lines.Add("resource " + name + " " + m.Attributes + " " + (bytes == null ? "linked" : (bytes.Length + " " + Sha(bytes))));
                }
                foreach (var th in r.TypeDefinitions) {
                    TypeDefinition t = r.GetTypeDefinition(th);
                    string tn = TypeName(r, th);
                    if (IsGen(tn)) continue;
                    // Roslyn marks an interface BeforeFieldInit and the old csc does not.
                    // An interface here has no static constructor, so the flag says nothing.
                    TypeAttributes ta = t.Attributes;
                    if ((ta & TypeAttributes.Interface) != 0) ta &= ~TypeAttributes.BeforeFieldInit;
                    lines.Add("type " + tn + " " + ta);
                    foreach (var mh in t.GetMethods()) {
                        MethodDefinition md = r.GetMethodDefinition(mh);
                        string mn = r.GetString(md.Name);
                        if (IsGen(mn)) continue;
                        MethodSignature<string> sig = md.DecodeSignature(prov, null);
                        lines.Add("method " + tn + "::" + mn + "(" + string.Join(",", sig.ParameterTypes) + ") " + sig.ReturnType + " " + md.Attributes);
                    }
                    foreach (var fh in t.GetFields()) {
                        FieldDefinition fd = r.GetFieldDefinition(fh);
                        string fn = r.GetString(fd.Name);
                        if (IsGen(fn)) continue;
                        lines.Add("field " + tn + "::" + fn + " " + fd.DecodeSignature(prov, null) + " " + fd.Attributes);
                    }
                    foreach (var ph in t.GetProperties()) {
                        PropertyDefinition pd = r.GetPropertyDefinition(ph);
                        lines.Add("property " + tn + "::" + r.GetString(pd.Name));
                    }
                    foreach (var eh in t.GetEvents()) {
                        EventDefinition ed = r.GetEventDefinition(eh);
                        lines.Add("event " + tn + "::" + r.GetString(ed.Name));
                    }
                }
            }
            lines.Sort(StringComparer.Ordinal);
            return lines.ToArray();
        }

        // What each compiler is free to do its own way, for the record.
        public static string[] Generated(string path) {
            var lines = new List<string>();
            using (var fs = File.OpenRead(path))
            using (var pe = new PEReader(fs)) {
                MetadataReader r = pe.GetMetadataReader();
                foreach (var th in r.TypeDefinitions) {
                    string tn = TypeName(r, th);
                    TypeDefinition t = r.GetTypeDefinition(th);
                    foreach (var mh in t.GetMethods()) {
                        string mn = r.GetString(r.GetMethodDefinition(mh).Name);
                        if (IsGen(tn) || IsGen(mn)) lines.Add("generated " + tn + "::" + mn);
                    }
                }
                foreach (var h in r.MemberReferences) {
                    MemberReference m = r.GetMemberReference(h);
                    string parent = m.Parent.Kind == HandleKind.TypeReference ? RefName(r, (TypeReferenceHandle)m.Parent) : m.Parent.Kind.ToString();
                    lines.Add("calls " + parent + "::" + r.GetString(m.Name));
                }
            }
            lines.Sort(StringComparer.Ordinal);
            return lines.Distinct().ToArray();
        }

        // Win32 resources of the given type ids, "type/name/lang sha256", from .rsrc.
        public static string[] Win32(string path, int[] types) {
            var lines = new List<string>();
            using (var fs = File.OpenRead(path))
            using (var pe = new PEReader(fs)) {
                DirectoryEntry dir = pe.PEHeaders.PEHeader.ResourceTableDirectory;
                if (dir.Size == 0) return lines.ToArray();
                PEMemoryBlock block = pe.GetSectionData(dir.RelativeVirtualAddress);
                byte[] rs = block.GetContent().ToArray();
                Walk(pe, rs, dir.RelativeVirtualAddress, 0, 0, "", types, lines);
            }
            lines.Sort(StringComparer.Ordinal);
            return lines.ToArray();
        }
        static void Walk(PEReader pe, byte[] rs, int baseRva, int off, int level, string label, int[] types, List<string> lines) {
            int named = BitConverter.ToUInt16(rs, off + 12), ids = BitConverter.ToUInt16(rs, off + 14);
            for (int i = 0; i < named + ids; i++) {
                int e = off + 16 + i * 8;
                uint name = BitConverter.ToUInt32(rs, e), target = BitConverter.ToUInt32(rs, e + 4);
                string id;
                if ((name & 0x80000000) != 0) { int so = (int)(name & 0x7FFFFFFF); int n = BitConverter.ToUInt16(rs, so); id = Encoding.Unicode.GetString(rs, so + 2, n * 2); }
                else id = name.ToString();
                if (level == 0) { int tid; if (!int.TryParse(id, out tid) || Array.IndexOf(types, tid) < 0) continue; }
                string here = label.Length == 0 ? id : label + "/" + id;
                if ((target & 0x80000000) != 0) { Walk(pe, rs, baseRva, (int)(target & 0x7FFFFFFF), level + 1, here, types, lines); continue; }
                int dataRva = BitConverter.ToInt32(rs, (int)target), size = BitConverter.ToInt32(rs, (int)target + 4);
                byte[] data = pe.GetSectionData(dataRva).GetContent(0, size).ToArray();
                lines.Add(here + " " + size + " " + Sha(data));
            }
        }
        // The icon images by their bytes, and the icon group with each entry's
        // image id left out: the old csc numbers the images from 2, Roslyn from 1,
        // and the group only points at them by that number.
        public static string[] Icons(string path) {
            var lines = new List<string>();
            foreach (string l in Win32(path, new int[] { 3 })) lines.Add("icon " + l.Substring(l.IndexOf(' ') + 1));
            byte[] g = Win32One(path, 14);
            if (g != null) {
                g = (byte[])g.Clone();
                int count = BitConverter.ToUInt16(g, 4);
                for (int i = 0; i < count; i++) { g[6 + i * 14 + 12] = 0; g[6 + i * 14 + 13] = 0; }
                lines.Add("group " + count + " " + Sha(g));
            }
            lines.Sort(StringComparer.Ordinal);
            return lines.ToArray();
        }
        public static byte[] Win32One(string path, int type) {
            using (var fs = File.OpenRead(path))
            using (var pe = new PEReader(fs)) {
                DirectoryEntry dir = pe.PEHeaders.PEHeader.ResourceTableDirectory;
                if (dir.Size == 0) return null;
                byte[] rs = pe.GetSectionData(dir.RelativeVirtualAddress).GetContent().ToArray();
                return Find(pe, rs, 0, 0, type);
            }
        }
        static byte[] Find(PEReader pe, byte[] rs, int off, int level, int type) {
            int named = BitConverter.ToUInt16(rs, off + 12), ids = BitConverter.ToUInt16(rs, off + 14);
            for (int i = 0; i < named + ids; i++) {
                int e = off + 16 + i * 8;
                uint name = BitConverter.ToUInt32(rs, e), target = BitConverter.ToUInt32(rs, e + 4);
                if (level == 0 && ((name & 0x80000000) != 0 || name != (uint)type)) continue;
                if ((target & 0x80000000) != 0) { byte[] b = Find(pe, rs, (int)(target & 0x7FFFFFFF), level + 1, type); if (b != null) return b; continue; }
                int dataRva = BitConverter.ToInt32(rs, (int)target), size = BitConverter.ToInt32(rs, (int)target + 4);
                return pe.GetSectionData(dataRva).GetContent(0, size).ToArray();
            }
            return null;
        }
    }
}
'@
}

function Diff-Lines([string]$what, [string[]]$a, [string[]]$b) {
    $onlyA = @($a | Where-Object { $b -notcontains $_ })
    $onlyB = @($b | Where-Object { $a -notcontains $_ })
    Yes $what ($onlyA.Count -eq 0 -and $onlyB.Count -eq 0)
    foreach ($l in ($onlyA | Select-Object -First 20)) { Write-Host "      csc only:     $l" }
    foreach ($l in ($onlyB | Select-Object -First 20)) { Write-Host "      msbuild only: $l" }
}
function Manifest-Xml([string]$exe) {
    $b = [Thornswood498.Describe]::Win32One($exe, 24)
    if (-not $b) { return '' }
    $t = [Text.Encoding]::UTF8.GetString($b).TrimStart([char]0xFEFF)
    $x = New-Object Xml.XmlDocument
    $x.PreserveWhitespace = $false
    $x.LoadXml($t)
    foreach ($c in @($x.SelectNodes('//comment()'))) { [void]$c.ParentNode.RemoveChild($c) }
    $x.DocumentElement.OuterXml
}

foreach ($kind in @(@{ Key = 'Exe'; Name = 'the launcher' }, @{ Key = 'Stub'; Name = 'the setup program' })) {
    $a = $builds.csc[$kind.Key]; $b = $builds.msbuild[$kind.Key]
    Write-Host ''
    Write-Host "---- $($kind.Name): $([IO.Path]::GetFileName($a))"
    $sa = [Thornswood498.Describe]::Surface($a); $sb = [Thornswood498.Describe]::Surface($b)
    Diff-Lines "$($kind.Name): the same resources, bytes included" @($sa | Where-Object { $_ -like 'resource *' }) @($sb | Where-Object { $_ -like 'resource *' })
    # The old csc keeps a second reference to System.IO.Compression 4.0.0.0
    # beside 4.2.0.0, because System.IO.Compression.FileSystem was built
    # against 4.0.0.0 (its CS1701 warning); Roslyn unifies the two into 4.2.0.0.
    # The runtime unifies framework assemblies to the one installed either
    # way. So: every MSBuild reference is in the csc exe, and a csc-only one
    # is only an older version of an assembly MSBuild references, same key.
    $ra = @($sa | Where-Object { $_ -like 'asmref *' }); $rb = @($sb | Where-Object { $_ -like 'asmref *' })
    $extra = @($ra | Where-Object { $rb -notcontains $_ })
    $unified = @($extra | Where-Object {
        $p = $_ -split ' '
        @($rb | Where-Object { $q = $_ -split ' '; $q[1] -eq $p[1] -and $q[3] -eq $p[3] -and [version]$q[2] -gt [version]$p[2] }).Count -gt 0 })
    Yes "$($kind.Name): the same assembly references, apart from what Roslyn unifies" (@($rb | Where-Object { $ra -notcontains $_ }).Count -eq 0 -and $unified.Count -eq $extra.Count)
    foreach ($l in $extra) { Write-Host "      csc only: $($l.Substring(7))" }
    foreach ($l in @($rb | Where-Object { $ra -notcontains $_ })) { Write-Host "      msbuild only: $($l.Substring(7))" }
    Diff-Lines "$($kind.Name): the same types, methods, fields, properties and events" @($sa | Where-Object { $_ -match '^(type|method|field|property|event) ' }) @($sb | Where-Object { $_ -match '^(type|method|field|property|event) ' })
    Diff-Lines "$($kind.Name): the same assembly, attributes and entry point" @($sa | Where-Object { $_ -match '^(assembly|assembly-attr|entrypoint) ' }) @($sb | Where-Object { $_ -match '^(assembly|assembly-attr|entrypoint) ' })
    Diff-Lines "$($kind.Name): the same PE kind" @($sa | Where-Object { $_ -like 'pe *' }) @($sb | Where-Object { $_ -like 'pe *' })
    Yes "$($kind.Name): no TargetFrameworkAttribute in either" (@($sa + $sb | Where-Object { $_ -like '*TargetFrameworkAttribute*' }).Count -eq 0)
    Yes "$($kind.Name): AnyCPU, not 32 bit preferred, GUI subsystem 4.00, high entropy ASLR off" (
        @($sb | Where-Object { $_ -eq 'pe corflags ILOnly' -or $_ -eq 'pe subsystem WindowsGui 4.0' -or $_ -eq 'pe highentropyva False' }).Count -eq 3)
    $ia = [Thornswood498.Describe]::Icons($a)
    Yes "$($kind.Name): the exe carries an icon group and its images" (@($ia | Where-Object { $_ -like 'group *' }).Count -eq 1 -and @($ia | Where-Object { $_ -like 'icon *' }).Count -ge 1)
    Diff-Lines "$($kind.Name): the same win32 icon, image for image" $ia ([Thornswood498.Describe]::Icons($b))
    $ma = Manifest-Xml $a; $mb = Manifest-Xml $b
    Yes "$($kind.Name): the same application manifest, as XML" ($ma -ne '' -and $ma -eq $mb)
    $va = (Get-Item -LiteralPath $a).VersionInfo; $vb = (Get-Item -LiteralPath $b).VersionInfo
    foreach ($f in 'FileVersion', 'ProductVersion', 'FileDescription', 'ProductName', 'CompanyName', 'LegalCopyright', 'OriginalFilename', 'InternalName') {
        Yes ("$($kind.Name): {0} is the same, '{1}'" -f $f, $vb.$f) ($va.$f -eq $vb.$f)
    }
    $la = (Get-Item -LiteralPath $a).Length; $lb = (Get-Item -LiteralPath $b).Length
    Yes ("$($kind.Name): sizes within five percent, csc {0:n0} and MSBuild {1:n0} bytes" -f $la, $lb) ([Math]::Abs($la - $lb) -le 0.05 * $la)
    $ga = [Thornswood498.Describe]::Generated($a); $gb = [Thornswood498.Describe]::Generated($b)
    Write-Host ("      for the record, not held: compiler made methods csc {0}, MSBuild {1}; outside members called csc {2}, MSBuild {3}" -f
        @($ga | Where-Object { $_ -like 'generated *' }).Count, @($gb | Where-Object { $_ -like 'generated *' }).Count,
        @($ga | Where-Object { $_ -like 'calls *' }).Count, @($gb | Where-Object { $_ -like 'calls *' }).Count)
    foreach ($l in @($ga | Where-Object { $_ -like 'calls *' -and $gb -notcontains $_ })) { Write-Host "      calls only from csc:     $($l.Substring(6))" }
    foreach ($l in @($gb | Where-Object { $_ -like 'calls *' -and $ga -notcontains $_ })) { Write-Host "      calls only from MSBuild: $($l.Substring(6))" }
}

Write-Host ''
$left = @(Get-ChildItem -LiteralPath (Split-Path -Parent $builds.msbuild.Exe) -File | ForEach-Object { $_.Name } | Sort-Object)
Yes ('nothing beside the MSBuild launcher but its pdb: ' + ($left -join ', ')) ((Same $left @('Thornswood.exe', 'Thornswood.pdb')))

foreach ($way in 'csc', 'msbuild') {
    $said = & $pwsh -NoProfile -File (Join-Path $repo 'tests\test-app-manifest.ps1') -Exe $builds[$way].Exe -Stub $builds[$way].Stub -Scratch (Join-Path $Scratch "manifest-$way") 2>&1 | Out-String
    Yes "tests\test-app-manifest.ps1 passes on the $way pair" ($LASTEXITCODE -eq 0)
    if ($LASTEXITCODE -ne 0) { Write-Host $said }
}
$said = & (Join-Path $repo 'scripts\dev\Check-Secrets.ps1') -Binary @($builds.msbuild.Exe, $builds.msbuild.Stub) 2>&1 | Out-String
Yes 'scripts\dev\Check-Secrets.ps1 -Binary passes on the MSBuild pair' ($LASTEXITCODE -eq 0)
if ($LASTEXITCODE -ne 0) { Write-Host $said }

if ($own) { Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue }
Done
