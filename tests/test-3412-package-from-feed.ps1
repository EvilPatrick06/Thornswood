<#
  test-3412-package-from-feed.ps1

      pwsh -NoProfile -File .\tests\test-3412-package-from-feed.ps1

  The installer built from main's feed, on any machine (#3412, part of
  #2862). A main Ship from the cloud stopped at the installer gate, because
  Package-Thornswood.ps1 packed the built install at C:\Thornswood with
  Vortex's record beside it, which only One has. -FromFeed builds it from
  what the site holds instead.

  What this proves, against a stand-in site (THORNSWOOD_TEST_SITE_DIR):
    1. Test-PeCertificateTable reads a signature off the file itself: a
       stand-in launcher with no certificate table reads unsigned, the same
       file with one reads signed, and something that is not a PE reads
       unsigned.
    2. -FromFeed refuses without -NoPublish (nothing signs it yet) and
       without -Stub (CI's setup program), before anything is fetched.
    3. A whole build: the installer carries the files main's newest release
       recorded and nothing a folder had before (a stray file, a plugin the
       record does not name), the launcher main's feed offers, the client
       file of that launcher's own record rather than the checkout's, the
       plugin list the release recorded, collection.txt because the feed
       names a collection, vanilla.json from records\skyrim-files.json by
       SHA-1, Setup.bat with CRLF line ends, and a note naming the release.
       The archive is .NET's zip, read back here the way Bootstrap.cs reads
       it.
    4. A feed whose newest release is not the one its record names, and a
       record that names no plugin list, are refused with nothing built.

  Nothing connects anywhere, and everything it writes is in its own temp
  folder. The stand-in launcher is compiled with the C# compiler PowerShell
  7 carries for Add-Type, so this runs off Windows as well.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$rel = Join-Path $repo 'scripts\release'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}
function Put([string]$path, $content) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    if ($content -is [byte[]]) { [IO.File]::WriteAllBytes($path, $content) }
    else { [IO.File]::WriteAllText($path, [string]$content, (New-Object Text.UTF8Encoding($false))) }
}
function ShaBytes([byte[]]$b) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return -join ($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) } finally { $h.Dispose() }
}
function Utf8([string]$s) { return [Text.Encoding]::UTF8.GetBytes($s) }
# MZ and then $n zero bytes, as one byte array.
function MzBytes([int]$n) { $b = [byte[]]::new(2 + $n); $b[0] = 0x4D; $b[1] = 0x5A; return , $b }

if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'SKIP  Package-Thornswood runs under PowerShell 7, and the stand-in launcher is compiled with its C# compiler'; Done }

# ---- the package script's own function, lifted out ---------------------------
$pkgPath = Join-Path $rel 'Package-Thornswood.ps1'
$tok = $null; $err = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($pkgPath, [ref]$tok, [ref]$err)
Yes 'Package-Thornswood.ps1 parses' (@($err).Count -eq 0)
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-PeCertificateTable' }, $true)
Yes 'Package-Thornswood.ps1 has Test-PeCertificateTable' ($null -ne $fn)
if ($null -eq $fn) { Done }
. ([scriptblock]::Create($fn.Extent.Text))

# A .NET exe with client-build.json embedded, as Build-Launcher embeds it
# (Package-ClientRecord.ps1 Read-LauncherClientRecord reads it back).
function New-StandInLauncher([string]$Out, [byte[]]$Record) {
    Add-Type -TypeDefinition 'public static class Ts3412Probe { }'
    $trees = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]'
    $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText('class P { static void Main() { } }'))
    $refs = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]'
    $refs.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile([object].Assembly.Location))
    $opt = New-Object Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions([Microsoft.CodeAnalysis.OutputKind]::ConsoleApplication)
    $comp = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('Thornswood', $trees, $refs, $opt)
    $res = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.ResourceDescription]'
    $res.Add((New-Object Microsoft.CodeAnalysis.ResourceDescription('client-build.json', [Func[IO.Stream]]{ New-Object IO.MemoryStream(, $Record) }.GetNewClosure(), $true)))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
    $fs = [IO.File]::Create($Out)
    try { $r = $comp.Emit($fs, $null, $null, $null, $res) } finally { $fs.Dispose() }
    if (-not $r.Success) { throw ('the stand-in launcher did not compile: ' + (($r.Diagnostics | ForEach-Object { $_.ToString() }) -join ' | ')) }
}

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ('ts-3412-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$keepEnv = @{ SITE = $env:THORNSWOOD_TEST_SITE_DIR; HARNESS = $env:THORNSWOOD_HARNESS; VPS = $env:THORNSWOOD_VPS }
try {
    # ---- the launcher's own client record: the checkout's fork, another file ----
    $checkoutClient = [IO.File]::ReadAllText((Join-Path $repo 'records\client-build.json')) | ConvertFrom-Json
    $clientRel = 'Data\Platform\Plugins\skymp5-client.js'
    $clientBytes = Utf8 "// the client the packed launcher was built with`r`n"
    $launcherRecord = [ordered]@{
        fork = [string]$checkoutClient.fork; forkBranch = [string]$checkoutClient.forkBranch
        forkCommit = [string]$checkoutClient.forkCommit; upstreamBase = [string]$checkoutClient.upstreamBase
        files = [ordered]@{ $clientRel = [ordered]@{ sha256 = (ShaBytes $clientBytes); bytes = $clientBytes.Length } }
    }
    $launcherExe = Join-Path $Scratch 'build\Thornswood.exe'
    New-StandInLauncher $launcherExe (Utf8 (([pscustomobject]$launcherRecord) | ConvertTo-Json -Depth 5))
    $launcherBytes = [IO.File]::ReadAllBytes($launcherExe)

    # ---- 1. a signature, read off the file ----------------------------------------
    Write-Host ''; Write-Host 'a signature, read off the file'
    Yes 'the stand-in launcher has no certificate table' (-not (Test-PeCertificateTable $launcherExe))
    $signed = Join-Path $Scratch 'signed.exe'
    $b = [byte[]]$launcherBytes.Clone()
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    $magic = [BitConverter]::ToUInt16($b, $pe + 24)
    $dirs = if ($magic -eq 0x20B) { $pe + 24 + 112 } else { $pe + 24 + 96 }
    [Array]::Copy([BitConverter]::GetBytes([uint32]4096), 0, $b, $dirs + 32, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]512), 0, $b, $dirs + 36, 4)
    [IO.File]::WriteAllBytes($signed, $b)
    Yes '  and with one it reads signed' (Test-PeCertificateTable $signed)
    $notPe = Join-Path $Scratch 'not-pe.exe'; Put $notPe (MzBytes 200)
    Yes 'a file that is not a PE reads unsigned' (-not (Test-PeCertificateTable $notPe))

    # ---- the stand-in site --------------------------------------------------------
    $site = Join-Path $Scratch 'site'
    $assets = Join-Path $site 'feed\assets'
    function Asset([byte[]]$bytes) { $s = ShaBytes $bytes; Put (Join-Path $assets $s) $bytes; return $s }
    $lSha = Asset $launcherBytes
    $cSha = Asset $clientBytes
    $esp = [byte[]](0x54, 0x45, 0x53, 0x34, 0x00, 0x01, 0x02, 0x03)
    $espSha = Asset $esp
    $js = Utf8 "// the emotes plugin as the release carried it`r`n"
    $jsSha = Asset $js
    $plugins = Utf8 "*Skyrim.esm`r`n*Thornswood-Content.esp`r`n*Thornswood-Last.esp`r`n"
    $pSha = Asset $plugins
    $order = Utf8 "Skyrim.esm`r`nThornswood-Content.esp`r`nThornswood-Last.esp`r`n"
    $oSha = Asset $order
    function New-Record([bool]$golden) {
        $m = [ordered]@{ ':record:files' = '1' }
        if ($golden) {
            $m[':golden:plugins.txt'] = ('{0}:{1}' -f $plugins.Length, $pSha)
            $m[':golden:loadorder.txt'] = ('{0}:{1}' -f $order.Length, $oSha)
        }
        $m['Data\Thornswood-Content.esp'] = ('{0}:{1}' -f $esp.Length, $espSha)
        $m['Data\Platform\Plugins\thornswood-emotes.js'] = ('{0}:{1}' -f $js.Length, $jsSha)
        # The release carried another client; the installer follows its launcher.
        $m[$clientRel] = ('{0}:{1}' -f 3, ('ab' * 32))
        return (Asset (Utf8 (([pscustomobject]$m) | ConvertTo-Json)))
    }
    function Set-Feed([string]$recordSha, [string]$newest = '20261026-120000', [string]$recordId = '20261026-120000') {
        $feed = [ordered]@{
            launcherVersion = '1.2.6'; launcherUrl = "https://thornswood.net/feed/assets/$lSha"; launcherSha256 = $lSha
            packs = @(); collectionUrl = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf'; collectionRevision = 2
            serverAddress = '192.0.2.7'; serverPort = 7777; siteUrl = 'https://thornswood.net'
            release = [ordered]@{ id = $newest; channel = 'main' }
            baseline = [ordered]@{ id = $recordId; sha256 = $recordSha; url = "https://thornswood.net/feed/assets/$recordSha"; entries = 3 }
        }
        Put (Join-Path $site 'feed\version\00000001.json') (([pscustomobject]$feed) | ConvertTo-Json -Depth 5)
    }
    $stub = Join-Path $Scratch 'ci\setup-stub.exe'
    Put $stub (MzBytes 4094)

    $env:THORNSWOOD_TEST_SITE_DIR = $site
    $env:THORNSWOOD_HARNESS = '1'
    $env:THORNSWOOD_VPS = 'harness.invalid'
    $Shell = (Get-Process -Id $PID).Path
    $root = Join-Path $Scratch 'feed-root'
    function Package([string]$Out, [string[]]$Extra) {
        $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $pkgPath, '-FromFeed', '-Root', $root, '-OutDir', $Out, '-NoPause') + $Extra
        $oldE = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $o = (& $Shell @a 2>&1 | Out-String); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $oldE }
        return [pscustomobject]@{ Code = $code; Out = $o; Squashed = ($o -replace '[\s|]', '') }
    }

    # ---- 2. what -FromFeed refuses before it fetches -------------------------------
    Write-Host ''; Write-Host 'what -FromFeed refuses first'
    Set-Feed (New-Record $true)
    $r = Package (Join-Path $Scratch 'out-a') @('-Stub', $stub)
    Yes ("without -NoPublish it stops (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Squashed -match 'Add-NoPublish')
    Yes '  having fetched nothing' (-not (Test-Path -LiteralPath (Join-Path $root 'Game')))
    $r = Package (Join-Path $Scratch 'out-b') @('-NoPublish')
    Yes ("without -Stub it stops (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Squashed -match '-Stub')

    # ---- 3. a whole build -----------------------------------------------------------
    Write-Host ''; Write-Host 'a whole build from the feed'
    Put (Join-Path $root 'Game\Data\stray.txt') 'left from something older'
    Put (Join-Path $root 'Game\Data\Unreleased.esp') 'a plugin no release carried'
    $outDir = Join-Path $Scratch 'out'
    $r = Package $outDir @('-NoPublish', '-Stub', $stub)
    Yes ("it builds (exit {0})" -f $r.Code) ($r.Code -eq 0)
    if ($r.Code -ne 0) { Write-Host $r.Out -ForegroundColor DarkGray; Done }
    Yes '  and says it is not signed' ($r.Out -match 'not signed: built from the feed')
    $zipPath = Join-Path $outDir 'Thornswood-Setup.zip'
    Yes '  into Thornswood-Setup.exe and its zip' ((Test-Path -LiteralPath (Join-Path $outDir 'Thornswood-Setup.exe')) -and (Test-Path -LiteralPath $zipPath))
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $got = @{}
    $za = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($e in $za.Entries) {
            if (-not $e.Name) { continue }
            $s = $e.Open(); $ms = New-Object IO.MemoryStream
            try { $s.CopyTo($ms); $got[$e.FullName] = $ms.ToArray() } finally { $s.Dispose(); $ms.Dispose() }
        }
    } finally { $za.Dispose() }
    Yes 'every entry is named with / between folders, as Bootstrap.cs reads them' (-not @($got.Keys | Where-Object { $_.Contains('\') }).Count)
    Yes 'the release''s plugin is in, its bytes' ($got.ContainsKey('payload/Data/Thornswood-Content.esp') -and (ShaBytes $got['payload/Data/Thornswood-Content.esp']) -eq $espSha)
    Yes 'the release''s emotes plugin is in, its bytes' ($got.ContainsKey('payload/Data/Platform/Plugins/thornswood-emotes.js') -and (ShaBytes $got['payload/Data/Platform/Plugins/thornswood-emotes.js']) -eq $jsSha)
    Yes 'a stray file and a plugin no release named are not' (-not $got.ContainsKey('payload/Data/stray.txt') -and -not $got.ContainsKey('payload/Data/Unreleased.esp'))
    $cKey = 'payload/' + $clientRel.Replace('\', '/')
    Yes 'the client is the packed launcher''s, not the release''s or the checkout''s' ($got.ContainsKey($cKey) -and (ShaBytes $got[$cKey]) -eq $cSha)
    Yes 'the launcher is the one main''s feed offers' ($got.ContainsKey('Thornswood.exe') -and (ShaBytes $got['Thornswood.exe']) -eq $lSha)
    Yes 'the plugin list is the one the release recorded' ($got.ContainsKey('profile/plugins.txt') -and (ShaBytes $got['profile/plugins.txt']) -eq $pSha -and (ShaBytes $got['profile/loadorder.txt']) -eq $oSha)
    Yes 'collection.txt is in, because the feed names a collection' ($got.ContainsKey('collection.txt'))
    $skyrim = [IO.File]::ReadAllText((Join-Path $repo 'records\skyrim-files.json')) | ConvertFrom-Json
    $van = [Text.Encoding]::UTF8.GetString($got['vanilla.json']).TrimStart([char]0xFEFF) | ConvertFrom-Json
    Yes 'vanilla.json holds the three Steam files by the SHA-1 records\skyrim-files.json names' (
        @($van.PSObject.Properties).Count -eq 3 -and
        $van.'SkyrimSE.exe' -eq ([string]$skyrim.files.'SkyrimSE.exe'.sha1).ToLowerInvariant() -and
        $van.'steam_api64.dll' -eq ([string]$skyrim.files.'steam_api64.dll'.sha1).ToLowerInvariant() -and
        $van.'bink2w64.dll' -eq ([string]$skyrim.files.'bink2w64.dll'.sha1).ToLowerInvariant())
    $bat = [Text.Encoding]::ASCII.GetString($got['Setup.bat'])
    Yes 'Setup.bat goes in with CRLF line ends, whatever the checkout holds' ($bat.Contains("`r`n") -and -not ($bat -replace "`r`n", '').Contains("`n"))
    $cfg = [Text.Encoding]::UTF8.GetString($got['config.json']) | ConvertFrom-Json
    Yes 'config.json names the feed''s own server' ($cfg.ServerAddress -eq '192.0.2.7')
    $note = [IO.File]::ReadAllText((Join-Path $outDir 'Thornswood-Setup.release.json')) | ConvertFrom-Json
    Yes 'the note beside it names the release' ($note.release -eq '20261026-120000')

    # ---- 4. refused with nothing built ----------------------------------------------
    Write-Host ''; Write-Host 'refused with nothing built'
    Set-Feed (New-Record $true) '20261026-130000' '20261026-120000'
    $o2 = Join-Path $Scratch 'out-c'
    $r = Package $o2 @('-NoPublish', '-Stub', $stub)
    Yes ("a newest release that is not the record's is refused (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Squashed -match 'wouldDiffer|woulddiffer')
    Yes '  and nothing is built' (-not (Test-Path -LiteralPath (Join-Path $o2 'Thornswood-Setup.exe')))
    Set-Feed (New-Record $false)
    $o3 = Join-Path $Scratch 'out-d'
    $r = Package $o3 @('-NoPublish', '-Stub', $stub)
    Yes ("a record with no plugin list is refused (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Squashed -match 'recordednoplugins\.txt')
    Yes '  and nothing is built' (-not (Test-Path -LiteralPath (Join-Path $o3 'Thornswood-Setup.exe')))
}
finally {
    $env:THORNSWOOD_TEST_SITE_DIR = $keepEnv.SITE; $env:THORNSWOOD_HARNESS = $keepEnv.HARNESS; $env:THORNSWOOD_VPS = $keepEnv.VPS
    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Done
