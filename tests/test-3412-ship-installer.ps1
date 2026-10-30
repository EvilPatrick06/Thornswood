<#
  test-3412-ship-installer.ps1

      pwsh -NoProfile -File .\tests\test-3412-ship-installer.ps1

  Issue #3412. A main Ship from the feed, the cloud included, takes -Package:
  installer.yml builds and signs the installer on GitHub, and
  Publish-InstallerFromGitHub.ps1 takes it off the launcher's draft and
  publishes it through Publish-Installer.ps1, which off Windows holds it to
  the publish gate on the box before it replaces the one people download.

  What it checks:
    1. Get-InstallerWorkflowRefusal with a stand-in gh: a tag with
       installer.yml is fine; one made before it merged is refused, saying to
       Ship from One; any other answer is refused as not known.
    2. Invoke-InstallerOnGitHub with a stand-in gh: it starts installer.yml on
       the tag, waits for that run, and is '' only for a green one.
    3. Get-SignedBoxFileRefusal with a stand-in box: the check script names
       the file already on the box and carries no copy of it; the box's
       answer comes back as Get-SignedFileRefusal's does.
    4. Publish-Installer.ps1 off Windows: the installer goes to a folder the
       site does not serve, is held to the gate there, is taken off again when
       it is refused, and is moved into files only once it passes, before
       files.json is written. On Windows the gate is the local one as before.
    5. Ship.ps1: -Package is no longer refused from the feed; installer.yml on
       the tag is asked about before anything is published; the release runs
       Publish-InstallerFromGitHub.ps1 and names it to put a failure right;
       and the launcher is not put into a folder for a local packager.
    6. Publish-InstallerFromGitHub.ps1 parses and finds the Ship.ps1 helpers
       it lifts.

  It never reaches GitHub or the box. Read only apart from files under its
  own temp folder.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$env:THORNSWOOD_HARNESS = '1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

. (Join-Path $Repo 'scripts\release\Sign-OnGitHub.ps1')
. (Join-Path $Repo 'scripts\release\Installer-OnGitHub.ps1')

# ---- 1. installer.yml on the tag ------------------------------------------------
$script:asked = @()
$ghHas = { $script:asked += , @($args); return '{"name":"installer.yml"}' }
Yes 'a tag that has installer.yml: nothing to refuse' ((Get-InstallerWorkflowRefusal 'o/r' 'v1.2.8' $ghHas) -eq '')
Yes '  asked for that file at that tag' (($script:asked[0] -join ' ') -eq 'api repos/o/r/contents/.github/workflows/installer.yml?ref=v1.2.8')
$gh404 = { throw 'gh api exited 1: gh: Not Found (HTTP 404)' }
$why = Get-InstallerWorkflowRefusal 'o/r' 'v1.2.7' $gh404
Yes 'a tag made before it merged: refused, saying to Ship -Package from One for this one' ($why -match 'v1\.2\.7 was made before installer\.yml merged' -and $why -match 'Ship this one with -Package from One')
$ghDown = { throw 'gh api exited 1: connection reset' }
Yes 'any other answer: refused as not known' ((Get-InstallerWorkflowRefusal 'o/r' 'v1.2.8' $ghDown) -match 'could not be read: gh api exited 1: connection reset')

# ---- 2. the run ------------------------------------------------------------------
$calls = New-Object System.Collections.ArrayList
function New-RunGh([string]$conclusion) {
    $calls.Clear()
    $c = $conclusion
    $seen = $calls
    return {
        [void]$seen.Add(($args -join ' '))
        if ($args[0] -eq 'workflow') { return '' }
        $made = (Get-Date).ToUniversalTime().ToString('o')
        return ('[{"databaseId":41,"displayTitle":"Installer from main''s feed (v1.2.8)","headBranch":"v1.2.8","status":"completed","conclusion":"' + $c +
                '","url":"https://github.invalid/runs/41","createdAt":"' + $made + '"},' +
                '{"databaseId":40,"displayTitle":"x","headBranch":"v1.2.7","status":"in_progress","conclusion":"","url":"u","createdAt":"' + $made + '"}]')
    }.GetNewClosure()
}
$gh = New-RunGh 'success'
$why = Invoke-InstallerOnGitHub -Repo 'o/r' -Tag 'v1.2.8' -Gh $gh -WaitSeconds 5 -Poll 1
Yes ("a green run on the tag: '' ('{0}')" -f $why) ($why -eq '')
Yes '  it started installer.yml on the tag' ($calls.Count -ge 2 -and $calls[0] -eq 'workflow run installer.yml -R o/r --ref v1.2.8')
Yes '  and read the workflow_dispatch runs of installer.yml' ($calls.Count -ge 2 -and $calls[1] -match '^run list -R o/r -w installer\.yml -e workflow_dispatch ')
$gh = New-RunGh 'failure'
$why = Invoke-InstallerOnGitHub -Repo 'o/r' -Tag 'v1.2.8' -Gh $gh -WaitSeconds 5 -Poll 1
Yes 'a red run: refused, with the run' ($why -match 'ended failure' -and $why -match 'runs/41')
Yes 'not a release tag: refused before anything is started' ((Invoke-InstallerOnGitHub -Repo 'o/r' -Tag 'main' -Gh $ghHas -WaitSeconds 1) -match 'not a release tag')

# ---- 3. the gate on the box, for a file already there ----------------------------
$script:sent = ''
$box = { param($s) $script:sent = $s; return @('noise', 'SIGNED ACCEPTED') }
$why = Get-SignedBoxFileRefusal 'C:\Thornswood-Docs\_incoming-installer\Thornswood-Setup.exe' 'Thornswood' $Repo $box
Yes 'the box accepts: nothing to refuse' ($why -eq '')
Yes '  the script names the file on the box' ($script:sent.Contains("`$f = 'C:\Thornswood-Docs\_incoming-installer\Thornswood-Setup.exe'"))
Yes '  and carries no copy of it, only Signature.cs' (@([regex]::Matches($script:sent, 'FromBase64String')).Count -eq 1 -and $script:sent.Contains('Signature.cs'))
$tt = $null; $te = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($script:sent, [ref]$tt, [ref]$te)
Yes '  and it parses' (@($te).Count -eq 0)
$box = { param($s) return @('SIGNED REFUSED Thornswood-Setup.exe is not Authenticode Valid (status NotSigned).') }
Yes 'the box refuses: its reason' ((Get-SignedBoxFileRefusal 'C:\x\Thornswood-Setup.exe' 'Thornswood' $Repo $box) -match 'NotSigned')
$box = { param($s) return @('hello') }
Yes 'the box does not say: refused' ((Get-SignedBoxFileRefusal 'C:\x\Thornswood-Setup.exe' 'Thornswood' $Repo $box) -match 'did not say whether Thornswood-Setup\.exe passes')

# ---- 4. Publish-Installer.ps1 ----------------------------------------------------
$piPath = Join-Path $Repo 'scripts\release\Publish-Installer.ps1'
$pi = [IO.File]::ReadAllText($piPath) -replace "`r`n", "`n"
$t = $null; $e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($piPath, [ref]$t, [ref]$e)
Yes 'Publish-Installer.ps1 parses' (@($e).Count -eq 0)
Yes 'off Windows it checks on the box; on Windows here, as before' ($pi -match '(?s)\$checkOnBox = -not \(\[Environment\]::OSVersion\.Platform -eq \[PlatformID\]::Win32NT\).*if \(\$checkOnBox\) \{.*\} else \{\s*\$signWhy = Get-PublishSignRefusal -Path \$exeItem\.FullName -ExpectedSigner \$expectWho')
$aSend = $pi.IndexOf('scp @ssh $exeItem.FullName "$User@${Vps}:$Root/$incoming/$exeOut"')
$aCheck = $pi.IndexOf('Get-SignedBoxFileRefusal "$rootWin\$incoming\$exeOut" $expectWho $repoRoot')
$aOff = $pi.IndexOf("Remove-Item -LiteralPath '`$rootWin\`$incoming\`$exeOut'")
$aMove = $pi.IndexOf("Move-Item -LiteralPath '`$rootWin\`$incoming\`$exeOut' -Destination '`$rootWin\files\`$exeOut'")
$aList = $pi.IndexOf('$listWrite = @(Remote')
Yes 'the installer goes to a folder the site does not serve, not into files' ($aSend -gt 0 -and $pi.Contains("`$incoming = '_incoming-installer'"))
Yes '  is held to the gate there after the send' ($aCheck -gt $aSend)
Yes '  is taken off again when refused' ($aOff -gt $aCheck)
Yes '  and is moved into files only after, before files.json is written' ($aMove -gt $aOff -and $aList -gt $aMove)
Yes '  and is not sent into files a second time' ($pi.Contains('if (-not $checkOnBox) { $send += , @($exeItem.FullName, $exeOut) }'))

# ---- 5. Ship.ps1 -----------------------------------------------------------------
$ship = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\release\Ship.ps1')) -replace "`r`n", "`n"
Yes '-Package is no longer refused from the feed' (-not $ship.Contains('Ship -Package from One. Nothing was built.'))
$aAsk = $ship.IndexOf("Get-InstallerWorkflowRefusal (Get-SourceRepo `$RepoDir) ('v' + `$target)")
$aPub = $ship.IndexOf("Head 'Publishing'")
Yes 'installer.yml on the tag is asked about before anything is published' ($aAsk -gt 0 -and ($aPub -lt 0 -or $aAsk -lt $aPub))
Yes '  and a refusal stops the release, put back' ($ship -match "(?s)Get-InstallerWorkflowRefusal.*?if \(\`$why\) \{\s*Unbump 'the installer cannot be built on GitHub for this tag'\s*Die")
Yes 'the release runs Publish-InstallerFromGitHub.ps1 on the launcher''s tag' ($ship -match "(?s)elseif \(\`$Package -and \`$FromFeed\) \{.*?Publish-InstallerFromGitHub\.ps1.*?\}\s*elseif \(\`$Package\) \{" -and
    $ship.Contains("`$pubArgs = @{ OutDir = `$DistDir; Tag = ('v' + `$target) }"))
Yes '  and names it to put a failure right' ($ship.Contains("Say `$(if (`$FromFeed) { '  .\scripts\release\Publish-InstallerFromGitHub.ps1' }"))
Yes 'the feed''s launcher is not put into a folder for a local packager from the feed' ($ship.Contains('if ($Package -and -not $Dev -and -not $DryRun -and $ModsOnly -and -not $FromFeed) {'))

# ---- 6. Publish-InstallerFromGitHub.ps1 -----------------------------------------
$pfPath = Join-Path $Repo 'scripts\release\Publish-InstallerFromGitHub.ps1'
$t = $null; $e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($pfPath, [ref]$t, [ref]$e)
Yes 'Publish-InstallerFromGitHub.ps1 parses' (@($e).Count -eq 0)
$shipAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'scripts\release\Ship.ps1'), [ref]$t, [ref]$e)
foreach ($name in 'Get-SourceRepo', 'ConvertTo-GhArgument', 'Invoke-GhToStream') {
    Yes "  Ship.ps1 still has $name, which it lifts" ($null -ne $shipAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true))
}
$pf = [IO.File]::ReadAllText($pfPath)
Yes '  it publishes only an installer whose note names the release main''s feed names now' ($pf -match '(?s)\$carries = Read-InstallerReleaseNote.*if \(\$newest -ne \$carries\) \{\s*throw')
Yes '  through Publish-Installer.ps1, one file' ($pf.Contains("`$pubArgs = @{ OutDir = `$OutDir; OneFile = `$true }") -and $pf.Contains("& (Join-Path `$Here 'Publish-Installer.ps1') @pubArgs"))

Done
