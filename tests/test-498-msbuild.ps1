<#
  test-498-msbuild.ps1

      pwsh -NoProfile -File .\tests\test-498-msbuild.ps1
      pwsh -NoProfile -File .\tests\test-498-msbuild.ps1 -RequireMSBuild      (the build check)
      pwsh -NoProfile -File .\tests\test-498-msbuild.ps1 -Scratch <folder>    keeps the build there

  Issue #498, Patrick's option C on 11 Oct, switched 15 Oct: the launcher and
  the setup program are built only by MSBuild from launcher\app\
  Thornswood.csproj and installer\setup\Setup.csproj. Until the switch this
  harness built them both ways and held the MSBuild pair to the in-box csc
  pair; that comparison is done (the figures are on #498), so now it holds the
  one build to what that comparison proved:

    1. as text, everywhere, MSBuild or not: both project files target .NET
       Framework 4.8.1 at C# 13.0, write no TargetFrameworkAttribute, restore
       nothing, keep WebView2 out of the output folder, embed exactly the
       resources the launcher's code reads by name; and the build has one way
       only (no -With, no in-box csc, no Ship -LauncherWith);
    2. Build-Launcher.ps1 builds both exes, unsigned, into scratch;
    3. each embedded resource is byte for byte its file in the repository;
    4. the references are the framework assemblies and WebView2, and nothing
       restored;
    5. the PE kind (AnyCPU, not 32 bit preferred, GUI subsystem 4.00, high
       entropy ASLR off), no TargetFrameworkAttribute, the entry point;
    6. the file details Windows shows carry Updater.cs's version, and the
       application manifest's identity carries it too;
    7. a win32 icon, nothing beside the launcher but its pdb, and
       tests\test-app-manifest.ps1 and scripts\dev\Check-Secrets.ps1 -Binary
       pass on the pair.

  Without MSBuild on the machine part 1 still runs and the rest says SKIP;
  -RequireMSBuild makes that a failure instead, which is how the build check
  calls it.

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

# ---- 1. the inputs, as text ----------------------------------------------
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

# The resources the launcher's code reads by name (Art.cs, Voice.cs,
# ThornIni.cs, ClientRuntime.cs, OwnGame.cs, Shell.cs): the list the two
# builds were compared on, and the file in the repository each one is.
$appResources = [ordered]@{
    'ui.xaml'                         = 'launcher\ui.xaml'
    'logo.png'                        = 'launcher\logo.png'
    'logo-dev.png'                    = 'launcher\logo-dev.png'
    'launcher-header.jpg'             = 'launcher\launcher-header.jpg'
    'launcher-header.mp4'             = 'launcher\launcher-header.mp4'
    'app.ico'                         = 'launcher\app.ico'
    'app-dev.ico'                     = 'launcher\app-dev.ico'
    'Microsoft.Web.WebView2.Core.dll' = 'launcher\lib\webview2\Microsoft.Web.WebView2.Core.dll'
    'Microsoft.Web.WebView2.Wpf.dll'  = 'launcher\lib\webview2\Microsoft.Web.WebView2.Wpf.dll'
    'WebView2Loader.dll'              = 'launcher\lib\webview2\WebView2Loader.dll'
    'voice-host.html'                 = 'launcher\voice-host.html'
    'Thornswood.ini'                  = 'launcher\Thornswood.ini'
    'client-build.json'               = 'records\client-build.json'
    'skyrim-files.json'               = 'records\skyrim-files.json'
    'ui-gone.json'                    = 'records\ui-gone.json'
}
$setupResources = [ordered]@{ 'logo.png' = 'launcher\logo-192.png' }
$frameworkRefs = @('System', 'System.Core', 'System.Drawing', 'System.Runtime.Serialization', 'System.Xml', 'System.Security',
                   'System.IO.Compression', 'System.IO.Compression.FileSystem', 'PresentationFramework', 'PresentationCore',
                   'WindowsBase', 'System.Xaml', 'System.Windows.Forms')

Yes ('the launcher project embeds exactly the resources the code reads: ' + (@(Names $appProj '//m:EmbeddedResource/m:LogicalName') -join ', ')) (
    Same @(Names $appProj '//m:EmbeddedResource/m:LogicalName') @($appResources.Keys))
Yes 'the setup project embeds logo-192.png as logo.png' ((Same @(Names $setupProj '//m:EmbeddedResource/m:LogicalName') @('logo.png')) -and
    (@(Attr $setupProj '//m:EmbeddedResource/@Include') -join '') -match 'logo-192\.png$')
Yes 'the launcher project references the framework assemblies and WebView2' (
    Same @(Attr $appProj '//m:Reference/@Include') (@($frameworkRefs) + 'Microsoft.Web.WebView2.Core', 'Microsoft.Web.WebView2.Wpf'))
Yes 'the setup project references the same framework assemblies' (Same @(Attr $setupProj '//m:Reference/@Include') $frameworkRefs)
Yes 'WebView2 is never copied beside the exe (Private false on both)' (
    @(Select-Xml -Xml $appProj -XPath "//m:Reference[starts-with(@Include,'Microsoft.Web.WebView2')]/m:Private" -Namespace $ns | Where-Object { $_.Node.InnerText -eq 'false' }).Count -eq 2)
foreach ($pair in @(@{ Doc = $appProj; Name = 'launcher' }, @{ Doc = $setupProj; Name = 'setup' })) {
    $d = $pair.Doc
    Yes "the $($pair.Name) project is at C# 13.0 (the C# 5 rule lifted with the switch)" ((Names $d '//m:LangVersion') -join '' -eq '13.0')
    Yes "the $($pair.Name) project targets .NET Framework 4.8.1" ((Names $d '//m:TargetFrameworkVersion') -join '' -eq 'v4.8.1')
    Yes "the $($pair.Name) project writes no TargetFrameworkAttribute" ((Names $d '//m:GenerateTargetFrameworkAttribute') -join '' -eq 'false')
    Yes "the $($pair.Name) project has no PackageReference (nothing restored, nothing loose)" (@(Select-Xml -Xml $d -XPath '//m:PackageReference' -Namespace $ns).Count -eq 0)
}

# One way to build.
Yes 'Build-Launcher.ps1 has no -With: MSBuild is the only build' ($bl -notmatch '\$With\b' -and $bl -notmatch "ValidateSet\('csc'")
Yes 'and no in-box csc and no hand-resolved references' ($bl -notmatch 'v4\.0\.30319' -and $bl -notmatch '\$refDirs' -and $bl -notmatch 'Find-Ref')
Yes 'and builds both project files with the MSBuild Find-MSBuild.ps1 finds' (
    $bl.Contains("& `$found.MSBuild (Resolve-Path -LiteralPath `$proj).Path") -and $bl.Contains("& `$found.MSBuild (Resolve-Path -LiteralPath `$stubProj).Path"))
$ship = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Ship.ps1'))
Yes 'Ship has no -LauncherWith any more and calls Build-Launcher.ps1 without -With' ($ship -notmatch 'LauncherWith' -and $ship -notmatch 'Build-Launcher\.ps1[^\r\n]*-With')
foreach ($wf in 'release.yml', 'build.yml', 'build-pr.yml', 'nightly.yml') {
    $t = [IO.File]::ReadAllText((Join-Path $repo ".github\workflows\$wf"))
    Yes "$wf passes no -With to Build-Launcher.ps1" ($t -notmatch 'Build-Launcher\.ps1[^\r\n]*-With')
}

# ---- 2 to 7 need MSBuild --------------------------------------------------
. (Join-Path $repo 'scripts\release\Find-MSBuild.ps1') -Load
$found = Find-ThornswoodMSBuild
if (-not $found.MSBuild -or -not $found.RefAssemblies) {
    $why = 'no MSBuild from Visual Studio 2022 or its Build Tools with the .NET Framework 4.8.1 targeting pack on this machine'
    if ($RequireMSBuild) { Yes "MSBuild is here ($why)" $false }
    else { Skip "the build and its checks: $why" }
    Done
}
Write-Host "      MSBuild $($found.MSBuild)"

$own = $false
if (-not $Scratch) { $Scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-498-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)); $own = $true }
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$pwsh = (Get-Process -Id $PID).Path
$root = Join-Path $Scratch 'build'
$stub = Join-Path $root 'setup-stub.exe'
$exe = Join-Path $root 'Launcher\Thornswood.exe'
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
$said = & $pwsh -NoProfile -File $blPath -Root $root -StubOut $stub -NoSign -NoPause 2>&1 | Out-String
$rc = $LASTEXITCODE
Yes "Build-Launcher.ps1 built both exes (exit $rc)" ($rc -eq 0 -and (Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $stub))
if ($rc -ne 0) { Write-Host $said }
Yes 'it signed nothing (-NoSign)' ($said -match 'not signing: -NoSign')
if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $stub)) { Done }

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

function Manifest-Xml([string]$path) {
    $b = [Thornswood498.Describe]::Win32One($path, 24)
    if (-not $b) { return $null }
    $t = [Text.Encoding]::UTF8.GetString($b).TrimStart([char]0xFEFF)
    $x = New-Object Xml.XmlDocument
    $x.PreserveWhitespace = $false
    $x.LoadXml($t)
    $x
}
function Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

$updater = [IO.File]::ReadAllText((Join-Path $repo 'launcher\app\Updater.cs'))
$ver = [regex]::Match($updater, 'Version\s*=\s*"([0-9.]+)"').Groups[1].Value
$verFour = $ver
while (($verFour -split '\.').Count -lt 4) { $verFour = "$verFour.0" }

foreach ($kind in @(@{ Path = $exe; Name = 'the launcher'; Res = $appResources; File = 'Thornswood.exe' },
                    @{ Path = $stub; Name = 'the setup program'; Res = $setupResources; File = 'Thornswood-Setup.exe' })) {
    $p = $kind.Path
    Write-Host ''
    Write-Host "---- $($kind.Name): $([IO.Path]::GetFileName($p))"
    $s = [Thornswood498.Describe]::Surface($p)
    $want = @($kind.Res.Keys | ForEach-Object { 'resource ' + $_ + ' Public ' + (Get-Item -LiteralPath (Join-Path $repo $kind.Res[$_])).Length + ' ' + (Sha (Join-Path $repo $kind.Res[$_])) })
    $have = @($s | Where-Object { $_ -like 'resource *' })
    $off = @($want | Where-Object { $have -notcontains $_ }) + @($have | Where-Object { $want -notcontains $_ })
    Yes "$($kind.Name): every embedded resource is byte for byte its file in the repository" ($off.Count -eq 0)
    foreach ($l in ($off | Select-Object -First 20)) { Write-Host "      differs: $l" }
    $refs = @($s | Where-Object { $_ -like 'asmref *' } | ForEach-Object { ($_ -split ' ')[1] })
    $allowed = @('mscorlib') + $frameworkRefs + @('Microsoft.Web.WebView2.Core', 'Microsoft.Web.WebView2.Wpf')
    Yes ("$($kind.Name): references only the framework and WebView2: " + ($refs -join ', ')) (@($refs | Where-Object { $allowed -notcontains $_ }).Count -eq 0)
    Yes "$($kind.Name): no TargetFrameworkAttribute" (@($s | Where-Object { $_ -like '*TargetFrameworkAttribute*' }).Count -eq 0)
    Yes "$($kind.Name): AnyCPU, not 32 bit preferred, GUI subsystem 4.00, high entropy ASLR off" (
        @($s | Where-Object { $_ -eq 'pe corflags ILOnly' -or $_ -eq 'pe subsystem WindowsGui 4.0' -or $_ -eq 'pe highentropyva False' }).Count -eq 3)
    Yes "$($kind.Name): it has an entry point" (@($s | Where-Object { $_ -like 'entrypoint *' }).Count -eq 1)
    $ic = [Thornswood498.Describe]::Icons($p)
    Yes "$($kind.Name): the exe carries an icon group and its images" (@($ic | Where-Object { $_ -like 'group *' }).Count -eq 1 -and @($ic | Where-Object { $_ -like 'icon *' }).Count -ge 1)
    $vi = (Get-Item -LiteralPath $p).VersionInfo
    Yes ("$($kind.Name): FileVersion is Updater.cs's, {0}" -f $vi.FileVersion) ($vi.FileVersion -eq $verFour)
    Yes ("$($kind.Name): ProductVersion is Updater.cs's, {0}" -f $vi.ProductVersion) ($vi.ProductVersion -eq $ver)
    Yes ("$($kind.Name): OriginalFilename is the name it ships under, {0}" -f $vi.OriginalFilename) ($vi.OriginalFilename -eq $kind.File)
    $m = Manifest-Xml $p
    $ident = if ($m) { $m.DocumentElement.SelectSingleNode("*[local-name()='assemblyIdentity']") } else { $null }
    Yes ("$($kind.Name): the manifest's identity carries the same version, {0}" -f $(if ($ident) { $ident.GetAttribute('version') } else { 'none' })) ($null -ne $ident -and $ident.GetAttribute('version') -eq $verFour)
}

Write-Host ''
$left = @(Get-ChildItem -LiteralPath (Split-Path -Parent $exe) -File | ForEach-Object { $_.Name } | Sort-Object)
Yes ('nothing beside the launcher but its pdb: ' + ($left -join ', ')) ((Same $left @('Thornswood.exe', 'Thornswood.pdb')))

$said = & $pwsh -NoProfile -File (Join-Path $repo 'tests\test-app-manifest.ps1') -Exe $exe -Stub $stub -Scratch (Join-Path $Scratch 'manifest') 2>&1 | Out-String
Yes 'tests\test-app-manifest.ps1 passes on the pair' ($LASTEXITCODE -eq 0)
if ($LASTEXITCODE -ne 0) { Write-Host $said }
$said = & (Join-Path $repo 'scripts\dev\Check-Secrets.ps1') -Binary @($exe, $stub) 2>&1 | Out-String
Yes 'scripts\dev\Check-Secrets.ps1 -Binary passes on the pair' ($LASTEXITCODE -eq 0)
if ($LASTEXITCODE -ne 0) { Write-Host $said }

if ($own) { Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue }
Done
