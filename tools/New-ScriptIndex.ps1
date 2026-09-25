<#
.SYNOPSIS
  Writes tools\README.md, the list of every PowerShell script in tools and the
  one line that says what each one is for.

.DESCRIPTION
  There were 128 scripts in tools and nothing listed them. Finding the one
  that does a job meant opening files until one of them said so, and only six
  of them had a help block Get-Help could read. Entry 260 on the To Do List:
  "a generated index at the top of the folder listing every script and its
  one-line purpose, regenerated in CI so it cannot drift".

  So the list is written from the scripts rather than by hand. A script's line
  is its .SYNOPSIS where it has one. Otherwise it is the first sentence of the
  comment at its top, after the line that only repeats the file name and
  after any usage lines indented under it, carried on into the next sentence
  when the first one is too short to say anything ("One command.", "Runs ON
  the VPS."). A script with no comment at its top gets a row that says so,
  and tests\test-script-index.ps1 fails on that row.

  Options are deliberately not in the list. Get-Help reads them off each
  script's param block, which is the only list of them that cannot fall
  behind, and a copy here would be one more that could.

  Read only apart from the one file it writes. It reads the scripts as text
  and never runs any of them.

.PARAMETER Check
  Writes nothing. Exits 1 when the index is missing or is not what this would
  write, and says which rows differ. The build check runs this through
  tests\test-script-index.ps1 on every pull request.

.PARAMETER Tools
  The folder whose scripts are listed. The folder this script is in, unless
  a test points it at a copy.

.PARAMETER Out
  Where the index goes. README.md in that folder unless said otherwise.

.EXAMPLE
  .\tools\New-ScriptIndex.ps1

  Writes tools\README.md. Run it after adding a script or changing the first
  lines of one, and commit the file with the change.

.EXAMPLE
  .\tools\New-ScriptIndex.ps1 -Check

  Says whether tools\README.md is current, and exits 1 when it is not.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Tools,
    [string]$Out
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Tools) { $Tools = $Here }
$Tools = (Resolve-Path -LiteralPath $Tools).Path
if (-not $Out) { $Out = Join-Path $Tools 'README.md' }

# What a row says when a script has nothing at its top to read. The harness
# looks for exactly this text, so the two have to agree.
$NoHeader = 'Nothing at the top of this script says what it is for.'

# Read as UTF-8 whatever the edition. Windows PowerShell 5.1 reads a file with
# no byte order mark as the machine's code page and PowerShell 7 reads it as
# UTF-8, and the index has to come out the same from either, because the one
# committed is compared against the one the build check makes.
$Utf8 = New-Object Text.UTF8Encoding($false)

function Get-Indent([string]$line) {
    return $line.Length - $line.TrimStart().Length
}

# The comment the file opens with, as lines with the comment marks taken off:
# a <# #> block, or a run of # lines. Empty when the file opens with code.
function Get-OpeningComment([string]$text) {
    $lines = @($text.TrimStart([char]0xFEFF) -split "\r?\n")
    $i = 0
    while ($i -lt $lines.Count -and -not $lines[$i].Trim()) { $i++ }
    if ($i -ge $lines.Count) { return @() }

    $out = New-Object System.Collections.Generic.List[string]
    $first = $lines[$i].TrimStart()
    if ($first.StartsWith('<#')) {
        $lines[$i] = $lines[$i].Substring($lines[$i].IndexOf('<#') + 2)
        for (; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            $end = $l.IndexOf('#>')
            if ($end -ge 0) { $out.Add($l.Substring(0, $end)); break }
            $out.Add($l)
        }
    } elseif ($first.StartsWith('#')) {
        for (; $i -lt $lines.Count; $i++) {
            $l = $lines[$i].TrimStart()
            if (-not $l.StartsWith('#')) { break }
            $l = $l.Substring(1)
            if ($l.StartsWith(' ')) { $l = $l.Substring(1) }
            $out.Add($l)
        }
    }
    return @($out)
}

# The first sentence of a paragraph, or the first two or more when the first
# is too short to say what the script is for.
function Get-FirstSentence([string]$para) {
    $para = ($para -replace '\s+', ' ').Trim()
    $parts = [regex]::Split($para, '(?<=[.?!])\s+(?=[A-Z"''(])')
    $said = ''
    foreach ($p in $parts) {
        $said = ($said + ' ' + $p).Trim()
        if ($said.Length -ge 40) { break }
    }
    return $said
}

function Get-ScriptPurpose([string]$path) {
    $text = [IO.File]::ReadAllText($path, $Utf8)

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, $path, [ref]$tokens, [ref]$errors)
    $help = $null
    try { $help = $ast.GetHelpContent() } catch { $help = $null }
    $said = ''
    if ($help -and $help.Synopsis -and $help.Synopsis.Trim()) {
        $said = ($help.Synopsis -replace '\s+', ' ').Trim()
    } else {
        $lines = @(Get-OpeningComment $text)
        $name = [IO.Path]::GetFileName($path)
        $i = 0
        while ($i -lt $lines.Count -and -not $lines[$i].Trim()) { $i++ }
        $para = New-Object System.Collections.Generic.List[string]
        $base = 0
        if ($i -lt $lines.Count) {
            $base = Get-Indent $lines[$i]
            $top = $lines[$i].Trim()
            # "Ship.ps1" on a line of its own says nothing. "Go.ps1 - installs
            # the front..." says it on the same line.
            if ($top.StartsWith($name, [StringComparison]::OrdinalIgnoreCase)) {
                $rest = ($top.Substring($name.Length).Trim() -replace '^[-:]+\s*', '')
                if ($rest) { $para.Add($rest) }
                $i++
            }
        }
        # A usage line sits deeper than the prose around it, and is never the
        # answer: Check-Build.ps1 opens with three of them.
        if ($para.Count -eq 0) {
            while ($i -lt $lines.Count -and
                   ((-not $lines[$i].Trim()) -or ((Get-Indent $lines[$i]) -ge $base + 4))) { $i++ }
        }
        while ($i -lt $lines.Count -and $lines[$i].Trim() -and
               ((Get-Indent $lines[$i]) -lt $base + 4)) {
            $para.Add($lines[$i].Trim())
            $i++
        }
        if ($para.Count) { $said = Get-FirstSentence ($para -join ' ') }
    }

    if (-not $said) { return $NoHeader }
    # A paragraph that introduces a list ends on a colon; the row is not
    # followed by the list, so it ends on a full stop instead.
    if ($said.EndsWith(':')) { $said = $said.Substring(0, $said.Length - 1) + '.' }
    $said = $said.Substring(0, 1).ToUpperInvariant() + $said.Substring(1)
    return $said
}

function Get-IndexText([string]$dir) {
    # Ordinal, so Windows PowerShell and PowerShell 7 agree on the order. The
    # culture comparers of the two runtimes do not agree about hyphens.
    [string[]]$names = @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File |
                         Where-Object { $_.Extension -eq '.ps1' } |
                         ForEach-Object { $_.Name })
    [Array]::Sort($names, [StringComparer]::OrdinalIgnoreCase)

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('# The PowerShell scripts in tools')
    $out.Add('')
    $out.Add('Every `.ps1` in this folder, ' + $names.Count + ' of them, with the one line that says')
    $out.Add('what each one is for. New-ScriptIndex.ps1 writes this file from the scripts')
    $out.Add('themselves: the line is a script''s .SYNOPSIS where it has one, and otherwise')
    $out.Add('the first sentence of the comment at its top. Do not edit it by hand. Change')
    $out.Add('the script, then run')
    $out.Add('')
    $out.Add('    .\tools\New-ScriptIndex.ps1')
    $out.Add('')
    $out.Add('and commit this file with it. The build check on every pull request runs')
    $out.Add('tests\test-script-index.ps1, which goes red when this file is not what that')
    $out.Add('would write.')
    $out.Add('')
    $out.Add('A script''s options are not listed here. Get-Help reads them off its param')
    $out.Add('block, so they are always all of them:')
    $out.Add('')
    $out.Add('    Get-Help .\tools\Ship.ps1 -Full')
    $out.Add('')
    $out.Add('The node and Python scripts beside these (`Build-*.js`, `Audit-*.py` and the')
    $out.Add('rest) and the `test-*.js` harnesses are not in this list.')
    $out.Add('')
    $out.Add('| Script | What it is for |')
    $out.Add('| --- | --- |')
    foreach ($n in $names) {
        $purpose = (Get-ScriptPurpose (Join-Path $dir $n)) -replace '\|', '\|'
        $out.Add('| [' + $n + '](' + $n + ') | ' + $purpose + ' |')
    }
    return (($out -join "`r`n") + "`r`n")
}

$want = Get-IndexText $Tools
$rows = @(($want -split "`r`n") | Where-Object { $_ -match '^\| \[' })

if (-not $Check) {
    [IO.File]::WriteAllText($Out, $want, $Utf8)
    Write-Host ('wrote {0}, {1} scripts' -f $Out, $rows.Count)
    foreach ($r in $rows) {
        if ($r.Contains($NoHeader)) { Write-Host ('  no header: ' + $r) -ForegroundColor Yellow }
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $Out)) {
    Write-Host ('{0} is missing. Run .\tools\New-ScriptIndex.ps1 and commit it.' -f $Out) -ForegroundColor Red
    exit 1
}
# Line endings are git's business, not ours: a checkout on another machine or
# on the build runner can turn them either way.
$have = [IO.File]::ReadAllText($Out, $Utf8).TrimStart([char]0xFEFF) -replace "\r\n", "`n"
$wantLf = $want -replace "\r\n", "`n"
if ($have -eq $wantLf) {
    Write-Host ('{0} is current, {1} scripts' -f $Out, $rows.Count)
    exit 0
}

Write-Host ('{0} is not what New-ScriptIndex.ps1 writes.' -f $Out) -ForegroundColor Red
$haveLines = @($have -split "`n")
$wantLines = @($wantLf -split "`n")
$shown = 0
foreach ($l in $wantLines) {
    if ($haveLines -notcontains $l -and $shown -lt 20) { Write-Host ('  + ' + $l) -ForegroundColor Yellow; $shown++ }
}
foreach ($l in $haveLines) {
    if ($wantLines -notcontains $l -and $shown -lt 20) { Write-Host ('  - ' + $l) -ForegroundColor Yellow; $shown++ }
}
Write-Host '  Run .\tools\New-ScriptIndex.ps1 and commit tools\README.md with the change.' -ForegroundColor Yellow
exit 1
