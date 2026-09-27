<#
  Check-Swallow.ps1

      .\scripts\dev\Check-Swallow.ps1          compare with the baseline
      .\scripts\dev\Check-Swallow.ps1 -List    print today's numbers in the
                                         baseline's own format

  Counts the silent catches in the launcher, file by file, and fails when any
  file has more than scripts\dev\swallow-baseline.txt allows, or fewer than it
  allows with its line not yet lowered.

  WHY. Entry 239 on the To Do List. Measured on 24 Sep: 386 of the 618 catch
  clauses in launcher\app\*.cs had nothing between their braces, so a failure in
  any of them left no line anywhere. A tester says the Save button did
  nothing, and launcher.log cannot say why, because nothing was written. The
  entry counted 367, then 373, then 386 while it sat on the list, which is why
  this is a rule with a frozen baseline and not a clean up somebody has to
  remember.

  THE RULE is written out at the top of swallow-baseline.txt. In short: a
  catch counts when its body holds nothing but whitespace, on one line or
  across several, and a body holding only a comment does not count.

  WHEN IT FAILS. Put Swallow.Note("Class.Method", ex) in the new catch
  (launcher\app\Swallow.cs), which writes one line to launcher.log, touches no
  control and never throws. If nothing should be done and nothing should be
  logged, say why in a comment inside the braces. Raising a number in the
  baseline is a decision for Patrick, not a fix.

  WHEN A NUMBER GOES DOWN this is red too, until that file's line in the
  baseline is lowered to what the file now holds. Issue #756. A fall used to
  print a yellow line and pass, which meant the lowering the rule asks for
  could be left for somebody else: Checks.cs and Verify.cs each sat a catch
  above their real count from #706 and #709 until the two lines were found by
  eye and lowered in #753. Red puts the lowering in the pull request that made
  the count fall, where it belongs, and the number cannot creep back up.
  Lowering a line is not a decision anybody has to take: the file already
  holds fewer, and -List prints the numbers in the baseline's own format.

  Read only. Exits 1 when any file rose, when a file fell and its line has not
  been lowered, or when the baseline cannot be read, and 0 otherwise.
  build.yml runs it on every pull request.
#>
[CmdletBinding()]
param(
  [string]$AppDir,
  [string]$Baseline,
  [switch]$List
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $AppDir)   { $AppDir   = Join-Path $Here '..\..\launcher\app' }
if (-not $Baseline) { $Baseline = Join-Path $Here 'swallow-baseline.txt' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Test-Path -LiteralPath $AppDir)) { Say "  no app folder at $AppDir" 'Red'; exit 1 }

# The rule as a pattern. \s takes new lines as well as spaces, so a catch whose
# braces sit on lines of their own counts the same as one written on one line.
# A comment inside the braces is not whitespace, so it stops the match, which
# is the rule's one exception. The optional brackets take catch (IOException)
# and catch (Exception ex) alike.
$Silent = [regex]'\bcatch\s*(\([^)]*\))?\s*\{\s*\}'
$NewLine = [regex]'\n'

# File name to the line numbers of its silent catches, for every .cs file.
$found = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$paths = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $AppDir -Filter '*.cs' -File | Sort-Object Name)) {
  $text = [IO.File]::ReadAllText($f.FullName)
  $at = New-Object 'System.Collections.Generic.List[int]'
  $line = 1; $from = 0
  foreach ($m in $Silent.Matches($text)) {
    $line += $NewLine.Matches($text.Substring($from, $m.Index - $from)).Count
    $from = $m.Index
    $at.Add($line)
  }
  $found[$f.Name] = $at
  $paths[$f.Name] = $f.FullName
}

if ($List) {
  foreach ($name in @($found.Keys | Sort-Object)) {
    if ($found[$name].Count -gt 0) { Write-Host ("{0} {1}" -f $name, $found[$name].Count) }
  }
  exit 0
}

if (-not (Test-Path -LiteralPath $Baseline)) { Say "  no baseline at $Baseline" 'Red'; exit 1 }

# One file name and one number a line. Anything starting with # is the rule
# and the reasons, and is skipped. A line that is neither is refused rather
# than skipped, because a baseline that reads as all zeroes fails every file
# and one that reads a typo as a big number hides a rise.
$allowed = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::OrdinalIgnoreCase)
$n = 0
foreach ($l in @(Get-Content -LiteralPath $Baseline)) {
  $n++
  $t = "$l".Trim()
  if (-not $t -or $t.StartsWith('#')) { continue }
  $mm = [regex]::Match($t, '^(\S+)\s+(\d+)$')
  if (-not $mm.Success) { Say ("  line {0} of the baseline is not a file name and a number: {1}" -f $n, $t) 'Red'; exit 1 }
  $allowed[$mm.Groups[1].Value] = [int]$mm.Groups[2].Value
}

Write-Host ''
Write-Host '  THORNSWOOD  -  silent catches in the launcher' -ForegroundColor White

$rose = 0; $fell = 0; $total = 0; $cap = 0
foreach ($v in $allowed.Values) { $cap += $v }
foreach ($name in @($found.Keys | Sort-Object)) {
  $now = $found[$name].Count
  $total += $now
  $may = 0
  if ($allowed.ContainsKey($name)) { $may = $allowed[$name] }
  if ($now -gt $may) {
    $rose++
    $where = ($found[$name] | ForEach-Object { "$_" }) -join ', '
    Say ("  NEW   {0} has {1} silent catches and the baseline allows {2}. They are on lines {3}." -f $name, $now, $may, $where) 'Red'
    if ($env:GITHUB_ACTIONS -eq 'true') {
      Write-Host ("::error file={0}::{1} has {2} silent catches and swallow-baseline.txt allows {3}. Log the new one with Swallow.Note." -f $paths[$name], $name, $now, $may)
    }
  } elseif ($now -lt $may) {
    $fell++
    Say ("  DOWN  {0} is at {1} and the baseline says {2}. Lower its line in swallow-baseline.txt to {1}." -f $name, $now, $may) 'Red'
    if ($env:GITHUB_ACTIONS -eq 'true') {
      Write-Host ("::error file={0}::{1} is at {2} and swallow-baseline.txt allows {3}. Lower its line to {2} in this pull request." -f $paths[$name], $name, $now, $may)
    }
  }
}
foreach ($name in @($allowed.Keys | Sort-Object)) {
  if (-not $found.ContainsKey($name) -and $allowed[$name] -gt 0) {
    $fell++
    Say ("  GONE  {0} is in the baseline and not in {1}. Take its line out." -f $name, $AppDir) 'Red'
    if ($env:GITHUB_ACTIONS -eq 'true') {
      Write-Host ("::error file={0}::{1} is in swallow-baseline.txt and not in the launcher any more. Take its line out in this pull request." -f $Baseline, $name)
    }
  }
}

Write-Host ''
Say ("  {0} silent catches in {1} source files; the baseline allows {2}." -f $total, $found.Count, $cap)
if ($rose) {
  Say ("  {0} file(s) have more than the baseline allows. Log the new catch with" -f $rose) 'Red'
  Say '  Swallow.Note, or say why in a comment inside its braces.' 'Red'
}
if ($fell) {
  Say ("  {0} line(s) in the baseline stand above what the launcher holds. Put them" -f $fell) 'Red'
  Say '  right in this pull request, where the count fell: .\scripts\dev\Check-Swallow.ps1 -List' 'Red'
  Say '  prints every number in the baseline''s own format.' 'Red'
}
if ($rose -or $fell) { exit 1 }
Say '  Nothing rose, and the baseline matches.' 'Green'
exit 0
