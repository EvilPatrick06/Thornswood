<#
  Read-JsonFile.ps1

  ConvertFrom-ThornswoodJson: JSON text read from a file, parsed, or a stop
  that names the file. An empty file (Get-Content -Raw hands back $null for
  one), a file cut off mid-write and one that is not JSON at all used to come
  out of ConvertFrom-Json as "Invalid JSON primitive", "Conversion from JSON
  failed", 5.1's "Cannot bind argument to parameter 'InputObject' because it
  is null", or a null property further on, and none of them said which file.

      $doc = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath $p -Raw) $p

  The caller reads the file the way it always did and hands the text over, so
  how each script opens its files is not this helper's business. A leading
  byte order mark is dropped. Throws '<Source> is empty' or '<Source> is not
  valid JSON: <what the parser said>'. A read inside try with a fallback still
  falls back: it is a throw like the parse error was. A top-level array comes
  back as ConvertFrom-Json itself gives it on this PowerShell (one array on
  5.1; 7 unrolls it as it always has).

  Dot-sourced by the release, deploy, ops and mods scripts that read records,
  settings and feed files; it defines one function and nothing else.
#>
function ConvertFrom-ThornswoodJson {
    param([AllowNull()][AllowEmptyString()][string]$Text, [string]$Source)
    $t = "$Text".TrimStart([char]0xFEFF)
    if (-not $t.Trim()) { throw "$Source is empty" }
    try { $doc = $t | ConvertFrom-Json }
    catch { throw ("$Source is not valid JSON: " + $_.Exception.Message) }
    if ($doc -is [array]) { return , $doc }
    return $doc
}