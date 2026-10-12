<#
  test-2347-publish-launcher-number.ps1

  Publish-Update refuses a launcher under the number its feed already offers,
  built from other sources, before anything is sent.

  MEASURED 12 OCTOBER. Dev Ship 20261012-004958-dev built, signed and sent a
  changed launcher as 1.2.3, which dev launchers already had, so none was
  offered it, and Publish-Update said so only afterwards:

      WARNING: the launcher changed but is still version 1.2.3.
      Anyone already on that version will never be offered this build.
      Re-run without -NoBump, or with -Version, to get it to them.

  #2366 made Ship's Assert-DevVersionSelection refuse that dev case before
  anything is built. A main Ship could still get here: one that signs the exe
  CI built for the number main's feed already offers, from other launcher
  sources than the ones that launcher was built from, re-signed and sent under
  that number. And the advice was out of date: -NoBump does nothing since a
  main Ship stopped bumping.

  So the publisher refuses that case itself, in the same terms as Ship, before
  anything is sent, and again before the feed is written in case the feed was
  received again meanwhile; the WARNING is gone. This lifts the three pieces
  out of the shipped Publish-Update.ps1 and runs them: the rule (the launcher
  number block), the launcher exe block that calls it before the upload, and
  the launcher block that writes the feed. tests\test-2347-dev-launcher-version.ps1
  covers Ship's side, the main Ship included.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$PublishPath)
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
if (-not $PublishPath) { $PublishPath = Join-Path $repo 'scripts\release\Publish-Update.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host "$script:pass passed, $script:fail failed"
    exit $(if ($script:fail) { 1 } else { 0 })
}

$src = [IO.File]::ReadAllText($PublishPath)
$t = $null; $e = $null
[void][Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Publish-Update.ps1 parses' (@($e).Count -eq 0)

function Cut([string]$from, [string]$to, [int]$start = 0) {
    $a = $src.IndexOf($from, $start)
    if ($a -lt 0) { return $null }
    $b = $src.IndexOf($to, $a + $from.Length)
    if ($b -lt 0) { return $null }
    return [pscustomobject]@{ Text = $src.Substring($a, $b - $a); At = $a; End = $b }
}
$rule = Cut '# ==== thornswood launcher number ====' '# ==== end thornswood launcher number ===='
$exe = Cut '# ------------------------------------------------------------ launcher exe' '# ==== thornswood packs gone ===='
$late = Cut 'if ($Launcher -and (Test-Path $exePath)) {' '# ==== thornswood min launcher ===='
Yes 'the launcher number block is there' ($null -ne $rule)
Yes 'the launcher exe block is there' ($null -ne $exe)
Yes 'the block that writes the launcher into the feed is there' ($null -ne $late)
if ($null -eq $rule -or $null -eq $exe -or $null -eq $late) { Done }

# ---- where the two refusals sit ----------------------------------------------
$feedNowAt = $src.IndexOf('$feedNow = ')
$uploadAt = $src.IndexOf('# ------------------------------------------------------------ upload')
$firstSend = $src.IndexOf('if (-not $NoUpload) {', $exe.End)
Yes 'the feed as received is read before the launcher exe block' ($feedNowAt -ge 0 -and $feedNowAt -lt $exe.At)
Yes 'the rule is defined before the launcher exe block uses it' ($rule.End -lt $exe.At)
Yes 'the launcher exe block refuses with the rule, against the feed as received' (
    $exe.Text.Contains('Get-LauncherNumberRefusal $feedNow $launcherVersion') -and $exe.Text.Contains('if ($numberWhy) { Die $numberWhy }'))
Yes '  and it comes before anything is uploaded' ($uploadAt -gt $exe.End -and $firstSend -gt $exe.End)
$late2 = $late.Text.IndexOf('Get-LauncherNumberRefusal $doc')
$setAt = $late.Text.IndexOf("Set-Prop `$doc 'launcherVersion'")
Yes 'the feed write asks again, of the feed as it is now, before it sets a launcher field' ($late2 -ge 0 -and $setAt -gt $late2)
$feedSend = $src.IndexOf('$sentFeed = Send-FeedStore')
Yes '  and that is before the feed is sent' ($feedSend -gt $late.End)
Yes 'the after-the-fact WARNING and its -NoBump advice are gone' (
    -not $src.Contains('the launcher changed but is still version') -and -not $src.Contains('Re-run without -NoBump'))

# ---- the rule --------------------------------------------------------------
Invoke-Expression $rule.Text
$M = 'a5035b57ce77e89f0620b769e4f42841697ce3c0d382a0d20369bb37a237d306'   # main's 1.2.3, 7cece557
$D = '0b5ba66bfe0cd1545a543c9822b7749206f4f1245b8aaec42deca2eb0d142d1d'   # 9ec48194, with #2343
$X = ('5' * 64)
$Y = ('6' * 64)
function Feed([string]$v, [string]$sha, [string]$inputs) {
    $o = [ordered]@{ packs = @() }
    if ($v) { $o.launcherVersion = $v }
    if ($sha) { $o.launcherSha256 = $sha }
    if ($inputs) { $o.launcherInputs = $inputs }
    return ([pscustomobject]$o)
}
$why = Get-LauncherNumberRefusal (Feed '1.2.3' $X $M) '1.2.3' $Y $D 'main' 'Nothing was sent.'
Yes ('main: another launcher under the 1.2.3 main offers is refused: ' + $why) ($why -like '1.2.3 is already out on the main feed as a launcher built from other sources than these*nobody on 1.2.3 would ever be offered this one. Nothing was sent.*Bump-Version.ps1*')
$why = Get-LauncherNumberRefusal (Feed '1.2.3' $X $M) '1.2.3' $Y $D 'dev' 'Nothing was sent.'
Yes ('dev: the same, with the dev way out: ' + $why) ($why -like '*on the dev feed*Ship without -Version so it takes the next dev number.')
Yes 'the same sources signed again go on (a new signature, the same launcher)' (-not (Get-LauncherNumberRefusal (Feed '1.2.3' $X $M) '1.2.3' $Y $M 'main' 'x'))
Yes 'the same bytes go on, fingerprint or not, in either case of hex' (
    -not (Get-LauncherNumberRefusal (Feed '1.2.3' $X '') '1.2.3' $X.ToUpperInvariant() '' 'main' 'x'))
Yes 'a feed launcher with no fingerprint and other bytes is not known to be this one, so it is refused' (
    [bool](Get-LauncherNumberRefusal (Feed '1.2.3' $X '') '1.2.3' $Y $D 'main' 'x'))
Yes 'and so is one published with no fingerprint here' ([bool](Get-LauncherNumberRefusal (Feed '1.2.3' $X $M) '1.2.3' $Y '' 'main' 'x'))
Yes 'a new number goes on' (-not (Get-LauncherNumberRefusal (Feed '1.2.3' $X $M) '1.2.4' $Y $D 'main' 'x'))
Yes 'a dev number over main''s goes on' (-not (Get-LauncherNumberRefusal (Feed '1.2.3' $X $M) '1.2.3.1' $Y $D 'dev' 'x'))
Yes 'a feed that offers no launcher yet, or no feed, goes on' (
    -not (Get-LauncherNumberRefusal (Feed '' '' '') '1.2.3' $Y $D 'main' 'x') -and -not (Get-LauncherNumberRefusal $null '1.2.3' $Y $D 'main' 'x'))

# ---- the two blocks, run -----------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts2347pub-' + [Guid]::NewGuid().ToString('N'))
try {
    $launcherDir = Join-Path $tmp 'Launcher'
    New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
    $exeFile = Join-Path $launcherDir 'Thornswood.exe'
    [IO.File]::WriteAllText($exeFile, 'the launcher CI built, signed again')
    $exeSha = (Get-FileHash -LiteralPath $exeFile -Algorithm SHA256).Hash.ToLowerInvariant()

    $stubs = @'
function Say($m, $c) { }
function Die($m) { throw ("STOP. " + $m) }
function Get-LauncherExe([string]$dir) { return (Join-Path $dir 'Thornswood.exe') }
function Val($o, [string]$k) { if ($o.PSObject.Properties[$k]) { return [string]$o.$k } return '' }
function Set-Prop($o, [string]$k, $v) { if ($o.PSObject.Properties[$k]) { $o.$k = $v } else { $o | Add-Member -NotePropertyName $k -NotePropertyValue $v } }
'@
    # The launcher exe block: what it decides before the upload.
    $sbExe = [scriptblock]::Create('param($a); $Launcher = $true; $Root = $a.Root; $Here = $a.Here; $VersionOverride = $a.Version;' +
        '$LauncherInputs = $a.Inputs; $Channel = $a.Channel; $feedNow = $a.Feed;' + "`n" + $stubs + "`n" + $rule.Text + "`n" + $exe.Text +
        "`nreturn `$launcherVersion")
    function RunExe([hashtable]$o) {
        $a = @{ Root = $tmp; Here = (Join-Path $repo 'scripts\release'); Version = $o.Version; Inputs = $o.Inputs; Channel = $o.Channel; Feed = $o.Feed }
        try { return [string](& $sbExe $a) } catch { return [string]$_.Exception.Message }
    }
    $r = RunExe @{ Version = '1.2.3'; Inputs = $D; Channel = 'main'; Feed = (Feed '1.2.3' $X $M) }
    Yes ('the main Ship''s re-signed 1.2.3 from other sources stops in the launcher exe block: ' + $r) ($r -like 'STOP. 1.2.3 is already out on the main feed*Nothing was sent.*')
    $r = RunExe @{ Version = '1.2.3'; Inputs = $M; Channel = 'main'; Feed = (Feed '1.2.3' $X $M) }
    Yes ('from the same sources it goes on with 1.2.3: ' + $r) ($r -eq '1.2.3')
    $r = RunExe @{ Version = '1.2.4'; Inputs = $D; Channel = 'main'; Feed = (Feed '1.2.3' $X $M) }
    Yes ('main moved to 1.2.4 goes on: ' + $r) ($r -eq '1.2.4')
    $r = RunExe @{ Version = '1.2.3'; Inputs = ''; Channel = 'main'; Feed = (Feed '1.2.3' $exeSha '') }
    Yes ('the very bytes the feed names go on: ' + $r) ($r -eq '1.2.3')
    $r = RunExe @{ Version = '1.2.3'; Inputs = $D; Channel = 'dev'; Feed = (Feed '1.2.3' $X $D) }
    Yes ('a dev feed offering this launcher already goes on: ' + $r) ($r -eq '1.2.3')

    # The feed write: a feed received again meanwhile that offers this number
    # from other sources stops it with the feed as it was.
    $sbLate = [scriptblock]::Create('param($a); $Launcher = $true; $exePath = $a.Exe; $launcherVersion = $a.Version; $exeUrl = ''u'';' +
        '$LauncherInputs = $a.Inputs; $Channel = $a.Channel; $doc = $a.Doc;' + "`n" + $stubs + "`n" + $rule.Text + "`n" + $late.Text +
        "`nreturn `$doc")
    function RunLate([hashtable]$o) {
        $a = @{ Exe = $exeFile; Version = $o.Version; Inputs = $o.Inputs; Channel = $o.Channel; Doc = $o.Doc }
        try { return (& $sbLate $a) } catch { return [string]$_.Exception.Message }
    }
    $doc = Feed '1.2.3' $X $M
    $before = $doc | ConvertTo-Json -Compress
    $r = RunLate @{ Version = '1.2.3'; Inputs = $D; Channel = 'main'; Doc = $doc }
    Yes ('a feed received again that offers 1.2.3 from other sources stops the feed write: ' + $r) ($r -is [string] -and $r -like 'STOP. 1.2.3 is already out on the main feed*Nothing was written to the feed*')
    Yes '  with not one launcher field of the feed changed' (($doc | ConvertTo-Json -Compress) -eq $before)
    $r = RunLate @{ Version = '1.2.4'; Inputs = $D; Channel = 'main'; Doc = (Feed '1.2.3' $X $M) }
    Yes 'a new number is written into the feed with its bytes and fingerprint' (
        $r -isnot [string] -and $r.launcherVersion -eq '1.2.4' -and $r.launcherSha256 -eq $exeSha -and $r.launcherInputs -eq $D -and $r.launcherUrl -eq 'u')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
