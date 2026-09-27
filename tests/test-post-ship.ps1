<#
  test-post-ship.ps1

      pwsh -NoProfile -File .\tests\test-post-ship.ps1

  The three things that follow a tip: the site feed mirror
  (Publish-SiteFeed.ps1), the launcher update (Update-Launcher.ps1) and the
  VirusTotal report (Publish-VirusTotal.ps1), and Ship.ps1's wiring of all
  three.

  WHY THIS EXISTS. Ship ended at "Everyone in the world has five minutes" while
  three things it had never done were left to somebody remembering: the site
  feed the launcher asks first held whatever was last copied there by hand, no
  release had ever been read back to see whether it was actually offered, and
  the VirusTotal link the Downloads page prints had never had a file behind it.

  WHAT IS PROVED HERE.

    - Each of the three scripts parses, says what it is for where Get-Help can
      read it, and documents every parameter it declares. Same rule as
      tests\test-script-index.ps1 holds Ship to, for the same reason: a list
      presented as complete is trusted as complete.
    - Ship calls each one inside the one block that a dry run never reaches, so
      a dry run cannot touch the VPS, the site or VirusTotal, and each call is
      behind its own -Skip switch.
    - The block sits after the publisher and before the site news, because the
      news, the Discord post and the server countdown all tell people to
      update, and the feed has to be serving the release before that.
    - A failure in any of them leaves the release published and makes Ship exit
      non-zero, which is the standing order that the three go out with the tip.
    - The mirror's -Plan works out what would be sent, by sha256 rather than by
      name, and sends nothing.
    - VirusTotal with no key on the machine stops and names where the key goes,
      rather than half running.
    - The launcher update refuses a feed that names a version and no download,
      which is the shape that offers every launcher an update it cannot take.

  Read only apart from files under its own temp folder. Nothing here reaches the
  network: the runs are the offline paths of each script (-Plan -Offline,
  -NoVerify, and a missing key).
#>
[CmdletBinding()]
param([string]$ScriptsPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ScriptsPath) { $ScriptsPath = Join-Path (Split-Path -Parent $Here) 'scripts' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
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

$Utf8 = New-Object Text.UTF8Encoding($false)
$IfAst = [System.Management.Automation.Language.IfStatementAst]
$CmdAst = [System.Management.Automation.Language.CommandAst]

function Parse([string]$path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    return [pscustomobject]@{ Ast = $ast; Tokens = @($t); Errors = @($e) }
}

# Every if clause a node sits inside, from the inside out. The clause and not
# just the if: a hook called in the else of "if ($SkipRemirror)" is guarded by
# that switch, and one called in its then branch would be the opposite.
function Conditions($node) {
    $out = @()
    $prev = $node
    $p = $node.Parent
    while ($p) {
        if ($p -is $IfAst) {
            foreach ($c in $p.Clauses) {
                if ([object]::ReferenceEquals($c.Item2, $prev)) { $out += $c.Item1.Extent.Text }
            }
            if ($p.ElseClause -and [object]::ReferenceEquals($p.ElseClause, $prev)) {
                # Every clause of the if, not only the first: the launcher
                # update is the else of "if ($ModsOnly) ... elseif
                # ($SkipLauncherUpdate)", and its own switch is the second one.
                $out += ('else of: ' + (@($p.Clauses | ForEach-Object { $_.Item1.Extent.Text }) -join ' and '))
            }
        }
        $prev = $p
        $p = $p.Parent
    }
    return $out
}

# ---- the three scripts themselves ------------------------------------------
$hooks = @(
    @{ Leaf = 'Publish-SiteFeed.ps1';   Skip = 'SkipRemirror' },
    @{ Leaf = 'Update-Launcher.ps1';    Skip = 'SkipLauncherUpdate' },
    @{ Leaf = 'Publish-VirusTotal.ps1'; Skip = 'SkipVirusTotal' }
)
foreach ($h in $hooks) {
    $path = Join-Path $ScriptsPath ('release\' + $h.Leaf)
    Yes ("$($h.Leaf) is in scripts\release") (Test-Path -LiteralPath $path)
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $p = Parse $path
    Yes "  $($h.Leaf) parses" ($p.Errors.Count -eq 0)
    $help = $p.Ast.GetHelpContent()
    Yes "  and says what it is for, where Get-Help reads it" ($null -ne $help -and [bool]([string]$help.Synopsis).Trim())
    $declared = @()
    if ($p.Ast.ParamBlock) { $declared = @($p.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    $documented = @()
    if ($help) {
        foreach ($k in $help.Parameters.Keys) {
            if (([string]$help.Parameters[$k]).Trim()) { $documented += $k.ToUpperInvariant() }
        }
    }
    $missing = @($declared | Where-Object { $documented -notcontains $_.ToUpperInvariant() })
    Yes ("  and every one of its $($declared.Count) parameter(s) has a .PARAMETER" +
         $(if ($missing.Count) { ': ' + ($missing -join ', ') + ' do not' } else { '' })) ($declared.Count -gt 0 -and $missing.Count -eq 0)
    # -NoPause is how Ship calls them: it has nobody there to press Enter.
    Yes '  and it takes -NoPause, which is how Ship calls it' ($declared -contains 'NoPause')
}

# ---- Ship's wiring ---------------------------------------------------------
$ShipPath = Join-Path $ScriptsPath 'release\Ship.ps1'
Yes 'Ship.ps1 is there' (Test-Path -LiteralPath $ShipPath)
if (-not (Test-Path -LiteralPath $ShipPath)) { Done }
$ship = Parse $ShipPath
Yes '  Ship.ps1 parses' ($ship.Errors.Count -eq 0)
$shipSrc = [IO.File]::ReadAllText($ShipPath, $Utf8)
$shipDeclared = @($ship.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($sw in 'SkipRemirror', 'SkipLauncherUpdate', 'SkipVirusTotal', 'SkipPostShip') {
    Yes "  Ship takes -$sw" ($shipDeclared -contains $sw)
}

# Where each hook is run from, and what it sits inside. Ship runs all three
# through one function, Invoke-PostShip, which is what reads each exit code and
# remembers a failure, so a hook started any other way would be one whose
# failure nothing counted. Named in a Say line is not running it: the AST is
# read for the call rather than the file for the name.
$calls = @($ship.Ast.FindAll({ param($n) $n -is $CmdAst -and $n.GetCommandName() -eq 'Invoke-PostShip' }, $true))
Yes ("  Ship runs them through one Invoke-PostShip ({0} call(s))" -f $calls.Count) ($calls.Count -eq 3)
$at = @{}
foreach ($h in $hooks) {
    $named = @($calls | Where-Object { $_.Extent.Text.Contains($h.Leaf) })
    Yes ("  Ship runs $($h.Leaf) once") ($named.Count -eq 1)
    if ($named.Count -ne 1) { continue }
    $at[$h.Leaf] = $named[0].Extent.StartOffset
    $conds = @(Conditions $named[0])
    Yes ("    inside the block a dry run never reaches" + $(if ($conds.Count) { ' (' + ($conds -join ' / ') + ')' } else { '' })) (
        @($conds | Where-Object { $_ -match '-not \$DryRun\b' }).Count -gt 0)
    Yes ("    and behind -$($h.Skip)") (@($conds | Where-Object { $_ -match ('else of: .*\$' + $h.Skip + '\b') }).Count -gt 0)
    Yes '    and behind -SkipPostShip as well' (
        @($conds | Where-Object { $_ -match 'else of: .*\$SkipPostShip\b' }).Count -gt 0)
}

# The order on screen is the order it happens in, and this one matters: the
# feed has to serve the release before the news, the Discord post and the
# server's countdown send anybody to get it.
$atPublish = $shipSrc.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs")
$atNews = $shipSrc.IndexOf("'..\ops\Publish-News.ps1'")
$atRun = @($at.Values | Sort-Object)
Yes 'the three follow the publisher' ($atPublish -gt 0 -and $atRun.Count -eq 3 -and $atRun[0] -gt $atPublish)
Yes '  and come before the site news, the Discord post and the countdown' (
    $atNews -gt 0 -and $atRun.Count -eq 3 -and $atRun[2] -lt $atNews)

# What happens when one of them fails. The tip is already published by then, so
# nothing may be unpublished, and the exit code is how the standing order that
# the three go out together is either kept or reported.
Yes 'a failed follow-on is remembered rather than exited on' ($shipSrc -match '\$script:PostShipFailed \+= ')
Yes '  and named again on the last screen, with the line that puts it right' (
    $shipSrc -match 'of the three things that follow it did NOT complete' -and $shipSrc -match '\$\(\$f\.PutRight\)')
$exitIfs = @($ship.Ast.FindAll({ param($n) $n -is $IfAst -and $n.Extent.Text -match '\$script:PostShipFailed\.Count' -and
                                           $n.Extent.Text -match 'exit 1' }, $true))
Yes '  and Ship exits non-zero because of it' ($exitIfs.Count -ge 1)
Yes '  while nothing in that block unpublishes anything' ($shipSrc -notmatch 'PostShipFailed[\s\S]{0,400}Unbump')

# ---- the mirror, offline ---------------------------------------------------
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-post-ship-' + [Guid]::NewGuid().ToString('N'))
$script:T = $T
$ps = (Get-Process -Id $PID).Path
function Run([string]$leaf, [string[]]$withArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptsPath ('release\' + $leaf)) @withArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = $out }
}

try {
    $rel = Join-Path $T 'Thornswood-Releases'
    $root = Join-Path $T 'Play'
    $dist = Join-Path $T 'dist'
    $stage = Join-Path (Join-Path $dist 'Play') '_dist'
    New-Item -ItemType Directory -Force -Path $rel, $stage, (Join-Path $root 'Launcher') | Out-Null

    # A pack and a launcher whose bytes are what the feed names, and a pack the
    # feed names that nobody has any more.
    $pack = Join-Path $stage 'pack-20990101-0000.zip'
    [IO.File]::WriteAllText($pack, 'the pack this release made')
    $exe = Join-Path $root 'Launcher\Thornswood.exe'
    [IO.File]::WriteAllText($exe, 'the launcher this release published')
    $packSha = (Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash.ToLower()
    $exeSha = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    $gone = 'c' * 64

    function Write-Feed($doc) {
        [IO.File]::WriteAllText((Join-Path $rel 'version.json'), (ConvertTo-Json -InputObject $doc -Depth 6), $Utf8)
    }
    Write-Feed @{
        launcherVersion = '1.1.99'
        launcherUrl     = "https://thornswood.net/feed/assets/$exeSha"
        launcherSha256  = $exeSha
        updateFeedUrl   = 'https://thornswood.net/feed/version.json'
        packs           = @(
            @{ id = '20990101-0000'; url = "https://thornswood.net/feed/assets/$packSha"; sha256 = $packSha },
            @{ id = '20260101-0000'; url = 'https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/1'; sha256 = $gone }
        )
    }

    $plan = Run 'Publish-SiteFeed.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-Plan', '-Offline', '-NoPause')
    Yes ("the mirror's -Plan runs to the end (exit $($plan.Code))") ($plan.Code -eq 0)
    Yes '  and reads the tip off the releases clone' ($plan.Out -match 'launcher 1\.1\.99')
    Yes '  and matches the pack to the file on this machine by its sha256' ($plan.Out -match [regex]::Escape($pack))
    Yes '  and the launcher too' ($plan.Out -match [regex]::Escape($exe))
    Yes '  and leaves out the pack the feed keeps on GitHub' ($plan.Out -notmatch $gone.Substring(0, 12))
    Yes '  and says version.json goes last' ($plan.Out -match 'version\.json, last')

    # ---- the launcher update, offline --------------------------------------
    $ok = Run 'Update-Launcher.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-NoVerify', '-NoPause')
    Yes ("the launcher update passes a feed that offers a download (exit $($ok.Code))") ($ok.Code -eq 0)
    Yes '  and says the install is running the exe that was published' ($ok.Out -match 'is the exe this release published')

    Write-Feed @{ launcherVersion = '1.1.99'; launcherUrl = ''; launcherSha256 = $exeSha; packs = @() }
    $noUrl = Run 'Update-Launcher.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-NoVerify', '-NoPause')
    Yes ("  and refuses a feed with a version and no download (exit $($noUrl.Code))") ($noUrl.Code -eq 1)
    Yes '  saying every launcher would read the number and be offered nothing' ($noUrl.Out -match 'offered nothing')

    Write-Feed @{ launcherVersion = '1.1.99'; launcherUrl = "https://thornswood.net/feed/assets/$exeSha"; launcherSha256 = 'not-a-hash'; packs = @() }
    $noSha = Run 'Update-Launcher.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-NoVerify', '-NoPause')
    Yes ("  and refuses one whose launcherSha256 is not a sha256 (exit $($noSha.Code))") ($noSha.Code -eq 1)

    # ---- VirusTotal with no key -------------------------------------------
    $noKey = Run 'Publish-VirusTotal.ps1' @('-Root', $root, '-DistRoot', $dist,
                                            '-KeyFile', (Join-Path $T 'no-key-here.txt'),
                                            '-KeyName', 'THORNSWOOD_VIRUSTOTAL_KEY_FOR_A_TEST', '-NoPause')
    Yes ("VirusTotal with no key on the machine stops (exit $($noKey.Code))") ($noKey.Code -eq 1)
    Yes '  and names the file the key goes in' ($noKey.Out -match 'no-key-here\.txt')
    Yes '  and the environment variable it reads instead' ($noKey.Out -match 'THORNSWOOD_VIRUSTOTAL_KEY_FOR_A_TEST')
    Yes '  and the switch that ships without waiting on it' ($noKey.Out -match '-SkipVirusTotal')
    Yes '  and sent nothing, because it had nothing to send with' ($noKey.Out -notmatch 'The report fills in')
}
finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Done
