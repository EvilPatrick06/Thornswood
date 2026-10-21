<#
.SYNOPSIS
  Writes scripts\vps\BoxGuard.ps1's Get-ThornswoodBoxRefusal into every box script that carries a copy of it.

.DESCRIPTION
  Issue #3041. A box script runs on the box with nothing beside it, so each
  one that asks "is this the box?" carries its own copy of the function,
  between the lines

      # ---- BoxGuard.ps1 (copy) ----
      # ---- end BoxGuard.ps1 ----

  BoxGuard.ps1 says why. The rule is changed in BoxGuard.ps1 only, and this
  writes it between those lines in every script under scripts\ that has
  them, keeping each file's own line endings. A script with the first line
  and not the second, or either one twice, is named and left as it is, and
  this exits 1.

  tests\test-3041-box-guard.ps1 fails while any copy differs, and runs this
  against a planted copy.

.PARAMETER Root
  The folder whose scripts are written. The repository's scripts folder when
  empty; only the harness passes another.
#>
[CmdletBinding()]
param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Root) { $Root = [IO.Path]::Combine($repo, 'scripts') }
$source = [IO.Path]::Combine($repo, 'scripts', 'vps', 'BoxGuard.ps1')

$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { throw "$source does not parse, so nothing was written." }
$fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ThornswoodBoxRefusal' }, $true))
if ($fn.Count -ne 1) { throw "$source does not define Get-ThornswoodBoxRefusal once, so nothing was written." }
$body = $fn[0].Extent.Text.Replace("`r`n", "`n")

$open = '# ---- BoxGuard.ps1 (copy) ----'
$close = '# ---- end BoxGuard.ps1 ----'
$bad = 0
foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1')) {
    if ($f.FullName -eq $source) { continue }
    $text = [IO.File]::ReadAllText($f.FullName)
    $nl = $(if ($text.Contains("`r`n")) { "`r`n" } else { "`n" })
    $lf = $text.Replace("`r`n", "`n")
    # The lines on their own, at the start of a line; a header that names
    # them indented (this one, BoxGuard.ps1's) carries no copy.
    $opens = ([regex]::Matches($lf, '(?m)^' + [regex]::Escape($open) + '$')).Count
    $closes = ([regex]::Matches($lf, '(?m)^' + [regex]::Escape($close) + '$')).Count
    if ($opens -eq 0 -and $closes -eq 0) { continue }
    if ($opens -ne 1 -or $closes -ne 1) {
        Write-Output ("NOT WRITTEN {0}: it has the opening line {1} times and the closing line {2} times, and takes one of each" -f $f.FullName, $opens, $closes)
        $bad++
        continue
    }
    $new = [regex]::Replace($lf, '(?s)(?m)(^' + [regex]::Escape($open) + '\n).*?(^' + [regex]::Escape($close) + '$)',
        { param($m) $m.Groups[1].Value + $body + "`n" + $m.Groups[2].Value })
    if ($new -eq $lf) { Write-Output ("SAME    " + $f.FullName); continue }
    [IO.File]::WriteAllText($f.FullName, $new.Replace("`n", $nl), (New-Object Text.UTF8Encoding $false))
    Write-Output ("WRITTEN " + $f.FullName)
}
if ($bad) { exit 1 }
exit 0
