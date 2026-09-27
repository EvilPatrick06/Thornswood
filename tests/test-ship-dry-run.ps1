<#
  test-ship-dry-run.ps1

  A dry run publishes nothing, and a real Ship still publishes the installer.

  The entry, found on 24 September by the script index run (entry 260):
  "-DryRun -Package publishes the installer to the site." Ship called
  Package-Thornswood.ps1 the same way on a dry run as on a real one, without
  -NoPublish, and Package-Thornswood ends by handing what it built to
  Publish-Installer.ps1, which copies it to the VPS over ssh. A dry run exists
  so a person can see what a release would do without doing it; one that puts
  a new installer on the live site is the opposite.

  The same read found one more way a dry run could reach outside the machine.
  On the dev channel, with no dev release worktree on the disk and no dev
  branch that git could see on the releases repository, Ship made the branch
  and pushed it, dry run or not.

  HOW. The real Ship.ps1 is copied into a temp folder shaped like this repo,
  beside a stand-in for every script it calls. Each stand-in writes down what it
  was asked and does nothing else. git, gh, ssh and scp are stand-ins too,
  first on PATH for the child, so anything that would leave the machine is
  written down instead of done. Ship then runs in a child PowerShell, start to
  finish:

    D  -DryRun -Package on main
    V  -DryRun -Package on dev
    R  a real Ship -Package on main
    E  -DryRun on dev, with no dev worktree and no dev branch on the releases repo

  R is there so D and V prove something: the same stand-ins, on a real Ship,
  do write down the installer going to the site, the upload, the push, the
  news, the Discord and the restart.

  R also proves the launcher that ships is the one CI built, not one compiled
  here (issue #457). A real main Ship never calls Build-Launcher.ps1: it runs
  gh release download for the tag, checks the exe against its SHA256SUMS, and
  only then installs and packs it. The gh stand-in writes a Thornswood.exe and a
  matching SHA256SUMS on "release download", so the verification passes and the
  path is exercised. A dev build and a dry run still compile locally, which is
  why V and D call Build-Launcher and never gh release download.

  The stand-ins are only worth what the real scripts do, so two of those are
  read as well: Package-Thornswood.ps1 calls Publish-Installer.ps1 only without
  -NoPublish, and every gh call and every git push, pull or fetch in
  Publish-Update.ps1 is behind -NoUpload or -NoPush, or in the dev worktree
  maker that runs only when no -ReleaseDir is given, and Ship always gives one.

  Nothing here touches this repository, the network, a game or a launcher.
  Everything it writes is under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $ShipPath) { $ShipPath = Join-Path $Here '..\scripts\release\Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    # The temp folder's path is long and says nothing; the calls read better without it.
    if ($script:T) { $what = $what.Replace($script:T, '<temp>') }
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$IfAst = [System.Management.Automation.Language.IfStatementAst]
$CmdAst = [System.Management.Automation.Language.CommandAst]
$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]

function Parse([string]$path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    return [pscustomobject]@{ Ast = $ast; Tokens = @($t); Errors = @($e) }
}

# The condition of the clause of the nearest enclosing if, walking out from a
# node, and the name of the nearest enclosing function. The clause, not just
# the if: an elseif under "-not $NoUpload" is not the branch that uploads.
function Enclosing($node) {
    $conds = @()
    $fn = ''
    $prev = $node
    $p = $node.Parent
    while ($p) {
        if ($p -is $IfAst) {
            foreach ($c in $p.Clauses) {
                if ([object]::ReferenceEquals($c.Item2, $prev)) { $conds += $c.Item1.Extent.Text }
            }
        }
        if ($p -is $FnAst -and -not $fn) { $fn = $p.Name }
        $prev = $p
        $p = $p.Parent
    }
    return [pscustomobject]@{ Conditions = $conds; Function = $fn }
}

# ---- the real scripts the stand-ins stand for ------------------------------------
$shipSrc = [IO.File]::ReadAllText($ShipPath)
$ship = Parse $ShipPath
Yes 'Ship.ps1 parses' ($ship.Errors.Count -eq 0)

$pkg = Parse (Join-Path $Here '..\scripts\release\Package-Thornswood.ps1')
$noPub = @($pkg.Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'NoPublish' })
Yes 'Package-Thornswood.ps1 has a -NoPublish switch' ($noPub.Count -eq 1)
$pubIf = @($pkg.Ast.FindAll({ param($n) $n -is $IfAst -and $n.Clauses[0].Item1.Extent.Text -eq '-not $NoPublish' }, $true))
Yes '  and one if (-not $NoPublish)' ($pubIf.Count -eq 1)
$named = @($pkg.Tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'Publish-Installer' })
$outside = @()
if ($pubIf.Count -eq 1) {
    $a = $pubIf[0].Extent.StartOffset; $b = $pubIf[0].Extent.EndOffset
    $outside = @($named | Where-Object { $_.Extent.StartOffset -lt $a -or $_.Extent.EndOffset -gt $b })
}
Yes ("  and Publish-Installer.ps1 is named only inside it ({0} time(s)), so without -NoPublish it publishes and with it it does not" -f $named.Count) ($named.Count -ge 1 -and $pubIf.Count -eq 1 -and $outside.Count -eq 0)

$pu = Parse (Join-Path $Here '..\scripts\release\Publish-Update.ps1')
$away = @($pu.Ast.FindAll({ param($n) $n -is $CmdAst }, $true) | Where-Object {
    $name = $_.GetCommandName()
    $words = @($_.CommandElements | ForEach-Object { $_.Extent.Text })
    ($name -eq 'gh') -or ($name -eq 'git' -and @($words | Where-Object { $_ -in 'push', 'pull', 'fetch', 'ls-remote', 'clone' }).Count -gt 0)
})
$loose = @()
foreach ($c in $away) {
    $e = Enclosing $c
    $held = @($e.Conditions | Where-Object { $_ -match '-not \$NoUpload\b' -or $_ -match '-not \$NoPush\b' }).Count -gt 0
    if (-not $held -and $e.Function -ne 'Ensure-DevReleases') { $loose += ('line ' + $c.Extent.StartLineNumber + ': ' + $c.Extent.Text) }
}
Yes ("Publish-Update.ps1 has gh and git calls that reach GitHub ({0}), so the next line reads something" -f $away.Count) ($away.Count -ge 5)
Yes ('  every one is behind -NoUpload or -NoPush, or in Ensure-DevReleases' + $(if ($loose.Count) { ': ' + ($loose -join '; ') } else { '' })) ($loose.Count -eq 0)
$edr = @($pu.Ast.FindAll({ param($n) $n -is $CmdAst -and $n.GetCommandName() -eq 'Ensure-DevReleases' }, $true))
$edrHeld = @($edr | Where-Object { @((Enclosing $_).Conditions | Where-Object { $_ -match '-not \$ReleaseDir\b' }).Count -gt 0 })
Yes '  Ensure-DevReleases runs there only when no -ReleaseDir is given' ($edr.Count -ge 1 -and $edrHeld.Count -eq $edr.Count)
Yes '  and Ship always gives one' ($shipSrc -match '\$pubArgs = @\{[^\r\n]*ReleaseDir = \$ReleaseDir')

# ---- a repository, a releases clone and two installs, all stand-ins --------------
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-ship-dry-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $T 'Thornswood'
$tools = Join-Path $repo 'tools'
$rel = Join-Path $T 'Thornswood-Releases'
$relDev = Join-Path $T 'Thornswood-Releases-dev'
$bin = Join-Path $T 'bin'
$root = Join-Path $T 'Play'
$rootDev = Join-Path $T 'Play-DevBuild'
$dist = Join-Path $T 'dist'
$appdata = Join-Path $T 'appdata'
$log = Join-Path $T 'calls.log'

# What every stand-in script writes down: its name and what it was given.
$noteText = @'
$line = 'NAME'
foreach ($k in @($PSBoundParameters.Keys | Sort-Object)) {
    $v = $PSBoundParameters[$k]
    if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $line += ' -' + $k } }
    else { $line += ' -' + $k + ' ' + [string]$v }
}
[IO.File]::AppendAllText($env:TS_DRY_CALLS, $line + "`r`n")
'@
function Stub([string]$name, [string]$params, [string]$body) {
    $text = "param($params)`r`n" + $noteText.Replace('NAME', $name) + "`r`n" + $body + "`r`nexit 0`r`n"
    # Each in its own area under scripts\ since phase 8 of issue #440, where Ship.ps1
    # in scripts\release calls it.
    $area = 'release'
    if ($name -in 'Publish-News', 'Publish-Discord') { $area = 'ops' }
    if ($name -eq 'Request-Restart') { $area = 'vps' }
    $dir = Join-Path $tools ('..\scripts\' + $area)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir ($name + '.ps1')), $text)
}

$oldPath = $env:PATH
$oldAppData = $env:LOCALAPPDATA
$oldCalls = $env:TS_DRY_CALLS
$oldGhPwsh = $env:TS_GH_PWSH
$oldGhDl = $env:TS_GH_DL
$ps = (Get-Process -Id $PID).Path

function Invoke-Ship([string[]]$shipArgs) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools '..\scripts\release\Ship.ps1') @shipArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $calls = @()
    if (Test-Path -LiteralPath $log) { $calls = @(Get-Content -LiteralPath $log | Where-Object { $_ }) }
    return [pscustomobject]@{ Code = $code; Out = $out; Calls = $calls }
}
# The comma keeps a one line answer an array: a return unrolls it otherwise,
# and [0] of a bare string is its first character.
function Called($run, [string]$name) { return ,@($run.Calls | Where-Object { $_ -eq $name -or $_.StartsWith($name + ' ') }) }
# Anything that would have left the machine, by the stand-ins on PATH.
function Away($run) { return ,@($run.Calls | Where-Object { $_ -match '^(git|gh|ssh|scp)( |$)' }) }
function Hash([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) } finally { $sha.Dispose() }
}
function Read-Version([string]$path) {
    $m = [regex]::Match([IO.File]::ReadAllText($path), 'Version\s*=\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

try {
    foreach ($d in @($tools, (Join-Path $tools '..\launcher\app'), (Join-Path $tools '..\scripts\release'), (Join-Path $rel '.git'), $relDev, $bin,
                     (Join-Path $root 'Launcher'), (Join-Path $rootDev 'Launcher'), $dist, (Join-Path $appdata 'Thornswood'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
    Copy-Item -LiteralPath $ShipPath -Destination (Join-Path $tools '..\scripts\release\Ship.ps1') -Force
    $updaterCs = Join-Path $tools '..\launcher\app\Updater.cs'
    [IO.File]::WriteAllText($updaterCs, "        public const string Version = `"1.1.93`";`r`n")
    [IO.File]::WriteAllText((Join-Path $rel 'version.json'), '{"launcherVersion":"1.1.93","packs":[]}')
    [IO.File]::WriteAllText((Join-Path $relDev 'version.json'), '{"launcherVersion":"1.1.93.2","packs":[],"serverPort":7001}')
    [IO.File]::WriteAllText((Join-Path $appdata 'Thornswood\published.json'), '{"main":"as last published"}')
    [IO.File]::WriteAllText((Join-Path $appdata 'Thornswood\published-dev.json'), '{"dev":"as last published"}')
    # An hour old, so the stand-in install is newer and Ship calls it built.
    foreach ($r in $root, $rootDev) {
        $exe = Join-Path $r 'Launcher\Thornswood.exe'
        [IO.File]::WriteAllText($exe, 'the launcher as installed')
        (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-1)
    }

    Stub 'Build-Launcher' '[string]$Root, [string]$OutDir, [switch]$NoPause' ''
    Stub 'Install-Launcher' '[string]$Root, [string]$From, [switch]$NoPause' @'
[IO.File]::WriteAllText((Join-Path $Root 'Launcher\Thornswood.exe'), 'the launcher this run built')
'@
    Stub 'Go' '[switch]$SkipServer, [string]$Game, [switch]$Vortex' ''
    Stub 'Sync-Client' '[switch]$Check, [switch]$NoPause, [string]$Game' ''
    # What the real publisher does under -NoUpload -NoPush: writes version.json
    # and its baseline. Otherwise it uploads and pushes, through the stand-ins.
    Stub 'Publish-Update' ('[string]$Notes, [string]$Root, [string]$RepoDir, [string]$ReleaseDir, [string]$DistRoot, ' +
                           '[switch]$NoPause, [switch]$MoveServer, [switch]$AcceptSize, [switch]$Launcher, ' +
                           '[string]$Channel, [string]$VersionOverride, [switch]$NoUpload, [switch]$NoPush') @'
$vf = Join-Path $ReleaseDir 'version.json'
$was = [string]((Get-Content -LiteralPath $vf -Raw | ConvertFrom-Json).launcherVersion)
$now = if ($VersionOverride) { $VersionOverride } else { $was }
[IO.File]::WriteAllText($vf, '{"launcherVersion":"' + $now + '","packs":[{"id":"20990101-0000"}]}')
$sn = if ($Channel -eq 'dev') { 'published-dev.json' } else { 'published.json' }
[IO.File]::WriteAllText((Join-Path (Join-Path $env:LOCALAPPDATA 'Thornswood') $sn), '{"written":"by the publisher"}')
if (-not $NoUpload) { & gh release create 20990101-0000 }
if (-not $NoPush) { & git -C $ReleaseDir push -u origin HEAD }
'@
    # The real one's last step, which the static check above holds it to.
    Stub 'Package-Thornswood' '[string]$Root, [string]$OutDir, [switch]$NoPause, [switch]$NoPublish, [string]$ReleaseDir' @'
if (-not $NoPublish) { & (Join-Path $PSScriptRoot 'Publish-Installer.ps1') -OutDir $OutDir }
'@
    Stub 'Publish-Installer' '[string]$OutDir, [switch]$OneFile' ''
    Stub 'Publish-News' '' ''
    Stub 'Publish-Discord' '[switch]$Dev' ''
    Stub 'Request-Restart' '[double]$Minutes, [string]$Mode, [string]$Why, [string]$Data' ''
    # What follows a tip: the host feed remirror and the VirusTotal upload, one
    # script run once per half. The real one reaches the VPS, the site and
    # VirusTotal, so a dry run must not call it at all and a real Ship calls it
    # twice. Ship reads each exit code and says at the end whether they
    # completed, so this hands back 0 like the rest.
    Stub 'Publish-PostShip' ('[string]$Channel, [string]$ReleaseDir, [string]$Root, [string]$DistRoot, ' +
                             '[string]$Only, [string]$Installer, [switch]$AlsoLauncher, ' +
                             '[switch]$SkipRemirror, [switch]$SkipVirusTotal, [switch]$NoPause') ''
    foreach ($n in 'git', 'gh', 'ssh', 'scp') {
        [IO.File]::WriteAllText((Join-Path $bin ($n + '.cmd')), "@echo off`r`n>>`"%TS_DRY_CALLS%`" echo %~n0 %*`r`nexit /b 0`r`n")
    }
    # gh needs one thing more than logging: on a real main Ship the launcher is
    # not compiled here, it is downloaded from the release CI built and checked
    # against SHA256SUMS (issue #457). So the gh stand-in, on "release download",
    # writes Thornswood.exe and a SHA256SUMS whose hash is that file's, into the
    # --dir it was given, the way the real gh would. It computes the hash itself,
    # so the download always verifies and the test proves the path runs, not that
    # a particular byte matches. Every other gh call still only logs.
    $ghDl = Join-Path $bin 'gh-download.ps1'
    [IO.File]::WriteAllText($ghDl, @'
$dir = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--dir') { $dir = $args[$i + 1] } }
if ($dir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'Thornswood.exe'
    [IO.File]::WriteAllText($exe, 'the launcher CI built for this tag')
    $h = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    Set-Content -LiteralPath (Join-Path $dir 'SHA256SUMS') -Value ("$h  Thornswood.exe") -Encoding ascii
}
'@)
    [IO.File]::WriteAllText((Join-Path $bin 'gh.cmd'),
        "@echo off`r`n>>`"%TS_DRY_CALLS%`" echo gh %*`r`n" +
        "if /I `"%~1`"==`"release`" if /I `"%~2`"==`"download`" `"%TS_GH_PWSH%`" -NoProfile -ExecutionPolicy Bypass -File `"%TS_GH_DL%`" %*`r`n" +
        "exit /b 0`r`n")

    $env:PATH = $bin + ';' + $oldPath
    $env:LOCALAPPDATA = $appdata
    $env:TS_DRY_CALLS = $log
    $env:TS_GH_PWSH = $ps
    $env:TS_GH_DL = $ghDl

    $feed = Join-Path $rel 'version.json'
    $devFeed = Join-Path $relDev 'version.json'
    $base = Join-Path $appdata 'Thornswood\published.json'
    $devBase = Join-Path $appdata 'Thornswood\published-dev.json'
    $distDir = Join-Path $dist 'Play\_dist'

    # ---- D: -DryRun -Package on main ------------------------------------------------
    $was = @{ feed = (Hash $feed); dev = (Hash $devFeed); base = (Hash $base) }
    $d = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-DryRun', '-Package', '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("D a main -DryRun -Package runs to the end (exit {0})" -f $d.Code) ($d.Code -eq 0 -and $d.Out -match 'Dry run finished')
    $pub = Called $d 'Publish-Update'
    Yes 'D the publisher ran, told not to upload and not to push' ($pub.Count -eq 1 -and $pub[0] -match ' -NoUpload\b' -and $pub[0] -match ' -NoPush\b')
    $pk = Called $d 'Package-Thornswood'
    Yes ('D the installer is not built for the site: Package-Thornswood.ps1 is not called without -NoPublish' +
         $(if ($pk.Count) { ' (' + ($pk -join '; ') + ')' } else { '' })) (@($pk | Where-Object { $_ -notmatch ' -NoPublish\b' }).Count -eq 0)
    Yes 'D nothing goes on the site: Publish-Installer.ps1 is not called' ((Called $d 'Publish-Installer').Count -eq 0)
    foreach ($n in 'Publish-News', 'Publish-Discord', 'Request-Restart', 'Publish-PostShip') {
        Yes "D $n.ps1 is not called" ((Called $d $n).Count -eq 0)
    }
    $gone = Away $d
    Yes ('D nothing leaves the machine: no git, gh, ssh or scp' + $(if ($gone.Count) { ' (' + ($gone -join '; ') + ')' } else { '' })) ($gone.Count -eq 0)
    $go = Called $d 'Go'
    Yes 'D Go.ps1 is told to leave the server alone' ($go.Count -eq 1 -and $go[0] -match ' -SkipServer\b')
    Yes 'D it says the installer was not rebuilt' ($d.Out -match 'not rebuilt')
    Yes '  and gives the command that builds it and publishes nothing' ($d.Out -match [regex]::Escape('Package-Thornswood.ps1 -NoPublish -OutDir "' + $distDir + '"'))
    Yes 'D version.json is byte for byte what it was' ((Hash $feed) -eq $was.feed)
    Yes '  and so is the baseline' ((Hash $base) -eq $was.base)
    Yes '  and the dev feed is not reset to match' ((Hash $devFeed) -eq $was.dev)

    # ---- V: -DryRun -Package on dev -------------------------------------------------
    $was = @{ dev = (Hash $devFeed); devBase = (Hash $devBase); feed = (Hash $feed) }
    $v = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-Package', '-Root', $rootDev, '-DistRoot', $dist, '-NoPause')
    Yes ("V a dev -DryRun -Package runs to the end (exit {0})" -f $v.Code) ($v.Code -eq 0 -and $v.Out -match 'Dry run finished')
    $pub = Called $v 'Publish-Update'
    Yes 'V the publisher ran on dev, told not to upload and not to push' ($pub.Count -eq 1 -and $pub[0] -match ' -Channel dev\b' -and $pub[0] -match ' -NoUpload\b' -and $pub[0] -match ' -NoPush\b')
    foreach ($n in 'Package-Thornswood', 'Publish-Installer', 'Publish-News', 'Publish-Discord', 'Request-Restart',
                   'Publish-PostShip') {
        Yes "V $n.ps1 is not called" ((Called $v $n).Count -eq 0)
    }
    $gone = Away $v
    Yes ('V nothing leaves the machine: no git, gh, ssh or scp' + $(if ($gone.Count) { ' (' + ($gone -join '; ') + ')' } else { '' })) ($gone.Count -eq 0)
    Yes 'V the dev feed is byte for byte what it was' ((Hash $devFeed) -eq $was.dev)
    Yes '  and so is the dev baseline' ((Hash $devBase) -eq $was.devBase)
    Yes '  and the main feed is not touched' ((Hash $feed) -eq $was.feed)
    Yes '  and Updater.cs is on the version it had' ((Read-Version $updaterCs) -eq '1.1.93')

    # ---- R: a real Ship -Package on main ----------------------------------------------
    $r = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Package', '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("R a real main Ship -Package runs to the end (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'Everyone in the world has')
    $pub = Called $r 'Publish-Update'
    Yes 'R the publisher ran, and was not told to hold anything back' ($pub.Count -eq 1 -and $pub[0] -notmatch ' -NoUpload\b' -and $pub[0] -notmatch ' -NoPush\b')
    $pk = Called $r 'Package-Thornswood'
    Yes ('R the installer is built, without -NoPublish, into the staging folder' + $(if ($pk.Count) { ' (' + ($pk -join '; ') + ')' } else { '' })) (
        $pk.Count -eq 1 -and $pk[0] -notmatch ' -NoPublish\b' -and $pk[0].Contains(' -OutDir ' + $distDir))
    Yes '  and so it goes on the site: Publish-Installer.ps1 is called' ((Called $r 'Publish-Installer').Count -eq 1)
    foreach ($n in 'Publish-News', 'Publish-Discord', 'Request-Restart') {
        Yes "R $n.ps1 is called" ((Called $r $n).Count -eq 1)
    }
    # What follows the tip: one call per half, on the main channel, each with the
    # releases clone and the staging folder, because that is where the tip and
    # its bytes are. Neither -SkipRemirror nor -SkipVirusTotal was given, so
    # neither is passed.
    $post = Called $r 'Publish-PostShip'
    Yes ('R what follows the tip runs twice, one half each, for main, with the releases clone and the staging folder' +
         $(if ($post.Count) { ' (' + ($post -join '; ') + ')' } else { '' })) (
        $post.Count -eq 2 -and
        @($post | Where-Object { $_ -match ' -Channel main\b' -and $_.Contains(' -ReleaseDir ' + $rel) -and
                                 $_.Contains(' -DistRoot ' + $dist) -and $_ -notmatch ' -Skip' }).Count -eq 2 -and
        @($post | Where-Object { $_ -match ' -Only Remirror\b' }).Count -eq 1 -and
        @($post | Where-Object { $_ -match ' -Only VirusTotal\b' }).Count -eq 1)
    # And the only launcher install is the mid-release one, into the root this
    # release was built from, before the publisher: there is no second one after
    # the tip, because a launcher updates itself from the feed it polls.
    $inst = Called $r 'Install-Launcher'
    Yes ('R Install-Launcher.ps1 runs once, on the root that shipped' + $(if ($inst.Count) { ' (' + ($inst -join '; ') + ')' } else { '' })) (
        $inst.Count -eq 1 -and $inst[0].Contains(' -Root ' + $root))
    $gone = Away $r
    Yes 'R the shipped launcher is not compiled here: Build-Launcher.ps1 is not called' ((Called $r 'Build-Launcher').Count -eq 0)
    Yes ('R the launcher CI built is downloaded and verified: gh release download runs once (' + ($gone -join '; ') + ')') (
        @($gone | Where-Object { $_ -match '^gh release download' }).Count -eq 1)
    Yes 'R the pack is uploaded: gh release create or upload runs' (
        @($gone | Where-Object { $_ -match '^gh release (create|upload)' }).Count -ge 1)
    Yes 'R the pushes happen' (@($gone | Where-Object { $_ -match '^git .*\bpush\b' }).Count -ge 1)

    # ---- E: a dev dry run with no dev worktree and no dev branch to see ---------------
    Remove-Item -LiteralPath $relDev -Recurse -Force
    $e = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-Root', $rootDev, '-DistRoot', $dist, '-NoPause')
    $gits = @($e.Calls | Where-Object { $_ -match '^git( |$)' })
    Yes ('E the stand-in git was asked, so the next lines measure something (' + ($gits -join '; ') + ')') ($gits.Count -ge 1)
    Yes 'E nothing is pushed to the releases repository' (@($gits | Where-Object { $_ -match '\bpush\b' }).Count -eq 0)
    Yes '  and no dev branch is made on this disk' (@($gits | Where-Object { $_ -match '\bworktree add\b' }).Count -eq 0)
    Yes ("E it stops and says why (exit {0})" -f $e.Code) ($e.Code -ne 0 -and $e.Out -match 'A dry run pushes nothing')
    Yes '  before anything is built or published' ((Called $e 'Build-Launcher').Count -eq 0 -and (Called $e 'Publish-Update').Count -eq 0)
}
finally {
    $env:PATH = $oldPath
    $env:LOCALAPPDATA = $oldAppData
    $env:TS_DRY_CALLS = $oldCalls
    $env:TS_GH_PWSH = $oldGhPwsh
    $env:TS_GH_DL = $oldGhDl
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Done
