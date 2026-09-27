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
    - Ship runs the helper twice, both times inside a block a dry run never
      reaches, so a dry run cannot touch the VPS, the site or VirusTotal.
    - The remirror call sits after the publisher and before the site news,
      because the news, the Discord post and the server countdown all tell
      people to update and the feed has to be serving the release before that.
      The VirusTotal call sits after all three, because an upload of most of a
      gigabyte that nobody is waiting on must not hold up a five minute warning.
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
foreach ($p in 'Channel', 'Only', 'NoPause') {
    Yes "  and it takes -$p" ($declared -contains $p)
}
foreach ($p in 'SkipRemirror', 'SkipVirusTotal') {
    Yes "  and no -$p, because no release leaves a half out" ($declared -notcontains $p)
}

$helperSrc = [IO.File]::ReadAllText($HelperPath, $Utf8)
Yes '  it looks for the website lane''s remirror at the expected path' (
    $helperSrc -match "'Remirror-Site-Feed\.ps1'" -and $helperSrc -match "deploy\\Remirror-Site-Feed\.ps1")
Yes '  and the installer lane''s upload hook at its own' (
    $helperSrc -match "'Publish-VirusTotal\.ps1'" -and $helperSrc -match "release\\Publish-VirusTotal\.ps1")
Yes '  by the settled name and never by a guess at one' ($helperSrc -notmatch '\*VirusTotal\*')
Yes '  and either of them can be named outright' ($declared -contains 'RemirrorScript' -and $declared -contains 'VirusTotalScript')
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
# No switch turns either half off, asked for by the website and launcher lanes so
# that every release exercises the block and dev exercises it often. A -Skip on
# Ship would be the thing somebody reaches for on the release where it matters.
foreach ($sw in 'SkipRemirror', 'SkipVirusTotal', 'SkipPostShip', 'SkipLauncherUpdate') {
    Yes "  Ship has no -$sw" ($shipDeclared -notcontains $sw)
}

# Two post-publish calls, both through Invoke-PostShip, which is what reads an
# exit code and remembers a failure. Named in a Say line is not running it, so
# the AST is read for the calls rather than the file for the name.
$calls = @($ship.Ast.FindAll({ param($n) $n -is $CmdAst -and $n.GetCommandName() -eq 'Invoke-PostShip' }, $true))
Yes ("  Ship has two Invoke-PostShip calls, one per half ({0})" -f $calls.Count) ($calls.Count -eq 2)
$atPublish = $shipSrc.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs")
$atNews = $shipSrc.IndexOf("'..\ops\Publish-News.ps1'")
$atAnnounce = $shipSrc.IndexOf("'..\vps\Request-Restart.ps1'")
$mirrorCall = @($calls | Where-Object { $_.Extent.Text -match "Only = 'Remirror'" })
$vtCall = @($calls | Where-Object { $_.Extent.Text -match "Only = 'VirusTotal'" })
Yes '  one for the remirror and one for the upload' ($mirrorCall.Count -eq 1 -and $vtCall.Count -eq 1)
foreach ($pair in @(@('the remirror', $mirrorCall), @('the upload', $vtCall))) {
    if ($pair[1].Count -ne 1) { continue }
    $call = $pair[1][0]
    Yes ("  $($pair[0]) runs Publish-PostShip.ps1") ($call.Extent.Text.Contains('Publish-PostShip.ps1'))
    $conds = @(Conditions $call)
    Yes ("    inside a block a dry run never reaches" + $(if ($conds.Count) { ' (' + ($conds -join ' / ') + ')' } else { '' })) (
        @($conds | Where-Object { $_ -match '-not \$DryRun\b' }).Count -gt 0)
    # And behind nothing else: a dry run is the only thing that holds it back,
    # which is what "the block always runs" means.
    Yes '    and behind nothing else' ($conds.Count -eq 1)
}
Yes '  both are given the channel it shipped' ($shipSrc -match '\$postArgs = @\{[^\r\n]*Channel = \$chan')
Yes '  and the releases clone and the staging folder' (
    $shipSrc -match '\$postArgs = @\{[^\r\n]*ReleaseDir = \$ReleaseDir' -and $shipSrc -match '\$postArgs = @\{[^\r\n]*DistRoot = \$DistRoot')

# The order on screen is the order it happens in, and this one matters: the feed
# has to serve the release before the news, the Discord post and the countdown
# send anybody to get it, and the upload must not hold any of those up.
if ($mirrorCall.Count -eq 1 -and $vtCall.Count -eq 1) {
    Yes 'the remirror follows the publisher' ($atPublish -gt 0 -and $mirrorCall[0].Extent.StartOffset -gt $atPublish)
    Yes '  and comes before the site news, the Discord post and the countdown' (
        $atNews -gt 0 -and $mirrorCall[0].Extent.StartOffset -lt $atNews)
    Yes '  and the upload comes after all three' (
        $atAnnounce -gt 0 -and $vtCall[0].Extent.StartOffset -gt $atAnnounce)
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

# ---- the helper, driven against stand-in hooks ------------------------------
#
# A copy of Publish-PostShip.ps1 in a folder shaped like scripts\, beside a
# stand-in for each hook that writes down what it was given and hands back the
# code it is told to. What is measured is where the hooks are looked for, what
# they are given, and what their exit codes mean, never the site or VirusTotal.
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-post-ship-' + [Guid]::NewGuid().ToString('N'))
$script:T = $T
$ps = (Get-Process -Id $PID).Path
function Run([string]$dir, [string[]]$withArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'Publish-PostShip.ps1') @withArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = $out }
}

try {
    $release = Join-Path $T 'release'
    $deploy = Join-Path $T 'deploy'
    $rel = Join-Path $T 'Thornswood-Releases'
    $root = Join-Path $T 'Play'
    $dist = Join-Path $T 'dist'
    $stage = Join-Path (Join-Path $dist 'Play') '_dist'
    New-Item -ItemType Directory -Force -Path $release, $deploy, $rel, $stage | Out-Null
    Copy-Item -LiteralPath $HelperPath -Destination $release -Force
    $setup = Join-Path $stage 'Thornswood-Setup.exe'
    [IO.File]::WriteAllText($setup, 'the installer people download')

    # A stand-in writes its name and every parameter it was actually given, so
    # the checks below read what the helper passed rather than guessing.
    function Hook([string]$dir, [string]$name, [string]$params, [int]$code) {
        [IO.File]::WriteAllText((Join-Path $dir ($name + '.ps1')),
            "param($params)`r`n" +
            "Write-Host '$name ran'`r`n" +
            "foreach (`$k in @(`$PSBoundParameters.Keys | Sort-Object)) { Write-Host ('  ' + `$k + '=' + [string]`$PSBoundParameters[`$k]) }`r`n" +
            "exit $code`r`n", $Utf8)
    }
    # The shapes the two lanes actually landed: the website remirror takes -Dev
    # and -FeedDir, the installer hook takes -Path and -Sha256.
    $mirrorParams = '[string]$FeedDir, [switch]$Dev, [string[]]$AssetDir, [switch]$Check, [switch]$Verify, [switch]$Quiet'
    $vtParams = '[string]$Path, [string]$Sha256'

    # ---- nothing landed yet ------------------------------------------------
    $none = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a branch with neither hook on it is not a failed release (exit $($none.Code))") ($none.Code -eq 0)
    Yes '  and it says which file the remirror would be, and whose it is' (
        $none.Out -match 'Remirror-Site-Feed\.ps1 is not on this branch' -and $none.Out -match 'website lane')
    Yes '  and the same for the VirusTotal upload' (
        $none.Out -match 'Publish-VirusTotal\.ps1 is not on this branch' -and $none.Out -match 'installer lane')
    Yes '  and says what is still to come rather than that everything is done' ($none.Out -match 'still to come')

    # ---- both landed, main -------------------------------------------------
    Hook $deploy 'Remirror-Site-Feed' $mirrorParams 0
    Hook $release 'Publish-VirusTotal' $vtParams 0
    $ok = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("both hooks on the branch, a main release passes (exit $($ok.Code))") ($ok.Code -eq 0)
    Yes '  the remirror ran, told the live feed and the clone that was published' (
        $ok.Out -match 'Remirror-Site-Feed ran' -and $ok.Out -match 'Dev=False' -and
        $ok.Out -match ('FeedDir=' + [regex]::Escape($rel)))
    Yes '  and it says where the tip is going' ($ok.Out -match 'the main tip to https://thornswood\.net/feed/')
    Yes '  the upload ran, on the installer in the staging folder' (
        $ok.Out -match 'Publish-VirusTotal ran' -and $ok.Out -match ('Path=' + [regex]::Escape($setup)))
    Yes '  and it does not pass a parameter the hook never declared' ($ok.Out -notmatch 'NoPause=')
    Yes '  and says everything that follows the tip is done' ($ok.Out -match 'Everything that follows the main tip is done')

    # ---- one half at a time, which is how Ship runs it ---------------------
    $one = Run $release @('-Only', 'Remirror', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("-Only Remirror runs the feed and not the upload (exit $($one.Code))") (
        $one.Code -eq 0 -and $one.Out -match 'Remirror-Site-Feed ran' -and $one.Out -notmatch 'Publish-VirusTotal ran')
    Yes '  and says the upload is the second call' ($one.Out -match 'second call, after everybody has been told')
    $two = Run $release @('-Only', 'VirusTotal', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("-Only VirusTotal runs the upload and not the feed (exit $($two.Code))") (
        $two.Code -eq 0 -and $two.Out -match 'Publish-VirusTotal ran' -and $two.Out -notmatch 'Remirror-Site-Feed ran')
    Yes '  and says the feed was the first call' ($two.Out -match 'first call, before anybody was told')

    # ---- the locked call shape, and nothing guessed at ---------------------
    #
    # -Path <file> and an optional -Sha256 <hex>, which is the installer lane's
    # contract. The hash goes with it because that script measures the file
    # itself and says so when the two disagree, which proves the file it read is
    # the file this picked.
    $hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLower()
    $shaRun = Run $release @('-Only', 'VirusTotal', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("the upload is given the file and its hash (exit $($shaRun.Code))") (
        $shaRun.Code -eq 0 -and $shaRun.Out -match ('Path=' + [regex]::Escape($setup)) -and
        $shaRun.Out -match ('Sha256=' + $hash))
    # Add-VirusTotalComment.ps1 also takes a -Path and writes a comment on a
    # report rather than sending a file. Nothing here may pick it up, and the
    # only thing that keeps that true is looking for the settled name.
    Remove-Item -LiteralPath (Join-Path $release 'Publish-VirusTotal.ps1') -Force
    Hook $release 'Add-VirusTotalComment' '[string]$Path, [string]$Sha256, [string]$Text' 0
    Hook $release 'Send-VirusTotal' '[string]$Path, [switch]$NoPause' 0
    $notNamed = Run $release @('-Only', 'VirusTotal', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("another VirusTotal script is never taken for the upload (exit $($notNamed.Code))") (
        $notNamed.Code -eq 0 -and $notNamed.Out -notmatch 'Add-VirusTotalComment ran' -and
        $notNamed.Out -notmatch 'Send-VirusTotal ran' -and
        $notNamed.Out -match 'Publish-VirusTotal\.ps1 is not on this branch')
    Yes '  and it says the key comes from VT_API_KEY' ($notNamed.Out -match 'VT_API_KEY')
    $named = Run $release @('-Only', 'VirusTotal', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist,
                            '-VirusTotalScript', (Join-Path $release 'Send-VirusTotal.ps1'), '-NoPause')
    Yes ("-VirusTotalScript names one outright (exit $($named.Code))") (
        $named.Code -eq 0 -and $named.Out -match 'Send-VirusTotal ran' -and $named.Out -notmatch 'Sha256=')
    Remove-Item -LiteralPath (Join-Path $release 'Send-VirusTotal.ps1') -Force
    Remove-Item -LiteralPath (Join-Path $release 'Add-VirusTotalComment.ps1') -Force
    Hook $release 'Publish-VirusTotal' $vtParams 0

    # ---- the launcher exe, only when asked --------------------------------
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'Launcher') | Out-Null
    $launcher = Join-Path $root 'Launcher\Thornswood.exe'
    [IO.File]::WriteAllText($launcher, 'the launcher this release published')
    $noLauncher = Run $release @('-Only', 'VirusTotal', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes 'the launcher exe is not sent by default, because the page does not offer it' (
        $noLauncher.Out -notmatch [regex]::Escape($launcher))
    $withLauncher = Run $release @('-Only', 'VirusTotal', '-AlsoLauncher', '-ReleaseDir', $rel, '-Root', $root,
                                  '-DistRoot', $dist, '-NoPause')
    Yes ("-AlsoLauncher sends it as well (exit $($withLauncher.Code))") (
        $withLauncher.Code -eq 0 -and $withLauncher.Out -match ('Path=' + [regex]::Escape($setup)) -and
        $withLauncher.Out -match ('Path=' + [regex]::Escape($launcher)))
    Remove-Item -LiteralPath $launcher -Force

    # ---- the same block on dev, which is where it gets exercised -----------
    $dev = Run $release @('-Channel', 'dev', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("the same block runs on dev (exit $($dev.Code))") ($dev.Code -eq 0)
    Yes '  the remirror is told it is the dev feed' ($dev.Out -match 'Dev=True' -and $dev.Out -match 'https://thornswood\.net/feed-dev/')
    Yes '  and the upload runs there too, on the installer this machine holds' (
        $dev.Out -match 'Publish-VirusTotal ran' -and $dev.Out -match 'did not rebuild the installer')

    # ---- a remirror that takes only -Dev -----------------------------------
    #
    # The website lane's pin says -FeedDir is optional and must not be required,
    # so a script that works the clone out from the channel by itself has to run
    # with nothing but -Dev.
    Hook $deploy 'Remirror-Site-Feed' '[switch]$Dev' 0
    $devOnly = Run $release @('-Channel', 'dev', '-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a remirror that takes only -Dev still runs (exit $($devOnly.Code))") (
        $devOnly.Code -eq 0 -and $devOnly.Out -match 'Remirror-Site-Feed ran' -and $devOnly.Out -match 'Dev=True')
    Yes '  and is given no -FeedDir it never declared' ($devOnly.Out -notmatch 'FeedDir=')
    Hook $deploy 'Remirror-Site-Feed' $mirrorParams 0

    # ---- wherever the website lane lands it --------------------------------
    Move-Item -LiteralPath (Join-Path $deploy 'Remirror-Site-Feed.ps1') -Destination (Join-Path $release 'Remirror-Site-Feed.ps1')
    $moved = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("the remirror is found in the other folder too (exit $($moved.Code))") ($moved.Code -eq 0 -and $moved.Out -match 'Remirror-Site-Feed ran')
    $odd = Join-Path $T 'site'
    New-Item -ItemType Directory -Force -Path $odd | Out-Null
    Move-Item -LiteralPath (Join-Path $release 'Remirror-Site-Feed.ps1') -Destination (Join-Path $odd 'Remirror-Site-Feed.ps1')
    $anywhere = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("and anywhere under scripts\ by name (exit $($anywhere.Code))") ($anywhere.Code -eq 0 -and $anywhere.Out -match 'Remirror-Site-Feed ran')

    # ---- and by another name for the same thing ----------------------------
    Remove-Item -LiteralPath (Join-Path $odd 'Remirror-Site-Feed.ps1') -Force
    Hook $deploy 'Mirror-Feed' '[string]$ReleaseDir, [string]$Channel, [switch]$NoPause' 0
    $named = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist,
                            '-RemirrorScript', (Join-Path $deploy 'Mirror-Feed.ps1'), '-NoPause')
    Yes ("-RemirrorScript names one outright (exit $($named.Code))") ($named.Code -eq 0 -and $named.Out -match 'Mirror-Feed ran')
    Yes '  and it is called with the parameters it declares, not the other lane''s' (
        $named.Out -match 'Channel=main' -and $named.Out -match ('ReleaseDir=' + [regex]::Escape($rel)) -and
        $named.Out -match 'NoPause=True' -and $named.Out -notmatch 'FeedDir=')

    # ---- a hook that is there and stops ------------------------------------
    Hook $deploy 'Remirror-Site-Feed' $mirrorParams 1
    $bad = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("a hook that stops makes the helper hand back non-zero (exit $($bad.Code))") ($bad.Code -eq 1)
    Yes '  and it names that half and the line that puts it right' (
        $bad.Out -match 'The host feed remirror' -and $bad.Out -match 'Remirror-Site-Feed\.ps1')
    Yes '  and the other half still ran, because the tip is already published' ($bad.Out -match 'Publish-VirusTotal ran')

    # ---- no installer to send ---------------------------------------------
    Hook $deploy 'Remirror-Site-Feed' $mirrorParams 0
    Remove-Item -LiteralPath $setup -Force
    $noSetup = Run $release @('-ReleaseDir', $rel, '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("no installer on this machine is not a failure (exit $($noSetup.Code))") ($noSetup.Code -eq 0)
    Yes '  and it says there is nothing to send' ($noSetup.Out -match 'nothing to send')
    Yes '  and did not call the upload hook with no file' ($noSetup.Out -notmatch 'Publish-VirusTotal ran')
}
finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Done
