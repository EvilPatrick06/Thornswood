<#
  test-installer-own-payload.ps1

  The installer unpacks its own payload or the site's, never a zip it finds
  lying about.

  25 September: a new tester ran the installer from the site and got the new
  setup window with an old multiplayer mod's setup and a very old launcher
  inside it. He had old installer zips in his Downloads folder. Bootstrap.cs
  looked for the old setup zip, payload.zip, Thornswood-Setup.zip and
  the biggest Thornswood-Setup*.zip or old setup zip beside itself
  and then in Downloads, took the first it found before the payload attached
  to it and before asking the site, and unpacked it with no check. The site's
  download is checked against its SHA-256 (test-payload-hash.ps1); a loose zip
  never was.

  This compiles the real Locate out of Bootstrap.cs, with the compiler the
  build runs (Add-LauncherType, tests\Launcher-Csc.ps1, #2821; off Windows it
  says SKIP, the build's compiler is only there), and gives it a stand-in
  installer with old zips beside it, with and without a payload attached, and
  reads Work and ShowWhatWasFound for where the payload can come from.
  Pointed at the file before the fix, the loose zip checks fail:

    pwsh -File tests\test-installer-own-payload.ps1 -BootstrapPath <old Bootstrap.cs>

  Read only. Everything it makes is under a temp folder it removes.
#>
[CmdletBinding()]
param([string]$BootstrapPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $BootstrapPath) { $BootstrapPath = Join-Path $Here 'installer\setup\Bootstrap.cs' }
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#2821)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bs = Get-Content -LiteralPath $BootstrapPath -Raw

# A C# method by its head and a brace match that steps over strings and line
# comments, the same reader test-payload-hash.ps1 uses.
function Get-Method([string]$text, [string]$head) {
    $at = $text.IndexOf($head)
    if ($at -lt 0) { return '' }
    $i = $text.IndexOf('{', $at)
    if ($i -lt 0) { return '' }
    $depth = 0
    while ($i -lt $text.Length) {
        $c = $text[$i]
        if ($c -eq '"' -or $c -eq "'") {
            $q = $c
            $i++
            while ($i -lt $text.Length -and $text[$i] -ne $q) {
                if ($text[$i] -eq '\') { $i++ }
                $i++
            }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '/') {
            $nl = $text.IndexOf("`n", $i)
            if ($nl -lt 0) { return '' }
            $i = $nl
        }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) }
        }
        $i++
    }
    return ''
}

# The code with its line comments taken out, so a comment that names the old
# zips to say why they are not used is not read as code that looks for them.
function Get-Code([string]$text) {
    return (($text -split "`n") | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
}

$locate = Get-Method $bs 'static Payload Locate('
$workBody = Get-Method $bs 'static void Work('
$shown  = Get-Method $bs 'static void ShowWhatWasFound('
Yes 'Locate is in Bootstrap.cs' ($locate.Length -gt 0)
Yes 'Work is in Bootstrap.cs' ($workBody.Length -gt 0)
Yes 'ShowWhatWasFound is in Bootstrap.cs' ($shown.Length -gt 0)

# ---- read: where a payload can come from -------------------------------------

$code = Get-Code $bs
Yes 'nothing in the installer reads the Downloads folder' (
    $code.IndexOf('Downloads') -lt 0 -and $code.IndexOf('SpecialFolder.UserProfile') -lt 0)
Yes 'and nothing looks for a zip by name' (
    $code.IndexOf('-Setup.zip"') -lt 0 -and $code.IndexOf('"payload.zip"') -lt 0 -and
    $code.IndexOf('Thornswood-Setup*.zip') -lt 0 -and $code.IndexOf('"Thornswood-Setup.zip"') -lt 0)

# Work unpacks what Locate found in this program or what Download fetched and
# checked, and nothing else.
$workCode = Get-Code $workBody
$sources = [regex]::Matches($workCode, 'new Payload\b').Count
Yes 'Work takes the payload from Locate on this program' ($workCode.Contains('Payload pay = Locate(exe);'))
Yes 'or from the checked download, and from nowhere else' (
    $workCode.Contains('Download(temp)') -and $sources -eq 1 -and
    $workCode.IndexOf('new Payload { File = got,') -ge 0)

# The setup window says what it will unpack. It never names a file off the disk,
# because the only file it can use is itself.
Yes 'the setup window never names a zip it found on the disk' (
    $shown.Length -gt 0 -and $shown.IndexOf('GetFileName(found.File)') -lt 0 -and
    $shown.IndexOf('GetDirectoryName(found.File)') -lt 0)

# ---- run: the real Locate ----------------------------------------------------

# The old file needs its zip finder and name lists to compile; the new one has
# neither, so each is lifted only when it is there.
$findZip = Get-Method $bs 'static string FindZip('
$lists = @()
foreach ($m in [regex]::Matches($bs, '(?s)static readonly string\[\] Payload(Names|Globs)\s*=\s*\{.*?\};')) { $lists += $m.Value }
$magic = [regex]::Match($bs, 'const string Magic = "[^"]*";').Value
$trail = [regex]::Match($bs, 'const int TrailerLen = \d+;').Value
Yes 'the trailer the packager writes is described in Bootstrap.cs' ($magic.Length -gt 0 -and $trail.Length -gt 0)

$members = @($magic, $trail) + $lists + @($findZip, $locate) | Where-Object { $_ } | ForEach-Object {
    'public ' + [string]$_
}
$cs = @"
using System;
using System.IO;
using System.Text;
public class ThornswoodOwnPayload_Payload
{
    public string File;
    public long Offset;
    public long Length;
}
public static class ThornswoodOwnPayload
{
$(($members -join "`n`n").Replace('new Payload', 'new ThornswoodOwnPayload_Payload').Replace('static Payload ', 'static ThornswoodOwnPayload_Payload '))
}
"@
$compiled = $false
if (-not $OnWindows) {
    Write-Host 'SKIP  the real Locate, compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'
}
else {
    try { $null = Add-LauncherType -Source $cs; $compiled = $true }
    catch { Write-Host ("      " + $_.Exception.Message) }
    Yes 'Locate compiles as it is in Bootstrap.cs, with the compiler the build runs' $compiled
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-own-payload-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    if ($compiled) {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        # A zip whose Setup.bat says which one it is, so what was picked is
        # read from inside it rather than taken on its name.
        function New-Zip([string]$path, [string]$which) {
            $fs = [IO.File]::Create($path)
            try {
                $z = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
                $e = $z.CreateEntry('Setup.bat')
                $w = New-Object IO.StreamWriter($e.Open())
                $w.Write('rem ' + $which)
                $w.Dispose()
                $z.Dispose()
            } finally { $fs.Dispose() }
        }
        function Which([object]$p) {
            if ($null -eq $p) { return '' }
            $fs = [IO.File]::OpenRead($p.File)
            try {
                $buf = New-Object byte[] ([int]$p.Length)
                $fs.Position = $p.Offset
                $got = 0
                while ($got -lt $buf.Length) {
                    $r = $fs.Read($buf, $got, $buf.Length - $got)
                    if ($r -le 0) { break }
                    $got += $r
                }
                $ms = New-Object IO.MemoryStream(, $buf)
                $z = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Read)
                try {
                    $r2 = New-Object IO.StreamReader($z.GetEntry('Setup.bat').Open())
                    $t = $r2.ReadToEnd(); $r2.Dispose()
                    return $t.Substring(4)
                } finally { $z.Dispose() }
            } catch { return '?' } finally { $fs.Dispose() }
        }
        # The installer as a person has it: a Windows program, and for a one
        # file build the payload and the 24 byte trailer on its end, then
        # optionally a signature after that.
        function New-Installer([string]$path, [string]$attach, [int]$signature) {
            $stub = New-Object byte[] 40000
            (New-Object Random 7).NextBytes($stub)
            $stub[0] = 0x4D; $stub[1] = 0x5A
            [IO.File]::WriteAllBytes($path, $stub)
            if (-not $attach) { return }
            $fs = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write)
            try {
                $off = $fs.Position
                $zb = [IO.File]::ReadAllBytes($attach)
                $fs.Write($zb, 0, $zb.Length)
                $bw = New-Object IO.BinaryWriter($fs)
                $bw.Write([Text.Encoding]::ASCII.GetBytes('TWSFX001'))
                $bw.Write([long]$off)
                $bw.Write([long]$zb.Length)
                if ($signature) { $bw.Write((New-Object byte[] $signature)) }
                $bw.Flush()
            } finally { $fs.Dispose() }
        }

        $T = [ThornswoodOwnPayload]
        $old = @('OldMod-Setup.zip', 'payload.zip', 'Thornswood-Setup.zip',
                 'Thornswood-Setup-20260915-1639.zip', 'Thornswood-Setup-20260915-1639 (1).zip',
                 'OldMod-Setup-20260901.zip')

        # 1. The small installer the site hands out, run from a folder with
        #    every old zip in it.
        $dl = Join-Path $work 'Downloads'
        New-Item -ItemType Directory -Path $dl -Force | Out-Null
        foreach ($n in $old) { New-Zip (Join-Path $dl $n) ('old ' + $n) }
        $stubExe = Join-Path $dl 'Thornswood-Setup-20260925-0100.exe'
        New-Installer $stubExe '' 0
        $p = $T::Locate($stubExe)
        Yes 'the small installer beside old zips finds nothing, so it fetches the site''s' ($null -eq $p)
        if ($p) { Write-Host ('      it took ' + $p.File + ', which says: ' + (Which $p)) }

        # 2. A one file installer in the same folder.
        $own = Join-Path $work 'own.zip'
        New-Zip $own 'attached'
        $oneExe = Join-Path $dl 'Thornswood-Setup-20260925-0200.exe'
        New-Installer $oneExe $own 0
        $p = $T::Locate($oneExe)
        Yes 'a one file installer beside old zips unpacks its own payload' ($null -ne $p -and $p.File -eq $oneExe)
        Yes 'and what it reads is the zip attached to it' ((Which $p) -eq 'attached')
        if ($p -and $p.File -ne $oneExe) { Write-Host ('      it took ' + $p.File) }

        # 3. Signed: the certificate goes on after the trailer.
        $signedExe = Join-Path $dl 'Thornswood-Setup-20260925-0300.exe'
        New-Installer $signedExe $own 9000
        $p = $T::Locate($signedExe)
        Yes 'signed, it still finds its own payload behind the signature' ($null -ne $p -and $p.File -eq $signedExe -and (Which $p) -eq 'attached')

        # 4. Alone in an empty folder, as it was always meant to run.
        $clean = Join-Path $work 'clean'
        New-Item -ItemType Directory -Path $clean -Force | Out-Null
        $cleanExe = Join-Path $clean 'Thornswood-Setup.exe'
        New-Installer $cleanExe '' 0
        Yes 'alone, the small installer finds nothing and fetches' ($null -eq $T::Locate($cleanExe))
        $cleanOne = Join-Path $clean 'Thornswood-Setup-one.exe'
        New-Installer $cleanOne $own 0
        $p = $T::Locate($cleanOne)
        Yes 'alone, the one file installer finds its own' ($null -ne $p -and (Which $p) -eq 'attached')
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
