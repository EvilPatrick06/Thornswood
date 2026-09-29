<#
  test-tools-retired.ps1

      pwsh -NoProfile -File .\tests\test-tools-retired.ps1

  tools\ holds nothing to run any more: git tracks only its README, the
  forwarding copies of the common commands are gone and nothing in the
  repository tells anybody to type one, and every file a script still reads
  out of tools\ is one git ignores and the README names.

  WHY. The reorganisation (issue #440) moved every script out of tools\ into
  scripts\<area> on 25 September and left forwarding copies of the eleven
  commands people typed most, plus tools\Vps.ps1, "for one release". Main
  release 1.1.101 went out from the new layout on 27 September, and the rule
  since 28 September is no backwards compatibility except for updating, so
  the copies went. A doc that still says .\tools\Ship.ps1 now sends somebody
  to a file that is not there, which is what this catches.

  HOW. git ls-files, and every tracked text file read for a path to one of
  the old copies. docs\archive and scripts\oneoff are history and keep the
  paths they were written with; tools\README.md names them on purpose, as the
  table of what moved where. Sync-LoadOrder.py is asked for its default
  settings file, because until this phase it looked two folders up from
  scripts\mods and fell back to the old C:\Thornswood-Dev folder.

  Read only.
#>
[CmdletBinding()]
param([string]$Repo)

$ErrorActionPreference = 'Stop'
if (-not $Repo) {
    $Here = $PSScriptRoot
    if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $Repo = Split-Path -Parent $Here
}

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# ---- 1. git tracks only the README in tools ---------------------------------
$trackedTools = @(& git -C $Repo ls-files -- tools)
Yes ('git tracks only tools/README.md in tools (' + ($trackedTools -join ', ') + ')') (
    $trackedTools.Count -eq 1 -and $trackedTools[0] -eq 'tools/README.md')

$stubs = @('Build-Launcher', 'Bump-Version', 'Deploy-DevGamemode', 'Deploy-Docs', 'Deploy-Gamemode',
           'Deploy-Server', 'Go', 'Install-Bot', 'Install-Runner', 'Install-Voice', 'Ship', 'Vps')
$areas = @('release', 'deploy', 'vps', 'ops', 'mods', 'dev')
foreach ($s in $stubs) {
    $real = @($areas | Where-Object { Test-Path -LiteralPath ([IO.Path]::Combine($Repo, 'scripts', $_, $s + '.ps1')) })
    Yes ('  ' + $s + '.ps1 is in scripts\' + ($real -join ',') + ' and not in tools') (
        $real.Count -eq 1 -and -not (@($trackedTools) -contains ('tools/' + $s + '.ps1')))
}

# ---- 2. nothing tells anybody to run one of the old copies ------------------
$rx = [regex]('(?i)tools[\\/]+(' + (($stubs | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\.ps1\b')
$skip = '^(docs/archive/|scripts/oneoff/|tools/README\.md$|tests/test-tools-retired\.ps1$|tests/test-vps-defaults\.ps1$)'
$hits = @()
$read = 0
foreach ($f in @(& git -C $Repo ls-files)) {
    if ($f -match $skip) { continue }
    if ($f -notmatch '\.(md|ps1|psm1|js|cs|py|json|yml|yaml|txt|cmd|bat|html|xaml|ini)$') { continue }
    $full = Join-Path $Repo $f
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $text = [IO.File]::ReadAllText($full)
    $read++
    $i = 0
    foreach ($line in ($text -split "`n")) {
        $i++
        if ($rx.IsMatch($line)) { $hits += ('{0}:{1}' -f $f, $i) }
    }
}
foreach ($h in $hits) { Write-Host "      still names an old tools copy: $h" }
Yes ("no tracked file names an old tools\ copy ($read files read)") ($hits.Count -eq 0 -and $read -gt 500)

# ---- 3. what a script still reads out of tools is ignored and named --------
$readme = [IO.File]::ReadAllText((Join-Path $Repo 'tools\README.md'))
$named = @{}
$scriptsDir = Join-Path $Repo 'scripts'
foreach ($f in @(Get-ChildItem -LiteralPath $scriptsDir -Filter *.ps1 -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/]oneoff[\\/]' })) {
    $text = [IO.File]::ReadAllText($f.FullName)
    foreach ($m in [regex]::Matches($text, "'(?:\.\.\\)+tools\\([^'\\]+)'")) { $named[$m.Groups[1].Value] = $f.Name }
    foreach ($m in [regex]::Matches($text, "Join-Path \`$RepoDir 'tools\\([^'\\]+)'")) { $named[$m.Groups[1].Value] = $f.Name }
}
Yes ('the scripts still read a few files out of tools (' + (@($named.Keys | Sort-Object) -join ', ') + ')') ($named.Count -ge 3)
foreach ($k in @($named.Keys | Sort-Object)) {
    & git -C $Repo check-ignore -q -- ('tools/' + $k)
    $ignored = ($LASTEXITCODE -eq 0)
    Yes ('  tools\' + $k + ' (read by ' + $named[$k] + ') is ignored by git and named in tools\README.md') (
        $ignored -and $readme.Contains('`' + $k + '`'))
}
Yes 'tools\README.md says nothing here is to be run' ($readme -match 'Nothing to run here')
Yes 'and gives the new path of every old copy' (@($stubs | Where-Object { -not $readme.Contains($_ + '.ps1') }).Count -eq 0)

# ---- 4. Sync-LoadOrder.py finds the fork in the repository ------------------
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if ($py) {
    $sync = Join-Path $Repo 'scripts\mods\Sync-LoadOrder.py'
    $code = "import importlib.util,sys; s=importlib.util.spec_from_file_location('s', sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m.default_settings())"
    $said = [string](& $py.Source -c $code $sync)
    $want = [IO.Path]::Combine($Repo, 'engine', 'skymp', 'build', 'dist', 'server', 'server-settings.json')
    Yes ('Sync-LoadOrder.py''s default settings are in the repository''s engine build (' + $said.Trim() + ')') (
        [IO.Path]::GetFullPath($said.Trim()) -eq [IO.Path]::GetFullPath($want))
}
else {
    Write-Host 'SKIP  no python here to ask Sync-LoadOrder.py'
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
