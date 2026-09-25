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

# A LONG SCRIPT GOES AS A FILE, because a command line cannot hold it and
# nothing says so. On the VPS a long command line arrives cut short, and the
# far end complains about a brace in a script nobody can see: Deploy-Docs.ps1
# hit it on 17 September and Deploy-DevGamemode.ps1 on 20 September, and
# sixteen scripts were given this guard that night. This one was not, and it
# is the one that takes any script at all. Base64 of UTF-16 is about 2.7 times
# the script, so the 6,000 character gate the sixteen use is a script of about
# 2 KB. Measured 24 September: a 10,266 character script made a 27,526
# character command line. Where exactly the VPS cuts a line has not been
# measured. Entry 197 on the To Do List asked for "the remote helper survives
# a 10 KB script"; tools\test-remote-big-script.ps1 is that.
#
# Under the limit nothing changes. Over it, the script is copied up and run
# from there. A name of its own, so two of these at once cannot run each
# other's script. Written with a byte order mark so Windows PowerShell on the
# box reads it as UTF-8 whichever PowerShell sent it. The exit code is the
# far end's, kept across the tidy up: the script's own number when cmd.exe
# hands the line on, and 1 for any failure when Windows PowerShell does,
# because that is what powershell -Command returns for a program that failed.
# Both measured on this machine, 24 September.
#
# The path goes bare, with no quotes round it; it is ours and has no spaces.
# Measured on this machine on 24 September, not on the VPS: bare runs whether
# cmd.exe or Windows PowerShell hands the line on, and the form the sixteen
# used, the path in single quotes, fails under cmd.exe. That form did run on
# the VPS on 20 and 21 September, so which shell sshd uses there is not known,
# and bare is the form that works under either. Bare also reaches ssh the same
# from Windows PowerShell and from pwsh, which quote an embedded double quote
# differently.
$cmd = "powershell -NoProfile -EncodedCommand $encoded"
if ($cmd.Length -gt 6000) {
    $far = 'C:/Windows/Temp/thornswood-remote-' + [Guid]::NewGuid().ToString('N') + '.ps1'
    $tmp = [IO.Path]::GetTempFileName()
    $rc = 1
    try {
        [IO.File]::WriteAllText($tmp, $full, (New-Object Text.UTF8Encoding($true)))
        & scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new $tmp "${VpsUser}@${VpsHost}:$far" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not copy the script to $VpsHost. Nothing was run." }
        & ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$VpsUser@$VpsHost" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
        $rc = $LASTEXITCODE
        & ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$VpsUser@$VpsHost" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    exit $rc
}

& ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$VpsUser@$VpsHost" "powershell -NoProfile -EncodedCommand $encoded" 2>&1
exit $LASTEXITCODE
