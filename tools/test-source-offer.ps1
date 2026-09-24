<#
  test-source-offer.ps1

  Where the source of the SkyMP files Thornswood ships is, said on the site and
  in the installed folder, and said truthfully.

  WHY IT MATTERS. Entry 170 on the To Do List. The installer and every pack
  carry six files built from SkyMP (tools\client-build.json), and the server
  runs a seventh (tools\server-build.json). SkyMP's folders carry the GNU GPL
  and AGPL version 3, each in its own LICENSE file. Nothing Thornswood put in
  front of a stranger said where the source was: credits.md named SkyMP with
  no licence and no link, and on 24 September the installer's READ ME
  FIRST.txt was still the Skyrim Together one, left in the setup program's
  scratch folder. The entry's closing condition: a stranger can reach,
  "from the download page and from inside the installed folder", a page
  naming skymp5-client, skyrim-platform and skymp5-server with their licences
  that links the corresponding source.

  MEASURED 24 SEPTEMBER. git ls-remote against the public fork with no
  credentials answers c8832519866e for thornswood/engine-changes, the commit
  both records name, and the tree, compare and upstream links on the page all
  answer 200 signed out.

  What this checks:
    - Get-SourceNotice, lifted out of the shipped Package-Thornswood.ps1 by
      text, writes SOURCE CODE.txt from the two records, names every recorded
      file, follows the records when they change, and stops on a file it has
      no source folder for.
    - Setup-Thornswood.ps1 copies that note into the install folder.
    - credits.md names the fork, the branch, the recorded commits and every
      shipped file, and carries no commit that is not in a record, so a
      rebuild that moves client-build.json fails here until the page moves too.
    - the download page points at it.
    - with the fork on this machine, every licence and every file to folder
      pair both notices state is read off the fork itself at the recorded
      commit. SKIP where the fork is not cloned, which is the build runner.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$Fork = 'C:\Thornswood-Dev\skymp')

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Read-Json([string]$p) {
    return (((Get-Content -LiteralPath $p -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json)
}
function Leaf([string]$p) { return $p.Substring($p.LastIndexOf('\') + 1) }

$clientPath  = Join-Path $Here 'client-build.json'
$serverPath  = Join-Path $Here 'server-build.json'
$packagePath = Join-Path $Here 'Package-Thornswood.ps1'
$setupPath   = Join-Path $Here 'Setup-Thornswood.ps1'
$creditsPath = Join-Path $Here 'docs-app\data\site\credits.md'
$homePath    = Join-Path $Here 'docs-app\public\home.html'

$client = Read-Json $clientPath
$server = Read-Json $serverPath
$files  = @($client.files.PSObject.Properties.Name)
$cCommit = [string]$client.forkCommit
$sCommit = [string]$server.source.commit
$forkUrl = ([string]$client.fork).TrimEnd('/')
$ub = [string]$client.upstreamBase
Yes ('the client record names a fork, a branch and a commit (' + $cCommit + ')') ($forkUrl -and $client.forkBranch -and $cCommit -match '^[0-9a-f]{7,40}$')
Yes ('the server record names a commit (' + $sCommit.Substring(0, [Math]::Min(8, $sCommit.Length)) + ')') ($sCommit -match '^[0-9a-f]{7,40}$')
Yes ('the client record lists the six runtime files') ($files.Count -eq 6)

# Every commit either record names, full or short. A hash on the page or in
# the note has to be a prefix of one of these, or one of these of it.
$known = @($cCommit, $sCommit, [string]$client.upstreamBase, [string]$server.source.upstreamBase) |
    Where-Object { $_ -match '^[0-9a-f]{7,40}$' }
function Test-Known([string]$h) {
    foreach ($k in $known) { if ($k.StartsWith($h) -or $h.StartsWith($k)) { return $true } }
    return $false
}
function Test-Words([string]$text) {
    return (-not ($text -match '\u2014') -and -not ($text -match '(?i)\bplayers?\b'))
}

# ---- the note the installer carries ----------------------------------------
#
# Lifted by name and by brace match, so the test drives the shipped function
# and a rename fails here rather than silently testing nothing.
function Get-FunctionText([string]$text, [string]$name) {
    $at = $text.IndexOf("function $name")
    if ($at -lt 0) { return $null }
    $b = $text.IndexOf('{', $at)
    if ($b -lt 0) { return $null }
    $depth = 0
    for ($i = $b; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) } }
    }
    return $null
}

$package = Get-Content -LiteralPath $packagePath -Raw
$fn = Get-FunctionText $package 'Get-SourceNotice'
Yes 'Package-Thornswood.ps1 has a Get-SourceNotice' ($null -ne $fn)

$note = ''
$rows = @()
if ($fn) {
    . ([ScriptBlock]::Create($fn))
    $note = Get-SourceNotice $clientPath $serverPath

    Yes 'the note names the fork' ($note.Contains($forkUrl))
    Yes 'the note names the branch' ($note.Contains([string]$client.forkBranch))
    Yes 'the note names the client commit and links its tree' ($note.Contains($forkUrl + '/tree/' + $cCommit))
    Yes 'the note names the server commit and links its tree' ($note.Contains(($server.source.repo -replace '\.git$', '') + '/tree/' + $sCommit))
    # New-ClientBuildRecord writes words here when upstream was not fetched,
    # and the note then says it does not know, which is the honest gap.
    Yes 'the note names the upstream commit it starts from, where the record has one' `
        (-not ($ub -match '^[0-9a-f]{7,40}$') -or $note.Contains($ub))
    $missing = @($files | Where-Object { -not $note.Contains((Leaf $_)) })
    Yes ('the note names every recorded file' + $(if ($missing.Count) { ', missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
    Yes 'the note names the server binary' ($note.Contains([string]$server.binary))
    Yes 'the note points at the credits page for later builds' ($note.Contains('https://thornswood.net/credits'))
    $stray = @([regex]::Matches($note, '\b[0-9a-f]{7,40}\b') | ForEach-Object { $_.Value } | Where-Object { -not (Test-Known $_) })
    Yes 'every commit in the note is one a record names' ($stray.Count -eq 0)
    Yes 'the note is plain ASCII, for Notepad' (-not ($note -match '[^\x09\x0A\x0D\x20-\x7E]'))
    Yes 'the note has no em dash and never says player' (Test-Words $note)

    # The table, as "  file  folder  licence".
    foreach ($l in ($note -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s{2}(\S+)(?: \(the server\))?\s{2,}(skymp5-client|skyrim-platform|skymp5-server)\s{2,}(GNU A?GPL version 3)\s*$')
        if ($m.Success) { $rows += [pscustomobject]@{ File = $m.Groups[1].Value; Folder = $m.Groups[2].Value; Licence = $m.Groups[3].Value; Where = 'note' } }
    }
    Yes ('the note gives a folder and a licence for all seven files, found ' + $rows.Count) ($rows.Count -eq 7)

    # It follows the records. A different commit in the records has to come out
    # in the note, and the old one must not, or the note was typed and not read.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-source-offer-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force -Path $tmp
    try {
        $c2 = Read-Json $clientPath
        $c2.forkCommit = 'abcdef12'
        $s2 = Read-Json $serverPath
        $s2.source.commit = 'abcdef1234567890abcdef1234567890abcdef12'
        $cp = Join-Path $tmp 'client-build.json'; $sp = Join-Path $tmp 'server-build.json'
        [IO.File]::WriteAllText($cp, ($c2 | ConvertTo-Json -Depth 6))
        [IO.File]::WriteAllText($sp, ($s2 | ConvertTo-Json -Depth 6))
        $n2 = Get-SourceNotice $cp $sp
        Yes 'a new client commit in the record comes out in the note' ($n2.Contains('/tree/abcdef12'))
        Yes 'a new server commit in the record comes out in the note' ($n2.Contains('/tree/abcdef1234567890abcdef1234567890abcdef12'))
        Yes 'the old commit does not survive a new record' (-not $n2.Contains($cCommit) -and -not $n2.Contains($sCommit))

        # Windows PowerShell 5.1 writes a byte order mark with -Encoding UTF8,
        # and a record saved that way still has to read.
        [IO.File]::WriteAllText($cp, ($c2 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($true)))
        Yes 'a record saved with a byte order mark still reads' ((Get-SourceNotice $cp $sp).Contains('/tree/abcdef12'))

        # A file the record gains with no known source folder stops the
        # package rather than shipping a note that leaves it out.
        $c3 = Read-Json $clientPath
        $c3.files | Add-Member -NotePropertyName 'Data\SKSE\Plugins\Unheard.dll' -NotePropertyValue ([pscustomobject]@{ sha256 = '00'; bytes = 1 })
        [IO.File]::WriteAllText($cp, ($c3 | ConvertTo-Json -Depth 6))
        $threw = $false
        try { $null = Get-SourceNotice $cp $sp } catch { $threw = $true }
        Yes 'a recorded file with no known source folder stops it' $threw

        $threw = $false
        try { $null = Get-SourceNotice (Join-Path $tmp 'nothing.json') $sp } catch { $threw = $true }
        Yes 'a missing client record stops it' $threw

        $c4 = Read-Json $clientPath
        $c4.forkCommit = ''
        [IO.File]::WriteAllText($cp, ($c4 | ConvertTo-Json -Depth 6))
        $threw = $false
        try { $null = Get-SourceNotice $cp $sp } catch { $threw = $true }
        Yes 'a record with no commit stops it' $threw

        # The words New-ClientBuildRecord writes when upstream was not fetched
        # say so in the note rather than passing for a commit.
        $c5 = Read-Json $clientPath
        $c5.upstreamBase = 'unknown, fetch upstream to fill this in'
        [IO.File]::WriteAllText($cp, ($c5 | ConvertTo-Json -Depth 6))
        $n5 = Get-SourceNotice $cp $serverPath
        Yes 'an upstream base the record does not know is said as a gap, not printed as a commit' `
            ($n5.Contains('a commit the build record does not name') -and -not $n5.Contains('unknown, fetch'))
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Written into the stage, which 7-Zip archives whole, and stopped on failure.
Yes 'Package-Thornswood.ps1 writes SOURCE CODE.txt into the stage from the records' `
    ($package -match "Join-Path \`$stage 'SOURCE CODE\.txt'" -and $package -match 'Get-SourceNotice \$clientRecordPath')

# The setup program unpacks into a scratch folder, so the note has to be put
# where a person keeps things.
$setup = Get-Content -LiteralPath $setupPath -Raw
Yes 'Setup-Thornswood.ps1 copies SOURCE CODE.txt into the install folder' `
    ($setup -match "Join-Path \`$Here 'SOURCE CODE\.txt'" -and $setup -match 'Copy-Item -LiteralPath \$srcNote -Destination \$Root')

# ---- the credits page ------------------------------------------------------
$credits = Get-Content -LiteralPath $creditsPath -Raw
$at = $credits.IndexOf("<a id='source'></a>")
Yes 'credits.md has the #source anchor the download page links to' ($at -ge 0)
$section = ''
if ($at -ge 0) {
    $section = $credits.Substring($at)
    $next = $section.IndexOf("`n## ", $section.IndexOf('## ') + 3)
    if ($next -gt 0) { $section = $section.Substring(0, $next) }
}
Yes 'the page names the fork' ($section.Contains($forkUrl))
Yes 'the page names the branch' ($section.Contains([string]$client.forkBranch))
Yes 'the page names the client commit' ($section.Contains($cCommit))
Yes 'the page links the server commit' ($section.Contains('/tree/' + $sCommit))
Yes 'the page names the upstream commit it starts from, where the record has one' `
    (-not ($ub -match '^[0-9a-f]{7,40}$') -or $section.Contains($ub.Substring(0, 8)))
$missing = @($files | Where-Object { -not $section.Contains((Leaf $_)) })
Yes ('the page names every recorded file' + $(if ($missing.Count) { ', missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
Yes 'the page names the server binary' ($section.Contains([string]$server.binary))
$stray = @([regex]::Matches($section, '\b[0-9a-f]{7,40}\b') | ForEach-Object { $_.Value } | Where-Object { -not (Test-Known $_) })
Yes ('every commit on the page is one a record names' + $(if ($stray.Count) { ', stale: ' + ($stray -join ', ') } else { '' })) ($stray.Count -eq 0)
Yes 'the page has no em dash and never says player' (Test-Words $credits)
foreach ($l in ($section -split "`r?`n")) {
    $m = [regex]::Match($l, '^\|\s*`([^`]+)`[^|]*\|\s*`(skymp5-client|skyrim-platform|skymp5-server)`\s*\|\s*(GNU A?GPL version 3)\s*\|')
    if ($m.Success) { $rows += [pscustomobject]@{ File = $m.Groups[1].Value; Folder = $m.Groups[2].Value; Licence = $m.Groups[3].Value; Where = 'page' } }
}
$pageRows = @($rows | Where-Object { $_.Where -eq 'page' })
Yes ('the page gives a folder and a licence for all seven files, found ' + $pageRows.Count) ($pageRows.Count -eq 7)
$disagree = @()
foreach ($r in $pageRows) {
    $o = @($rows | Where-Object { $_.Where -eq 'note' -and $_.File -eq $r.File })
    if ($o.Count -and ($o[0].Folder -ne $r.Folder -or $o[0].Licence -ne $r.Licence)) { $disagree += $r.File }
}
Yes 'the page and the note agree on every folder and licence' ($disagree.Count -eq 0)

$homeHtml = Get-Content -LiteralPath $homePath -Raw
$dl = $homeHtml.IndexOf("here === '/downloads'")
$dlEnd = if ($dl -ge 0) { $homeHtml.IndexOf("here === '/report'", $dl) } else { -1 }
$dlCode = if ($dl -ge 0 -and $dlEnd -gt $dl) { $homeHtml.Substring($dl, $dlEnd - $dl) } else { '' }
Yes 'the download page links /credits#source beside the installer' ($dlCode.Contains('href="/credits#source"'))

# ---- read off the fork itself ----------------------------------------------
#
# Every licence and every file to folder pair above is a claim. Where the fork
# is on this machine, each is checked against the fork at the recorded commit:
# the folder's LICENSE names that licence, and the folder's build is what makes
# that file.
$evidence = @{
    'skymp5-client.js'             = @('skymp5-client/package.json', '"name": "skymp5-client"')
    'SkyrimPlatform.dll'           = @('skyrim-platform/src/platform_se/CMakeLists.txt', 'OUTPUT_NAME "SkyrimPlatform"')
    'SkyrimPlatformImpl.dll'       = @('skyrim-platform/src/platform_se/CMakeLists.txt', 'OUTPUT_NAME "SkyrimPlatformImpl"')
    'SkyrimPlatformCEF.exe.hidden' = @('skyrim-platform/src/platform_se/CMakeLists.txt', 'SUFFIX ".exe.hidden"')
    'TESModPlatform.pex'           = @('skyrim-platform/src/platform_se/psc/TESModPlatform.psc', 'scriptName TESModPlatform')
    'MpClientPlugin.dll'           = @('skymp5-server/cpp/CMakeLists.txt', 'OUTPUT_NAME "MpClientPlugin"')
    'scam_native.node'             = @('skymp5-server/CMakeLists.txt', 'OUTPUT_NAME "scam_native"')
}
function Test-ForkHas([string]$commit) {
    if (-not (Test-Path -LiteralPath (Join-Path $Fork '.git'))) { return $false }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git -C $Fork cat-file -e ($commit + '^{commit}') 2>$null; return ($LASTEXITCODE -eq 0) }
    finally { $ErrorActionPreference = $old }
}
if (-not ((Test-ForkHas $cCommit) -and (Test-ForkHas $sCommit))) {
    Write-Host ('SKIP  the fork is not at ' + $Fork + ' with both recorded commits, so the licences are not read off it here')
} else {
    # Each file at the commit its own record names: the server binary at the
    # server's, the six at the client's. Today they are the same commit.
    function Show-AtCommit([string]$commit, [string]$path) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { return ((& git -C $Fork show ($commit + ':' + $path) 2>$null) -join "`n") }
        finally { $ErrorActionPreference = $old }
    }
    $wrongLicence = @(); $wrongFolder = @()
    foreach ($r in $rows) {
        $atCommit = if ($r.File -eq [string]$server.binary) { $sCommit } else { $cCommit }
        $lic = Show-AtCommit $atCommit ($r.Folder + '/LICENSE')
        $want = if ($r.Licence -eq 'GNU AGPL version 3') { 'GNU AFFERO GENERAL PUBLIC LICENSE' } else { 'GNU GENERAL PUBLIC LICENSE' }
        $head = (($lic -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' '
        if (-not ($head -match [regex]::Escape($want) -and $head -match 'Version 3')) { $wrongLicence += ($r.Where + ': ' + $r.Folder) }
        if ($r.Licence -eq 'GNU GPL version 3' -and $head -match 'AFFERO') { $wrongLicence += ($r.Where + ': ' + $r.Folder) }
        $ev = $evidence[$r.File]
        if (-not $ev -or -not $ev[0].StartsWith($r.Folder + '/') -or -not (Show-AtCommit $atCommit $ev[0]).Contains($ev[1])) { $wrongFolder += ($r.Where + ': ' + $r.File) }
    }
    Yes ('every licence named matches that folder''s LICENSE at the recorded commit' + $(if ($wrongLicence.Count) { ', wrong: ' + ($wrongLicence -join ', ') } else { '' })) ($rows.Count -gt 0 -and $wrongLicence.Count -eq 0)
    Yes ('every file is built by the folder named for it' + $(if ($wrongFolder.Count) { ', wrong: ' + ($wrongFolder -join ', ') } else { '' })) ($rows.Count -gt 0 -and $wrongFolder.Count -eq 0)
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
