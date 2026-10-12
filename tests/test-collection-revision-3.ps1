<#
  test-collection-revision-3.ps1

      pwsh -NoProfile -File .\tests\test-collection-revision-3.ps1

  docs\COLLECTION-REVISION-3.md, the page for collection revision 3, which
  adds the Unofficial Skyrim Special Edition Patch (#1262). Reads only the two
  pages; talks to nothing.

  The order table must be revision 2's 48 positions with
  Unofficial Skyrim Special Edition Patch.esp at 6, right after the five base
  masters, and everything else one position later in the same order. Each
  rule the page adds ties a plugin to the one right before it. The USSEP
  version must be one that supports Skyrim 1.6.1170 (4.3.8a, the last for
  SSE 1.6.1130+), never 4.3.9 or later (SSE 1.7.99+).
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
function Order([string]$path) {
    $lines = [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)
    $s = [Array]::IndexOf($lines, '<!-- order:start -->'); $e = [Array]::IndexOf($lines, '<!-- order:end -->')
    $o = New-Object Collections.Generic.List[string]
    $numbered = $true
    if ($s -ge 0 -and $e -gt $s) {
        foreach ($l in $lines[($s + 1)..($e - 1)]) {
            $m = [regex]::Match($l, '^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|')
            if (-not $m.Success) { continue }
            if ([int]$m.Groups[1].Value -ne $o.Count + 1) { $numbered = $false }
            [void]$o.Add($m.Groups[2].Value)
        }
    }
    return @{ Order = @($o); Numbered = $numbered; Found = ($s -ge 0 -and $e -gt $s) }
}
$usp = 'Unofficial Skyrim Special Edition Patch.esp'
$p3 = Join-Path $Repo 'docs\COLLECTION-REVISION-3.md'
$p2 = Join-Path $Repo 'docs\COLLECTION-REVISION-2.md'
Yes 'docs\COLLECTION-REVISION-3.md exists' (Test-Path -LiteralPath $p3)
if (-not (Test-Path -LiteralPath $p3)) { exit 1 }
$doc = [IO.File]::ReadAllText($p3, [Text.Encoding]::UTF8)
$r3 = Order $p3; $r2 = Order $p2
Yes 'the page marks its order table' $r3.Found
Yes 'its positions run 1, 2, 3 with no gap' $r3.Numbered
Yes ("it has revision 2's positions plus one ({0} and {1})" -f $r3.Order.Count, $r2.Order.Count) ($r3.Order.Count -eq $r2.Order.Count + 1)
Yes "position 6 is $usp" ($r3.Order.Count -ge 6 -and $r3.Order[5] -eq $usp)
$want = @($r2.Order[0..4]) + @($usp) + @($r2.Order[5..($r2.Order.Count - 1)])
$same = ($want.Count -eq $r3.Order.Count)
for ($i = 0; $same -and $i -lt $want.Count; $i++) { if ($want[$i] -ne $r3.Order[$i]) { $same = $false } }
Yes "everything else is revision 2's order, one position later" $same

$rules = 0
foreach ($l in ($doc -split "`r`n|`n")) {
    $m = [regex]::Match($l, '^\|\s*([^|]+?\.es[mpl])\s*\|\s*(none|load after [^|]+?)\s*\|\s*(none|load after [^|]+?)\s*\|\s*$')
    if (-not $m.Success) { continue }
    $rules++
    $at = [Array]::IndexOf($r3.Order, $m.Groups[1].Value)
    if ($m.Groups[3].Value -match '^load after (.+)$') {
        $before = [Array]::IndexOf($r3.Order, $Matches[1].Trim())
        Yes ("{0} loads after the plugin right before it ({1} then {2})" -f $m.Groups[1].Value, ($before + 1), ($at + 1)) ($before -ge 0 -and $before + 1 -eq $at)
    }
}
Yes "the page adds rules for $usp and the plugin after it ($rules)" ($rules -eq 2)
Yes 'the page pins USSEP 4.3.8a' ($doc -match 'USSEP\s+\*{0,2}4\.3\.8a')
Yes 'and pins no USSEP 4.3.9 or later' (-not ($doc -match 'USSEP\s+\*{0,2}4\.3\.(9|\d\d)'))
Yes 'the page tells the person to run Check-CleanInstall.ps1' ($doc -match 'scripts\\mods\\Check-CleanInstall\.ps1')
Yes 'the page names this harness' ($doc -match 'tests\\test-collection-revision-3\.ps1')
Yes 'the page tells the person to leave "Skip plugin rules" off' ($doc -match 'Skip\s+plugin rules')
Yes 'the page has no em dash' (-not $doc.Contains([string][char]0x2014))
Yes 'the page never says player' (-not ($doc -match '\bplayers?\b'))
# Patrick's rule of 11 October: Claude alone runs every Vortex app, Publish,
# Deploy and live step. Every numbered step must name Claude, and no step may
# name anyone else as the one doing it. "when Patrick asks" is the gate for
# Main, not an owner, so it is the one mention of Patrick a step may keep.
$steps = [regex]::Matches($doc, '(?ms)^## (\d+)\.([^\r\n]*)\r?\n(.*?)(?=^## |\z)')
Yes ("the page has steps 1 to 7 ({0})" -f $steps.Count) ($steps.Count -eq 7)
foreach ($st in $steps) {
    $n = $st.Groups[1].Value
    Yes "step $n names Claude in its heading" ($st.Groups[2].Value -match '\(Claude\b')
    $text = ($st.Groups[2].Value + "`n" + $st.Groups[3].Value) -replace 'only when Patrick asks', '' -replace 'when Patrick asks', ''
    $other = [regex]::Matches($text, '\b(Patrick|Smeagle|Wyrd|Anvil|Waystone|Herald|Codex|Gavin|Jin)\b') | ForEach-Object { $_.Value }
    Yes ("step $n names no one but Claude ({0})" -f (@($other) -join ', ')) (@($other).Count -eq 0)
}
Yes 'the page says Claude runs every Vortex, Publish and deploy step' ($doc -match 'Claude alone runs every Vortex')
Yes 'the page says Main waits for Patrick to ask' ($doc -match 'Main follows (Dev )?only when Patrick asks')
Yes 'the page sends the run through a claude-queue note' ($doc -match 'claude-queue note')
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }