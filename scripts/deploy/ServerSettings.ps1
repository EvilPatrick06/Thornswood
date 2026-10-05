<#
  ServerSettings.ps1

  Which settings a game server install takes from the release, and which it
  keeps from the server it replaces. Dot-sourced by Install-ThornswoodServer.ps1
  (on the box, from beside it: Publish-Server.ps1 sends the two together),
  Export-ServerPayload.ps1 and Deploy-Server.ps1. Deploy-Server also sends
  this file's text to the box in front of $settingsCarryBlock, so the carry
  is done there, against the file the running server has.

  WHY, issue #1222. Dev rollout 6, 29 September: Publish-Server.ps1 -Channel
  dev unpacked the build's server-settings.json over the dev server's own,
  with only the port, the voice port and the name made the dev ones. The dev
  server came up with thornswoodServer, thornswoodLoadOrderRefuse and
  thornswoodRequirePass empty and an npcSettings "default" key, which refuses
  every NPC, until Deploy-DevGamemode.ps1 put them back. A live publish would
  have done the same to live, and so would a Deploy-Server.ps1 from a build
  whose settings are not the live server's (#1221).

  THE RULE. The settings a server runs are its own. An install starts from the
  file the running server has, and takes from the release only the keys the
  release is meant to change:

    a server install, Publish-Server.ps1 and Install-ThornswoodServer.ps1
    ($ThornswoodInstallKeys):
      loadOrder             the payload carries the plugins it names, and
                            every form id resolves against their order
      startPoints           a form id, whose file index is that order's
      thornswoodMostOnline  how many it holds, and the engine's seats over it
      maxPlayers            for staff, from records\most-online.json, which
                            Publish-Server holds to the commit and every deploy
                            writes the same (#481)

    Deploy-Server.ps1, the second half of the live pair
    ($ThornswoodGamemodeKeys): those, and what Deploy-Gamemode.ps1 writes for
    the live server on purpose, because Deploy-Gamemode then Deploy-Server is
    the one route that changes them on live: offlineMode, the live voice
    port, thornswoodServer main, the NPC, gear, reloot and damage settings,
    and the join pass and the written role lists once Deploy-Gamemode has been
    given them.

  Everything else stays as the running server has it: every other thornswood
  switch (the load order refusal, and the join pass on a publish), npcSettings,
  the ports, the name, dataDir, and anything the release does not name. A key
  the release has and the server does not is not added, and a release key the
  release does not have stays as the server has it. On dev,
  Deploy-DevGamemode.ps1 is what changes the switches; on live, Deploy-Gamemode
  then Deploy-Server. The two boxes keep their own, on their own folders.

  Values are compared as compact JSON, so an array and an object compare by
  what they hold. Nothing here prints a value: server-settings.json is the
  server's config, and only key names are said.

  Keep it ASCII and Windows PowerShell 5.1: it runs on the box.
#>

$ThornswoodInstallKeys = @('loadOrder', 'startPoints', 'thornswoodMostOnline', 'maxPlayers')
$ThornswoodGamemodeKeys = @($ThornswoodInstallKeys + @(
    'offlineMode', 'thornswoodVoicePort', 'thornswoodServer', 'thornswoodRequirePass',
    'thornswoodDevs', 'thornswoodPlaytesters', 'npcEnabled', 'npcAllowCrimeFaction',
    'npcAllowEssential', 'npcSettings', 'forbiddenReloot', 'equipmentSlotCheckEnabled',
    'equipmentSpellCheckEnabled', 'equipmentInventoryCheckEnabled', 'damageMultFormulaSettings'))

function Get-ThornswoodSettingText($Value) {
    if ($null -eq $Value) { return 'null' }
    return (ConvertTo-Json -InputObject $Value -Compress -Depth 30)
}

function Get-ThornswoodSettingNames($Settings) {
    if ($null -eq $Settings) { return @() }
    return @($Settings.PSObject.Properties | ForEach-Object { $_.Name })
}

<#
  The running server's settings with the release's keys put in. Returns
  Settings (the object to write), Changed (release keys that move) and Kept
  (keys the release had differently, or had and the server does not, left as
  the server has them), and Said, the lines to print.
#>
function Join-ThornswoodServerSettings($Running, $Release, [string[]]$Keys) {
    $runNames = Get-ThornswoodSettingNames $Running
    $relNames = Get-ThornswoodSettingNames $Release
    $out = [ordered]@{}
    foreach ($n in $runNames) { $out[$n] = $Running.$n }
    $changed = @()
    foreach ($k in $Keys) {
        if ($relNames -notcontains $k) { continue }
        if ($runNames -notcontains $k -or (Get-ThornswoodSettingText $Running.$k) -ne (Get-ThornswoodSettingText $Release.$k)) { $changed += $k }
        $out[$k] = $Release.$k
    }
    $kept = @()
    foreach ($k in $relNames) {
        if ($Keys -contains $k) { continue }
        if ($runNames -notcontains $k -or (Get-ThornswoodSettingText $Running.$k) -ne (Get-ThornswoodSettingText $Release.$k)) { $kept += $k }
    }
    $said = @()
    if ($changed.Count) { $said += ('the settings this release changes: ' + ($changed -join ', ')) }
    else { $said += 'this release changes none of the settings' }
    if ($kept.Count) { $said += ('kept as the running server has them, not as the release had them: ' + ($kept -join ', ')) }
    $said += ('every other setting of the ' + $runNames.Count + ' the running server has is carried across as it is')
    return [pscustomobject]@{ Settings = [pscustomobject]$out; Changed = $changed; Kept = $kept; Said = $said }
}

# The keys outside -Keys whose values differ between two settings objects, or
# that one has and the other does not: what a read-back after an install
# refuses.
function Compare-ThornswoodCarried($Before, $After, [string[]]$Keys) {
    $a = Get-ThornswoodSettingNames $Before
    $b = Get-ThornswoodSettingNames $After
    $moved = @()
    foreach ($k in @($a + $b | Sort-Object -Unique)) {
        if ($Keys -contains $k) { continue }
        if (($a -contains $k) -ne ($b -contains $k)) { $moved += $k; continue }
        if ((Get-ThornswoodSettingText $Before.$k) -ne (Get-ThornswoodSettingText $After.$k)) { $moved += $k }
    }
    return $moved
}

<#
  The join pass hold (#410) fails closed in the gamemode (#1319): false is the
  one way to turn it off, and anything that is neither true nor false holds.
  A server whose settings hold neither would change what it does the moment a
  new gamemode reached it, with nobody having asked, so Deploy-Server's carry
  refuses one until Deploy-Gamemode.ps1 -RequirePass says which. Returns ''
  for true or false, otherwise the reason, which names the key and not its
  value.
#>
function Get-ThornswoodPassSwitchProblem($Settings) {
    $names = Get-ThornswoodSettingNames $Settings
    if ($names -contains 'thornswoodRequirePass' -and $Settings.thornswoodRequirePass -is [bool]) { return '' }
    $had = 'missing'
    if ($names -contains 'thornswoodRequirePass') { $had = 'neither true nor false' }
    return ('thornswoodRequirePass is ' + $had + ' on this server and in the release, and the gamemode reads ' +
            'that as on (#1319). Say which with .\scripts\deploy\Deploy-Gamemode.ps1 -RequirePass on, or off, then deploy again.')
}

<#
  What makes a settings file wrong to send at all, whatever it is carried
  into. Any channel: an npcSettings "default" key, which the engine reads as a
  plugin name and so refuses every NPC (#879). -Channel main: anything that is
  the dev server's (#1114, #1221): a port that is not 7777, the dev voice port
  7789, the name Thornswood Dev, thornswoodServer dev.
#>
function Get-ThornswoodServerSettingsProblems($Settings, [string]$Channel = '') {
    $why = @()
    $names = Get-ThornswoodSettingNames $Settings
    if ($names -contains 'npcSettings' -and $null -ne $Settings.npcSettings -and
        (Get-ThornswoodSettingNames $Settings.npcSettings) -contains 'default') {
        $why += 'an npcSettings "default" key, which refuses every NPC'
    }
    if ($Channel -eq 'main') {
        $port = 'none'
        if ($names -contains 'port') { $port = [string]$Settings.port }
        if ($port -ne '7777') { $why += ('port ' + $port + ', not 7777') }
        if ($names -contains 'thornswoodVoicePort' -and [string]$Settings.thornswoodVoicePort -eq '7789') { $why += 'the dev voice port 7789' }
        if ($names -contains 'name' -and [string]$Settings.name -eq 'Thornswood Dev') { $why += 'the name Thornswood Dev' }
        if ($names -contains 'thornswoodServer' -and [string]$Settings.thornswoodServer -eq 'dev') { $why += 'thornswoodServer dev' }
    }
    return $why
}

<#
  Deploy-Server.ps1's carry, run on the box against its stage, after the files
  are up and before the stage is checked. It takes $Root, $Stage and
  $ReleaseKeys from the lines SwapVars puts in front of it, and this file's
  functions from the text Deploy-Server puts in front of those. Ends with
  CARRIED <sha256 of the settings it wrote> or CARRY REFUSED.
#>
$settingsCarryBlock = @'
$ProgressPreference = 'SilentlyContinue'
$stageDir = Join-Path $Root $Stage
$sp = Join-Path $stageDir 'server-settings.json'
$run = $null
$rel = $null
try { $run = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) | ConvertFrom-Json } catch { }
try { $rel = [IO.File]::ReadAllText($sp) | ConvertFrom-Json } catch { }
if ($null -eq $run -or $null -eq $rel) {
  'the settings the server runs on, or the ones sent, cannot be read, so nothing can be carried across'
  Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
  'the stage is cleared and the server was not touched'
  'CARRY REFUSED'
} else {
  $m = Join-ThornswoodServerSettings $run $rel $ReleaseKeys
  foreach ($l in $m.Said) { $l }
  $passWhy = Get-ThornswoodPassSwitchProblem $m.Settings
  if ($passWhy) {
    $passWhy
    Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
    'the stage is cleared and the server was not touched'
    'CARRY REFUSED'
  } else {
    [IO.File]::WriteAllText($sp, (ConvertTo-Json -InputObject $m.Settings -Depth 30), (New-Object Text.UTF8Encoding($false)))
    'CARRIED ' + (Get-FileHash -LiteralPath $sp -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}
'@
