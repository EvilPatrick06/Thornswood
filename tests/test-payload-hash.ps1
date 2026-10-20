<#
  test-payload-hash.ps1

  The setup program checks the payload it downloads against a hash the site
  publishes, and deletes one that does not match instead of running it.

  From the To Do List, entry 173: "The 527 MB payload is downloaded and
  executed without any integrity check". Bootstrap.cs tested nothing but the
  length, then unpacked the zip and started the Setup.bat inside it. "The
  launcher already holds itself to exactly this standard for every pack; the
  installer does not."

  THREE PIECES HAVE TO AGREE, AND THIS RUNS ALL THREE. Publish-Installer.ps1
  measures the zip and writes the hash into files.json. The /api/payload route
  in site\server.js reads files.json and hands the hash over. Bootstrap.cs
  reads it out of that reply with the same string search it uses for the rest,
  and deletes a download that does not match. Each piece is lifted out of the
  real file by text and run, the way test-dev-version.ps1 and
  test-master-flag.ps1 do it, so this fails if any one of them stops doing its
  part. The hash that goes in at one end is followed all the way out of the
  other.

  The site half runs under node, which the build check already has. The
  installer half is compiled with Add-Type from the methods lifted out of
  Bootstrap.cs; Build-Launcher.ps1 is what holds that file to C# 5.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param(
    [string]$InstallerPath,
    [string]$ServerPath,
    [string]$BootstrapPath
)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $InstallerPath) { $InstallerPath = Join-Path $Here 'scripts\release\Publish-Installer.ps1' }
if (-not $ServerPath)    { $ServerPath    = Join-Path $Here 'site\server.js' }
if (-not $BootstrapPath) { $BootstrapPath = Join-Path $Here 'installer\setup\Bootstrap.cs' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# A property that may not be there. A reply from before this has no sha256 on
# it, and that has to read as a FAIL line rather than stop the run.
function Field($o, [string]$name) {
    if ($null -eq $o) { return $null }
    $p = $o.PSObject.Properties[$name]
    if ($p) { return $p.Value }
    return $null
}

function Sha([string]$file) {
    return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-payload-hash-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$noBom = New-Object Text.UTF8Encoding($false)

try {
    # ---- the payload ---------------------------------------------------------
    #
    # Two megabytes of random bytes stand in for the 527 MB zip. Nothing here
    # opens it as a zip; what is measured is the bytes.
    $site = Join-Path $work 'files'
    New-Item -ItemType Directory -Path $site -Force | Out-Null
    $exeOut = 'Thornswood-Setup.exe'
    $zipOut = 'Thornswood-Setup.zip'
    $zipPath = Join-Path $site $zipOut
    $bytes = New-Object byte[] (2MB + 17)
    (New-Object Random 173).NextBytes($bytes)
    [IO.File]::WriteAllBytes($zipPath, $bytes)
    [IO.File]::WriteAllBytes((Join-Path $site $exeOut), [byte[]](1, 2, 3))
    $want = Sha $zipPath

    # ---- 1. Publish-Installer writes the hash into files.json -----------------
    #
    # Two pieces of it. The line that measures the zip, which sits where the
    # zip is found, beside the one that measures the exe. And the block that
    # builds $meta, from "if ($single) {" to the line that encodes it for the
    # trip to the VPS. The rest of the script copies files to the VPS and
    # cannot run here.
    $pub = Get-Content -LiteralPath $InstallerPath -Raw
    $hm = [regex]::Match($pub, '(?m)^[ \t]*\$zipSha = \(Get-FileHash -LiteralPath \$zipItem\.FullName -Algorithm SHA256\)\.Hash[^\r\n]*')
    Yes 'Publish-Installer measures the zip it publishes' ($hm.Success)
    $hashLine = ''
    if ($hm.Success) { $hashLine = $hm.Value.Trim() }
    # A one file build carries the payload inside the exe and has no zip to
    # measure, so the measuring has to sit inside the branch that found one.
    $z0 = $pub.IndexOf('if (-not $single) {')
    $z1 = -1
    if ($z0 -ge 0) { $z1 = $pub.IndexOf("`n}", $z0) }
    Yes 'and only when there is a zip to measure' ($hm.Success -and $z0 -ge 0 -and $hm.Index -gt $z0 -and $hm.Index -lt $z1)

    $a = $pub.IndexOf('if ($single) {')
    $b = $pub.IndexOf('$b64 = [Convert]::ToBase64String(')
    Yes 'the block that builds files.json is in Publish-Installer.ps1' ($a -ge 0 -and $b -gt $a)
    $metaBlock = ''
    if ($a -ge 0 -and $b -gt $a) { $metaBlock = $pub.Substring($a, $b - $a) }

    $meta = $null
    $single = $false
    $Version = 'launcher 1.2.3'
    $zipItem = Get-Item -LiteralPath $zipPath
    $zipSha = $null
    if ($hashLine) { Invoke-Expression $hashLine }
    if ($metaBlock) { Invoke-Expression $metaBlock }
    $zipMeta = $null
    if ($meta) { $zipMeta = $meta[$zipOut] }
    Yes 'the payload zip has an entry' ($null -ne $zipMeta)
    $wrote = ''
    if ($zipMeta) { $wrote = [string]$zipMeta['sha256'] }
    Yes 'and the entry carries a sha256' ($wrote.Length -gt 0)
    Yes 'which is the hash Get-FileHash prints for the zip, ignoring case' ($wrote -ieq $want)
    Yes 'written lower case, the shape launcherSha256 already has' ($wrote -cmatch '^[0-9a-f]{64}$')
    Yes 'the entry is still hidden, so nobody is offered the payload as a button' ($zipMeta -and $zipMeta['hidden'] -eq $true)

    # And the $meta block of a one file build names no zip and no zip hash.
    $meta = $null
    $single = $true
    $zipItem = $null
    $zipSha = $null
    $oneFileOk = $true
    try { if ($metaBlock) { Invoke-Expression $metaBlock } } catch { $oneFileOk = $false }
    Yes 'a one file build still builds its entry without a zip to measure' ($oneFileOk -and $meta -and $meta.Count -eq 1)

    # files.json as the VPS writes it: the same merge and the same write the
    # remote half of Publish-Installer does, byte order mark left off.
    $single = $false
    $zipItem = Get-Item -LiteralPath $zipPath
    $zipSha = $null
    if ($hashLine) { Invoke-Expression $hashLine }
    $meta = $null
    if ($metaBlock) { Invoke-Expression $metaBlock }
    $all = @{}
    if ($meta) {
        (($meta | ConvertTo-Json -Depth 4 -Compress) | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $all[$_.Name] = $_.Value }
    }
    [IO.File]::WriteAllText((Join-Path $site 'files.json'), ($all | ConvertTo-Json -Depth 4), $noBom)

    # ---- 1b. a files.json that does not read (#2711) ---------------------------
    #
    # The remote half read files.json in a try with an empty catch, so a list
    # that did not read became an empty one and was written back naming the
    # installer alone, after the installer had already replaced the old one.
    # Now a check reads it before the send, and the write leaves one that does
    # not read as it is. Both scripts are lifted out of Publish-Installer.ps1,
    # filled in as Remote fills them, and run under Windows PowerShell 5.1, as
    # the box runs them, against a stand-in Thornswood-Docs.
    $docs = Join-Path $work 'docs'
    New-Item -ItemType Directory -Path (Join-Path $docs 'files') -Force | Out-Null
    $listFile = Join-Path $docs 'files\files.json'
    function Lift-Remote([string]$opener) {
        $i = $pub.IndexOf($opener)
        if ($i -lt 0) { return '' }
        $s = $pub.IndexOf("`n", $i) + 1
        $e = $pub.IndexOf("`n`"@)", $s)
        if ($e -lt 0) { return '' }
        return $pub.Substring($s, $e - $s).TrimEnd("`r")
    }
    $checkBody = Lift-Remote '$listCheck = @(Remote @"'
    $writeBody = Lift-Remote '$listWrite = @(Remote @"'
    Yes 'Publish-Installer reads files.json on the box, and writes it, as two scripts' ($checkBody -and $writeBody)
    $scpAt = $pub.IndexOf('& scp @ssh $pair[0]')
    Yes '  the read comes before the installer is sent, and the write after' ($scpAt -gt 0 -and $pub.IndexOf('$listCheck = @(Remote @"') -lt $scpAt -and $pub.IndexOf('$listWrite = @(Remote @"') -gt $scpAt)
    Yes '  and a refusal from either stops the script (the first before anything is sent)' (
        $pub -match '(?s)\$listCode = \$LASTEXITCODE.{0,600}throw \("files\.json on the site.{0,200}Nothing was sent' -and
        $pub -match '(?s)\$listWriteCode = \$LASTEXITCODE.{0,200}if \(\$listWriteCode -ne 0\) \{\s*throw')
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    function Run-Remote([string]$body) {
        $rootWin = $docs
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($meta | ConvertTo-Json -Depth 4 -Compress)))
        $text = $ExecutionContext.InvokeCommand.ExpandString($body)
        $f = Join-Path $work ('remote-' + [Guid]::NewGuid().ToString('N') + '.ps1')
        [IO.File]::WriteAllText($f, $text, (New-Object Text.UTF8Encoding($true)))
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = @(& $winps -NoProfile -ExecutionPolicy Bypass -File $f 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        return @{ Out = ($out -join ' '); Code = $code }
    }
    if ($checkBody -and $writeBody) {
        $r = Run-Remote $checkBody
        Yes 'no files.json yet: the check lets the send go on' ($r.Code -eq 0 -and $r.Out -match 'FILESJSON\|none')
        [IO.File]::WriteAllText($listFile, '{"Other-Download.zip":{"label":"something else on the page","sha256":"ab"}}', $noBom)
        $r = Run-Remote $checkBody
        Yes 'a files.json that reads: the check lets the send go on' ($r.Code -eq 0 -and $r.Out -match 'FILESJSON\|reads')
        $r = Run-Remote $writeBody
        $after = Get-Content -LiteralPath $listFile -Raw | ConvertFrom-Json
        Yes '  and the write keeps every other download, adding the installer' ($r.Code -eq 0 -and $after.PSObject.Properties['Other-Download.zip'] -and $after.PSObject.Properties[$exeOut])
        $broken = '{"Other-Download.zip":{"label":"cut off'
        [IO.File]::WriteAllText($listFile, $broken, $noBom)
        $r = Run-Remote $checkBody
        Yes 'a files.json that does not read: the check exits 1, saying why' ($r.Code -eq 1 -and $r.Out -match 'FILESJSON\|' -and $r.Out -notmatch 'FILESJSON\|(none|reads)')
        $r = Run-Remote $writeBody
        Yes '  and the write exits 1 and leaves it as it was, not a list of the installer alone' ($r.Code -eq 1 -and $r.Out -match 'does not read, so it was left as it is' -and [IO.File]::ReadAllText($listFile) -eq $broken)
    }

    # ---- 2. the site hands it over --------------------------------------------
    #
    # server.js opens a port and reads a config when it is required, so the
    # route is lifted out of it with jsonFile and run on its own against a
    # folder, and what it would send is printed. The driver is written into the
    # temp folder, so the harness is one file.
    $node = Get-Command node -ErrorAction SilentlyContinue
    Yes 'node is on the path, for the site half' ($null -ne $node)
    $driver = Join-Path $work 'payload-route.js'
    $js = @'
// Written and run by test-payload-hash.ps1. Lifts jsonFile and the
// /api/payload route out of server.js and prints what the route sends.
const fs = require('fs');
const path = require('path');
const src = process.argv[2];
const FILES = process.argv[3];
const text = fs.readFileSync(src, 'utf8').split(String.fromCharCode(13)).join('');
const j0 = text.indexOf('const jsonFile = (p, fallback) => {');
const j1 = text.indexOf('const putJson', j0);
const r0 = text.indexOf("if (route === '/api/payload' && req.method === 'GET') {");
if (j0 < 0 || j1 < 0 || r0 < 0) { process.stdout.write('NOT FOUND'); process.exit(2); }
const open = text.indexOf('{', r0);
let depth = 0, end = -1;
for (let i = open; i < text.length; i++) {
  const c = text[i];
  if (c === '{') depth++;
  else if (c === '}') { depth--; if (depth === 0) { end = i; break; } }
}
if (end < 0) { process.stdout.write('NOT FOUND'); process.exit(2); }
const block = text.slice(r0, end + 1);
const route = '/api/payload';
const req = { method: 'GET' };
const res = {};
let sent = null;
// The real one is send(res, code, JSON.stringify(obj)); the string is what
// crosses the wire and what Bootstrap.cs searches.
const sendJson = (r, code, obj) => { sent = JSON.stringify(obj); return true; };
eval(text.slice(j0, j1) + '\n(function () {\n' + block + '\n})();');
process.stdout.write(sent === null ? 'NOTHING SENT' : sent);
'@
    [IO.File]::WriteAllText($driver, $js, $noBom)

    function Reply([string]$dir) {
        if (-not $node) { return '' }
        # stdout only. A lift that throws prints its stack to stderr, the
        # reply comes back empty, and the checks below say FAIL.
        $out = & $node.Source $driver $ServerPath $dir
        return (($out | ForEach-Object { [string]$_ }) -join '')
    }
    function Parse([string]$text) {
        try { return ($text | ConvertFrom-Json) } catch { return $null }
    }

    $reply = Reply $site
    $got = Parse $reply
    Yes 'the route answers with JSON' ($null -ne $got)
    Yes 'naming the zip' ((Field $got 'name') -eq $zipOut)
    Yes 'with its size' ([long](Field $got 'size') -eq $bytes.Length)
    $siteSha = [string](Field $got 'sha256')
    Yes 'and a sha256' ($siteSha.Length -gt 0)
    Yes 'which is the hash Get-FileHash prints, ignoring case' ($siteSha -ieq $want)

    # A publish from before this wrote no hash. The route still answers, with
    # an empty one, which the installer refuses to fetch anything against.
    $old = Join-Path $work 'files-old'
    New-Item -ItemType Directory -Path $old -Force | Out-Null
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $old $zipOut)
    $o = Parse (Reply $old)
    Yes 'no files.json still names the zip' ((Field $o 'name') -eq $zipOut)
    Yes 'and gives an empty hash rather than none at all' ((Field $o 'sha256') -eq '')

    # Something in files.json that is not a hash would make every install
    # delete a good download, so it does not leave the site.
    $bad = Join-Path $work 'files-bad'
    New-Item -ItemType Directory -Path $bad -Force | Out-Null
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $bad $zipOut)
    [IO.File]::WriteAllText((Join-Path $bad 'files.json'),
        ('{"' + $zipOut + '":{"sha256":"not a hash","hidden":true}}'), $noBom)
    Yes 'a value that is not a hash goes out empty' ((Field (Parse (Reply $bad)) 'sha256') -eq '')

    # Upper case in the file, as Get-FileHash prints it, comes out lower.
    $up = Join-Path $work 'files-upper'
    New-Item -ItemType Directory -Path $up -Force | Out-Null
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $up $zipOut)
    [IO.File]::WriteAllText((Join-Path $up 'files.json'),
        ('{"' + $zipOut + '":{"sha256":"' + $want.ToUpper() + '"}}'), $noBom)
    Yes 'an upper case hash in files.json goes out lower case' ((Field (Parse (Reply $up)) 'sha256') -ceq $want.ToLower())

    # Two zips sit there (stable tip plus a leftover stamped name). The newest
    # is the one offered, and the hash has to be that one's, not the other's.
    $two = Join-Path $work 'files-two'
    New-Item -ItemType Directory -Path $two -Force | Out-Null
    $olderName = 'Thornswood-Setup-20260920-0900.zip'
    $older = Join-Path $two $olderName
    [IO.File]::WriteAllBytes($older, [byte[]](9, 9, 9, 9))
    (Get-Item -LiteralPath $older).LastWriteTime = (Get-Date).AddDays(-4)
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $two $zipOut)
    [IO.File]::WriteAllText((Join-Path $two 'files.json'),
        ('{"' + $olderName + '":{"sha256":"' + (Sha $older).ToLower() + '"},"' +
         $zipOut + '":{"sha256":"' + $want.ToLower() + '"}}'), $noBom)
    $t = Parse (Reply $two)
    Yes 'with two zips the newest is offered' ((Field $t 'name') -eq $zipOut)
    Yes 'with its own hash, not the older one''s' ((Field $t 'sha256') -ieq $want)

    # No zip at all is a one file build, and the reply stays empty.
    $none = Join-Path $work 'files-none'
    New-Item -ItemType Directory -Path $none -Force | Out-Null
    Yes 'no zip means an empty reply, as before' ((Reply $none) -eq '{}')

    # ---- 3. the installer checks it ------------------------------------------
    $bs = Get-Content -LiteralPath $BootstrapPath -Raw

    # A C# method by its head and a brace match that steps over strings, char
    # literals and line comments, because Download has "}" in a string.
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

    $between  = Get-Method $bs 'static string Between('
    $matches_ = Get-Method $bs 'static bool PayloadMatches('
    $check    = Get-Method $bs 'static void CheckPayload('
    $url      = Get-Method $bs 'static string PayloadUrl('
    $download = Get-Method $bs 'static string Download('
    Yes 'Between is in Bootstrap.cs' ($between.Length -gt 0)
    Yes 'PayloadMatches is in Bootstrap.cs' ($matches_.Length -gt 0)
    Yes 'CheckPayload is in Bootstrap.cs' ($check.Length -gt 0)
    Yes 'PayloadUrl is in Bootstrap.cs' ($url.Length -gt 0)
    Yes 'Download is in Bootstrap.cs' ($download.Length -gt 0)

    # Download itself talks to the site and draws on a window, so its wiring
    # is read rather than run: it has to take the field, check the file it
    # already has before trusting its length, and check what it fetched after
    # the length test and before handing it to the unpack.
    Yes 'Download reads sha256 out of the reply' ($download.Contains('sha = Between(doc, "\"sha256\":\"", "\"")'))
    $gotAt   = $download.IndexOf('PayloadMatches(target, sha)')
    $already = $download.IndexOf('Say("Already got Thornswood''s files")')
    Yes 'a file already here is checked before it is trusted for its size' ($gotAt -ge 0 -and $already -gt $gotAt)
    $early  = $download.IndexOf('The download stopped early')
    $check2 = $download.IndexOf('CheckPayload(target, sha)')
    $ret    = $download.LastIndexOf('return target;')
    Yes 'what it fetched is checked after the length test' ($early -ge 0 -and $check2 -gt $early)
    Yes 'and before it is handed on to be unpacked' ($check2 -ge 0 -and $ret -gt $check2)
    Yes 'the hash is read streamed, never the whole file into memory' (
        $matches_.Length -gt 0 -and $matches_.Contains('ComputeHash(s)') -and -not $matches_.Contains('ReadAllBytes'))

    # The address the site gives goes through PayloadUrl, and a reply with no
    # hash on it stops the install before half a gigabyte is fetched rather
    # than after, since there would be nothing to measure it against.
    $urlAt   = $download.IndexOf('url = PayloadUrl(Site, url)')
    $noSha   = $download.IndexOf('if (sha.Length == 0)')
    $fetch   = $download.IndexOf('WebRequest.Create(url)')
    Yes 'Download puts the site''s address through PayloadUrl' ($urlAt -ge 0)
    Yes 'and refuses a reply with no hash on it' ($noSha -ge 0)
    Yes 'before it fetches a byte' ($fetch -gt $noSha -and $noSha -gt $urlAt)

    $compiled = $false
    if ($between -and $matches_ -and $check -and $url) {
        $members = @($between, $matches_, $check, $url) | ForEach-Object {
            $m = [string]$_
            'public ' + $m
        }
        $cs = @"
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
public static class ThornswoodPayloadCheck
{
$($members -join "`n`n")
}
"@
        try { Add-Type -TypeDefinition $cs -Language CSharp; $compiled = $true }
        catch { Write-Host ("      " + $_.Exception.Message) }
    }
    Yes 'the lifted methods compile' $compiled

    if ($compiled) {
        $T = [ThornswoodPayloadCheck]

        # What Download does to the reply, on the reply the site gave above.
        $parsed = $T::Between($reply, '"sha256":"', '"').Trim()
        Yes 'the installer pulls the same hash out of the site''s reply' ($parsed -ieq $want)
        # An installer from before this searches for "size": up to a comma
        # first. sha256 comes after size, so that still finds the number.
        Yes 'an older installer still reads the size out of the new reply' ($T::Between($reply, '"size":', ',').Trim() -eq [string]$bytes.Length)

        $pc = Join-Path $work 'pc'
        New-Item -ItemType Directory -Path $pc -Force | Out-Null
        $good = Join-Path $pc $zipOut
        Copy-Item -LiteralPath $zipPath -Destination $good

        Yes 'the published bytes match the published hash' ($T::PayloadMatches($good, $parsed))
        Yes 'in upper case too' ($T::PayloadMatches($good, $parsed.ToUpper()))
        # Issue #1365. A hash the site did not give is not a hash that matched:
        # the bytes behind it are unpacked and run, so no hash is a refusal.
        Yes 'an empty hash does not pass' (-not $T::PayloadMatches($good, ''))
        Yes 'nor a hash of nothing but spaces' (-not $T::PayloadMatches($good, "  `t "))
        Yes 'nor no hash at all' (-not $T::PayloadMatches($good, $null))
        # Padding either side of a real hash is still that hash.
        Yes 'a hash with space around it is still the hash' ($T::PayloadMatches($good, ' ' + $parsed + ' '))

        $threw = $null
        try { $T::CheckPayload($good, $parsed) } catch { $threw = $_ }
        Yes 'a good download is not refused' ($null -eq $threw)
        Yes 'and is left where it is for the unpack' (Test-Path -LiteralPath $good)

        # One byte changed and nothing else. The same length, so every test
        # the installer had before this passes it.
        $tampered = Join-Path $pc 'tampered.zip'
        $evil = [byte[]]$bytes.Clone()
        $evil[1234567] = $evil[1234567] -bxor 0x5A
        [IO.File]::WriteAllBytes($tampered, $evil)
        Yes 'a tampered payload is the same length, which is all that was checked' ((Get-Item -LiteralPath $tampered).Length -eq $bytes.Length)
        Yes 'and its bytes do not match the hash' (-not $T::PayloadMatches($tampered, $parsed))

        $threw = $null
        try { $T::CheckPayload($tampered, $parsed) } catch { $threw = $_ }
        Yes 'CheckPayload refuses it' ($null -ne $threw)
        Yes 'and deletes it, so nothing in it runs and the next run fetches it fresh' (-not (Test-Path -LiteralPath $tampered))
        $msg = ''
        if ($threw) { $msg = $threw.Exception.GetBaseException().Message }
        Yes 'the message says it was deleted' ($msg -match 'deleted')
        Yes 'and what to do next' ($msg -match 'Run this again')
        Yes 'in the house words' ($msg -notmatch 'player')
        Yes 'and no em dash' ($msg.IndexOf([char]0x2014) -lt 0)

        # A site that gives no hash is refused too, rather than passed through
        # unmeasured. Download stops before it fetches anything in that case;
        # this is the same answer from the other end.
        [IO.File]::WriteAllBytes($tampered, $evil)
        $threw = $null
        try { $T::CheckPayload($tampered, '') } catch { $threw = $_ }
        Yes 'with no hash from the site nothing is trusted' ($null -ne $threw)
        Yes 'and the download is deleted rather than unpacked' (-not (Test-Path -LiteralPath $tampered))

        # ---- the address the site gives -------------------------------------
        #
        # Issue #1365. The url out of /api/payload is what gets fetched,
        # unpacked and run. A relative one is joined onto the site as it always
        # was; an absolute one has to be https.
        $S = 'https://thornswood.net'
        Yes 'a relative address is joined onto the site' ($T::PayloadUrl($S, '/file/Thornswood-Setup.zip') -eq ($S + '/file/Thornswood-Setup.zip'))
        Yes 'the real reply''s address is joined onto the site' ($T::PayloadUrl($S, [string](Field $got 'url')) -eq ($S + [string](Field $got 'url')))
        Yes 'an https address is taken as it stands' ($T::PayloadUrl($S, 'https://thornswood.net/file/x.zip') -eq 'https://thornswood.net/file/x.zip')

        function Refused([string]$u) {
            try { $T::PayloadUrl($S, $u) | Out-Null; return $false } catch { return $true }
        }
        Yes 'plain http is refused' (Refused 'http://thornswood.net/file/x.zip')
        Yes 'http anywhere else is refused' (Refused 'http://evil.example/x.zip')
        Yes 'upper case HTTP is refused too' (Refused 'HTTP://thornswood.net/file/x.zip')
        Yes 'a file address is refused' (Refused 'file://server/share/x.zip')
        Yes 'and an ftp one' (Refused 'ftp://thornswood.net/x.zip')
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
