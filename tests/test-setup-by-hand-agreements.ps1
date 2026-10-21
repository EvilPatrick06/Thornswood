<#
  test-setup-by-hand-agreements.ps1

      pwsh -NoProfile -File .\tests\test-setup-by-hand-agreements.ps1

  Installing by hand from the payload asks the same four questions as the
  setup window (#1018).

  The setup window locks Install until the age box and the terms, privacy and
  rules boxes are ticked, and writes Profile\accepted.json (#1009). The
  payload it downloads also carries Setup.bat and Install.bat, which run
  installer\Setup-Thornswood.ps1 in a console for a person with an unpacked
  payload, and that installed with none of the four asked and no note.

  This runs the real Setup-Thornswood.ps1 out of a scratch payload (an empty
  payload folder beside it) with answers on standard input:
    - by hand, any no, or no answer at all, stops it with exit 1 before it
      writes anything, and no accepted.json;
    - four yeses write Profile\accepted.json in the shape the setup window
      writes, and it carries on to look for Skyrim (pointed at a folder that
      does not exist, so it stops there and installs nothing);
    - from the setup window (-NonInteractive) with no accepted.json it stops
      with exit 1 and writes nothing; with one it carries on.
  And by reading: the four questions are the window's own words, the pages
  are the window's three, and both .bat files run the asking way.

  The four yeses case asks https://thornswood.net/api/page/<name> for each
  page's text, as the setup window does; offline, each sha256 is empty and
  that is what is checked. Everything else it writes is in its own temp folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 } else { exit 0 }
}

$setupPath = Join-Path $Repo 'installer\Setup-Thornswood.ps1'
$bootPath  = Join-Path $Repo 'installer\setup\Bootstrap.cs'
$setup = [IO.File]::ReadAllText($setupPath)
$boot  = [IO.File]::ReadAllText($bootPath)

# ---- by reading ---------------------------------------------------------------
$tokens = $null; $errs = $null
[void][Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$errs)
Yes 'Setup-Thornswood.ps1 parses' ($errs.Count -eq 0)

$windowAge = [regex]::Match($boot, 'x:Name=""ChkAge""[\s\S]*?Text=""([^""]+)""').Groups[1].Value
Yes ('the age question is the window''s words: "' + $windowAge + '"') ($windowAge.Length -gt 0 -and $setup.Contains("'" + $windowAge + "'"))
$m = [regex]::Match($boot, 'static readonly string\[\] Pages = \{([^}]*)\};')
$windowPages = @([regex]::Matches($m.Groups[1].Value, '"(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Yes ('the window''s pages are ' + ($windowPages -join ', ')) ($windowPages.Count -eq 3)
foreach ($p in $windowPages) {
    $cap = $p.Substring(0, 1).ToUpper() + $p.Substring(1)
    $words = [regex]::Match($boot, 'x:Name=""Chk' + $cap + '""[\s\S]*?Text=""([^""]+)""').Groups[1].Value
    Yes ("the $p question is the window's words: `"$words`"") ($words.Length -gt 0 -and $setup -match ("(?m)^\s*$p\s*=\s*'" + [regex]::Escape($words) + "'\r?$"))
}
foreach ($bat in 'Install.bat', 'Setup.bat') {
    $t = [IO.File]::ReadAllText((Join-Path $Repo "installer\$bat"))
    Yes "$bat runs the script the asking way, without -NonInteractive" ($t.Contains('Setup-Thornswood.ps1') -and -not $t.Contains('NonInteractive'))
}
Yes 'the window still writes accepted.json before it starts the script' (
    $boot -match '(?s)RecordAcceptance\(Path\.Combine\(installRoot, "Profile"\), acceptedAt\);.{0,300}Setup-Thornswood\.ps1')
Yes 'the answers are asked before the script looks for Skyrim or writes anything' (
    $setup.IndexOf('# ------------------------------------------------------------- agreements') -gt 0 -and
    $setup.IndexOf('# ------------------------------------------------------------- agreements') -lt $setup.IndexOf("Head 'Finding Skyrim'") -and
    $setup.IndexOf('# ------------------------------------------------------------- agreements') -lt $setup.IndexOf('New-Item -ItemType Directory -Force -Path $ProfileDir, $LaunchDir'))

# ---- run it -------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-by-hand-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $pay = Join-Path $tmp 'unpacked'
    New-Item -ItemType Directory -Force -Path (Join-Path $pay 'payload') | Out-Null
    Copy-Item -LiteralPath $setupPath -Destination $pay
    $script = Join-Path $pay 'Setup-Thornswood.ps1'
    $noSkyrim = Join-Path $tmp 'no-skyrim-here'
    $ps = (Get-Process -Id $PID).Path

    function Run([string]$root, [string[]]$answers, [switch]$Window) {
        $p = New-Object Diagnostics.ProcessStartInfo($ps)
        $p.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script + '" -Root "' + $root + '" -SteamGamePath "' + $noSkyrim + '" -NoOpen'
        if ($Window) { $p.Arguments += ' -NonInteractive' }
        $p.UseShellExecute = $false; $p.CreateNoWindow = $true
        $p.RedirectStandardInput = $true; $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
        $proc = [Diagnostics.Process]::Start($p)
        foreach ($a in @($answers)) { $proc.StandardInput.WriteLine($a) }
        $proc.StandardInput.Close()
        $o = $proc.StandardOutput.ReadToEndAsync(); $e = $proc.StandardError.ReadToEndAsync()
        $done = $proc.WaitForExit(120000)
        if (-not $done) { try { $proc.Kill() } catch { } }
        [pscustomobject]@{ Done = $done; Code = $(if ($done) { $proc.ExitCode } else { -1 }); Out = $o.Result + $e.Result }
    }
    function Note([string]$root) { Join-Path $root 'Profile\accepted.json' }

    # ---- by hand: a no stops it ------------------------------------------------
    $cases = @(
        @{ Name = 'a no to the age question'; Answers = @('no') },
        @{ Name = 'a no to the rules, after three yeses'; Answers = @('yes', 'yes', 'yes', 'no') },
        @{ Name = 'an answer that is not yes'; Answers = @('yes', 'maybe') },
        @{ Name = 'no answer at all, the input shut'; Answers = @() }
    )
    $k = 0
    foreach ($c in $cases) {
        $k++
        $root = Join-Path $tmp "root-no-$k"
        $r = Run $root $c.Answers
        Yes "by hand, $($c.Name) stops it, exit 1" ($r.Done -and $r.Code -eq 1)
        Yes '  saying nothing was installed' ($r.Out -match 'STOP\. Setup installs only once all four are a yes\. Nothing was installed\.')
        Yes '  before it looks for Skyrim' (-not ($r.Out -match 'Finding Skyrim'))
        Yes '  and having written nothing, no accepted.json and no install folder' (-not (Test-Path -LiteralPath $root))
    }

    # ---- by hand: four yeses ---------------------------------------------------
    $root = Join-Path $tmp 'root-yes'
    $r = Run $root @('y', 'YES', 'yes', 'Yes')
    Yes 'by hand, it asks the age question and the three pages with their addresses' (
        $r.Out -match 'I am 18 or over' -and $r.Out -match 'https://thornswood\.net/terms' -and
        $r.Out -match 'https://thornswood\.net/privacy' -and $r.Out -match 'https://thornswood\.net/rules')
    $file = Note $root
    Yes 'four yeses write Profile\accepted.json' (Test-Path -LiteralPath $file)
    Yes 'and it carries on to look for Skyrim' ($r.Out -match 'Finding Skyrim')
    Yes 'where it stops, installing nothing, because Skyrim is pointed at a folder that is not there' (
        $r.Done -and $r.Code -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $root 'Launcher')) -and -not (Test-Path -LiteralPath (Join-Path $root 'Game')))
    if (Test-Path -LiteralPath $file) {
        $raw = [IO.File]::ReadAllText($file)
        $j = $raw | ConvertFrom-Json
        $bytes = [IO.File]::ReadAllBytes($file)
        Yes 'accepted.json has no byte order mark' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
        Yes 'it has the window''s three fields: accepted, pages, about' (
            (@($j.PSObject.Properties.Name) -join ',') -eq 'accepted,pages,about' -and
            $boot.Contains('\"accepted\": \"') -and $boot.Contains('\"pages\": {') -and $boot.Contains('\"about\": \"'))
        Yes 'accepted is a UTC time in the window''s format' ($raw -match '"accepted":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"')
        Yes 'pages are the window''s three, in its order' ((@($j.pages.PSObject.Properties.Name) -join ',') -eq ($windowPages -join ','))
        foreach ($p in $windowPages) {
            $e = $j.pages.$p
            Yes "$p carries its address and a sha256 that is empty or 64 hex" (
                $e.url -eq "https://thornswood.net/$p" -and ([string]$e.sha256 -eq '' -or [string]$e.sha256 -match '^[0-9a-f]{64}$'))
        }
        Yes 'and nothing about the person or the machine' (-not ($raw -match [regex]::Escape([Environment]::UserName)) -and -not ($raw -match [regex]::Escape([Environment]::MachineName)))
    }

    # ---- from the setup window ---------------------------------------------------
    $root = Join-Path $tmp 'root-window-none'
    $r = Run $root @() -Window
    Yes 'from the setup window with no accepted.json it stops, exit 1' ($r.Done -and $r.Code -eq 1)
    Yes '  with the STOP line the window shows, saying where to get the setup again' ($r.Out -match '(?m)^STOP\. Setup found no note that you accepted the terms, the privacy policy and the rules, so nothing was installed\. Download the setup again from https://thornswood\.net')
    Yes '  asking nothing on the console' (-not ($r.Out -match 'yes or no'))
    Yes '  and having written nothing' (-not (Test-Path -LiteralPath $root))

    $root = Join-Path $tmp 'root-window-noted'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'Profile') | Out-Null
    [IO.File]::WriteAllText((Note $root), '{ "accepted": "2026-09-29T00:00:00Z" }')
    $r = Run $root @() -Window
    Yes 'from the setup window with accepted.json it asks nothing and carries on to look for Skyrim' (
        $r.Out -match 'Finding Skyrim' -and -not ($r.Out -match 'yes or no'))
    Yes '  and leaves the window''s note as the window wrote it' ([IO.File]::ReadAllText((Note $root)) -eq '{ "accepted": "2026-09-29T00:00:00Z" }')

    $said = $setup.Substring($setup.IndexOf('# ------------------------------------------------------------- agreements'))
    $said = $said.Substring(0, $said.IndexOf('# ------------------------------------------------------------- find steam'))
    Yes 'no em dash and never the word the project does not use in the new section' (-not ($said -match [char]0x2014) -and -not ($said -match '(?i)player'))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
