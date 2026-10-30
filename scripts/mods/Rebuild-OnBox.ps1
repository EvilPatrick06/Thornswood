<#
  Rebuild-OnBox.ps1

  The deploy gate's Rebuild-ContentTables verb (#2841): the whole content
  chain, scripts\mods\Rebuild-ContentTables.ps1, run by Run-OnBox.ps1
  against a server's plugins on the box, from main as main is when the gate
  reads it. Every file the chain wrote is copied into -Out, the gate's out
  folder for the run, so it goes back to the session that asked, sealed:

      pwsh scripts/vps/Box-Run.ps1 -Line 'Rebuild-ContentTables'
      pwsh scripts/vps/Box-Run.ps1 -Line 'Rebuild-ContentTables -Server main'

  The files land in that session's box-run\<run>\files at their repository
  paths, for a pull request of their own.

  WHY. Since the cloud's key to the box came off (30 Oct 2026), Run-OnBox.ps1
  from a cloud session stops at the bridge's 401, and Patrick's card of that
  afternoon put content rebuilds through the gate rather than on One. The
  gate runs main only, never a branch: it runs as SYSTEM, and its scripts
  reach the box as Administrator, so a pushed branch's builders would be
  unreviewed code on the production box.

  It is Run-OnBox.ps1 as One runs it, here over the gate's loopback key: the
  run's own folder, a copy of the server's plugins, the archives linked in,
  and nothing the chain did not write brought back.

  A PULL REQUEST'S DATA, NEVER ITS CODE (Patrick's B on the #4835 card, 30
  Oct 2026: a cloud route for data-only changes). With -Pull and -Head the
  box fetches that pull request's head with the gate's read-only key, and
  only when the head is still -Head lays the files $DataFromPull names, and
  nothing else, from it over main's tree. Main's own builders then read them:

      pwsh scripts/vps/Box-Run.ps1 -Line 'Rebuild-ContentTables -Pull 4835 -Head <its full head commit>'

  The tables come back sealed, for the pull request's branch. A file of the
  list the pull request does not change is main's as it is. Patrick accepted
  that main's builders read a pull request's plugin as SYSTEM on the box; no
  builder, script or test of the pull request's runs, so a change to a
  builder lands on main first, in a pull request of its own.
#>
[CmdletBinding()]
param(
    # Whose plugins: the dev server's (the load order dev runs) or live's.
    [ValidateSet('dev', 'main')]
    [string]$Server = 'dev',

    # Where every file the chain wrote is copied, at its repository path.
    [string]$Out = '',

    # A pull request whose data files go over main's, and the head commit
    # it must still be at.
    [int]$Pull = 0,
    [string]$Head = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The only files a pull request may hand main's builders: data they read,
# never anything they run. The content plugin, and who makes each recipe and
# at what rank (#3132), which Build-RecipeTable.ps1 reads.
$DataFromPull = @('game/content/Thornswood-Content.esp', 'records/recipe-owners.json')

$repo = (Resolve-Path -LiteralPath (Join-Path $Here '..\..')).ProviderPath
function Invoke-PullGit([string[]]$Words) {
    $was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = @(& git -C $repo @Words 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $was }
    return [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}
if ($Pull -or $Head) {
    if ($Pull -le 0 -or $Head -cnotmatch '^[0-9a-f]{40}$') { Write-Host 'STOP. -Pull and -Head go together: the pull request''s number and the full commit its head is at. Nothing was run.' -ForegroundColor Red; exit 1 }
    $ref = "refs/remotes/origin/pull-$Pull"
    $f = Invoke-PullGit @('fetch', '--quiet', '--depth', '1', '--no-tags', 'origin', "+refs/pull/$Pull/head:$ref")
    if ($f.Code -ne 0) { Write-Host ("STOP. pull request $Pull could not be fetched: " + (($f.Out | Select-Object -Last 2) -join ' ') + ' Nothing was run.') -ForegroundColor Red; exit 1 }
    $at = (Invoke-PullGit @('rev-parse', $ref)).Out -join ''
    if ($at -cne $Head) { Write-Host "STOP. pull request $Pull is at $at now, not $Head. Nothing was run." -ForegroundColor Red; exit 1 }
    $took = @()
    foreach ($p in $DataFromPull) {
        if ((Invoke-PullGit @('cat-file', '-e', "$($Head):$p")).Code -ne 0) { continue }
        $c = Invoke-PullGit @('checkout', $Head, '--', $p)
        if ($c.Code -ne 0) { Write-Host ("STOP. $p could not be taken from pull request $Pull`: " + ($c.Out -join ' ') + ' Nothing was run.') -ForegroundColor Red; exit 1 }
        $took += $p
    }
    # Run-OnBox.ps1 sends a commit, never the working tree, so the files go
    # into one of this checkout's own, which the gate's next run throws away.
    $c = Invoke-PullGit @('-c', 'user.name=Thornswood Gate', '-c', 'user.email=gate@thornswood.invalid', 'commit', '--quiet', '--allow-empty', '-m', "main with the data of pull request $Pull at $Head")
    if ($c.Code -ne 0) { Write-Host ('STOP. the data could not be committed in the checkout: ' + ($c.Out -join ' ') + ' Nothing was run.') -ForegroundColor Red; exit 1 }
    Write-Host ("main's builders read, from pull request $Pull at $Head`: " + $(if ($took.Count) { $took -join ', ' } else { 'nothing, it changes none of ' + ($DataFromPull -join ', ') }))
}

# Quoted, so each goes to Run-OnBox.ps1 as one of the tool's words and never
# as a parameter of its own.
& (Join-Path $Here 'Run-OnBox.ps1') 'scripts/mods/Rebuild-ContentTables.ps1' '-Data' '{data}' '-PluginsTxt' '{plugins}' -Server $Server -Out $Out
exit $LASTEXITCODE
