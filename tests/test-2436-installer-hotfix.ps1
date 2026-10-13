# test-2436-installer-hotfix.ps1
#
# #2436: main 1.2.4 shipped from hotfix/1.2.4 on 12 Oct, which Ship accepts,
# and then Package-Thornswood.ps1 refused the same checkout ("behind main by
# 4 commit(s)"), and with -AllowStaleCheckout it built the installer but its
# own call to Publish-Installer.ps1 refused again, because Package did not
# pass the override on. Both asked Assert-FreshCheckout for origin/main only.
# Now both ask Ship's rule for a live release, Test-FreshAnyBranch -Channel
# main (scripts\deploy\Fresh-Checkout.ps1, shared, not copied), and Package
# hands Publish-Installer its -AllowStaleCheckout, as Ship hands it to
# Package and Publish-Update.
#
# A. The question each script asks, taken out of the script's own text and
#    run against scratch git repos (a bare "origin" in a temp folder and
#    clones of it, so git never leaves this machine): a clean hotfix/ branch
#    that matches its origin branch is let through, a hotfix/ branch behind
#    its origin branch is refused, a feature branch is refused, a dirty
#    hotfix is refused, and current main is let through.
# B. The scripts: Package passes -AllowStaleCheckout to Publish-Installer,
#    Ship passes it to Package, and neither installer script asks for main
#    alone any more.
# Package and Publish-Installer are never run whole. Runs under Stop, as 5.1 would.
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Repo = Split-Path -Parent $Here
$pass = 0; $fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
$env:THORNSWOOD_HARNESS = ''
. (Join-Path $Repo 'scripts\deploy\Fresh-Checkout.ps1')

function Read-Script([string]$rel) { return ((Get-Content -Raw (Join-Path $Repo $rel)) -replace "`r", '') }
$pkgText = Read-Script 'scripts\release\Package-Thornswood.ps1'
$pubText = Read-Script 'scripts\release\Publish-Installer.ps1'
$shipText = Read-Script 'scripts\release\Ship.ps1'

# The one Assert-FreshCheckout line in each script, exactly as written.
function Get-FreshLine([string]$text, [string]$who) {
    $m = [regex]::Matches($text, "(?m)^Assert-FreshCheckout [^\n]*-What '$who'[^\n]*$")
    if ($m.Count -ne 1) { return '' }
    return $m[0].Value
}
$pkgLine = Get-FreshLine $pkgText 'Package-Thornswood'
$pubLine = Get-FreshLine $pubText 'Publish-Installer'
Yes 'Package-Thornswood has one Assert-FreshCheckout line' ([bool]$pkgLine)
Yes 'Publish-Installer has one Assert-FreshCheckout line' ([bool]$pubLine)

# Runs a script's own line with $freshRepo pointed at a scratch clone, the
# way the script runs it with $freshRepo pointed at the repository. '' is a
# pass, anything else the refusal.
function Ask([string]$line, [string]$dir, [bool]$stale = $false) {
    $env:THORNSWOOD_FRESH_CHECKED = ''
    $freshRepo = $dir; $Vps = ''; $AllowStaleCheckout = [switch]$stale
    try { & ([scriptblock]::Create($line)) *> $null; return '' }
    catch { return $_.Exception.Message }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-2436-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
function G([string]$dir) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git -C $dir @args 2>&1 | Out-Null
    $c = $LASTEXITCODE; $ErrorActionPreference = $old
    if ($c -ne 0) { throw "git $($args -join ' ') failed in $dir ($c)" }
}
function Commit([string]$dir, [string]$name) {
    Set-Content -LiteralPath (Join-Path $dir $name) -Value $name
    G $dir add -- $name
    G $dir -c user.name=t -c user.email=t@t commit -q -m $name
}

try {
    if ($pkgLine -and $pubLine) {
        $origin = Join-Path $tmp 'origin.git'
        G $tmp init -q --bare -b main $origin
        $seed = Join-Path $tmp 'seed'
        G $tmp clone -q $origin $seed
        G $seed checkout -q -b main
        Commit $seed 'a.txt'
        G $seed push -q origin main
        $me = Join-Path $tmp 'me'
        G $tmp clone -q $origin $me

        # The reported case: hotfix/ from the live build, its fix pushed,
        # and main four commits on.
        G $me checkout -q -b hotfix/1.2.4 origin/main
        Commit $me 'fix.txt'
        G $me push -q -u origin hotfix/1.2.4
        foreach ($n in 'b', 'c', 'd', 'e') { Commit $seed "$n.txt" }
        G $seed push -q origin main
        G $me fetch -q origin

        $p = Ask $pkgLine $me; $q = Ask $pubLine $me
        Yes 'A1 a clean hotfix/ branch that matches its origin branch: Package-Thornswood lets it through' ($p -eq '')
        Yes 'A2 and so does Publish-Installer' ($q -eq '')
        $old = ''; $env:THORNSWOOD_FRESH_CHECKED = ''
        try { Assert-FreshCheckout -RepoDir $me -What 'Package-Thornswood' *> $null } catch { $old = $_.Exception.Message }
        Yes "A3 (the old question, origin/main only, refused it: $old)" ($old -match 'origin/main')

        # One process, Package then Publish-Installer: the second check is
        # the same question, so it passes on the first one's answer.
        $env:THORNSWOOD_FRESH_CHECKED = ''
        $freshRepo = $me; $Vps = ''; $AllowStaleCheckout = [switch]$false
        $second = 'not run'
        try {
            & ([scriptblock]::Create($pkgLine)) *> $null
            $second = ''
            try { & ([scriptblock]::Create($pubLine)) *> $null } catch { $second = $_.Exception.Message }
        } catch { $second = 'Package refused: ' + $_.Exception.Message }
        Yes 'A4 Package then Publish-Installer in one run: the second passes on the first one''s answer' ($second -eq '')

        # The hotfix branch moved on GitHub and this checkout is behind it.
        $other = Join-Path $tmp 'other'
        G $tmp clone -q $origin $other
        G $other checkout -q hotfix/1.2.4
        Commit $other 'second-fix.txt'
        G $other push -q origin hotfix/1.2.4
        $p = Ask $pkgLine $me; $q = Ask $pubLine $me
        Yes "A5 a hotfix/ branch behind its origin branch: Package-Thornswood refuses: $p" ($p -match '^Package-Thornswood refused' -and $p -match 'behind hotfix/1\.2\.4 by 1')
        Yes "A6 and so does Publish-Installer: $q" ($q -match '^Publish-Installer refused' -and $q -match 'behind hotfix/1\.2\.4 by 1')
        G $me pull -q origin hotfix/1.2.4

        # Uncommitted work on the hotfix.
        Set-Content -LiteralPath (Join-Path $me 'fix.txt') -Value 'changed'
        $p = Ask $pkgLine $me; $q = Ask $pubLine $me
        Yes "A7 a dirty hotfix/ branch: both refuse: $p" ($p -match 'uncommitted change' -and $q -match 'uncommitted change')
        G $me checkout -q -- fix.txt

        # A feature branch, pushed and clean, is not a live source.
        G $me checkout -q -b claude/feature origin/main
        Commit $me 'feature.txt'
        G $me push -q -u origin claude/feature
        $p = Ask $pkgLine $me; $q = Ask $pubLine $me
        Yes "A8 a pushed feature branch: Package-Thornswood refuses against origin/main: $p" ($p -match '^Package-Thornswood refused' -and $p -match 'origin/main')
        Yes "A9 and so does Publish-Installer: $q" ($q -match '^Publish-Installer refused' -and $q -match 'origin/main')
        Yes 'A10 and -AllowStaleCheckout still goes past it, loudly' ((Ask $pkgLine $me $true) -eq '' -and (Ask $pubLine $me $true) -eq '')

        # Current main.
        G $me checkout -q main
        G $me pull -q origin main
        Yes 'A11 current main: both let it through' ((Ask $pkgLine $me) -eq '' -and (Ask $pubLine $me) -eq '')
        G $me reset -q --hard HEAD~1
        $p = Ask $pkgLine $me
        Yes "A12 main behind origin/main: refused: $p" ($p -match 'behind main by 1')
    }
} finally {
    $env:THORNSWOOD_FRESH_CHECKED = ''
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# B. The scripts.
$rule = "-AnyBranch:(Test-FreshAnyBranch -RepoDir `$freshRepo -Channel main)"
Yes 'B1 Package-Thornswood asks Ship''s rule for a live release' ($pkgLine.Contains($rule) -and $pkgLine.Contains('-AllowStale:$AllowStaleCheckout'))
Yes 'B2 Publish-Installer asks the same' ($pubLine.Contains($rule) -and $pubLine.Contains('-AllowStale:$AllowStaleCheckout'))
Yes 'B3 Ship asks the same function (one rule, not a copy)' ($shipText.Contains("-AnyBranch:(Test-FreshAnyBranch -RepoDir `$freshRepo -Channel `$Channel)"))
Yes 'B4 Package passes -AllowStaleCheckout on to Publish-Installer' ($pkgText.Contains("if (`$AllowStaleCheckout) { `$pubArgs['AllowStaleCheckout'] = `$true }") -and $pkgText.Contains('& $pub @pubArgs'))
Yes 'B5 and passes -OneFile on as before' ($pkgText.Contains("if (`$OneFile) { `$pubArgs['OneFile'] = `$true }"))
Yes 'B6 Ship passes -AllowStaleCheckout on to Package' ($shipText.Contains("if (`$AllowStaleCheckout) { `$pkgArgs['AllowStaleCheckout'] = `$true }"))
$shipAt = $shipText.IndexOf("if (`$AllowStaleCheckout) { `$pkgArgs['AllowStaleCheckout'] = `$true }")
$callAt = $shipText.IndexOf("& (Join-Path `$Here 'Package-Thornswood.ps1') @pkgArgs")
Yes 'B7 before it calls Package' ($shipAt -gt 0 -and $callAt -gt $shipAt)

Write-Host ''
Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
