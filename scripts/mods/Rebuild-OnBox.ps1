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
#>
[CmdletBinding()]
param(
    # Whose plugins: the dev server's (the load order dev runs) or live's.
    [ValidateSet('dev', 'main')]
    [string]$Server = 'dev',

    # Where every file the chain wrote is copied, at its repository path.
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# Quoted, so each goes to Run-OnBox.ps1 as one of the tool's words and never
# as a parameter of its own.
& (Join-Path $Here 'Run-OnBox.ps1') 'scripts/mods/Rebuild-ContentTables.ps1' '-Data' '{data}' '-PluginsTxt' '{plugins}' -Server $Server -Out $Out
exit $LASTEXITCODE
