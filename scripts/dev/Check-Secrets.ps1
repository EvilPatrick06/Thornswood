<#
  Check-Secrets.ps1

  Read only. Looks for anything that must never leave a machine: in the files
  this repository tracks, in a pack or installer zip, in the installer's staged
  folder, or in a built program. For every hit it prints the file, the line and
  the name of the rule, and NEVER the thing it matched. A scan that prints what
  it found has just published it, in a build log anybody on the repository can
  read.

      .\scripts\dev\Check-Secrets.ps1                            every file git tracks here
      .\scripts\dev\Check-Secrets.ps1 -Zip <pack or installer>   the entries of a zip
      .\scripts\dev\Check-Secrets.ps1 -Dir <installer stage>     a staged folder
      .\scripts\dev\Check-Secrets.ps1 -Binary <Thornswood.exe>   a built program, byte by byte

  Exit 0 when nothing was found, 1 when something was, 2 when something could
  not be read. A 2 is not a pass.

  WHY IT EXISTS. Entry 236. Two secrets have shipped inside built artefacts, and
  neither was in the source, so nothing that only read the source could have
  seen them:
    - the installer carried Data\Platform\PluginsNoLoad\auth-data-no-load.js,
      the SkyMP client's saved sign in from the machine that built it (the
      header of Ship-Rules.ps1 tells it);
    - nine main packs from 18 to 20 September, and at least two dev packs
      beside them, carried Data\Platform\voice-token.txt, the voice join token
      of the machine that built them, because Ship-Rules did not list it yet.
  Ship-Rules lists both now. This is the check that does not wait for somebody
  to think of the file first: both names say what they are, and the token has
  a shape. In a pack or the installer it also asks Ship-Rules itself, so a file
  that the rules keep out and that got in anyway stops the release.

  The tree scan reads what git tracks and nothing else, so the credential files
  that sit gitignored on the shipping machine (the two webhook files,
  server-secret.txt, config.json) are never opened.

  A known non-secret that a rule matches goes in Check-Secrets.allow.txt beside
  this script, by path and rule, with a line saying why it is safe. Never a real
  secret: a real one is taken out and replaced, not allowed.
#>
[CmdletBinding()]
param(
    # The repository to scan. Empty is the one this script is in.
    [string]$Root = '',
    # Pack or installer zips. Entries under game/ (a pack) or payload/ (the
    # installer) are also checked against Ship-Rules.
    [string[]]$Zip = @(),
    # A staged folder, the installer's stage. Its payload\ is the game.
    [string]$Dir = '',
    # A built program, read byte by byte as text and as UTF-16.
    [string[]]$Binary = @(),
    # The allow list. Empty is Check-Secrets.allow.txt beside this script.
    [string]$Allow = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
. (Join-Path $Here '..\release\Ship-Rules.ps1')

# ---------------------------------------------------------------- the rules
#
# By shape, over the text of a file. Each is one kind of credential this
# project holds or has held, or one that turns up in any repository by
# accident. The lookarounds keep a rule from firing on a longer run of the
# same characters, which is what random data and base64 look like.
$ContentRules = @(
    # The news and dev webhooks (bot). Anyone holding one can post
    # as the bot.
    @{ Name = 'discord-webhook';   Rx = '(?i)discord(?:app)?\.com/api/webhooks/[0-9]{15,22}/[A-Za-z0-9_-]{30,}' },
    # The bot's own token (bot.env.json on the VPS).
    @{ Name = 'discord-bot-token'; Rx = '(?<![A-Za-z0-9_-])[MNO][A-Za-z0-9_-]{23,28}\.[A-Za-z0-9_-]{6,7}\.[A-Za-z0-9_-]{27,40}(?![A-Za-z0-9_-])' },
    # The update token is a fine-grained personal access token; any other
    # GitHub token has one of these prefixes.
    @{ Name = 'github-token';      Rx = '(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})' },
    # The key that signs in to the VPS, or any other private key.
    @{ Name = 'private-key';       Rx = '-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----' },
    # A voice join token, the shape signToken in voice\voice-server.js
    # makes: v1.<profile id>.<expiry in ms>.<43 character signature>. This is
    # what nine published packs carried in voice-token.txt.
    @{ Name = 'voice-join-token';  Rx = '(?<![A-Za-z0-9_.-])v1\.[0-9]{1,12}\.[0-9]{12,14}\.[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])' },
    @{ Name = 'aws-access-key';    Rx = '(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])' },
    @{ Name = 'slack-token';       Rx = '(?<![A-Za-z0-9])xox[abposr]-[A-Za-z0-9-]{10,}' },
    @{ Name = 'google-api-key';    Rx = '(?<![A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}(?![A-Za-z0-9_-])' }
)

# The matching runs in this small compiled class and not in PowerShell, for a
# measured reason. PowerShell 7.6 on Patrick's machine is slow at handing a
# large string to a .NET method: one regex over the 6 MB recipes.json took
# 1.4 s that way and the whole tree took 41 s, where the -match operator over
# the same text took 0.03 s and Windows PowerShell 5.1 took 0.013 s for the
# same call. Here the bytes go in, and only a rule name and a position come
# back out. The value never reaches PowerShell at all, which is the other half
# of never printing it. C# 5, so the Framework csc that Windows PowerShell uses
# for Add-Type compiles it too.
if (-not ('ThornswoodSecretScan1' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

public static class ThornswoodSecretScan1
{
    static string[] names = new string[0];
    static Regex[] rules = new Regex[0];

    public static void SetRules(string[] ruleNames, string[] patterns)
    {
        names = ruleNames;
        rules = new Regex[patterns.Length];
        for (int i = 0; i < patterns.Length; i++)
            rules[i] = new Regex(patterns[i], RegexOptions.CultureInvariant | RegexOptions.Compiled);
    }

    // Null when the bytes are not text: a NUL in the first 8 KB with no UTF-16
    // byte order mark to explain it. Latin-1 otherwise, which maps every byte
    // to one character, so nothing fails to decode and every rule sees the
    // bytes as they are.
    static string Decode(byte[] b)
    {
        if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return Encoding.Unicode.GetString(b, 2, b.Length - 2);
        if (b.Length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return Encoding.BigEndianUnicode.GetString(b, 2, b.Length - 2);
        int n = Math.Min(b.Length, 8192);
        if (n > 0 && Array.IndexOf(b, (byte)0, 0, n) >= 0) return null;
        return Encoding.GetEncoding(28591).GetString(b);
    }

    // "rule<TAB>line" for every hit, or null when the bytes are not text.
    public static string[] ScanText(byte[] b)
    {
        string text = Decode(b);
        if (text == null) return null;
        List<string> hits = new List<string>();
        for (int r = 0; r < rules.Length; r++)
        {
            int line = 1, at = 0;
            foreach (Match m in rules[r].Matches(text))
            {
                for (; at < m.Index; at++) if (text[at] == '\n') line++;
                hits.Add(names[r] + "\t" + line);
            }
        }
        return hits.ToArray();
    }

    // "rule<TAB>byte offset" for every hit in a program: the bytes as Latin-1,
    // then as UTF-16 at both alignments, because .NET keeps its string literals
    // as UTF-16 and an embedded file as it was.
    public static string[] ScanBinary(byte[] b)
    {
        List<string> hits = new List<string>();
        HashSet<string> seen = new HashSet<string>();
        Scan(Encoding.GetEncoding(28591).GetString(b), 1, 0, hits, seen);
        Scan(Encoding.Unicode.GetString(b, 0, b.Length - (b.Length % 2)), 2, 0, hits, seen);
        if (b.Length > 2)
        {
            int odd = b.Length - 1;
            Scan(Encoding.Unicode.GetString(b, 1, odd - (odd % 2)), 2, 1, hits, seen);
        }
        return hits.ToArray();
    }

    static void Scan(string text, int scale, int shift, List<string> hits, HashSet<string> seen)
    {
        for (int r = 0; r < rules.Length; r++)
        {
            foreach (Match m in rules[r].Matches(text))
            {
                string hit = names[r] + "\t" + (m.Index * (long)scale + shift);
                if (seen.Add(hit)) hits.Add(hit);
            }
        }
    }
}
'@
}
[ThornswoodSecretScan1]::SetRules([string[]]@($ContentRules | ForEach-Object { $_.Name }),
                                  [string[]]@($ContentRules | ForEach-Object { $_.Rx }))

# By name. Every one of these is gitignored or kept out by Ship-Rules, so
# finding one tracked, packed or staged means a rule somewhere was missed.
$SecretNames = @(
    'backup-key.txt', 'thornswood-backup-key.txt', 'bot.env.json', '.env',
    'signing.json', 'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519'
)
$SecretExts = @('.pfx', '.p12', '.pem', '.ppk')
# A word in the name that says what the file holds, standing on its own:
# server-secret.txt, news-webhook.txt, token-key.txt, and the two that shipped,
# voice-token.txt and auth-data-no-load.js. "Secrets.cs" and "UpdateToken" do
# not match, because the word has to stand alone.
$SecretWord = New-Object System.Text.RegularExpressions.Regex (
    '(^|[^a-z0-9])(token|secret|password|passwd|webhook|credentials?|auth-data)([^a-z0-9]|$)',
    [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant')

# Never worth reading as text. Anything not on this list is read, and passed
# over as binary only when it has a NUL in its first 8 KB.
$BinaryExts = @(
    '.dds', '.nif', '.bsa', '.ba2', '.esp', '.esm', '.esl', '.hkx', '.wav', '.xwm',
    '.fuz', '.mp3', '.mp4', '.ogg', '.webm', '.bik', '.png', '.jpg', '.jpeg', '.gif',
    '.bmp', '.tga', '.ico', '.ttf', '.otf', '.woff', '.woff2', '.dll', '.exe', '.pex',
    '.swf', '.lip', '.tri', '.pdb', '.zip', '.7z', '.rar', '.gfx', '.egm', '.egt',
    '.btr', '.bto', '.lod', '.seq', '.pak', '.bin'
)
$TextCap = 100MB

# ---------------------------------------------------------------- allow list
$allowRules = @()
if (-not $Allow) { $Allow = Join-Path $Here 'Check-Secrets.allow.txt' }
if (Test-Path -LiteralPath $Allow) {
    foreach ($line in [IO.File]::ReadAllLines($Allow)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $p = $t -split '\s+'
        if ($p.Count -lt 2) { continue }
        $allowRules += ,@($p[0], $p[1])
    }
}

$script:found = 0
$script:allowed = 0
$script:unread = 0
$script:read = 0

function Test-Allowed([string]$key, [string]$rule) {
    foreach ($a in $allowRules) {
        if ($rule -eq $a[1] -and $key -like $a[0]) { return $true }
    }
    return $false
}

# The one place a hit is written, so there is one place to check that it never
# carries the value: the file, the line or byte, the rule. Nothing else.
function Write-Hit([string]$where, [string]$key, [string]$line, [string]$rule, [bool]$isByte) {
    if (Test-Allowed $key $rule) { $script:allowed++; return }
    $script:found++
    if ($env:GITHUB_ACTIONS -eq 'true') {
        if ($isByte) { Write-Host ('::error file={0}::{1} at byte {2}' -f $where, $rule, $line) }
        else { Write-Host ('::error file={0},line={1}::{2}' -f $where, $line, $rule) }
    } else {
        if ($isByte) { Write-Host ('  {0} at byte {1}  {2}' -f $where, $line, $rule) -ForegroundColor Red }
        else { Write-Host ('  {0}:{1}  {2}' -f $where, $line, $rule) -ForegroundColor Red }
    }
}

function Write-Unread([string]$where, [string]$why) {
    $script:unread++
    Write-Host ('  could not read {0}: {1}' -f $where, $why) -ForegroundColor Yellow
}

# ---------------------------------------------------------------- checks
function Test-Name([string]$where, [string]$key, [string]$leaf, [bool]$tree) {
    $ext = [IO.Path]::GetExtension($leaf).ToLowerInvariant()
    $hit = $false
    foreach ($n in $SecretNames) { if ($leaf -ieq $n) { $hit = $true } }
    if ($leaf -like '*.env') { $hit = $true }
    if ($SecretExts -contains $ext) { $hit = $true }
    if ($SecretWord.IsMatch($leaf)) { $hit = $true }
    # The launcher's config.json holds the server address and the update
    # token. The installer carries one on purpose, so this is the tree only.
    if ($tree -and $leaf -ieq 'config.json') { $hit = $true }
    if ($hit) { Write-Hit $where $key '0' 'credential-file-name' $false }
}

# Whether a zip entry or a staged file at one of the six client runtime paths
# is the recorded build, by its own bytes. $source is the zip entry, or the
# staged file's full path.
function Test-ClientBytes([string]$rel, $source) {
    if ($source -is [string]) { return (Test-ShipClientRecorded $rel $source) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $s = $source.Open()
        try { $have = ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-', '').ToLowerInvariant() }
        finally { $s.Dispose() }
    }
    finally { $sha.Dispose() }
    return ($have -eq $ShipClientHashes[$rel])
}

# A path inside a pack (game/...) or the installer (payload/...), asked of
# Ship-Rules the same way Publish-Update and Package-Thornswood ask it before
# they pack a file. Anything it says never ships and that is here anyway is
# the failure this whole script is for.
#
# The six client runtime files are asked by the bytes in hand, not through
# Test-ShipMachine (entry 128). Ship-Rules calls one of them ours only when its
# sha256 is the recorded build, and given just a path it hashes the file under
# the caller's $GameDir. Here that is the wrong file: the game folder a pack
# was built from, not the zip or stage being read. Measured 24 September on
# scratch copies of the real bundle: run on its own, with no $GameDir, this
# failed a pack and a stage that carried the recorded build as never-ship;
# called with & from a script that had one, the way Publish-Update calls it, it
# passed a pack whose bundle had one byte changed.
function Test-ShipPath([string]$where, [string]$key, [string]$inner, $source) {
    $m = [regex]::Match($inner, '^(?:game|payload)[/\\](.+)$', 'IgnoreCase')
    if (-not $m.Success) { return }
    $rel = $m.Groups[1].Value -replace '/', '\'
    if (Test-ShipRuntime $rel) { Write-Hit $where $key '0' 'never-ship-runtime' $false; return }
    if ($ShipClientFiles.Contains($rel)) {
        if (-not (Test-ClientBytes $rel $source)) { Write-Hit $where $key '0' 'client-not-recorded-build' $false }
        return
    }
    # Bethesda's game, its Creation Kit or a copy of one of its programs, and
    # backups (#1152): named apart from the machine's own files, because they
    # are never ours to give. The same question the record guard and the
    # rollback filter ask (Test-ShipBethesda, #1229).
    if (Test-ShipBethesda $rel) { Write-Hit $where $key '0' 'never-ship-bethesda' $false; return }
    if (Test-ShipBackup $rel) { Write-Hit $where $key '0' 'never-ship-backup' $false; return }
    # One machine's own by kind (#1239): its runtime state and tokens in
    # Data\Platform, logs, Vortex's records, window layouts, settings saved from
    # a mod's menu, saves. The question the record guard, the rollback filter
    # and Scrub-Feed ask. Other servers' files and other people's frameworks
    # are the rest of Test-ShipMachine.
    if ((Test-ShipOneMachine $rel) -or (Test-ShipMachine $rel)) { Write-Hit $where $key '0' 'never-ship-machine' $false; return }
}

function Test-TextBytes([string]$where, [string]$key, [byte[]]$b) {
    $hits = [ThornswoodSecretScan1]::ScanText($b)
    if ($null -eq $hits) { return }
    $script:read++
    foreach ($h in $hits) {
        $p = $h -split "`t"
        Write-Hit $where $key $p[1] $p[0] $false
    }
}

function Test-Bytes([string]$where, [string]$key, [byte[]]$b) {
    foreach ($h in [ThornswoodSecretScan1]::ScanBinary($b)) {
        $p = $h -split "`t"
        Write-Hit $where $key $p[1] $p[0] $true
    }
}

function Read-Entry($entry) {
    $ms = New-Object IO.MemoryStream
    $s = $entry.Open()
    try { $s.CopyTo($ms) } finally { $s.Dispose() }
    return ,$ms.ToArray()
}

# ---------------------------------------------------------------- modes
function Invoke-Tree([string]$root) {
    if (-not $root) { $root = Split-Path -Parent (Split-Path -Parent $Here) }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $files = @(& git -C $root -c core.quotepath=off ls-files 2>$null)
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0 -or -not $files.Count) { Write-Unread $root 'git ls-files gave no list of tracked files'; return }
    foreach ($rel in $files) {
        if (-not $rel) { continue }
        Test-Name $rel $rel (Split-Path $rel -Leaf) $true
        $full = Join-Path $root $rel
        # Tracked but deleted in this working copy: nothing to read.
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $ext = [IO.Path]::GetExtension($rel).ToLowerInvariant()
        if ($BinaryExts -contains $ext) { continue }
        $len = (Get-Item -LiteralPath $full -Force).Length
        if ($len -gt $TextCap) { Write-Unread $rel 'larger than the text cap'; continue }
        Test-TextBytes $rel $rel ([IO.File]::ReadAllBytes($full))
    }
    Write-Host ('  {0} tracked files, {1} read as text' -f $files.Count, $script:read)
}

function Invoke-Zip([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Unread $path 'no such file'; return }
    $leaf = Split-Path $path -Leaf
    try { $z = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $path).ProviderPath) }
    catch { Write-Unread $leaf 'it does not open as a zip'; return }
    try {
        $n = 0
        foreach ($e in $z.Entries) {
            $inner = $e.FullName -replace '\\', '/'
            if ($inner.EndsWith('/')) { continue }
            $n++
            $where = $leaf + '!' + $inner
            $name = Split-Path $inner -Leaf
            Test-Name $where $inner $name $false
            Test-ShipPath $where $inner $inner $e
            $ext = [IO.Path]::GetExtension($name).ToLowerInvariant()
            # The launcher at the top of the installer is ours and built here,
            # so it is read byte by byte. Every other program is somebody's mod.
            if ($ext -eq '.exe' -and $inner.IndexOf('/') -lt 0) {
                if ($e.Length -gt $TextCap) { Write-Unread $where 'larger than the text cap'; continue }
                Test-Bytes $where $inner (Read-Entry $e)
                continue
            }
            if ($BinaryExts -contains $ext) { continue }
            if ($e.Length -gt $TextCap) { Write-Unread $where 'larger than the text cap'; continue }
            Test-TextBytes $where $inner (Read-Entry $e)
        }
        Write-Host ('  {0}: {1} entries' -f $leaf, $n)
    } finally { $z.Dispose() }
}

function Invoke-Dir([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { Write-Unread $dir 'no such folder'; return }
    $base = (Resolve-Path -LiteralPath $dir).ProviderPath.TrimEnd('\') + '\'
    $n = 0
    foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
        $n++
        $rel = $f.FullName.Substring($base.Length)
        $key = $rel -replace '\\', '/'
        Test-Name $rel $key $f.Name $false
        Test-ShipPath $rel $key $key $f.FullName
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -eq '.exe' -and $rel.IndexOf('\') -lt 0) {
            Test-Bytes $rel $key ([IO.File]::ReadAllBytes($f.FullName))
            continue
        }
        if ($BinaryExts -contains $ext) { continue }
        if ($f.Length -gt $TextCap) { Write-Unread $rel 'larger than the text cap'; continue }
        Test-TextBytes $rel $key ([IO.File]::ReadAllBytes($f.FullName))
    }
    Write-Host ('  {0}: {1} files' -f $dir, $n)
}

function Invoke-Binary([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Unread $path 'no such file'; return }
    $leaf = Split-Path $path -Leaf
    Test-Bytes $path $leaf ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path).ProviderPath))
    Write-Host ('  {0}: read byte by byte' -f $leaf)
}

try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $any = $false
    foreach ($z in $Zip) { if ($z) { $any = $true; Invoke-Zip $z } }
    if ($Dir) { $any = $true; Invoke-Dir $Dir }
    foreach ($b in $Binary) { if ($b) { $any = $true; Invoke-Binary $b } }
    if (-not $any) { Invoke-Tree $Root }
} catch {
    # The message only, which says what failed and not what a file held.
    Write-Unread 'the scan' $_.Exception.Message
}

if ($script:allowed) { Write-Host ('  {0} known non-secret(s) passed by Check-Secrets.allow.txt' -f $script:allowed) -ForegroundColor DarkGray }
if ($script:found) {
    Write-Host ('{0} thing(s) that must never ship. Each line above names the file and the rule, never the value.' -f $script:found) -ForegroundColor Red
    exit 1
}
if ($script:unread) {
    Write-Host ('Nothing found, but {0} thing(s) could not be read, so this is not a pass.' -f $script:unread) -ForegroundColor Yellow
    exit 2
}
Write-Host 'No secrets found.' -ForegroundColor Green
exit 0
