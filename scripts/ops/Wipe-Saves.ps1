<#
  Wipe-Saves.ps1

      .\scripts\ops\Wipe-Saves.ps1

  Starts the world over. Everybody begins again, nothing is claimed, nothing
  has been looted, and every container in the province is holding what
  Bethesda put in it.

  Patrick, 21 September: "we also need an easy way to start the world from
  scratch so all of the property is unclamied, things arent looted, etc so when
  we test things and when launch out of Alpha". This is that, and it is this
  script rather than a second one beside it, because a second one would have
  overlapped this by three quarters and the two would have drifted apart.

  FOUR THINGS MOVE, and between them they are the whole of what the world
  remembers:

    world                    the changeform database. Every reference the
                             server has ever written to: what is in each
                             container, what has been picked up, which chests
                             it emptied of weapons, who has had their starting
                             purse. Take this away and every chest in Skyrim is
                             full again and untouched.
    private\characters.json  who everybody is.
    private\property.json    who holds which building, which are locked, and
                             the ground each one covers.
    private\farm-claims.json the farms on ground with no building on it.
    data\property.json and data\farm-claims.json, where both were until
                             25 September (issue #541: data is served to
                             anybody), so a wipe on a server still running
                             the older gamemode takes them too.

  The first two were here from the start. The last two are the gamemode's own
  and were added on 21 September: without them a fresh world would have come
  up with every house still claimed by somebody who no longer exists.

  It does NOT delete anything. It stops the server, renames the storage out of
  the way with today's date on it, and starts the server again on an empty one.
  The old storage sits beside the new one until you decide it can go, which
  means a wipe you regret at midnight is a rename away from being undone
  instead of gone.

  Why a wipe is on the table at all: taking a plugin out of the middle of the
  load order shifts the index of every plugin below it, and SkyMP turns a form
  id into a plugin by that index. Stored character references made under the
  old numbering then point at the wrong plugin. A wipe is the version of that
  problem with no half broken characters in it.

  Stop before you run this if people are on. It puts them out.

  It asks you to type WIPE before it does anything. -Yes answers that, for a
  release being run start to finish without somebody sitting at it:

    .\Wipe-Saves.ps1          asks
    .\Wipe-Saves.ps1 -Yes     does not ask

  Read-Host reads the console rather than standard input, so a wipe run from a
  script or from an agent cannot answer the question however it is fed: it comes
  back empty and the script stops with "Left alone.". That is the whole reason
  this switch exists, and it is a switch rather than the question going away,
  because the question is what stops a wipe nobody meant to run.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = 'Administrator',
  # There was a -Task here naming one scheduled task. It is gone because the
  # tasks are now read off the box, one per server folder found, and a
  # parameter that no longer decides anything is worse than no parameter: it
  # reads like it works.
  [switch]$NoPause,
  # Skip the typed confirmation. The list of what would go is still printed
  # first, so an unattended run still leaves a record of exactly what it took.
  [switch]$Yes
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}
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
    # And bare, with no quotes round it; the path above is ours and has no
    # spaces. Measured on this machine on 24 September, not on the VPS: bare
    # runs whether cmd.exe or Windows PowerShell hands the line on, and the
    # old form, the path in single quotes, fails under cmd.exe. The old form
    # did run on the VPS on 20 and 21 September, so which shell sshd uses
    # there is not known, and bare is the form that works under either.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

$stamp = (Get-Date).ToString('yyyyMMdd-HHmm')

Write-Host ''
Write-Host '  THORNSWOOD  -  wipe the characters' -ForegroundColor White
Say "  on $Vps" 'DarkGray'

# ------------------------------------------------------------ what is there ---
Head 'What would go'
$lines = Remote @"
`$ErrorActionPreference = 'Continue'
`$roots = @()
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  if (Test-Path (Join-Path `$d.FullName 'server-settings.json')) { `$roots += `$d.FullName }
}
if (`$roots.Count -eq 0) { 'NOROOT'; exit }
# Which scheduled task runs out of which folder, read off the task's own action
# rather than guessed from the folder name. The live one is 'Thornswood Server'
# and the dev one is 'Thornswood Dev Server', which no transform of
# 'Thornswood-Server-Dev' produces, so guessing it would stop the wrong server.
#
# Each task takes the LONGEST root its action mentions, not the first one that
# matches. C:\Thornswood-Server is a prefix of C:\Thornswood-Server-Dev, so a
# plain contains test gives the dev task the live folder, and on 22 September
# that stopped the dev server twice and moved the live world out from under a
# server that was still running.
`$taskOf = @{}
foreach (`$t in (Get-ScheduledTask -EA SilentlyContinue)) {
  foreach (`$a in @(`$t.Actions)) {
    `$line = "`$(`$a.Execute) `$(`$a.Arguments) `$(`$a.WorkingDirectory)"
    `$best = ''
    foreach (`$r in `$roots) {
      if (`$line -like ('*' + `$r + '*') -and `$r.Length -gt `$best.Length) { `$best = `$r }
    }
    if (`$best -ne '' -and -not `$taskOf.ContainsKey(`$best)) { `$taskOf[`$best] = `$t.TaskName }
  }
}
foreach (`$r in `$roots) {
  'ROOT|' + `$r
  if (`$taskOf.ContainsKey(`$r)) { 'TASK|' + `$r + '|' + `$taskOf[`$r] } else { 'NOTASK|' + `$r }
  foreach (`$n in @('world', 'private\characters.json', 'private\property.json', 'private\farm-claims.json', 'data\property.json', 'data\farm-claims.json')) {
    `$p = Join-Path `$r `$n
    if (-not (Test-Path `$p)) { 'NONE|' + `$n; continue }
    `$b = 0; `$c = 0
    if ((Get-Item `$p).PSIsContainer) {
      foreach (`$f in (Get-ChildItem `$p -Recurse -File -EA SilentlyContinue)) { `$b += `$f.Length; `$c++ }
    } else {
      `$b = (Get-Item `$p).Length; `$c = 1
      try {
        `$j = Get-Content `$p -Raw | ConvertFrom-Json
        'CHARS|' + @(`$j).Count
      } catch { }
    }
    'ITEM|' + `$p + '|' + `$b + '|' + `$c
  }
}
"@

# Every root, not the last one. This held a single $root until 22 September,
# and the survey emits a ROOT line per server, so it kept whichever came last.
# On the VPS that is C:\Thornswood-Server-Dev, so every wipe ever run took the
# dev world, left the live world alone, and printed a list of both as though it
# had taken both. Nothing said otherwise and the live characters stayed.
$roots  = @()
$taskOf = @{}
$items  = @()
foreach ($l in $lines) {
  $s = "$l"
  if ($s -eq 'NOROOT') { Die 'No server-settings.json anywhere under C:\ on that machine, so there is no server to wipe.' }
  $bits = $s -split '\|'
  switch ($bits[0]) {
    'ROOT'   { $roots += $bits[1]; Say "  server at $($bits[1])" 'DarkGray' }
    'TASK'   { $taskOf[$bits[1]] = $bits[2]; Say ("    run by the '{0}' task" -f $bits[2]) 'DarkGray' }
    'NOTASK' { Say '    no scheduled task runs out of this folder, so it is moved but not restarted' 'Yellow' }
    'ITEM'  { $items += $bits[1]; Say ("  {0,8:n1} MB  {1}   ({2} file(s))" -f ([int64]$bits[2] / 1MB), $bits[1], $bits[3]) 'Yellow' }
    'CHARS' { Say ("  {0} character record(s) in characters.json" -f $bits[1]) 'Yellow' }
    'NONE'  { Say ("  not there: {0}" -f $bits[1]) 'DarkGray' }
  }
}
if ($items.Count -eq 0) { Die 'Nothing to wipe. Either it is already empty or the paths moved.' }

# ------------------------------------------------------------------- ask it ---
Write-Host ''
Say '  Every character anybody has made on this server goes back to nothing.' 'Red'
Say '  They are renamed rather than deleted, so this is undoable today, but' 'DarkGray'
Say '  anybody who logs in after it starts over and that part is not.' 'DarkGray'
Write-Host ''
if ($Yes) {
  Say '  -Yes was passed, so it is not asking. Going ahead.' 'Yellow'
}
else {
  $typed = Read-Host '  Type WIPE to go ahead'
  if ($typed -cne 'WIPE') { Die 'Left alone.' }
}

# ------------------------------------------------------------------- do it ---
# Both lists go across as literals. A single quote inside either would end the
# string early on the far side, so it is doubled first.
function Lit($a) { return (($a | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ',') }
$rootsLit = Lit $roots
$tasksLit = Lit @($roots | Where-Object { $taskOf.ContainsKey($_) } | ForEach-Object { $taskOf[$_] })

Head 'Stopping the servers'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$t in @($tasksLit)) {
  `$null = & schtasks /end /tn `$t 2>&1
  'ended ' + `$t
}
Start-Sleep -Seconds 3
foreach (`$p in (Get-Process -Name 'skymp*','node' -EA SilentlyContinue)) {
  if ("`$(`$p.Path)" -like '*Thornswood-Server*') { 'still running: ' + `$p.ProcessName + ' ' + `$p.Id }
}
'stopped'
"@
foreach ($l in $out) { Say "  $l" }

Head 'Moving the old storage aside'
$moved = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$r in @($rootsLit)) {
foreach (`$n in @('world', 'private\characters.json', 'private\property.json', 'private\farm-claims.json', 'data\property.json', 'data\farm-claims.json')) {
  `$p = Join-Path `$r `$n
  if (-not (Test-Path `$p)) { continue }
  `$leaf = Split-Path -Leaf `$p
  `$dir  = Split-Path -Parent `$p
  if (`$leaf -like '*.json') {
    # Each json file keeps its own name, or a fresh world would
    # come up with the property register saved as characters-before-<stamp>.
    `$to = Join-Path `$dir ((`$leaf -replace '[.]json$', '') + '-before-$stamp.json')
  }
  else { `$to = Join-Path `$dir ('world-before-$stamp') }
  try { Move-Item -LiteralPath `$p -Destination `$to -Force -EA Stop; 'moved  ' + `$p + '  ->  ' + `$to }
  catch { 'FAILED ' + `$p + '  ' + `$_.Exception.Message }
}
}
"@
$bad = $false
foreach ($l in $moved) {
  if ("$l" -match '^FAILED') { $bad = $true; Say "  $l" 'Red' } else { Say "  $l" 'Green' }
}
if ($bad) {
  Say '  The server is stopped. Start it again from the panel or re-run once' 'Yellow'
  Say '  whatever is holding those files has let go.' 'Yellow'
}

Head 'Starting them again'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$t in @($tasksLit)) { `$null = & schtasks /run /tn `$t 2>&1 }
Start-Sleep -Seconds 12
foreach (`$r in @($rootsLit)) {
  `$r
  `$cf = Join-Path `$r 'private\characters.json'
  if (Test-Path `$cf) {
    try { `$j = Get-Content `$cf -Raw | ConvertFrom-Json; '  now  ' + @(`$j).Count + ' character record(s)' } catch { '  now  characters.json is there but unreadable yet' }
  } else { '  now  no characters.json yet, which is what empty looks like' }
  # The tail is read per server and only two lines each, because six lines of
  # one server's log was what made a wipe that touched one of them read as
  # though it had done the lot.
  `$lg = Join-Path `$r 'server.log'
  if (Test-Path `$lg) { Get-Content `$lg -Tail 2 | ForEach-Object { '  log  ' + `$_ } }
}
"@
foreach ($l in $out) { Say "  $l" 'DarkGray' }

Head 'Done'
Say '  The old storage is beside the new one with today''s date on it.' 'Green'
Say '  Leave it a week. Clean-Everything.ps1 will offer it once you are sure.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
