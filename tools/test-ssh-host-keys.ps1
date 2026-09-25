<#
  test-ssh-host-keys.ps1

      pwsh -NoProfile -File .\tools\test-ssh-host-keys.ps1

  No script talks to the VPS with host key checking switched off.

  WHY. About thirty scripts ran ssh and scp against the VPS as Administrator
  with StrictHostKeyChecking=no, which takes whatever key answers. Anything
  sitting between this machine and the box could have answered as the box and
  been handed the scripts, the logs and the secrets they carry. The 25
  September audit found it; they use accept-new now, which records the box's
  key the first time and refuses a key that has changed, the same as
  Setup-SshKey.ps1 and Add-VpsKey.ps1 always did.

  HOW. Every .ps1 under tools and scripts is read with PowerShell's own parser,
  so a comment that explains the old option does not count and a string that
  passes it to ssh does.
#>
[CmdletBinding()]
param([string]$Tools)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Tools) { $Tools = $Here }
$repo = Split-Path -Parent $Tools

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$files = @(Get-ChildItem -LiteralPath $Tools -Filter *.ps1 -File -Recurse)
$more = Join-Path $repo 'scripts'
if (Test-Path -LiteralPath $more) { $files += @(Get-ChildItem -LiteralPath $more -Filter *.ps1 -File -Recurse) }

$off = @()
$checked = 0
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    foreach ($t in $tokens) {
        if ($t.Kind -eq 'Comment') { continue }
        if ($t.Text -match '(?i)StrictHostKeyChecking\s*=\s*(no|off)\b') {
            $off += ('{0}:{1}' -f $f.FullName.Substring($repo.Length + 1), $t.Extent.StartLineNumber)
        }
        elseif ($t.Text -match '(?i)StrictHostKeyChecking\s*=\s*(accept-new|yes)\b') { $checked++ }
    }
}

Yes ('no script switches host key checking off' + $(if ($off.Count) { ': ' + ($off -join ', ') } else { '' })) ($off.Count -eq 0)
Yes ("the scripts that reach the VPS check its key ($checked places)") ($checked -ge 30)

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
