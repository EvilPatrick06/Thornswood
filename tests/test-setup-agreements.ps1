<#
  test-setup-agreements.ps1

      powershell -NoProfile -STA -File .\tests\test-setup-agreements.ps1
      powershell -NoProfile -STA -File .\tests\test-setup-agreements.ps1 -Live

  The setup window locks Install behind the terms, the privacy policy and the
  rules, each with a link to its page on the site, and notes what was accepted.

  Issue #1009, Patrick on 28 September: "I want on the installer check boxes
  that lock the install for reading and accepting terms and conditions,
  privacy policy, and agreeing to the rules", "And links to all 3".

  What this holds installer\setup\Bootstrap.cs to:
    - the window, parsed out of Bootstrap.cs's own markup, has three unticked
      boxes with the agreed words, each beside a link to its page on
      https://thornswood.net (terms, privacy, rules), and the age box is kept;
    - the gate, compiled out of Bootstrap.cs and wired to that parsed window,
      leaves Install off for every one of the sixteen ways the four boxes can
      be ticked except all four, and turns it off again when one is unticked;
    - Run wires the gate and the links, Install locks the boxes, and Work
      writes Profile\accepted.json before the install script starts;
    - the record says when and which version of each page (a SHA-256 of the
      page's text as the site serves it), and nothing about the person;
    - the one Process.Start opens only the site's own pages;
    - no em dash and never the word the project does not use.

  -Live also asks the site: each link answers 200 over https, and the record
  the setup program writes carries the same hashes as the pages served now.

  WPF needs a single threaded apartment. Run from anything else, this starts
  itself again under Windows PowerShell with -STA.
#>
[CmdletBinding()]
param([string]$Root, [switch]$Live)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Root) { $Root = Split-Path -Parent $Here }

. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $OnWindows) { Write-Host 'NOT RUN  the setup program''s agreement pages are WPF, which only Windows has'; exit 0 }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA' -or $PSVersionTable.PSEdition -eq 'Core') {
    $args2 = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path, '-Root', $Root)
    if ($Live) { $args2 += '-Live' }
    & (Get-WindowsPowerShell) @args2
    exit $LASTEXITCODE
}

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

# A C# method by its head and a brace match that steps over strings and line
# comments, the same reader test-setup-in-window.ps1 uses.
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

$bsPath = Join-Path $Root 'installer\setup\Bootstrap.cs'
$bs = [IO.File]::ReadAllText($bsPath)

$pages = [ordered]@{
    terms   = @{ Box = 'ChkTerms';   Link = 'LnkTerms';   Words = 'I have read and accept the Terms and Conditions'; File = 'terms.md' }
    privacy = @{ Box = 'ChkPrivacy'; Link = 'LnkPrivacy'; Words = 'I have read and accept the Privacy Policy';       File = 'privacy.md' }
    rules   = @{ Box = 'ChkRules';   Link = 'LnkRules';   Words = 'I have read and agree to the Rules';              File = 'rules.md' }
}

# ---- 1. the block, compiled -------------------------------------------------
$a = $bs.IndexOf('// ==== the three pages a person accepts ====')
$b = $bs.IndexOf('// ==== end the three pages a person accepts ====')
Yes 'Bootstrap.cs has the three pages block' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) { Done }
$block = $bs.Substring($a, $b - $a)
$site = [regex]::Match($bs, 'const string Site = "([^"]+)";')
Yes 'and the one site it is built for' ($site.Success -and $site.Groups[1].Value -eq 'https://thornswood.net')

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$refs = @(
    [Windows.Window].Assembly.Location
    [Windows.UIElement].Assembly.Location
    [Windows.DependencyObject].Assembly.Location
    [Xaml.XamlReader].Assembly.Location
    'System.Xml'
)
# Warnings are the fields Run and Start use and this copy does not.
Add-Type -IgnoreWarnings -ReferencedAssemblies $refs -TypeDefinition (@'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Controls;
public static class Ts1009 {
    const string Site = "https://thornswood.net";
    static Window win;
    static void Say(string s) { }
'@ + "`n" + $block + "`n" + @'
    public static string[] PageNames() { return Pages; }
    public static CheckBox[] Find(FrameworkElement w) { return FindAgreements(w); }
    public static void Lock(Button go, CheckBox[] boxes) { Gate(go, boxes); }
    public static string Json(string doc, string key) { return JsonString(doc, key); }
    public static string Sha(string md) { return PageSha(md); }
    public static string Record(DateTime at, string[] shas) { return AcceptanceJson(at, shas); }
    public static void Write(string dir, DateTime at) { RecordAcceptance(dir, at); }
    public static string FileName() { return AcceptedFile; }
}
'@)
Yes 'the block compiles on its own' ($true)
$names = [Ts1009]::PageNames()
Yes 'the pages are terms, privacy and rules, in that order' (($names -join ',') -eq 'terms,privacy,rules')

# ---- 2. the window, from Bootstrap.cs's own markup --------------------------
$u = [regex]::Match($bs, '(?s)const string Ui = @"(.*?</Window>)";')
Yes 'the window markup is where this expects it' ($u.Success)
if (-not $u.Success) { Done }
$xaml = $u.Groups[1].Value.Replace('""', '"')
$win = [Windows.Markup.XamlReader]::Parse($xaml)
Yes 'the window parses' ($null -ne $win)

$age = $win.FindName('ChkAge')
$go = $win.FindName('BtnGo')
Yes 'the age box is still there' ($null -ne $age -and $age.Content.Text -eq 'I am 18 or over. Thornswood is an adult server.')
Yes 'Install starts off' ($null -ne $go -and -not $go.IsEnabled)

$found = [Ts1009]::Find($win)
Yes 'FindAgreements finds all three boxes' ($null -ne $found -and $found.Count -eq 3)
$i = 0
foreach ($k in $pages.Keys) {
    $p = $pages[$k]
    $box = $win.FindName($p.Box)
    Yes ("the $k box is there") ($null -ne $box)
    if ($null -eq $box) { continue }
    Yes ("and says: " + $p.Words) ($box.Content.Text -eq $p.Words)
    Yes ("and starts unticked") ($box.IsChecked -ne $true)
    Yes ("and is the one FindAgreements gives in place " + $i) ($null -ne $found -and [object]::ReferenceEquals($found[$i], $box))
    $link = $win.FindName($p.Link)
    Yes ("the $k link is there") ($null -ne $link -and $link -is [Windows.Documents.Hyperlink])
    if ($null -ne $link) {
        $want = 'https://thornswood.net/' + $k
        Yes ("and points at $want") ($link.NavigateUri.AbsoluteUri -eq $want)
        Yes ('and sits beside its box, not inside it, so opening it does not tick it') (
            -not ($box.Content -is [Windows.Controls.TextBlock] -and @($box.Content.Inlines | Where-Object { $_ -is [Windows.Documents.Hyperlink] }).Count))
        $page = Join-Path $Root ('site\data\site\' + $p.File)
        Yes ("and the site has that page, site\data\site\" + $p.File) (Test-Path -LiteralPath $page)
    }
    $i++
}
$srv = [IO.File]::ReadAllText((Join-Path $Root 'site\server.js'))
$md = [regex]::Match($srv, "const MD_PAGES = \[([^\]]+)\]")
Yes 'the site serves all three as written pages' ($md.Success -and $md.Groups[1].Value.Contains("'/terms'") -and
    $md.Groups[1].Value.Contains("'/privacy'") -and $md.Groups[1].Value.Contains("'/rules'"))
# Since #1020 the answer also carries the text's sha256 and the day it last
# changed, after the md and the html this reads.
Yes 'and answers /api/page/<name> with the text' ($srv.Contains('/^\/api\/page\/([a-z-]+)$/') -and
    ($srv -match 'sendJson\(res, 200, \{\s*md: md, html: pageHtml\(md\)'))

# ---- 3. Install is locked until all four are ticked -------------------------
$all = @($age) + @($found)
[Ts1009]::Lock($go, [Windows.Controls.CheckBox[]]$all)
Yes 'the gate leaves Install off with nothing ticked' (-not $go.IsEnabled)
$onFor = @()
for ($m = 0; $m -lt 16; $m++) {
    for ($j = 0; $j -lt 4; $j++) { $all[$j].IsChecked = [bool]($m -band (1 -shl $j)) }
    if ($go.IsEnabled) { $onFor += $m }
}
Yes 'of the sixteen ways to tick the four boxes, only all four turns Install on' ($onFor.Count -eq 1 -and $onFor[0] -eq 15)
foreach ($j in 0..3) {
    foreach ($x in $all) { $x.IsChecked = $true }
    $wasOn = $go.IsEnabled
    $all[$j].IsChecked = $false
    Yes ('unticking ' + $all[$j].Name + ' turns Install off again') ($wasOn -and -not $go.IsEnabled)
}

# ---- 4. where it is wired ---------------------------------------------------
$run = Get-Method $bs 'static void Run('
Yes 'Run finds the three boxes and the links' ($run.Contains('agree = FindAgreements(win);') -and $run.Contains('HookPageLinks(win);'))
$iAll = $run.IndexOf('all.Add(chkAge);')
Yes 'and gates Install on the age box and all three' ($iAll -gt 0 -and $run.IndexOf('all.AddRange(agree);') -gt $iAll -and
    $run.IndexOf('Gate(btnGo, all.ToArray());') -gt $iAll)
Yes 'with Install off first' ($run.Contains('btnGo.IsEnabled = false;'))
$start = Get-Method $bs 'static void Start('
Yes 'Install locks the boxes and notes the time' ($start.Contains('foreach (CheckBox c in agree) c.IsEnabled = false;') -and
    $start.Contains('acceptedAt = DateTime.UtcNow;') -and $start.IndexOf('acceptedAt = DateTime.UtcNow;') -lt $start.IndexOf('new Thread(Work)'))
$work = Get-Method $bs 'static void Work('
$iRec = $work.IndexOf('RecordAcceptance(Path.Combine(installRoot, "Profile"), acceptedAt);')
Yes 'Work writes the record into the install''s Profile folder before the script starts' (
    $iRec -gt 0 -and $work.IndexOf('RunSetupScript(') -gt $iRec)
$hook = Get-Method $block 'static void HookPageLinks('
Yes 'each link opens its page through OpenPage' ($hook.Contains('link.RequestNavigate +=') -and $hook.Contains('OpenPage(e.Uri);'))
$open = Get-Method $block 'static void OpenPage('
Yes 'OpenPage opens nothing but the site''s own pages' ($open.Contains('if (!url.StartsWith(Site + "/", StringComparison.OrdinalIgnoreCase)) return;') -and
    $open.IndexOf('StartsWith(Site') -lt $open.IndexOf('Process.Start('))
Yes 'and it is the one Process.Start in the setup program' (@([regex]::Matches($bs, 'Process\.Start\(')).Count -eq 1 -and $open.Contains('Process.Start('))

# ---- 5. the record ----------------------------------------------------------
$doc = '{"md":"# T\r\n\u00e9 \"q\" \\ \/ \ud83d\ude00 end","html":"<h1>T</h1>"}'
$want = ($doc | ConvertFrom-Json).md
Yes 'JsonString reads the page text as a JSON reader does' ([Ts1009]::Json($doc, 'md') -eq $want)
Yes 'and gives nothing for a key that is not there' ($null -eq [Ts1009]::Json($doc, 'nope'))
$sha = [Security.Cryptography.SHA256]::Create()
$hex = (($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($want)) | ForEach-Object { $_.ToString('x2') }) -join '')
Yes 'PageSha is the SHA-256 of the text as UTF-8' ([Ts1009]::Sha($want) -eq $hex)
Yes 'and empty for no text' ([Ts1009]::Sha([NullString]::Value) -eq '')

$at = [DateTime]::new(2026, 9, 28, 23, 40, 5, [DateTimeKind]::Utc)
$rec = [Ts1009]::Record($at, @(('a' * 64), '', ('c' * 64)))
$j = $rec | ConvertFrom-Json
Yes 'the record is JSON' ($null -ne $j)
Yes 'with when it was accepted, in UTC' ($j.accepted -is [DateTime] -or $j.accepted -eq '2026-09-28T23:40:05Z')
Yes 'written as 2026-09-28T23:40:05Z' ($rec.Contains('"accepted": "2026-09-28T23:40:05Z"'))
Yes 'each page with its address and version' ($j.pages.terms.url -eq 'https://thornswood.net/terms' -and $j.pages.terms.sha256 -eq ('a' * 64) -and
    $j.pages.privacy.url -eq 'https://thornswood.net/privacy' -and $j.pages.privacy.sha256 -eq '' -and
    $j.pages.rules.url -eq 'https://thornswood.net/rules' -and $j.pages.rules.sha256 -eq ('c' * 64))
Yes 'and nothing else about anybody' ((@($j.PSObject.Properties.Name) -join ',') -eq 'accepted,pages,about')
Yes 'the file is accepted.json' ([Ts1009]::FileName() -eq 'accepted.json')

# ---- 6. the words -----------------------------------------------------------
$bar = [regex]::Match($xaml, '(?s)<CheckBox x:Name="ChkAge".*?<StackPanel Grid.Column="1"').Value
$mine = $block + "`n" + $bar
Yes 'the words this added are all there to check' ($bar.Length -gt 1000 -and $block.Length -gt 3000)
Yes 'no em dash in them' ($mine.IndexOf([char]0x2014) -lt 0)
Yes 'and never the word the project does not use' ($mine -notmatch '(?i)\bplayers?\b')
Yes 'no em dash anywhere in the setup program' ($bs.IndexOf([char]0x2014) -lt 0)

# ---- 7. the live site, when asked -------------------------------------------
if ($Live) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    foreach ($k in $pages.Keys) {
        $code = 0
        try { $code = (Invoke-WebRequest -UseBasicParsing -Uri ('https://thornswood.net/' + $k)).StatusCode } catch { }
        Yes ("https://thornswood.net/$k answers 200") ($code -eq 200)
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-1009-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $prof = Join-Path $tmp 'Profile'
        [Ts1009]::Write($prof, [DateTime]::UtcNow)
        $file = Join-Path $prof 'accepted.json'
        Yes 'the setup program writes Profile\accepted.json' (Test-Path -LiteralPath $file)
        if (Test-Path -LiteralPath $file) {
            $got = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            foreach ($k in $pages.Keys) {
                $served = (Invoke-RestMethod -Uri ('https://thornswood.net/api/page/' + $k)).md
                $h = (($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($served)) | ForEach-Object { $_.ToString('x2') }) -join '')
                Yes ("and its $k version is the page the site serves now, " + $h.Substring(0, 12)) ($got.pages.$k.sha256 -eq $h)
            }
        }
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Done
