<#
  Remote.ps1

  Runs a bit of PowerShell on the VPS, properly.

      .\tools\Remote.ps1 "Get-Content 'C:\Thornswood-Voice\voice.log' -Tail 20"
      .\tools\Remote.ps1 -File .\tools\some-check.ps1
      .\tools\Remote.ps1 "Restart-Service W32Time" -Dev

  WHY THIS EXISTS. Every other way of doing it goes wrong, and it goes wrong
  quietly enough to waste an hour.

  Typing it inline loses the quotes. The local shell strips one layer, ssh
  hands a single string to the remote shell, and that strips another, so

      ssh ... "powershell -NoProfile -Command Remove-NetFirewallRule -DisplayName 'Thornswood Voice'"

  arrives as two bare words and fails with "a positional parameter cannot be
  found that accepts argument 'Voice'". Entry 1 on the To Do List has this in
  writing from 17 September and it has been done wrong four times since.

  Pasting a pre-encoded string does not work either, past a certain length. A
  base64 blob for anything real runs to thousands of characters on one line, and
  terminals drop pieces of it in the middle. "The value must be Base64 encoded"
  is what that looks like.

  So the encoding happens here, on this machine, a moment before it is sent.
  The command typed stays short and readable, nothing is pasted, and the remote
  end gets exactly the script that was written.

  $ProgressPreference is set at the far end as well, or PowerShell wraps the
  answer in a block of CLIXML progress records, which is the other thing that
  has eaten an afternoon.

  READ ONLY IS NOT ASSUMED. This will run whatever it is given. CLAUDE.md is
  clear that the person runs what touches the VPS, so this is a tool for the
  person, not a way around that.
#>
[CmdletBinding(DefaultParameterSetName = 'Script')]
param(
    [Parameter(ParameterSetName = 'Script', Mandatory = $true, Position = 0)]
    [string]$Script,

    [Parameter(ParameterSetName = 'File', Mandatory = $true)]
    [string]$File,

    [string]$VpsHost = '192.135.112.23',
    [string]$VpsUser = 'Administrator',

    # Show the script before sending it. Worth doing for anything that writes.
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'File') {
    if (-not (Test-Path -LiteralPath $File)) { throw "There is no script at $File" }
    $body = Get-Content -LiteralPath $File -Raw
    # A syntax error is worth catching here rather than at the far end, where
    # the message arrives wrapped in CLIXML and half explained.
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) {
        foreach ($e in ($errs | Select-Object -First 5)) {
            Write-Host ("  line " + $e.Extent.StartLineNumber + ": " + $e.Message) -ForegroundColor Red
        }
        throw "$File does not parse. Nothing was sent."
    }
} else {
    $body = $Script
}

$full = "`$ProgressPreference = 'SilentlyContinue'`r`n" + $body

if ($Show) {
    Write-Host '--- sending ---' -ForegroundColor Cyan
    $body -split "`r?`n" | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor DarkGray }
    Write-Host ''
}

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
& ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$VpsUser@$VpsHost" "powershell -NoProfile -EncodedCommand $encoded" 2>&1
exit $LASTEXITCODE
