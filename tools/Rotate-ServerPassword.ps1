<#
  Rotate-ServerPassword.ps1

  Changes the server password and hands the new one to the site, so the
  launcher can fetch it after checking Discord.

  This is what makes a ban stick. Someone removed from the Discord cannot get a
  new password, but they still have the last one, so after a ban you rotate and
  their copy stops connecting.

    .\Rotate-ServerPassword.ps1
    .\Rotate-ServerPassword.ps1 -Password 'something-you-chose'
    .\Rotate-ServerPassword.ps1 -Minutes 10 -Why 'a ban'

  READ THIS FIRST. It used to also write the password into the game server's
  settings and restart it, and that step was always a lie. SkyMP has no join
  password: there is no sPassword in server-settings.json, nothing in
  gamemode.js reads one, and the field only exists in the launcher's config
  because Skyrim Together had a join screen and SkyMP does not.

  So what this actually changes is which password the SITE hands out, and that
  is all it changes. The game server itself is open to anyone who knows the
  address and port, with or without this. The thing that will close it is a
  check in gamemode.js on connect, and that does not exist yet.

  Which means this is still worth running after a ban, because it stops a
  removed person's launcher from getting a live answer out of the site. It is
  not a door, it is a bolt on one door out of two.

  What it does, in order:

    1. Makes a new password, or takes yours.
    2. Writes it into the site's config, so the launcher can be handed it.

  It no longer touches the game server or restarts it, because there was
  nothing to write there and the restart threw everybody out for nothing.

  On a launcher older than 1.0.197 the password comes out of version.json
  rather than the site, so those copies keep whatever they last read. Once
  1.0.197 is out and everyone has it, this starts biting properly.
#>
[CmdletBinding()]
param(
  [string]$Password,
  [int]$Minutes = 5,
  [string]$Why = 'a password change',
  [switch]$Now,
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$DocsRoot   = 'C:/Thornswood-Docs',
  [string]$ServerRoot = 'C:/Thornswood-Server',
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. Deploy-Docs.ps1 hit this on 17 Sep and
  # solved it; every other script here carried the short version that cannot,
  # and on 20 Sep this one truncated at 10,252 characters and reported
  # "Unexpected token '$?'" about a line fifteen above the one that was cut.
  # This is that fix, copied across so the sixteen scripts that talk to the VPS
  # all behave the same way.
  #
  # Under the limit it goes on the command line as before, because that is one
  # round trip. Over it, the script is sent as a file and run from there, which
  # has no length to run into.
  if ($cmd.Length -le 6000) {
    return & ssh @ssh "$User@$Vps" $cmd 2>&1
  }

  $far = 'C:/Windows/Temp/thornswood-remote.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & scp @ssh $tmp "$User@${Vps}:$far" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Vps" }
    # The path goes across as it is. Windows PowerShell takes forward
    # slashes, and converting them was how this shipped with the slashes
    # stripped out of it entirely: C:WindowsTempthornswood-remote.ps1.
    # And bare, with no quotes round it. sshd hands this line to cmd.exe,
    # which passes single quotes on to Windows PowerShell as part of the
    # path, and -File refuses it: "The given path's format is not supported".
    # Measured 24 September. The path above is ours and has no spaces.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

if (-not $Yes) {
  Write-Host ''
  Write-Host '  This changes the password the site hands out. Nobody is disconnected' -ForegroundColor Yellow
  Write-Host '  and the game server is not touched, because it has no password of its' -ForegroundColor Yellow
  Write-Host '  own. Launchers older than 1.0.197 keep whatever version.json gave them.' -ForegroundColor Yellow
  Write-Host ''
  $a = Read-Host '  Type yes to go ahead'
  if ($a -ne 'yes') { Write-Host '  stopped, nothing changed'; return }
}

if (-not $Password) {
  # Long and from a real random source, because nobody types this one any more.
  # Generated until it is long enough: stripping the non alphanumeric characters
  # out of base64 can leave fewer than asked for, and Substring throws on that.
  function NewKey([int]$n) {
    $out = ''
    while ($out.Length -lt $n) {
      $b = New-Object byte[] 48
      [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
      $out += ([Convert]::ToBase64String($b) -replace '[^A-Za-z0-9]','')
    }
    return $out.Substring(0, $n)
  }
  $Password = NewKey 28
}

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Password))
$docsWin = $DocsRoot.Replace('/','\')
$srvWin  = $ServerRoot.Replace('/','\')

Write-Host ''
Write-Host 'Handing it to the site...'
Remote @"
`$ErrorActionPreference = 'Stop'
`$pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))
`$f = '$docsWin\config.json'
`$cfg = @{}
if (Test-Path `$f) {
  try { (Get-Content `$f -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { `$cfg[`$_.Name] = `$_.Value } } catch { }
}
`$cfg['serverPassword'] = `$pw
# No byte order mark. Node refuses to parse a file that starts with one.
[IO.File]::WriteAllText(`$f, (`$cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding(`$false)))
'site config written'

Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -eq 'node.exe' -and `$_.CommandLine -like '*Thornswood-Docs*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName 'Thornswood Docs' -EA SilentlyContinue
Start-Sleep -Seconds 3
if (Get-NetTCPConnection -LocalPort 3001 -State Listen -EA SilentlyContinue) { 'site restarted' }
else { 'SITE DID NOT COME BACK' }
"@ | ForEach-Object { "  $_" }

# The game server settings used to be written here. They are not any more.
# There is no sPassword in server-settings.json, nothing in gamemode.js reads
# one, and the write threw every time. The restart that followed it emptied the
# world for a change that was never landing anywhere.
Write-Host ''
Write-Host '  Done. Nobody needs to be told the new password, because nobody' -ForegroundColor Green
Write-Host '  has it. The launcher asks the site for it after checking Discord.' -ForegroundColor Green
Write-Host ''
Write-Host '  It is not printed here on purpose.' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  The game server was not touched and nobody was disconnected.' -ForegroundColor DarkGray
Write-Host '  It has no password of its own to change. Until gamemode.js checks' -ForegroundColor Yellow
Write-Host '  who is connecting, the address and port are the only thing between' -ForegroundColor Yellow
Write-Host '  a stranger and the world.' -ForegroundColor Yellow
