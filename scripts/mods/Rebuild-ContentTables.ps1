<#
  Rebuild-ContentTables.ps1

  Rebuilds every table that is read out of the plugins of the load order, in
  the order they read each other, after a change to one of Thornswood's own
  plugins in game\content, and says what changed. Issue #2923.

      pwsh scripts/mods/Rebuild-ContentTables.ps1
      pwsh scripts/mods/Rebuild-ContentTables.ps1 -Data D:\Thornswood\Game\Data
      pwsh scripts/mods/Rebuild-ContentTables.ps1 -List

  WHY. Nothing said which tables a content change makes stale, so each change
  found them one red build at a time. Measured on #1382 (#2911, 20 Oct): two
  VPS builds went red after Thornswood-Content.esp gained three teas, first
  on merchant-role-tables.json, then on the merchant bundle inside
  gamemode.js; before those, four harnesses were red on One until their
  tables were rebuilt. docs\systems\station-placement.md named four builders;
  #2911 ran eleven; and the /give names table, which reads every item in the
  load order, was in neither list, so the teas and the furniture items are
  still not in it (counted in gamemode.js's ADMIN_NAMES, 20 Oct).
  Since #2923 every builder reads Thornswood's own plugins from game\content
  (scripts\dev\OwnPlugins.js, OwnPlugins.ps1, own_plugins.py), so a content
  change is built from the repository's plugin with no Data folder made for it.

  WHAT IT RUNS. scripts\mods\content-tables.json, top to bottom: every
  builder that reads a load order, with what each reads and writes, and the
  three that are left out and why. tests\test-2923-own-plugins.js holds that
  list to the builders and its order to what they read. The first builder
  that fails stops the chain; what the ones before it changed is still
  listed. -Data and -PluginsTxt are handed to every builder that takes them;
  left out, each builder uses its own default, which on One is the game at
  C:\Thornswood (most read the Default profile's plugin list, the hunt,
  harvest, worldspace, wake and /give tables the OwnGame one).

  AFTER THE BUILDERS. records\asset-provenance.json holds each of Thornswood's
  own plugins by sha256, and tests\test-asset-provenance.js refuses a file
  that changed since it was registered. These three are built here, so their
  entries take the new hash; each entry's status, licence and ask stay as
  written, and the line printed for each says the entry's "what" describes
  what the plugin holds, which only the change's author can say.

  WHAT IT SAYS. Every file under game, docs\systems and records that is
  different from before it ran, by sha256. git diff then shows what each one
  is.

  -List prints the steps it would run, with their arguments, and runs none.
#>
[CmdletBinding()]
param(
    # The game's Data folder, for every builder that reads one.
    [string]$Data = '',
    # The plugin list, for every builder that takes one.
    [string]$PluginsTxt = '',
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = (Resolve-Path -LiteralPath (Join-Path $Here '..\..')).ProviderPath
$chain = [IO.File]::ReadAllText((Join-Path $Here 'content-tables.json')) | ConvertFrom-Json

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

function Find-Exe([string[]]$Names) {
    foreach ($n in $Names) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Path }
    }
    return $null
}

# Every file the builders can write, by sha256, so what changed is measured.
function Get-TreePrint {
    $map = @{}
    foreach ($top in @('game', 'docs\systems', 'records')) {
        $dir = Join-Path $repo $top
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File) {
            $rel = $f.FullName.Substring($repo.Length).TrimStart('\', '/').Replace('\', '/')
            $map[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $map
}

$node = Find-Exe @('node')
$python = Find-Exe @('python', 'py', 'python3')
$shell = (Get-Process -Id $PID).Path
$need = @()
if (-not $node) { $need += 'node' }
if (-not $python) { $need += 'python' }
if ($need.Count -and -not $List) { throw ('not found on this machine: ' + ($need -join ', ') + '. Nothing was run.') }

$steps = @($chain.steps)
$runs = @()
foreach ($s in $steps) {
    $tool = Join-Path $repo $s.tool
    if (-not (Test-Path -LiteralPath $tool)) { throw ("content-tables.json names $($s.tool), which is not in this checkout. Nothing was run.") }
    $a = @()
    if ($Data -and $s.data) { $a += @($s.data, $Data) }
    if ($PluginsTxt -and $s.plugins) { $a += @($s.plugins, $PluginsTxt) }
    switch ([IO.Path]::GetExtension($tool).ToLowerInvariant()) {
        '.js'  { $runs += , @($node, (@($tool) + $a)) }
        '.py'  { $runs += , @($python, (@($tool) + $a)) }
        '.ps1' { $runs += , @($shell, (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool) + $a)) }
        default { throw ("content-tables.json names $($s.tool), which is not a .js, .py or .ps1 builder. Nothing was run.") }
    }
}

if ($List) {
    for ($i = 0; $i -lt $steps.Count; $i++) {
        Say ('{0,2}. {1} {2}' -f ($i + 1), $steps[$i].tool, (@($runs[$i][1] | Select-Object -Skip ($(if ($steps[$i].tool -like '*.ps1') { 5 } else { 1 }))) -join ' '))
    }
    Say ('{0} steps, then the hashes of game\content in records\asset-provenance.json. Nothing was run.' -f $steps.Count)
    exit 0
}

$before = Get-TreePrint
$stopped = $null
$unregistered = @()
for ($i = 0; $i -lt $steps.Count; $i++) {
    Say ''
    Say ('[{0}/{1}] {2}' -f ($i + 1), $steps.Count, $steps[$i].tool) 'Cyan'
    $exe = $runs[$i][0]
    $line = $runs[$i][1]
    & $exe @line
    if ($LASTEXITCODE -ne 0) { $stopped = '{0} ended with exit {1}' -f $steps[$i].tool, $LASTEXITCODE; break }
}

if (-not $stopped) {
    Say ''
    Say 'records\asset-provenance.json' 'Cyan'
    $regPath = Join-Path $repo 'records\asset-provenance.json'
    $bytes = [IO.File]::ReadAllBytes($regPath)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($regPath)
    $reg = $text | ConvertFrom-Json
    $wrote = $false
    $unregistered = @()
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repo 'game\content') -File) {
        $rel = 'game/content/' + $f.Name
        $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry = @($reg.assets | Where-Object { $_.path -eq $rel }) | Select-Object -First 1
        if (-not $entry) {
            Say ("  {0} has no entry. Register where it came from, as test-asset-provenance.js says, before it ships." -f $rel) 'Yellow'
            $unregistered += $rel
            continue
        }
        if ($entry.sha256 -eq $sha) { Say ("  {0} is the registered bytes" -f $rel); continue }
        $at = $text.IndexOf('"path": "' + $rel + '"')
        $m = ([regex]'"sha256": "[0-9a-f]{64}"').Match($text, $at)
        if ($at -lt 0 -or -not $m.Success -or $m.Value -ne ('"sha256": "' + $entry.sha256 + '"')) {
            Say ("  {0}: its sha256 is not where this reads it, so the register was left as it is." -f $rel) 'Yellow'
            $unregistered += $rel
            continue
        }
        $text = $text.Substring(0, $m.Index) + '"sha256": "' + $sha + '"' + $text.Substring($m.Index + $m.Length)
        $wrote = $true
        Say ("  {0}: sha256 {1} (status {2}). Its ""what"" says what the plugin holds: add what this change put in it." -f $rel, $sha.Substring(0, 16), $entry.status) 'Yellow'
    }
    if ($wrote) { [IO.File]::WriteAllText($regPath, $text, (New-Object System.Text.UTF8Encoding($bom))) }
}

$after = Get-TreePrint
$changed = @()
foreach ($k in $after.Keys) { if (-not $before.ContainsKey($k)) { $changed += "new      $k" } elseif ($before[$k] -ne $after[$k]) { $changed += "changed  $k" } }
foreach ($k in $before.Keys) { if (-not $after.ContainsKey($k)) { $changed += "gone     $k" } }
Say ''
if ($changed.Count) {
    Say ('{0} file(s) are different from before this ran:' -f $changed.Count) 'Cyan'
    foreach ($c in ($changed | Sort-Object { $_.Substring(9) })) { Say ('  ' + $c) }
} elseif ($stopped) {
    Say 'Nothing is different from before this ran.' 'Cyan'
} else {
    Say 'Nothing is different from before this ran: every table already read the plugins as they are.' 'Cyan'
}
if ($stopped) {
    Say ''
    Say ('STOP. ' + $stopped + '. The steps after it did not run.') 'Red'
    exit 1
}
if ($unregistered.Count) {
    Say ''
    Say ('STOP. records\asset-provenance.json does not hold ' + ($unregistered -join ', ') + ' the way this reads it; its hash was not written.') 'Red'
    exit 1
}
Say ''
Say ('All {0} builders ran. Run the harnesses next: the ones that hold a table to the plugin bytes are test-2468, test-2551, test-516 and test-asset-provenance.' -f $steps.Count) 'Green'
exit 0
