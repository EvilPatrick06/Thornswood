<#
  test-post-ship.ps1

      pwsh -NoProfile -File .\tests\test-post-ship.ps1

  What follows a published tip: Publish-PostShip.ps1, the one script Ship.ps1
  calls after the release is on the feed, and the two scripts it calls in turn,
  the website lane's scripts\deploy\Remirror-Site-Feed.ps1 and the installer
  lane's scripts\release\Publish-VirusTotal.ps1.

  WHY THIS EXISTS. Ship ended at "Everyone in the world has five minutes" while
  two things it had never done were left to somebody remembering: the site feed
  a launcher polls held whatever was last copied there by hand, and the
  VirusTotal link the Downloads page prints had never had a file behind it.

  WHAT IT WATCHES FOR, beyond that the wiring is there.

    - Publish-PostShip.ps1 implements neither half. It is checked for calling
      the two owned scripts by path, so a later session cannot quietly grow a
      third copy of a remirror in here.
    - There is no launcher step after the tip. The Launcher lane answered on
      27 September that the tip customers get is version.json and launchers poll
      the feed url in it, so the remirror is how a launcher update reaches
      anybody, and Ship's mid-release Install-Launcher.ps1 refreshes the install
      on the machine that shipped. This fails if a second launcher step is ever
      added after the publish, and it checks the mid-release one is still there,
      before the publisher, with the root and the build output.
    - Ship runs the helper inside the one block a dry run never reaches, so a
      dry run cannot touch the VPS, the site or VirusTotal, and passes its own
      -Skip switches on rather than giving them a second meaning.
    - It sits after the publisher and before the site news, because the news,
      the Discord post and the server countdown all tell people to update, and
      the feed has to be serving the release before that.
    - A failure leaves the release published and makes Ship exit non-zero, which
      is the standing order that the follow-ons go out with the tip.
    - The helper reads each half's exit code, runs the second half even when the
      first stopped, says which line puts a failed half right, and treats a half
      that is not on the machine as a failure rather than a quiet pass.

  Read only apart from files under its own temp folder. Nothing here reaches the
  network: the halves it drives are stand-ins that write a line and hand back the
  code they are told to.
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

# ---- the helper itself -----------------------------------------------------
$HelperPath = Join-Path $ScriptsPath 'release\Publish-PostShip.ps1'
Yes 'Publish-PostShip.ps1 is in scripts\release' (Test-Path -LiteralPath $HelperPath)
if (-not (Test-Path -LiteralPath $HelperPath)) { Done }
$helper = Parse $HelperPath
Yes '  it parses' ($helper.Errors.Count -eq 0)
$help = $helper.Ast.GetHelpContent()
Yes '  and says what it is for, where Get-Help reads it' ($null -ne $help -and [bool]([string]$help.Synopsis).Trim())
$declared = @()
if ($helper.Ast.ParamBlock) { $declared = @($helper.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
$documented = @()
if ($help) {
    foreach ($k in $help.Parameters.Keys) {
        if (([string]$help.Parameters[$k]).Trim()) { $documented += $k.ToUpperInvariant() }
    }
}
$missing = @($declared | Where-Object { $documented -notcontains $_.ToUpperInvariant() })
Yes ("  and every one of its $($declared.Count) parameter(s) has a .PARAMETER" +
     $(if ($missing.Count) { ': ' + ($missing -join ', ') + ' do not' } else { '' })) ($declared.Count -gt 0 -and $missing.Count -eq 0)
foreach ($p in 'Channel', 'SkipRemirror', 'SkipVirusTotal', 'NoPause') {
    Yes "  and it takes -$p" ($declared -contains $p)
}

$helperSrc = [IO.File]::ReadAllText($HelperPath, $Utf8)
Yes '  it calls the website lane''s remirror by path' ($helperSrc -match "\.\.\\deploy\\Remirror-Site-Feed\.ps1")
Yes '  and the installer lane''s VirusTotal script' ($helperSrc -match "'Publish-VirusTotal\.ps1'")
# Neither half is reimplemented here, so nothing in it talks to the VPS or to
# VirusTotal itself.
Yes '  and does neither job itself: no ssh, no scp, no virustotal.com' (
    $helperSrc -notmatch '(?m)^\s*&\s*ssh\b' -and $helperSrc -notmatch '(?m)^\s*&\s*scp\b' -and
    $helperSrc -notmatch 'virustotal\.com/api')

# ---- the two owned scripts, when they are on the branch --------------------
$mirrorPath = Join-Path $ScriptsPath 'deploy\Remirror-Site-Feed.ps1'
if (Test-Path -LiteralPath $mirrorPath) {
    $m = Parse $mirrorPath
    Yes 'the website lane''s Remirror-Site-Feed.ps1 parses' ($m.Errors.Count -eq 0)
    $mp = @()
    if ($m.Ast.ParamBlock) { $mp = @($m.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    Yes '  and takes the -Dev and -FeedDir this helper gives it' (($mp -contains 'Dev') -and ($mp -contains 'FeedDir'))
} else {
    Write-Host 'SKIP  scripts\deploy\Remirror-Site-Feed.ps1 is not on this branch yet (website lane, pull request #730)'
}
$vtPath = Join-Path $ScriptsPath 'release\Publish-VirusTotal.ps1'
if (Test-Path -LiteralPath $vtPath) {
    $v = Parse $vtPath
    Yes 'the installer lane''s Publish-VirusTotal.ps1 parses' ($v.Errors.Count -eq 0)
    $vp = @()
    if ($v.Ast.ParamBlock) { $vp = @($v.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    Yes '  and takes the -Path this helper gives it' ($vp -contains 'Path')
} else {
    Write-Host 'SKIP  scripts\release\Publish-VirusTotal.ps1 is not on this branch yet (installer lane, pull request #734)'
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
$atPublish = $shipSrc.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs")
$atNews = $shipSrc.IndexOf("'..\ops\Publish-News.ps1'")
if ($calls.Count -eq 1) {
    Yes '  and it runs Publish-PostShip.ps1' ($calls[0].Extent.Text.Contains('Publish-PostShip.ps1'))
    $conds = @(Conditions $calls[0])
    Yes ('  inside the block a dry run never reaches' + $(if ($conds.Count) { ' (' + ($conds -join ' / ') + ')' } else { '' })) (
        @($conds | Where-Object { $_ -match '-not \$DryRun\b' }).Count -gt 0)
    Yes '  and behind -SkipPostShip' (@($conds | Where-Object { $_ -match 'else of: .*\$SkipPostShip\b' }).Count -gt 0)
    Yes '  with the channel it shipped' ($shipSrc -match '\$postArgs = @\{[^\r\n]*Channel = \$chan')
    Yes '  and the releases clone and the staging folder' (
        $shipSrc -match '\$postArgs = @\{[^\r\n]*ReleaseDir = \$ReleaseDir' -and $shipSrc -match '\$postArgs = @\{[^\r\n]*DistRoot = \$DistRoot')
    Yes '  and -SkipRemirror and -SkipVirusTotal passed on' (
        $shipSrc -match "\`$postArgs\['SkipRemirror'\] = \`$true" -and $shipSrc -match "\`$postArgs\['SkipVirusTotal'\] = \`$true")

    # The order on screen is the order it happens in, and this one matters: the
    # feed has to serve the release before the news, the Discord post and the
    # server's countdown send anybody to get it.
    $at = $calls[0].Extent.StartOffset
    Yes 'what follows the tip follows the publisher' ($atPublish -gt 0 -and $at -gt $atPublish)
    Yes '  and comes before the site news, the Discord post and the countdown' ($atNews -gt 0 -and $at -lt $atNews)
}

# The one launcher install Ship does is the mid-release one, before the publish,
# into the root this release was built from.
#
# The Join-Path inside the call is a CommandAst of its own and names the same
# file, so the invocation is the one whose command is not Join-Path.
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

# ---- the helper, driven against stand-in halves ----------------------------
#
# A copy of Publish-PostShip.ps1 in a folder shaped like scripts\, beside a
# stand-in for each half that writes a line and hands back the code it is told
# to. What is measured is the reading of those codes, not the site or VirusTotal.
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

try {
    $release = Join-Path $T 'release'
    $deploy = Join-Path $T 'deploy'
    $rel = Join-Path $T 'Thornswood-Releases'
    $root = Join-Path $T 'Play'
    $stage = Join-Path (Join-Path (Join-Path $T 'dist') 'Play') '_dist'
    New-Item -ItemType Directory -Force -Path $release, $deploy, $rel, $stage | Out-Null
    Copy-Item -LiteralPath $HelperPath -Destination $release -Force
    $setup = Join-Path $stage 'Thornswood-Setup.exe'
    [IO.File]::WriteAllText($setup, 'the installer people download')
    $dist = Join-Path $T 'dist'

    function Half([string]$dir, [string]$name, [string]$params, [int]$code) {
        [IO.File]::WriteAllText((Join-Path $dir ($name + '.ps1')),
            "param($params)`r`n" +
            "Write-Host '$name ran'`r`n" +
            "foreach (`$k in @(`$PSBoundParameters.Keys | Sort-Object)) { Write-Host ('  ' + `$k + '=' + [string]`$PSBoundParameters[`$k]) }`r`n" +
            "exit $code`r`n", $Utf8)
    }
    $mirrorParams = '[string]$FeedDir, [switch]$Dev, [string[]]$AssetDir, [switch]$Check, [switch]$Verify, [switch]$Quiet'
    $vtParams = '[string]$Path, [string]$Sha256'

    # Main, both halves fine.
    Half $deploy 'Remirror-Site-Feed' $mirrorParams 0
    Half $release 'Publish-VirusTotal' $vtParams 0
    $ok = Run $release 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("the helper runs both halves on main and passes (exit $($ok.Code))") ($ok.Code -eq 0)
    Yes '  the remirror ran, told which feed and which clone' (
        $ok.Out -match 'Remirror-Site-Feed ran' -and $ok.Out -match 'Dev=False' -and $ok.Out -match ('FeedDir=' + [regex]::Escape($rel)))
    Yes '  VirusTotal ran, on the installer in the staging folder' (
        $ok.Out -match 'Publish-VirusTotal ran' -and $ok.Out -match ('Path=' + [regex]::Escape($setup)))
    Yes '  and it says everything that follows the tip is done' ($ok.Out -match 'Everything that follows the main tip is done')

    # Dev: the dev feed, and the installer left alone.
    $dev = Run $release 'Publish-PostShip.ps1' @('-Channel', 'dev', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("the dev channel passes (exit $($dev.Code))") ($dev.Code -eq 0)
    Yes '  the remirror is told it is the dev feed' ($dev.Out -match 'Dev=True')
    Yes '  and VirusTotal is not asked, because a dev release does not touch the installer' (
        $dev.Out -notmatch 'Publish-VirusTotal ran' -and $dev.Out -match 'does not touch the installer')

    # A half that stops.
    Half $deploy 'Remirror-Site-Feed' $mirrorParams 1
    $bad = Run $release 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a half that stops makes the helper hand back non-zero (exit $($bad.Code))") ($bad.Code -eq 1)
    Yes '  and it names that half and the line that puts it right' (
        $bad.Out -match 'The host feed remirror' -and $bad.Out -match 'Remirror-Site-Feed\.ps1')
    Yes '  and the other half still ran, because the tip is already published' ($bad.Out -match 'Publish-VirusTotal ran')

    # Both skipped.
    Half $deploy 'Remirror-Site-Feed' $mirrorParams 0
    $skipped = Run $release 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist,
                                                    '-SkipRemirror', '-SkipVirusTotal', '-NoPause')
    Yes ("both halves skipped is not a failure (exit $($skipped.Code))") ($skipped.Code -eq 0)
    Yes '  and neither ran' ($skipped.Out -notmatch ' ran')
    Yes '  and it says what an unmirrored feed means' ($skipped.Out -match 'offered that release rather than this one')

    # A half that is not on the machine at all.
    Remove-Item -LiteralPath (Join-Path $deploy 'Remirror-Site-Feed.ps1') -Force
    $gone = Run $release 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a half that is not there is a failure, not a quiet pass (exit $($gone.Code))") ($gone.Code -eq 1)
    Yes '  and it says which file is missing and whose it is' (
        $gone.Out -match 'Remirror-Site-Feed\.ps1 is not here' -and $gone.Out -match 'website lane')

    # No installer on this machine: said, and not a failure, because the file the
    # page offers is not this machine's to send.
    Half $deploy 'Remirror-Site-Feed' $mirrorParams 0
    Remove-Item -LiteralPath $setup -Force
    $noSetup = Run $release 'Publish-PostShip.ps1' @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("no installer on this machine is not a failure (exit $($noSetup.Code))") ($noSetup.Code -eq 0)
    Yes '  and it says there is nothing to send' ($noSetup.Out -match 'nothing to send')
}
finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Done
