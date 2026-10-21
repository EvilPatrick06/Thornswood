<#
  Check-Controls.ps1

      .\scripts\dev\Check-Controls.ps1

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
    stale   control-baseline.txt lists it, but nothing looks it up any more,
            or ui.xaml has it again. Take the line off in the same change.

  It also parses ui.xaml the way Shell.cs does at startup, with
  XamlReader.Parse. A window that does not parse is a launcher that does not
  open, and nothing else in the build reads the file: Build-Launcher.ps1
  embeds it as a resource without looking inside.

  It exits 1 on a NEW name or a window that does not parse, and 0 otherwise,
  and the build check on every pull request runs it
  (.github/workflows/build.yml). known, unused and stale are information and
  never fail it. Until 24 September it set no exit code at all, so anything
  that ran it read success whatever it printed, and nothing ran it: a renamed
  control was found by the person using the launcher, not by the build.
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
if (-not $Xaml)   { $Xaml   = Join-Path $Here '..\..\launcher\ui.xaml' }
if (-not $AppDir) { $AppDir = Join-Path $Here '..\..\launcher\app' }

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

# A line in control-baseline.txt silences that exact name for good. Once
# nothing looks the name up, or ui.xaml has the control again, the line covers
# nothing, and the next time that name goes missing it says known instead of
# NEW. Deleting the guarded C# and deleting its line are one change, not two.
# Information only: a branch that brings a control back should not go red over
# a line in a text file.
$stale = @($baseline.Keys | Where-Object { -not $lookup.ContainsKey($_) -or $named.ContainsKey($_) } | Sort-Object)
if ($stale.Count) {
  Head 'In control-baseline.txt but no longer missing'
  foreach ($n in $stale) {
    if ($named.ContainsKey($n)) { Say ("  stale {0}  ui.xaml has it again, take it off the list" -f $n) 'Yellow' }
    else { Say ("  stale {0}  nothing looks it up any more, take it off the list" -f $n) 'Yellow' }
  }
}

# Parse it the way Shell.cs does at startup. Everything above reads the file
# as text, so a window that is not valid XAML, or sets a property to a value
# WPF refuses, passes all of it and then stops the launcher before anybody sees
# a window. WPF will not build a window off an STA thread; both PowerShells
# start STA unless told -MTA.
Head 'Does ui.xaml parse'
$broken = $null
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  # Off Windows the thread is MTA as well, and saying -MTA was the reason sent
  # people looking for a switch nobody passed (#2989).
  Say '  not checked: WPF, which reads it, is only on Windows' 'Yellow'
} elseif ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
  Say '  not checked: WPF needs an STA thread and this PowerShell was started with -MTA' 'Yellow'
} else {
  Add-Type -AssemblyName PresentationFramework
  try {
    [void][System.Windows.Markup.XamlReader]::Parse($xamlText)
    Say '  yes' 'Green'
  } catch {
    $e = $_.Exception
    if ($e -is [System.Management.Automation.MethodInvocationException] -and $e.InnerException) { $e = $e.InnerException }
    $broken = $e.Message
    if ($e.InnerException -and $e.InnerException.Message -ne $e.Message) { $broken += ' ' + $e.InnerException.Message }
    Say ("  NO    {0}" -f $broken) 'Red'
  }
}

Write-Host ''
if ($bad.Count) {
  Say ("  {0} name(s) the C# looks up do not exist in ui.xaml." -f $bad.Count) 'Red'
  Say '  Each one is null at runtime. Fix the name, or add it to' 'Yellow'
  Say '  control-baseline.txt if the control really is gone and the use is guarded.' 'Yellow'
} else {
  Say '  Every name the C# looks up exists in ui.xaml.' 'Green'
}
if ($broken) {
  Say '  ui.xaml does not parse, so the launcher would stop at startup.' 'Red'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# The build check reads this, and so does anybody who runs it and then reads
# $LASTEXITCODE. The exit 0 is not decoration: run in the same session after a
# failing run, a script that simply ended would leave that session's 1 behind.
if ($bad.Count -or $broken) { exit 1 }
exit 0
