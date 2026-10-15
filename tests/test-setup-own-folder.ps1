<#
  test-setup-own-folder.ps1

      pwsh -NoProfile -File .\tests\test-setup-own-folder.ps1

  The setup window offers Thornswood's own Skyrim folder, and what is chosen
  there is what the launcher starts with.

  Issue #906, Patrick on 28 September: "let's offer the own folder during
  install as well". The launcher makes Root\Game out of what Vortex has
  deployed (OwnGame.Make) and offers it in a box the first time it opens and
  in Settings, Maintenance; a new person only found it there. The setup window
  now has a card with that panel's own words, a tick box, and Choose Vortex's
  folder. A tick goes to Setup-Thornswood.ps1 as -MakeOwnGame and into
  config.json as MakeOwnGame, and the launcher then makes the folder without
  asking once Vortex has deployed. A chosen folder goes in as VortexGame, the
  field the Settings button writes. Left alone, nothing changes: the launcher
  asks, as it did before.

  What this holds the files to:
    - the card says what Settings says, word for word, from launcher\ui.xaml;
    - the tick box starts empty, an untouched card starts the script with
      exactly the arguments it had before, and the script then writes no
      MakeOwnGame, so the default is unchanged;
    - SetupStartInfo, compiled out of Bootstrap.cs, adds -MakeOwnGame and
      -VortexGame only when they were chosen;
    - the Vortex folder check, compiled out of Bootstrap.cs, takes and refuses
      the folders OwnGame.PointAt does, with its sentences;
    - the config part of Setup-Thornswood.ps1, lifted out of its syntax tree
      and run on a temp folder, writes MakeOwnGame and VortexGame, keeps what
      was already there, and writes neither on a standalone install; what it
      writes is read back through the launcher's own Config field lines;
    - the launcher makes the folder without its question when MakeOwnGame is
      set, and still asks when it is not;
    - no em dash and never the word the project does not use, in anything
      this added.

  Everything it makes is under a temp folder it removes.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Root) { $Root = Split-Path -Parent $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bsPath    = Join-Path $Root 'installer\setup\Bootstrap.cs'
$setupPath = Join-Path $Root 'installer\Setup-Thornswood.ps1'
$uiPath    = Join-Path $Root 'launcher\ui.xaml'
$cfgPath   = Join-Path $Root 'launcher\app\Config.cs'
$shellPath = Join-Path $Root 'launcher\app\ShellOwnGame.cs'
$ownPath   = Join-Path $Root 'launcher\app\OwnGame.cs'
$bs    = [IO.File]::ReadAllText($bsPath)
$ui    = [IO.File]::ReadAllText($uiPath)
$cfgCs = [IO.File]::ReadAllText($cfgPath)
$shell = [IO.File]::ReadAllText($shellPath)
$own   = [IO.File]::ReadAllText($ownPath)

# A C# method by its head and a brace match that steps over strings and line
# comments, the same reader test-setup-in-window.ps1 uses.
function Get-Method([string]$text, [string]$head) {
    $at = $text.IndexOf($head)
    if ($at -lt 0) { return '' }
    $i = $text.IndexOf('{', $at)
    if ($i -lt 0) { return '' }
    $depth = 0
    while ($i -lt $text.Length) {
        $c = $text[$i]
        if ($c -eq '"' -or $c -eq "'") {
            $q = $c
            $i++
            while ($i -lt $text.Length -and $text[$i] -ne $q) {
                if ($text[$i] -eq '\') { $i++ }
                $i++
            }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '/') {
            $nl = $text.IndexOf("`n", $i)
            if ($nl -lt 0) { return '' }
            $i = $nl
        }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) }
        }
        $i++
    }
    return ''
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-906-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # ---- 1. the card says what Settings says --------------------------------
    $card = [regex]::Match($bs, '(?s)<Border x:Name=""OwnBox"".*?</Border>')
    Yes 'the setup window has the own folder card' ($card.Success)
    $cardText = if ($card.Success) { $card.Value } else { '' }
    $pnl = [regex]::Match($ui, '(?s)<StackPanel x:Name="PnlOwnGame">.*?<Rectangle ')
    Yes 'the Settings panel is where this expects it, in launcher\ui.xaml' ($pnl.Success)
    if ($pnl.Success) {
        $texts = @([regex]::Matches($pnl.Value, '(?:Text|Content)="([^"]{12,})"') | ForEach-Object { $_.Groups[1].Value })
        $want = @($texts | Where-Object {
            $_ -eq "Thornswood's own Skyrim folder" -or $_ -like 'Runs Thornswood from a Skyrim folder of its own*' -or
            $_ -like 'The launcher finds the folder Vortex deploys into*' -or
            $_ -eq "Choose Vortex's folder" -or $_ -eq 'Forget the chosen folder' })
        Yes 'the panel has the five pieces the card copies' ($want.Count -eq 5)
        foreach ($t in $want) {
            $short = if ($t.Length -gt 48) { $t.Substring(0, 48) + '...' } else { $t }
            Yes ('the card says it word for word: ' + $short) ($cardText.Contains('""' + $t + '""'))
        }
    }
    Yes 'and the Vortex folder picker says what the Settings picker says' (
        $bs.Contains('"Choose the Skyrim folder Vortex deploys into. In Vortex, Mods, Open, Open Game Folder opens it."') -and
        $shell.Contains('"Choose the Skyrim folder Vortex deploys into. In Vortex, Mods, Open, Open Game Folder opens it."'))
    Yes 'the card is hidden with the others once the script is running' (
        (Get-Method $bs 'static int RunSetupScript(').Contains('ownBox.Visibility = Visibility.Collapsed'))

    # ---- 2. the default is what it was ---------------------------------------
    $chk = [regex]::Match($cardText, '<CheckBox x:Name=""ChkOwnGame""[^>]*>')
    Yes 'the tick box is on the card' ($chk.Success)
    Yes 'and starts empty, so an untouched card is the launcher asking as before' ($chk.Success -and -not $chk.Value.Contains('IsChecked'))
    $startM = Get-Method $bs 'static void Start('
    $iRead = $startM.IndexOf('makeOwnGame = chkOwn != null && chkOwn.IsChecked == true;')
    Yes 'Install reads the tick on the window''s thread before the work thread starts' (
        $iRead -gt 0 -and $startM.IndexOf('new Thread(Work)') -gt $iRead)
    Yes 'and the card cannot be changed once Install is pressed' (
        $startM.Contains('chkOwn.IsEnabled = false;') -and $startM.Contains('btnVortexPick.IsEnabled = false;'))
    Yes 'Work passes the choice to the script' (
        (Get-Method $bs 'static void Work(').Contains('SetupStartInfo(PowerShellExe(), script, installRoot, makeOwnGame, vortexGame)'))
    Yes 'the launcher''s field is false unless set, with no initialiser to turn it on' (
        $cfgCs -match '(?m)^\s*\[DataMember\] public bool MakeOwnGame;\s*$')

    # ---- 3. SetupStartInfo and the Vortex folder check, compiled -------------
    $start = Get-Method $bs 'static ProcessStartInfo SetupStartInfo('
    $probl = Get-Method $bs 'static string VortexFolderProblem('
    Yes 'Bootstrap has SetupStartInfo and VortexFolderProblem' ($start.Length -gt 0 -and $probl.Length -gt 0)
    Add-Type -TypeDefinition (@'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
public static class Ts906 {
'@ + "public $start`npublic $probl`n}")

    $script = 'C:\payload\Setup-Thornswood.ps1'
    $before = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script + '" -MovePayload -Root "D:\Thornswood" -NonInteractive'
    Yes 'untouched, the script gets exactly the arguments it had before' (
        ([Ts906]::SetupStartInfo('powershell.exe', $script, 'D:\Thornswood', $false, '')).Arguments -eq $before)
    Yes 'and a null folder is the same as none' (
        ([Ts906]::SetupStartInfo('powershell.exe', $script, 'D:\Thornswood', $false, $null)).Arguments -eq $before)
    Yes 'ticked, it adds -MakeOwnGame and nothing else' (
        ([Ts906]::SetupStartInfo('powershell.exe', $script, 'D:\Thornswood', $true, '')).Arguments -eq ($before + ' -MakeOwnGame'))
    $vf = 'S:\Steam Library\steamapps\common\Other Server Online'
    Yes 'a chosen folder goes as -VortexGame, quoted' (
        ([Ts906]::SetupStartInfo('powershell.exe', $script, 'D:\Thornswood', $true, $vf + '\')).Arguments -eq ($before + ' -MakeOwnGame -VortexGame "' + $vf + '"'))

    $sky = Join-Path $tmp 'Other Skyrim'
    New-Item -ItemType Directory -Force -Path (Join-Path $sky 'Data') | Out-Null
    $full = ''
    $why = [Ts906]::VortexFolderProblem($sky, [ref]$full)
    Yes 'a folder with no SkyrimSE.exe is refused, in PointAt''s words' (
        $null -ne $why -and $why.Contains('has no SkyrimSE.exe in it, so it is not a Skyrim folder and nothing changed.'))
    [IO.File]::WriteAllText((Join-Path $sky 'SkyrimSE.exe'), 'x')
    $why = [Ts906]::VortexFolderProblem($sky, [ref]$full)
    Yes 'a Skyrim Vortex has not deployed into is refused, in PointAt''s words' (
        $null -ne $why -and $why.Contains('it has no Data\vortex.deployment.json, the record Vortex leaves in every folder it deploys to'))
    [IO.File]::WriteAllText((Join-Path $sky 'Data\vortex.deployment.json'), '{}')
    $why = [Ts906]::VortexFolderProblem('"' + $sky + '\"', [ref]$full)
    Yes 'a Skyrim with Vortex''s record is taken, quotes and trailing backslash and all' ($null -eq $why)
    Yes 'and saved as its full path' ($full -eq $sky)
    foreach ($s in @('has no SkyrimSE.exe in it, so it is not a Skyrim folder and nothing changed. Choose the folder that Open Game Folder opens in Vortex.',
                     'the record Vortex leaves in every folder it deploys to, so nothing changed. Choose the folder that Open Game Folder opens in Vortex.')) {
        Yes ('the launcher says the same: ' + $s.Substring(0, 40) + '...') ($own.Contains($s) -and $bs.Contains($s))
    }

    # ---- 4. the script's config part, lifted and run -------------------------
    $tokens = $null; $errs = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$errs)
    Yes 'Setup-Thornswood.ps1 parses' ($errs.Count -eq 0)
    $params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    Yes 'it takes -MakeOwnGame and -VortexGame' ($params -contains 'MakeOwnGame' -and $params -contains 'VortexGame')
    $stmts = @($ast.EndBlock.Statements)
    $from = -1; $to = -1
    for ($i = 0; $i -lt $stmts.Count; $i++) {
        $t = $stmts[$i].Extent.Text
        if ($from -lt 0 -and $t.StartsWith('$cfgFrom = ')) { $from = $i }
        if ($from -ge 0 -and $t.StartsWith('if ((Test-Path $cfgFrom) -or $ownGame.Count)')) { $to = $i; break }
    }
    Yes 'the config part is where this expects it' ($from -ge 0 -and $to -gt $from)
    $lifted = (($stmts[$from..$to]) | ForEach-Object { $_.Extent.Text }) -join "`n"

    # The launcher's own two field lines, so what the script writes is read
    # the way the launcher reads it.
    $fields = @([regex]::Matches($cfgCs, '(?m)^\s*(\[DataMember\] public (?:string VortexGame = "";|bool MakeOwnGame;))\s*$') | ForEach-Object { $_.Groups[1].Value })
    Yes 'the launcher''s VortexGame and MakeOwnGame lines are in Config.cs' ($fields.Count -eq 2)
    # The attributes live in a different assembly on each .NET.
    $serRef = if ($PSVersionTable.PSEdition -eq 'Core') { 'System.Runtime.Serialization.Primitives' } else { 'System.Runtime.Serialization' }
    Add-Type -ReferencedAssemblies $serRef -TypeDefinition (@'
using System.Runtime.Serialization;
[DataContract] public class Cfg906 {
'@ + ($fields -join "`n") + "`n}")
    function Read-AsLauncher([string]$path) {
        $raw = [IO.File]::ReadAllBytes($path)
        $skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF) { 3 } else { 0 }
        $ms = New-Object IO.MemoryStream(, $raw[$skip..($raw.Length - 1)])
        return (New-Object Runtime.Serialization.Json.DataContractJsonSerializer([Cfg906])).ReadObject($ms)
    }

    $editions = @('powershell.exe')
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { $editions += 'pwsh' }
    $n = 0
    function Invoke-Config([string]$ps, [bool]$collection, [bool]$make, [string]$vortex, [string]$oldJson) {
        $script:n++
        $case = Join-Path $tmp ('case' + $script:n)
        $pay = Join-Path $case 'payload'
        $inst = Join-Path $case 'install'
        New-Item -ItemType Directory -Force -Path $pay, $inst | Out-Null
        [IO.File]::WriteAllText((Join-Path $pay 'config.json'), '{ "ServerAddress": "203.0.113.23", "VortexGame": "", "ServerPassword": "" }')
        if ($oldJson) { [IO.File]::WriteAllText((Join-Path $inst 'config.json'), $oldJson) }
        $pre = @(
            'Set-StrictMode -Version Latest'
            '$ErrorActionPreference = ''Stop'''
            'function Say($m, $c = ''Gray'') { Write-Host $m }'
            'function Head($m) { Write-Host $m }'
            ('$Here = ''' + $pay + '''')
            ('$Root = ''' + $inst + '''')
            ('$Collection = $' + $collection)
            ('$MakeOwnGame = [switch]$' + $make)
            ('$VortexGame = ''' + $vortex + '''')
        ) -join "`n"
        $file = Join-Path $case 'run.ps1'
        [IO.File]::WriteAllText($file, $pre + "`n" + $lifted, (New-Object Text.UTF8Encoding($false)))
        $out = & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file 2>&1 | Out-String
        $cfg = Join-Path $inst 'config.json'
        $json = if (Test-Path -LiteralPath $cfg) { Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json } else { $null }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out; Json = $json; Path = $cfg }
    }
    function Has($o, [string]$name) { return ($null -ne $o) -and ($o.PSObject.Properties.Name -contains $name) }

    foreach ($ps in $editions) {
        $tag = if ($ps -eq 'pwsh') { ' (PowerShell 7)' } else { ' (Windows PowerShell)' }
        $plain = Invoke-Config $ps $true $false '' ''
        Yes ('untouched, the config is written and has no MakeOwnGame' + $tag) ($plain.Code -eq 0 -and $null -ne $plain.Json -and -not (Has $plain.Json 'MakeOwnGame'))
        Yes ('and says nothing about the own folder' + $tag) (-not $plain.Out.Contains("Thornswood's own Skyrim folder"))
        if ($plain.Json) {
            $l = Read-AsLauncher $plain.Path
            Yes ('which the launcher reads as asking first' + $tag) (-not $l.MakeOwnGame -and $l.VortexGame -eq '')
        }

        $made = Invoke-Config $ps $true $true '' '{ "ServerPassword": "kept", "VortexGame": "" }'
        Yes ('ticked, config.json says MakeOwnGame true' + $tag) ($made.Code -eq 0 -and (Has $made.Json 'MakeOwnGame') -and $made.Json.MakeOwnGame -eq $true)
        Yes ('and what was already in it is kept' + $tag) ((Has $made.Json 'ServerPassword') -and $made.Json.ServerPassword -eq 'kept')
        Yes ('and the window is told' + $tag) ($made.Out.Contains('On. The launcher makes it by itself once Vortex has deployed the Thornswood collection.'))
        if ($made.Json) { Yes ('which the launcher reads as make it without asking' + $tag) ((Read-AsLauncher $made.Path).MakeOwnGame) }

        $vg = Invoke-Config $ps $true $false ($sky + '\') ''
        Yes ('a chosen Vortex folder goes in as VortexGame' + $tag) ($vg.Code -eq 0 -and (Has $vg.Json 'VortexGame') -and $vg.Json.VortexGame -eq $sky)
        Yes ('and alone it does not turn MakeOwnGame on' + $tag) (-not (Has $vg.Json 'MakeOwnGame'))
        if ($vg.Json) { Yes ('the launcher reads the same folder' + $tag) ((Read-AsLauncher $vg.Path).VortexGame -eq $sky) }

        $bad = Invoke-Config $ps $true $true (Join-Path $tmp 'no such folder') ''
        Yes ('a folder that is not a Skyrim is said and left out, not a stop' + $tag) (
            $bad.Code -eq 0 -and $bad.Json.VortexGame -eq '' -and $bad.Out.Contains('is not a Skyrim folder') -and $bad.Json.MakeOwnGame -eq $true)

        $alone = Invoke-Config $ps $false $true $sky ''
        Yes ('a standalone install has nothing to make, and writes neither' + $tag) (
            $alone.Code -eq 0 -and -not (Has $alone.Json 'MakeOwnGame') -and $alone.Json.VortexGame -eq '' -and
            $alone.Out.Contains('already has a Game folder of its own'))
    }

    # ---- 5. the launcher takes it --------------------------------------------
    $ask = Get-Method $shell 'static void AskOwnGame('
    $iMake = $ask.IndexOf('if (cfg.MakeOwnGame)')
    $iBox  = $ask.IndexOf('MessageBox.Show(' + "`r`n" + '                "Give Thornswood a Skyrim folder of its own?')
    if ($iBox -lt 0) { $iBox = $ask.IndexOf('"Give Thornswood a Skyrim folder of its own?') }
    Yes 'the launcher makes the folder without its question when MakeOwnGame is set' (
        $iMake -gt 0 -and $iBox -gt $iMake -and $ask.Substring($iMake, $iBox - $iMake).Contains('StartOwnGame(true, true);'))
    Yes 'only once WhyNot says it can be made' ($ask.IndexOf('if (why != null)') -ge 0 -and $ask.IndexOf('if (why != null)') -lt $iMake)
    Yes 'and still asks when it is not set' ($iBox -gt 0)
    $atStart = Get-Method $shell 'static void OwnGameAtStart('
    Yes 'a tick given at install outweighs a no left by an earlier install' ($atStart.Contains('(!OwnGame.Declined || c.MakeOwnGame)'))

    # ---- 6. the house words, in everything this added ------------------------
    $setup = [IO.File]::ReadAllText($setupPath)
    $mine = @(
        $cardText
        (Get-Method $bs 'static void SayOwnGame(')
        $probl
        (Get-Method $bs 'static void PickVortexFolder(')
        $lifted
        $ask
        [regex]::Match($setup, '(?s)if \(\$ownGame\.Contains\(''MakeOwnGame''\)\) \{.*?\}').Value
    ) -join "`n"
    Yes 'the words this added are all there to check' ($mine.Length -gt 4000)
    Yes 'no em dash in them' ($mine.IndexOf([char]0x2014) -lt 0)
    Yes 'and never the word the project does not use' ($mine -notmatch '(?i)\bplayers?\b')
    Yes 'no em dash anywhere in the setup program' ($bs.IndexOf([char]0x2014) -lt 0)
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
