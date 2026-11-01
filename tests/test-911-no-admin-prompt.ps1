<#
  test-browser-args.ps1

      pwsh -NoProfile -File .\tests\test-browser-args.ps1

  Nothing Thornswood runs asks for administrator or gives Windows Firewall a
  reason to ask. Issue #911.

  Patrick, 28 September: "we need to get it so it doesn't do that
  administrator prompt for the firewall rule", then "I also want to allow for
  the emotes/voice chat/text chat without the admin prompt".

  Windows Firewall asks about a program that listens on the network. It does
  not ask about outbound connections (the chat and voice sockets, the site)
  or about listeners on 127.0.0.1. So this holds the launcher to:

    1. BrowserArgs.DisableFeature merges into one --disable-features switch.
       Chromium keeps only the last copy of a switch, so a second one would
       quietly undo the first.
    2. The voice browser (WebView2) is started with WebRtcHideLocalIpsWithMdns
       off, set before its environment is created. That feature is an mDNS
       responder on UDP 5353 on every network: a listener. Microsoft's
       machine-wide WebView2 carries a rule for it; the copy the launcher
       installs for one account when there is none does not.
    3. Every HttpListener the launcher opens is on 127.0.0.1.
    4. The launcher asks for asInvoker, and no launcher, installer or game
       file asks for elevation or writes a firewall rule.

  The in-game side (the voice page making no WebRTC connection once the
  launcher has the audio) is tests\test-voice-relay-no-peers.js.

  HOW. Compiles the shipped launcher\app\BrowserArgs.cs by itself, with the
  compiler the build runs (Add-LauncherType, tests\Launcher-Csc.ps1, #2821),
  and calls it; reads the other files as text. Read only. Off Windows, 1 says
  SKIP: the build's compiler is only there.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'launcher\app'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#2821)

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# ------------------------------------------------------------ 1. the merge
if ($OnWindows) {
    $cs = Get-Content -LiteralPath (Join-Path $app 'BrowserArgs.cs') -Raw
    $cs = $cs -replace 'namespace Thornswood', 'namespace ThornswoodBrowserArgsTest'
    $null = Add-LauncherType -Source $cs
    $T = [ThornswoodBrowserArgsTest.BrowserArgs]
    $f = $T::NoMdns

    Yes 'the feature is the one Chromium calls WebRtcHideLocalIpsWithMdns' ($f -eq 'WebRtcHideLocalIpsWithMdns')
    Yes 'nothing set yet: one switch' ($T::DisableFeature($null, $f) -eq "--disable-features=$f")
    Yes 'an empty value: one switch' ($T::DisableFeature('  ', $f) -eq "--disable-features=$f")
    Yes 'beside another switch, added after it' `
        ($T::DisableFeature('--autoplay-policy=no-user-gesture-required', $f) -eq "--autoplay-policy=no-user-gesture-required --disable-features=$f")
    Yes 'an existing --disable-features gets it inside, not a second switch' `
        ($T::DisableFeature('--disable-features=Foo --x=1', $f) -eq "--disable-features=Foo,$f --x=1")
    Yes 'at the end of the line too' `
        ($T::DisableFeature('--x=1 --disable-features=Foo,Bar', $f) -eq "--x=1 --disable-features=Foo,Bar,$f")
    $once = $T::DisableFeature('--disable-features=Foo', $f)
    Yes 'already off: unchanged' ($T::DisableFeature($once, $f) -eq $once)
    Yes 'already off in another case: unchanged' ($T::DisableFeature('--disable-features=webrtchidelocalipswithmdns', $f) -eq '--disable-features=webrtchidelocalipswithmdns')
    $n = ([regex]::Matches($T::DisableFeature($T::DisableFeature('--disable-features=A', $f), 'B'), '--disable-features=')).Count
    Yes 'two features, still one switch' ($n -eq 1)
}
else {
    Write-Host 'SKIP  1, BrowserArgs.cs compiled and asked: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'
}

# ------------------------------------------------ 2. the voice browser uses it
$voice = Get-Content -LiteralPath (Join-Path $app 'Voice.cs') -Raw
$set = $voice.IndexOf('BrowserArgs.NoMdns')
$create = $voice.IndexOf('CoreWebView2Environment.CreateAsync')
Yes 'Voice.cs turns mDNS off for the voice browser' ($set -ge 0)
Yes 'before the environment is created, which is when WebView2 reads it' ($set -ge 0 -and $create -gt $set)
Yes 'through WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS, not the options that faulted' `
    ($voice -match 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS' -and $voice -notmatch 'CoreWebView2EnvironmentOptions\s*\(')
$music = Get-Content -LiteralPath (Join-Path $app 'MenuMusic.cs') -Raw
Yes 'menu music sets no browser switches: it plays from the launcher, not a browser (#3207)' `
    ($music -notmatch 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS' -and $music -notmatch 'Microsoft\.Web\.WebView2')

# ------------------------------------------------ 3. listeners are loopback
$cs = @(Get-ChildItem -LiteralPath $app -Filter *.cs -File)
$prefixes = @()
foreach ($file in $cs) {
    foreach ($m in [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), 'Prefixes\.Add\(\s*"([^"]*)"')) {
        $prefixes += [pscustomobject]@{ File = $file.Name; Prefix = $m.Groups[1].Value }
    }
}
Yes 'the launcher has HttpListeners to check (voice push to talk, Discord sign in)' ($prefixes.Count -ge 2)
$wide = @($prefixes | Where-Object { $_.Prefix -notmatch '^http://127\.0\.0\.1:' })
Yes ('every HttpListener is on 127.0.0.1' + $(if ($wide) { ' (' + (($wide | ForEach-Object { $_.File + ' ' + $_.Prefix }) -join ', ') + ')' } else { '' })) ($wide.Count -eq 0)
$raw = @($cs | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'new\s+TcpListener|new\s+UdpClient\s*\(\s*\d|IPAddress\.Any|IPAddress\.IPv6Any' })
Yes ('no TcpListener, UdpClient on a port, or bind to every address' + $(if ($raw) { ' (' + (($raw | ForEach-Object Name) -join ', ') + ')' } else { '' })) ($raw.Count -eq 0)

# ------------------------------------------------ 4. nothing elevates
$manifest = Get-Content -LiteralPath (Join-Path $app 'Thornswood.manifest') -Raw
Yes 'the launcher asks for asInvoker' ($manifest -match 'requestedExecutionLevel\s+level="asInvoker"')
$files = @()
foreach ($dir in 'launcher', 'installer', 'game\plugins', 'game\ui') {
    $files += @(Get-ChildItem -LiteralPath (Join-Path $root $dir) -Recurse -File -Include *.cs, *.ps1, *.js, *.xaml, *.html, *.manifest)
}
$asks = @($files | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw) -match '"runas"|-Verb\s+RunAs|advfirewall|NetFirewallRule|HNetCfg\.FwPolicy|requireAdministrator|highestAvailable'
})
Yes ('no launcher, installer or game file elevates or writes a firewall rule' + $(if ($asks) { ' (' + (($asks | ForEach-Object Name) -join ', ') + ')' } else { '' })) ($asks.Count -eq 0)
Yes 'there is no Firewall.cs' (-not (Test-Path -LiteralPath (Join-Path $app 'Firewall.cs')))

Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
exit 0
