<#
  Check-Controls.ps1

      .\tools\Check-Controls.ps1

  Every control in the launcher is found at runtime by name:

      static T F<T>(string name) { return win.FindName(name) as T; }

  There is no compiler anywhere in that. A name that does not match ui.xaml
  returns null, quietly, and the first sign is either a button that does
  nothing or a NullReferenceException minutes later in an unrelated place.
  ui.xaml is an embedded resource parsed by XamlReader at startup, so nothing
  in the build catches it either.

  This reads both sides and compares them. Run it after touching ui.xaml or
  after adding any control, and before shipping.

  It reports three things:

    NEW     the C# looks it up, ui.xaml has no such name, and it is not in
            control-baseline.txt. This is null at runtime. Fix it.
    known   missing, but listed in control-baseline.txt as a control that was
            deliberately taken out of the UI with the C# left guarded behind it.
    unused  ui.xaml names it and nothing looks it up. Usually harmless, but a
            control added and never wired up looks exactly like this.
#>
[CmdletBinding()]
param(
  [string]$Xaml,
  [string]$AppDir,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Xaml)   { $Xaml   = Join-Path $Here 'ui.xaml' }
if (-not $AppDir) { $AppDir = Join-Path $Here 'app' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

if (-not (Test-Path -LiteralPath $Xaml))   { throw "no ui.xaml at $Xaml" }
if (-not (Test-Path -LiteralPath $AppDir)) { throw "no app folder at $AppDir" }

Write-Host ''
Write-Host '  THORNSWOOD  -  do the control names line up' -ForegroundColor White

$xamlText = Get-Content -LiteralPath $Xaml -Raw
# Ordinal, not the default. A PowerShell hashtable matches keys case
# INSENSITIVELY, but WPF's FindName does not: look up "TabAddOns" when the
# xaml says "TabAddons" and you get null. With a plain @{} this script cannot
# see that at all, which it proved by passing a deliberately planted typo.
$named = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
foreach ($m in [regex]::Matches($xamlText, 'x:Name="([^"]+)"')) { $named[$m.Groups[1].Value] = $true }

$lookup = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
$files = @(Get-ChildItem -LiteralPath $AppDir -Filter '*.cs' -File)
foreach ($f in $files) {
  $src = Get-Content -LiteralPath $f.FullName -Raw
  foreach ($m in [regex]::Matches($src, '\bF<\s*[A-Za-z0-9_.<>]+\s*>\s*\(\s*"([^"]+)"\s*\)')) {
    $n = $m.Groups[1].Value
    if (-not $lookup.ContainsKey($n)) { $lookup[$n] = @() }
    $lookup[$n] += $f.Name
  }
  foreach ($m in [regex]::Matches($src, '\bFindName\(\s*"([^"]+)"\s*\)')) {
    $n = $m.Groups[1].Value
    if (-not $lookup.ContainsKey($n)) { $lookup[$n] = @() }
    $lookup[$n] += $f.Name
  }
}

Say ("  {0} names in ui.xaml, {1} looked up across {2} source files" -f `
     $named.Count, $lookup.Count, $files.Count)

$missing = @($lookup.Keys | Where-Object { -not $named.ContainsKey($_) } | Sort-Object)
$unused  = @($named.Keys  | Where-Object { -not $lookup.ContainsKey($_) } | Sort-Object)

# Known missing names, one per line, in control-baseline.txt next to this
# script. Everything in there is a control whose UI was taken out of ui.xaml
# while the C# was left behind and guarded. They are not worth reporting every
# run; a name that is NOT in there is new, and new is what matters.
#
# An earlier version of this script tried to work out for itself whether each
# missing name was safe, by looking for a null check earlier in the same
# method. It got it wrong in the way that counts. BuildModList opens with
# "if (modList == null) return;" so it called every later line safe, including
# a deliberately planted typo in a different control. A sibling guard protects
# against a whole page being absent, not against one name being mistyped, and
# mistyped is the case this script exists to catch.
$baseFile = Join-Path $Here 'control-baseline.txt'
$baseline = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
if (Test-Path -LiteralPath $baseFile) {
  foreach ($l in (Get-Content -LiteralPath $baseFile)) {
    $t = "$l".Trim()
    if ($t -and -not $t.StartsWith('#')) { $baseline[$t] = $true }
  }
}
$bad  = @($missing | Where-Object { -not $baseline.ContainsKey($_) })
$dead = @($missing | Where-Object { $baseline.ContainsKey($_) })

Head 'Looked up but not in ui.xaml'
if (-not $missing.Count) { Say '  none' 'Green' }
foreach ($n in $bad)  { Say ("  NEW   {0}  ({1})  this will be null at runtime" -f $n, ($lookup[$n] -join ', ')) 'Red' }
foreach ($n in $dead) { Say ("  known {0}  ({1})  in control-baseline.txt" -f $n, ($lookup[$n] -join ', ')) 'DarkGray' }

Head 'In ui.xaml but never looked up'
if (-not $unused.Count) { Say '  none' 'Green' }
# Template parts and one letter names inside styles are not controls anybody
# reaches for by name, so they are not worth reporting.
foreach ($n in $unused) {
  if ($n -like 'PART_*' -or $n.Length -le 2) { continue }
  Say ("  {0}" -f $n) 'DarkGray'
}

Write-Host ''
if ($bad.Count) {
  Say ("  {0} name(s) the C# looks up do not exist in ui.xaml." -f $bad.Count) 'Red'
  Say '  Each one is null at runtime. Fix the name, or add it to' 'Yellow'
  Say '  control-baseline.txt if the control really is gone and the use is guarded.' 'Yellow'
} else {
  Say '  Every name the C# looks up exists in ui.xaml.' 'Green'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
