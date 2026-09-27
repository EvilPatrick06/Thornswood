<#
  test-post-ship.ps1

      pwsh -NoProfile -File .\tests\test-post-ship.ps1

  What follows a published tip: Publish-PostShip.ps1, the one script Ship.ps1
  calls, and its two halves, the host feed remirror (Publish-SiteFeed.ps1) and
  the VirusTotal report for what the Downloads page offers
  (Publish-VirusTotal.ps1).

  WHY THIS EXISTS. Ship ended at "Everyone in the world has five minutes" while
  two things it had never done were left to somebody remembering: the site feed
  a launcher polls held whatever was last copied there by hand, and the
  VirusTotal link the Downloads page prints had never had a file behind it.

  AND WHY IT CHECKS THAT THERE IS NO THIRD HALF. The Launcher lane answered on
  27 September that the tip customers get is version.json and launchers poll the
  feed url in it, so the remirror is how a launcher update reaches anybody.
  Ship's mid-release Install-Launcher.ps1 refreshes the install on the machine
  that shipped, and re-running it after the tip would refresh the same one
  install again. So this fails if a second launcher step is ever added after the
  publish, and it checks the mid-release one is still there and still passed the
  build output.

  WHAT IS PROVED HERE.

    - Each of the three scripts parses, says what it is for where Get-Help can
      read it, and documents every parameter it declares. Same rule as
      tests\test-script-index.ps1 holds Ship to, for the same reason: a list
      presented as complete is trusted as complete.
    - Ship runs one post-publish script, inside the one block a dry run never
      reaches, so a dry run cannot touch the VPS, the site or VirusTotal, and
      passes its own -Skip switches on rather than having a second meaning for
      them.
    - It sits after the publisher and before the site news, because the news,
      the Discord post and the server countdown all tell people to update, and
      the feed has to be serving the release before that.
    - A failure leaves the release published and makes Ship exit non-zero, which
      is the standing order that the follow-ons go out with the tip.
    - Publish-PostShip.ps1 runs both halves, keyed off the channel, reads each
      exit code, and hands back non-zero when either did not complete.
    - The mirror's -Plan works out what would be sent, by sha256 rather than by
      name, and sends nothing.
    - VirusTotal with no key on the machine stops and names where the key goes,
      rather than half running.

  Read only apart from files under its own temp folder. Nothing here reaches the
  network: the runs are the offline paths of each script (-Plan -Offline, and a
  missing key), and the stand-in halves under Publish-PostShip write a line and
  exit.
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
# just the if: something called in the else of "if ($SkipPostShip)" is held back
# by that switch, and the same call in its then branch would be the opposite.
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
                $out += ('else of: ' + (@($p.Clauses | ForEach-Object { $_.Item1.Extent.Text }) -join ' and '))
            }
        }
        $prev = $p
        $p = $p.Parent
    }
    return $out
}

# ---- the three scripts themselves ------------------------------------------
$leaves = @('Publish-PostShip.ps1', 'Publish-SiteFeed.ps1', 'Publish-VirusTotal.ps1')
foreach ($leaf in $leaves) {
    $path = Join-Path $ScriptsPath ('release\' + $leaf)
    Yes "$leaf is in scripts\release" (Test-Path -LiteralPath $path)
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $p = Parse $path
    Yes "  $leaf parses" ($p.Errors.Count -eq 0)
    $help = $p.Ast.GetHelpContent()
    Yes '  and says what it is for, where Get-Help reads it' ($null -ne $help -and [bool]([string]$help.Synopsis).Trim())
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
    Yes '  and it takes -NoPause, which is how it is called from a script' ($declared -contains 'NoPause')
    Yes '  and -Channel, so one call covers main and dev' ($declared -contains 'Channel')
}

# There is no launcher script after the tip, and this is the check that keeps it
# that way.
Yes 'there is no post-tip launcher script' (
    -not (Test-Path -LiteralPath (Join-Path $ScriptsPath 'release\Update-Launcher.ps1')))

# ---- Ship's wiring ---------------------------------------------------------
$ShipPath = Join-Path $ScriptsPath 'release\Ship.ps1'
Yes 'Ship.ps1 is there' (Test-Path -LiteralPath $ShipPath)
if (-not (Test-Path -LiteralPath $ShipPath)) { Done }
$ship = Parse $ShipPath
Yes '  Ship.ps1 parses' ($ship.Errors.Count -eq 0)
$shipSrc = [IO.File]::ReadAllText($ShipPath, $Utf8)
$shipDeclared = @($ship.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($sw in 'SkipRemirror', 'SkipVirusTotal', 'SkipPostShip') {
    Yes "  Ship takes -$sw" ($shipDeclared -contains $sw)
}
Yes '  and no switch for a launcher step that does not exist' ($shipDeclared -notcontains 'SkipLauncherUpdate')

# One post-publish script, run through Invoke-PostShip, which is what reads its
# exit code and remembers a failure. Named in a Say line is not running it, so
# the AST is read for the call rather than the file for the name.
$calls = @($ship.Ast.FindAll({ param($n) $n -is $CmdAst -and $n.GetCommandName() -eq 'Invoke-PostShip' }, $true))
Yes ("  Ship has one Invoke-PostShip call ({0})" -f $calls.Count) ($calls.Count -eq 1)
if ($calls.Count -eq 1) {
    Yes '  and it runs Publish-PostShip.ps1' ($calls[0].Extent.Text.Contains('Publish-PostShip.ps1'))
    $conds = @(Conditions $calls[0])
    Yes ('  inside the block a dry run never reaches' + $(if ($conds.Count) { ' (' + ($conds -join ' / ') + ')' } else { '' })) (
        @($conds | Where-Object { $_ -match '-not \$DryRun\b' }).Count -gt 0)
    Yes '  and behind -SkipPostShip' (@($conds | Where-Object { $_ -match 'else of: .*\$SkipPostShip\b' }).Count -gt 0)
    # The two narrower switches are passed on rather than acted on twice.
    $text = $calls[0].Extent.Text
    Yes '  with the channel it shipped' ($shipSrc -match '\$postArgs = @\{[^\r\n]*Channel = \$chan')
    Yes '  and the releases clone and the staging folder' (
        $shipSrc -match '\$postArgs = @\{[^\r\n]*ReleaseDir = \$ReleaseDir' -and $shipSrc -match '\$postArgs = @\{[^\r\n]*DistRoot = \$DistRoot')
    Yes '  and -SkipRemirror and -SkipVirusTotal passed on' (
        $shipSrc -match "\`$postArgs\['SkipRemirror'\] = \`$true" -and $shipSrc -match "\`$postArgs\['SkipVirusTotal'\] = \`$true")
}

# The order on screen is the order it happens in, and this one matters: the feed
# has to serve the release before the news, the Discord post and the server's
# countdown send anybody to get it.
$atPublish = $shipSrc.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs")
$atNews = $shipSrc.IndexOf("'..\ops\Publish-News.ps1'")
$atRun = if ($calls.Count -eq 1) { $calls[0].Extent.StartOffset } else { -1 }
Yes 'what follows the tip follows the publisher' ($atPublish -gt 0 -and $atRun -gt $atPublish)
Yes '  and comes before the site news, the Discord post and the countdown' ($atNews -gt 0 -and $atRun -gt 0 -and $atRun -lt $atNews)

# The one launcher install Ship does is the mid-release one, before the publish,
# into the root this release was built from.
# The Join-Path inside the call is a CommandAst of its own and names the same
# file, so the invocation is the one whose text starts with the call operator.
$installs = @($ship.Ast.FindAll({ param($n) $n -is $CmdAst -and $n.Extent.Text.Contains('Install-Launcher.ps1') -and
                                            $n.GetCommandName() -ne 'Join-Path' }, $true))
Yes ("Ship calls Install-Launcher.ps1 once ({0})" -f $installs.Count) ($installs.Count -eq 1)
if ($installs.Count -eq 1) {
    Yes '  before the publisher, not after the tip' ($installs[0].Extent.StartOffset -lt $atPublish)
    Yes '  with the root and the build output' (
        $installs[0].Extent.Text -match '-Root \$Root' -and $installs[0].Extent.Text -match '-From \$buildOut')
}

# What happens when it fails. The tip is already published by then, so nothing
# may be unpublished, and the exit code is how the standing order is either kept
# or reported.
Yes 'a failed follow-on is remembered rather than exited on' ($shipSrc -match '\$script:PostShipFailed \+= ')
Yes '  and named again on the last screen, with the line that puts it right' (
    $shipSrc -match 'what follows it did NOT complete' -and $shipSrc -match '\$\(\$f\.PutRight\)')
$exitIfs = @($ship.Ast.FindAll({ param($n) $n -is $IfAst -and $n.Extent.Text -match '\$script:PostShipFailed\.Count' -and
                                           $n.Extent.Text -match 'exit 1' }, $true))
Yes '  and Ship exits non-zero because of it' ($exitIfs.Count -ge 1)
Yes '  while nothing in that block unpublishes anything' ($shipSrc -notmatch 'PostShipFailed[\s\S]{0,400}Unbump')

# ---- the runs --------------------------------------------------------------
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-post-ship-' + [Guid]::NewGuid().ToString('N'))
$script:T = $T
$ps = (Get-Process -Id $PID).Path
function Run([string]$dir, [string]$leaf, [string[]]$withArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir $leaf) @withArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = $out }
}
$release = Join-Path $ScriptsPath 'release'

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
    [IO.File]::WriteAllText((Join-Path $rel 'version.json'), (ConvertTo-Json -Depth 6 -InputObject @{
        launcherVersion = '1.1.99'
        launcherUrl     = "https://thornswood.net/feed/assets/$exeSha"
        launcherSha256  = $exeSha
        updateFeedUrl   = 'https://thornswood.net/feed/version.json'
        packs           = @(
            @{ id = '20990101-0000'; url = "https://thornswood.net/feed/assets/$packSha"; sha256 = $packSha },
            @{ id = '20260101-0000'; url = 'https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/1'; sha256 = $gone }
        )
    }), $Utf8)

    # ---- the mirror, offline ----------------------------------------------
    $plan = Run $release 'Publish-SiteFeed.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-Plan', '-Offline', '-NoPause')
    Yes ("the mirror's -Plan runs to the end (exit $($plan.Code))") ($plan.Code -eq 0)
    Yes '  and reads the tip off the releases clone' ($plan.Out -match 'launcher 1\.1\.99')
    Yes '  and matches the pack to the file on this machine by its sha256' ($plan.Out -match [regex]::Escape($pack))
    Yes '  and the launcher too' ($plan.Out -match [regex]::Escape($exe))
    Yes '  and leaves out the pack the feed keeps on GitHub' ($plan.Out -notmatch $gone.Substring(0, 12))
    Yes '  and says version.json goes last' ($plan.Out -match 'version\.json, last')

    $devPlan = Run $release 'Publish-SiteFeed.ps1' @('-Channel', 'dev', '-ReleaseDir', $rel, '-Root', $root,
                                                     '-DistRoot', $dist, '-Plan', '-Offline', '-NoPause')
    Yes ("  and the dev channel mirrors the dev feed folder (exit $($devPlan.Code))") ($devPlan.Code -eq 0 -and $devPlan.Out -match 'feed-dev')

    # ---- VirusTotal with no key -------------------------------------------
    $noKey = Run $release 'Publish-VirusTotal.ps1' @('-File', $exe, '-Root', $root, '-DistRoot', $dist,
                                                     '-KeyFile', (Join-Path $T 'no-key-here.txt'),
                                                     '-KeyName', 'THORNSWOOD_VIRUSTOTAL_KEY_FOR_A_TEST', '-NoPause')
    Yes ("VirusTotal with no key on the machine stops (exit $($noKey.Code))") ($noKey.Code -eq 1)
    Yes '  and names the file the key goes in' ($noKey.Out -match 'no-key-here\.txt')
    Yes '  and the environment variable it reads instead' ($noKey.Out -match 'THORNSWOOD_VIRUSTOTAL_KEY_FOR_A_TEST')
    Yes '  and the switch that ships without waiting on it' ($noKey.Out -match '-SkipVirusTotal')
    Yes '  and sent nothing, because it had nothing to send with' ($noKey.Out -notmatch 'The report fills in')
    Yes '  and asked the site nothing either, having stopped first' ($noKey.Out -notmatch 'api/public')

    # ---- the shared helper, against stand-in halves ------------------------
    #
    # A copy of Publish-PostShip.ps1 in a folder of its own, beside a stand-in
    # for each half that writes a line and hands back the code it is told to, so
    # the reading of those codes is what is measured here rather than the site or
    # VirusTotal.
    $fake = Join-Path $T 'release'
    New-Item -ItemType Directory -Force -Path $fake | Out-Null
    Copy-Item -LiteralPath (Join-Path $release 'Publish-PostShip.ps1') -Destination $fake -Force
    function Half([string]$name, [int]$code) {
        [IO.File]::WriteAllText((Join-Path $fake ($name + '.ps1')),
            "param([string]`$Channel, [string]`$ReleaseDir, [string]`$Root, [string]`$DistRoot, [switch]`$NoPause)`r`n" +
            "Write-Host ('$name ran on ' + `$Channel)`r`n" +
            "exit $code`r`n", $Utf8)
    }

    Half 'Publish-SiteFeed' 0
    Half 'Publish-VirusTotal' 0
    $both = Run $fake 'Publish-PostShip.ps1' @('-Channel', 'dev', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("the helper runs both halves and passes (exit $($both.Code))") ($both.Code -eq 0)
    Yes '  the mirror ran, on the channel it was given' ($both.Out -match 'Publish-SiteFeed ran on dev')
    Yes '  and VirusTotal ran' ($both.Out -match 'Publish-VirusTotal ran on dev')
    Yes '  and it says everything that follows the tip is done' ($both.Out -match 'Everything that follows the dev tip is done')

    Half 'Publish-VirusTotal' 1
    $oneBad = Run $fake 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a half that stops makes the helper hand back non-zero (exit $($oneBad.Code))") ($oneBad.Code -eq 1)
    Yes '  and it names that half and the line that puts it right' (
        $oneBad.Out -match 'The VirusTotal report' -and $oneBad.Out -match 'Publish-VirusTotal\.ps1')
    Yes '  and the other half still ran, because the tip is already published' ($oneBad.Out -match 'Publish-SiteFeed ran on main')

    Half 'Publish-VirusTotal' 0
    $skipped = Run $fake 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist,
                                                  '-SkipRemirror', '-SkipVirusTotal', '-NoPause')
    Yes ("both halves skipped is not a failure (exit $($skipped.Code))") ($skipped.Code -eq 0)
    Yes '  and neither ran' ($skipped.Out -notmatch 'ran on main')
    Yes '  and it says what an unmirrored feed means' ($skipped.Out -match 'offered that release rather than this one')

    Remove-Item -LiteralPath (Join-Path $fake 'Publish-SiteFeed.ps1') -Force
    $missing = Run $fake 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a half that is not there is a failure, not a quiet pass (exit $($missing.Code))") ($missing.Code -eq 1)
    Yes '  and it says which file is missing' ($missing.Out -match 'Publish-SiteFeed\.ps1 is not beside this script')
}
finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Done
