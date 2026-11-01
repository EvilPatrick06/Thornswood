<#
  Check-PrBody.ps1

      pwsh -NoProfile -File scripts/dev/Check-PrBody.ps1 -BodyFile <file> [-Author <login>]

  The parts of a pull request's body that a release reads, checked while the
  pull request is open (#5179). .github\workflows\pr-body.yml runs it on every
  pull request when it is opened, pushed to or its body is edited, so fixing
  the body is enough to turn it green.

  WHAT IT CHECKS. The "Release note:" line: there is one, and it says none or
  is a note the release can carry as written. The rules are
  scripts\release\Note-Rules.ps1's, the same ones Ship.ps1 holds a release's
  note to, so a note that passes here cannot be refused at release time.

  Prints PASS or STOP lines and exits 1 when anything is wrong. Reads only the
  file it is given.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BodyFile,
    [string]$Author = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path (Split-Path -Parent $Here) 'release/Note-Rules.ps1')

if (-not (Test-Path -LiteralPath $BodyFile)) { Write-Host "STOP  no body file at $BodyFile"; exit 1 }
$body = [IO.File]::ReadAllText($BodyFile)

$problems = @(Get-PrReleaseNoteProblems $body $Author)
if ($problems.Count) {
    foreach ($p in $problems) { Write-Host "STOP  release note: $p" }
    Write-Host 'Edit the pull request body and this check runs again by itself. Developer-Guide.md, "Say so, then write the note", has the shape.'
    exit 1
}
$n = Get-PrReleaseNote $body
if ($Author -eq 'dependabot[bot]') { Write-Host 'PASS  release note: none, by rule for a Dependabot pull request' }
elseif ($n.None) { Write-Host 'PASS  release note: none (nobody would notice this change)' }
else {
    Write-Host 'PASS  release note, as the release will carry it:'
    foreach ($l in @($n.Text -split "`n")) { Write-Host "      $l" }
}
exit 0
