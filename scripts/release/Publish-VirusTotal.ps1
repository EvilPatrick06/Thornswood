<#
.SYNOPSIS
  Makes sure VirusTotal holds a report for every download the site's Downloads
  page offers, so the link the page prints beside a file's SHA-256 lands on a
  report rather than on item-not-found.

.DESCRIPTION
  WHY THIS EXISTS. Publish-Installer.ps1 measures the installer's SHA-256, puts
  it in files.json on the VPS, and prints the VirusTotal address for that hash.
  The site prints the same address under the download button
  (site\public\home.html, sum()), and site\data\help.md tells anybody worried
  about the Defender warning to read it. Publish-Installer's own note said what
  was wrong with that: "A file nobody has sent to VirusTotal has no report, so
  until this exe is uploaded there once the link lands on a page saying so."
  Nothing ever uploaded one, so the one answer we give somebody who does not
  want to run an unsigned installer was a page saying VirusTotal has never seen
  the file.

  IT READS THE PAGE'S OWN LIST, not a guess about which file that is. The site
  hands out what the Downloads page shows at /api/public, each file with the
  sha256 the page builds the VirusTotal address from, so what is checked here is
  exactly what a visitor can click. Anything the page hides (the payload zip,
  which the setup program fetches itself) is left alone, and if the page is ever
  given a second download, the launcher binary included, it is covered the day
  it appears without this script changing.

  WHAT IT SENDS. Only a file the site is already handing out, found on this
  machine by the same sha256 the page prints. Sending a file to VirusTotal makes
  its bytes available to their customers, so the rule is that it has to be
  public already, and everything on that page is.

  IT ASKS BEFORE IT SENDS. A hash that already has a report needs nothing, and
  most releases leave the installer where it was, so the usual run is one read
  and no upload.

  THE ONE THING IT CANNOT DO. The public API takes a file of up to 32 MB
  directly and up to 650 MB through an upload url. A one file installer
  (Package-Thornswood.ps1 -OneFile) is over a gigabyte, so no report can exist
  for it, and this says so plainly rather than failing: the pair build, a small
  setup exe beside its payload zip, is the one whose Downloads link works.

  MAIN AND DEV. A dev release does not change what the Downloads page offers, so
  on the dev channel a listed file whose bytes are not on this machine is
  reported and not counted as a failure: it is the live installer, and the
  machine that built it is where a report can come from. On main, where the
  release and the installer come off the same machine, it is a failure.

  THE KEY IS NAMED, NEVER HELD HERE. It is read from tools\virustotal.txt in
  the repository folder on the machine that ships (kept out by .gitignore, the
  same shape as bot\news-webhook.txt and tools\signing.json), or from the
  environment variable -KeyName names. It is never printed, never logged and
  never put on a command line: the upload is a .NET request from this process.
  DEVELOPING.md, the secrets table, has the row for it.

    .\scripts\release\Publish-VirusTotal.ps1
    .\scripts\release\Publish-VirusTotal.ps1 -CheckOnly        asks, uploads nothing
    .\scripts\release\Publish-VirusTotal.ps1 -File .\out\dist\Thornswood\_dist\Thornswood-Setup.exe

.PARAMETER SiteUrl
  The site whose Downloads page decides what is checked. Its /api/public is
  read, which is public and needs no sign in.

.PARAMETER File
  Files to check and send instead of whatever the page lists, for a build that
  is not on the site yet or for putting one report right by hand. The site is
  not read at all when this is given.

.PARAMETER Channel
  main or dev, which only decides how hard it is about a listed file this
  machine does not hold. See MAIN AND DEV above.

.PARAMETER Root
  The install the release was built from. Its Launcher folder is one of the
  places a listed file's bytes are looked for, so a page that ever offers the
  launcher binary is covered.

.PARAMETER DistRoot
  Where releases are staged, so the installer is found in the same place
  Package-Thornswood.ps1 and Publish-Installer.ps1 use.

.PARAMETER KeyFile
  Where the API key is read from. tools\virustotal.txt in the repository folder
  unless said otherwise. One line, the key and nothing else.

.PARAMETER KeyName
  The environment variable read when there is no key file.
  THORNSWOOD_VIRUSTOTAL_KEY unless said otherwise.

.PARAMETER CheckOnly
  Asks whether each file has a report and sends nothing. Exits 1 when one has
  none, so it can be used to find out where the page stands without changing
  anything.

.PARAMETER MaxUploadMB
  The largest file this will try to send, 650 by default, which is the public
  API's own limit. A file over it is reported and skipped.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-VirusTotal.ps1

  Reads what the Downloads page offers, uploads whichever of those files
  VirusTotal has never seen, and prints the address the page links for each.

.NOTES
  Exit codes: 0 every download the page offers has a report or has just been
  sent for one, 1 something the operator can act on stopped it: no key, a
  refused key, a rejected upload, an answer this does not understand, or, on
  main, a listed file whose bytes are not here. Ship.ps1 reads that code through
  Publish-PostShip.ps1.

  A file sent now is queued for analysis, so its report page fills in over the
  next minute or two. The address is stable from the moment the hash is known,
  because the address IS the hash.
#>
[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://thornswood.net',
    [string[]]$File,
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$Root = 'C:\Thornswood',
    [string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist),
    [string]$KeyFile,
    [string]$KeyName = 'THORNSWOOD_VIRUSTOTAL_KEY',
    [switch]$CheckOnly,
    [int]$MaxUploadMB = 650,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
    Write-Host ''
    Write-Host "STOP. $m" -ForegroundColor Red
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
    exit 1
}

function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

Head 'Thornswood - VirusTotal'
$Dev = ($Channel -eq 'dev')

try {
    # Windows PowerShell 5.1 still defaults to an older TLS on some machines,
    # and then every request here fails for a reason that has nothing to do
    # with the site or with VirusTotal.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# ------------------------------------------------------------ the key
#
# Read before anything else: asking the site what it offers and then stopping
# for want of a key wastes the reader's time and tells them nothing new.
if (-not $KeyFile) { $KeyFile = Join-Path $RepoDir 'tools\virustotal.txt' }
$key = ''
if (Test-Path -LiteralPath $KeyFile) {
    $key = (@(Get-Content -LiteralPath $KeyFile | Where-Object { $_.Trim() }) + @(''))[0].Trim()
}
if (-not $key) {
    $key = [string][Environment]::GetEnvironmentVariable($KeyName)
    if ($key) { $key = $key.Trim() }
}
if (-not $key) {
    Die ("There is no VirusTotal API key on this machine, so nothing could be checked or sent. Put the key on one line in $KeyFile " +
         "(it is kept out of git), or set the environment variable $KeyName. A key is free from a VirusTotal account, under the " +
         'profile menu, API key. To ship without waiting on this at all: .\scripts\release\Ship.ps1 -SkipVirusTotal.')
}
Say ("  key read from " + $(if (Test-Path -LiteralPath $KeyFile) { $KeyFile } else { "the environment variable $KeyName" })) 'DarkGray'

# ------------------------------------------------- what the page actually offers
#
# Each entry is a name, the sha256 the page prints and builds its VirusTotal
# address from, and the address a visitor clicks. Hidden entries are what the
# page itself never shows, so they are not what this is about.
$want = New-Object System.Collections.ArrayList
if ($File -and @($File | Where-Object { $_ }).Count) {
    Say '  -File given, so the site was not read' 'DarkGray'
    foreach ($f in @($File | Where-Object { $_ })) {
        if (-not (Test-Path -LiteralPath $f)) {
            Say "  $f is not there, so it was not checked" 'Yellow'
            continue
        }
        $full = (Resolve-Path -LiteralPath $f).ProviderPath
        [void]$want.Add([pscustomobject]@{
            Name = [IO.Path]::GetFileName($full)
            Sha  = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
            Url  = ''
            Path = $full
        })
    }
    if (-not $want.Count) { Die 'None of the files given by -File are there, so there was nothing to check.' }
}
else {
    $listUrl = $SiteUrl.TrimEnd('/') + '/api/public'
    $files = @()
    try {
        $answer = Invoke-WebRequest -Uri $listUrl -UseBasicParsing -TimeoutSec 30
        $doc = ([string]$answer.Content -replace '^\uFEFF', '') | ConvertFrom-Json
        if ($doc.PSObject.Properties['files']) { $files = @($doc.files) }
    } catch {
        Die ("$listUrl could not be read, so what the Downloads page offers is not known and nothing was checked: " +
             $_.Exception.Message + ' Pass -File to check a build by hand instead.')
    }
    foreach ($f in $files) {
        if ($null -eq $f) { continue }
        if ($f.PSObject.Properties['hidden'] -and $f.hidden) { continue }
        $sha = ''
        if ($f.PSObject.Properties['sha256']) { $sha = ([string]$f.sha256).Trim().ToLowerInvariant() }
        $name = ''
        if ($f.PSObject.Properties['name']) { $name = [string]$f.name }
        if ($sha -notmatch '^[a-f0-9]{64}$') {
            if ($name) { Say "  $name is offered with no sha256, so the page prints no VirusTotal link for it" 'Yellow' }
            continue
        }
        [void]$want.Add([pscustomobject]@{
            Name = $name
            Sha  = $sha
            Url  = ($SiteUrl.TrimEnd('/') + '/file/' + [Uri]::EscapeDataString($name))
            Path = ''
        })
    }
    Say ("  the Downloads page offers $($want.Count) file(s) with a sha256 on $($SiteUrl.TrimEnd('/'))") 'DarkGray'
    if (-not $want.Count) {
        Say '  so there is no VirusTotal link on it to put right.' 'Yellow'
        Write-Host ''
        if (-not $NoPause) { [void](Read-Host 'Enter to close') }
        exit 0
    }
}

# ------------------------------------------- where those bytes are on this disk
#
# By sha256, never by name: the site serves Thornswood-Setup-<stamp>.exe and
# this machine built Thornswood-Setup.exe, and only the hash says whether they
# are the same bytes.
$wanted = @{}
foreach ($w in $want) { if (-not $w.Path) { $wanted[$w.Sha] = $w } }
if ($wanted.Count) {
    $candidates = New-Object System.Collections.ArrayList
    $stage = Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist'
    foreach ($dir in @($stage, $DistRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'Thornswood-Setup*' -File -Recurse -EA SilentlyContinue)) {
            [void]$candidates.Add($f.FullName)
        }
    }
    $exe = Get-LauncherExe (Join-Path $Root 'Launcher')
    if ($exe) { [void]$candidates.Add($exe) }
    foreach ($path in @($candidates | Select-Object -Unique)) {
        $h = ''
        try { $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { continue }
        if ($wanted.ContainsKey($h) -and -not $wanted[$h].Path) { $wanted[$h].Path = $path }
    }
}

# The status code of a failed request, whichever edition of PowerShell this is.
# Invoke-WebRequest throws on 404 in both, and a 404 here is the answer rather
# than a fault: it is how VirusTotal says it has never seen the file.
function Get-Status($err) {
    $response = $null
    try { $response = $err.Exception.Response } catch { $response = $null }
    if ($null -eq $response) { return 0 }
    try { return [int]$response.StatusCode } catch { return 0 }
}

function Test-Report([string]$sha) {
    try {
        [void](Invoke-WebRequest -Uri "https://www.virustotal.com/api/v3/files/$sha" -Headers @{ 'x-apikey' = $key } `
                                 -UseBasicParsing -TimeoutSec 60)
        return 'yes'
    } catch {
        $code = Get-Status $_
        if ($code -eq 404) { return 'no' }
        if ($code -eq 401 -or $code -eq 403) { return 'refused' }
        if ($code -eq 429) { return 'limited' }
        return 'unknown:' + $(if ($code) { $code } else { $_.Exception.Message })
    }
}

# Uploads a file. Multipart, streamed from disk, with the key in a header of
# this process's own request: never on a command line, where any other process
# on the machine could read it.
Add-Type -AssemblyName System.Net.Http -EA SilentlyContinue
function Send-File([string]$path, [string]$url) {
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    $body = New-Object System.Net.Http.MultipartFormDataContent
    $stream = [IO.File]::OpenRead($path)
    try {
        $part = New-Object System.Net.Http.StreamContent $stream
        $part.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue 'application/octet-stream'
        $body.Add($part, 'file', [IO.Path]::GetFileName($path))
        $request = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post, $url)
        $request.Headers.Add('x-apikey', $key)
        $request.Content = $body
        $answer = $client.SendAsync($request).GetAwaiter().GetResult()
        return [pscustomobject]@{ Code = [int]$answer.StatusCode
                                  Text = [string]$answer.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
    } finally {
        $stream.Dispose()
        $body.Dispose()
        $client.Dispose()
    }
}

# Where a file over 32 MB goes. VirusTotal hands out a one time url for those.
function Get-UploadUrl {
    $answer = Invoke-WebRequest -Uri 'https://www.virustotal.com/api/v3/files/upload_url' -Headers @{ 'x-apikey' = $key } `
                                -UseBasicParsing -TimeoutSec 60
    $doc = [string]$answer.Content | ConvertFrom-Json
    if ($doc.PSObject.Properties['data']) { return [string]$doc.data }
    return ''
}

# ------------------------------------------------------------ each download
$had = 0
$sent = 0
$tooBig = @()
$notHere = @()
$failed = @()
foreach ($w in $want) {
    Head $w.Name
    if ($w.Url) { Say ("  the page offers it at $($w.Url)") 'DarkGray' }
    Say ("  sha256 $($w.Sha)") 'DarkGray'
    $gui = "https://www.virustotal.com/gui/file/$($w.Sha)"

    $state = Test-Report $w.Sha
    if ($state -eq 'yes') {
        $had++
        Say '  VirusTotal already has a report, so the link on the page works' 'Green'
        Say "  $gui" 'DarkGray'
        continue
    }
    if ($state -eq 'refused') {
        $failed += $w.Name
        Say '  VirusTotal refused the key. Check it in the account it came from; nothing was sent.' 'Red'
        continue
    }
    if ($state -eq 'limited') {
        $failed += $w.Name
        Say '  VirusTotal is rate limiting this key (four requests a minute on a free one), so this was not checked.' 'Red'
        Say '  Wait a minute and run this script again on its own.' 'Yellow'
        continue
    }
    if ($state -ne 'no') {
        $failed += $w.Name
        Say ('  VirusTotal answered something this does not understand: ' + $state.Substring(8)) 'Red'
        continue
    }

    Say '  VirusTotal has never seen this file, so the link on the page says item-not-found' 'Yellow'
    if ($CheckOnly) {
        $failed += $w.Name
        Say '  -CheckOnly, so nothing was sent.' 'DarkGray'
        continue
    }
    if (-not $w.Path) {
        # The bytes the page is handing out are not on this machine, so no
        # report can be made from here. On main that is the machine that builds
        # the installer, so it is something to put right; on dev it is the live
        # installer somebody else built and this release did not touch it.
        $notHere += $w.Name
        Say '  and its bytes are not on this machine, so no report can be made from here.' $(if ($Dev) { 'Yellow' } else { 'Red' })
        if ($Dev) {
            Say '  A dev release does not change what the Downloads page offers, so this is not this' 'DarkGray'
            Say '  release. Whoever built that installer runs Publish-VirusTotal.ps1 on their machine.' 'DarkGray'
        } else {
            Say '  Build the installer here (.\scripts\release\Package-Thornswood.ps1) or run this on the' 'Yellow'
            Say '  machine that built the one the site is serving.' 'Yellow'
        }
        continue
    }
    $item = Get-Item -LiteralPath $w.Path
    Say ("  found here: {0}, {1:N0} bytes" -f $item.FullName, $item.Length) 'DarkGray'
    if ($item.Length -gt ($MaxUploadMB * 1MB)) {
        $tooBig += $w.Name
        Say ("  and it is {0:N1} GB, past the {1} MB the public API takes, so no report can exist for it." -f ($item.Length / 1GB), $MaxUploadMB) 'Yellow'
        Say '  The pair build is the one whose Downloads link works: a small setup exe beside its payload' 'DarkGray'
        Say '  zip, which is what Package-Thornswood.ps1 makes without -OneFile.' 'DarkGray'
        continue
    }

    $url = 'https://www.virustotal.com/api/v3/files'
    if ($item.Length -gt 32MB) {
        try { $url = Get-UploadUrl } catch { $url = '' }
        if (-not $url) {
            $failed += $w.Name
            Say '  VirusTotal would not give an upload url for a file this size, so nothing was sent.' 'Red'
            continue
        }
        Say ("  {0:N1} MB, so it goes through an upload url" -f ($item.Length / 1MB)) 'DarkGray'
    }
    $answer = $null
    try { $answer = Send-File $item.FullName $url }
    catch {
        $failed += $w.Name
        Say ('  the upload stopped: ' + $_.Exception.Message) 'Red'
        continue
    }
    if ($answer.Code -ge 200 -and $answer.Code -lt 300) {
        $sent++
        Say '  sent. The report fills in over the next minute or two.' 'Green'
        Say "  $gui" 'DarkGray'
    } else {
        $failed += $w.Name
        Say ("  VirusTotal answered $($answer.Code) to the upload, so it was not accepted.") 'Red'
    }
}

Head 'Done'
$bad = @($failed) + @(if ($Dev) { @() } else { $notHere })
Say ("$had of the page's download(s) already had a report, $sent sent.") $(if ($bad.Count) { 'Yellow' } else { 'Green' })
if ($tooBig.Count) {
    Say ("$($tooBig.Count) file(s) are past what the public API takes, so the page's link for them stays item-not-found:") 'Yellow'
    foreach ($t in $tooBig) { Say "  $t" 'DarkGray' }
}
if ($notHere.Count -and $Dev) {
    Say ("$($notHere.Count) file(s) the page offers are not on this machine, which a dev release does not change:") 'Yellow'
    foreach ($n in $notHere) { Say "  $n" 'DarkGray' }
}
if ($bad.Count) {
    Say ("$($bad.Count) download(s) on the page have no report and this run could not get one:") 'Red'
    foreach ($f in $bad) { Say "  $f" 'Yellow' }
    Say '  The release itself is published and is fine. What is missing is the report the' 'DarkGray'
    Say '  Downloads page links, so somebody checking the file before running it reads' 'DarkGray'
    Say '  item-not-found. .\scripts\release\Publish-VirusTotal.ps1 puts that right on its own.' 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
if ($bad.Count) { exit 1 }
exit 0
