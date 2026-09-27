<#
.SYNOPSIS
  Makes sure VirusTotal holds a report for the files a release just published,
  so the link the Downloads page prints beside the installer's SHA-256 lands on
  a report rather than on item-not-found.

.DESCRIPTION
  WHY THIS EXISTS. Publish-Installer.ps1 measures the installer's SHA-256, puts
  it in files.json, and prints the VirusTotal address for that hash. The site
  prints the same address under the download button (site\public\home.html,
  sum()), and site\data\help.md tells anybody worried about the Defender
  warning to read it. Its own note said what was wrong with that: "A file
  nobody has sent to VirusTotal has no report, so until this exe is uploaded
  there once the link lands on a page saying so." Nothing ever uploaded one, so
  the one answer we give a person who does not want to run an unsigned
  installer was a page saying VirusTotal has never seen the file.

  WHAT IT SENDS. Only files a release has already published to the world: the
  launcher exe that every launcher downloads, and the installer exe the
  Downloads page offers. Nothing from a profile, nothing from the VPS, nothing
  a pack keeps out (Ship-Rules.ps1). Sending a file to VirusTotal makes its
  bytes available to their customers, so the rule is that it has to be public
  already, and these two are.

  IT ASKS BEFORE IT SENDS. A hash that already has a report needs nothing, and
  most releases reuse an installer, so the usual run is two reads and no
  upload.

  THE ONE THING IT CANNOT DO. The public API takes a file of up to 32 MB
  directly and up to 650 MB through an upload url. A one file installer
  (Package-Thornswood.ps1 -OneFile) is over a gigabyte, so no report can exist
  for it and this says so plainly rather than failing: the pair build, a small
  setup exe beside its payload zip, is the one whose Downloads link works,
  because the exe the page links is a few hundred kilobytes.

  THE KEY IS NAMED, NEVER HELD HERE. It is read from tools\virustotal.txt in
  the repository folder on the machine that ships (kept out by .gitignore, the
  same shape as bot\news-webhook.txt and tools\signing.json), or from the
  environment variable -KeyName names. It is never printed, never logged and
  never put on a command line: the upload is a .NET request from this process.
  DEVELOPING.md, the secrets table, has the row for it.

    .\scripts\release\Publish-VirusTotal.ps1
    .\scripts\release\Publish-VirusTotal.ps1 -CheckOnly        asks, uploads nothing
    .\scripts\release\Publish-VirusTotal.ps1 -File .\out\dist\Thornswood\_dist\Thornswood-Setup.exe

.PARAMETER File
  The files to check and, when VirusTotal has never seen them, to send. Left
  out, it is the launcher exe in -Root and, on the main channel, the installer
  exe in the staging folder, when one is there.

.PARAMETER Channel
  main or dev. A dev release never touches the installer (Ship.ps1), so the dev
  channel only looks at the launcher exe.

.PARAMETER Root
  The install the release was built from, whose Launcher folder holds the
  shipped exe.

.PARAMETER DistRoot
  Where releases are staged, so the installer exe can be found in the same
  place Package-Thornswood.ps1 and Publish-Installer.ps1 use.

.PARAMETER KeyFile
  Where the API key is read from. tools\virustotal.txt in the repository folder
  unless said otherwise. One line, the key and nothing else.

.PARAMETER KeyName
  The environment variable read when there is no key file.
  THORNSWOOD_VIRUSTOTAL_KEY unless said otherwise.

.PARAMETER CheckOnly
  Asks whether each file has a report and sends nothing. Exits 1 when one has
  none, so it can be used to find out where a release stands without changing
  anything.

.PARAMETER MaxUploadMB
  The largest file this will try to send, 650 by default, which is the public
  API's own limit. A file over it is reported and skipped.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-VirusTotal.ps1

  Checks the launcher and the installer this machine last built, uploads
  whichever VirusTotal has never seen, and prints the address the Downloads
  page links for each.

.NOTES
  Exit codes: 0 every file has a report or has just been sent for one, 1 the key
  is missing or an answer could not be understood. Ship.ps1 reads that code and
  says at the end which of its three follow-ons did not complete; -SkipVirusTotal
  is the way to ship without waiting on this at all.

  A file sent now is queued for analysis, so its report page fills in over the
  next minute or two. The address is stable from the moment the hash is known,
  because the address IS the hash.
#>
[CmdletBinding()]
param(
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

# ------------------------------------------------------------ what to send
if (-not $File -or -not @($File | Where-Object { $_ }).Count) {
    $File = @()
    $exe = Get-LauncherExe (Join-Path $Root 'Launcher')
    if ($exe) { $File += $exe }
    if ($Channel -ne 'dev') {
        # The same folder Publish-Installer.ps1 reads and Ship.ps1 measures the
        # installer in: one staging folder per install root.
        $setup = Join-Path (Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist') 'Thornswood-Setup.exe'
        if (Test-Path -LiteralPath $setup) { $File += $setup }
    }
}
$files = @()
foreach ($f in @($File)) {
    if (-not $f) { continue }
    if (-not (Test-Path -LiteralPath $f)) {
        Say "  $f is not there, so it was not checked" 'Yellow'
        continue
    }
    $files += (Resolve-Path -LiteralPath $f).ProviderPath
}
$files = @($files | Select-Object -Unique)
if (-not $files.Count) {
    Say '  nothing to check: no launcher exe and no installer exe on this machine.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------ the key
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

try {
    # Windows PowerShell 5.1 still defaults to an older TLS on some machines,
    # and then every request here fails for a reason that has nothing to do
    # with VirusTotal.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# The status code of a failed request, whichever edition of PowerShell this is.
# Invoke-WebRequest throws on 404 in both, and a 404 here is the answer rather
# than a fault: it is how VirusTotal says it has never seen the file.
function Get-Status($err) {
    $response = $null
    try { $response = $err.Exception.Response } catch { $response = $null }
    if ($null -eq $response) { return 0 }
    try { return [int]$response.StatusCode } catch { return 0 }
}

# Asks whether a hash has a report. 200 yes, 404 no, anything else is a reason
# to stop rather than a guess.
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
        $code = [int]$answer.StatusCode
        $text = $answer.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return [pscustomobject]@{ Code = $code; Text = [string]$text }
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

# ------------------------------------------------------------ each file
$had = 0
$sent = 0
$tooBig = @()
$failed = @()
foreach ($path in $files) {
    $item = Get-Item -LiteralPath $path
    $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Head $item.Name
    Say ("  {0:N0} bytes, sha256 {1}" -f $item.Length, $sha) 'DarkGray'
    $gui = "https://www.virustotal.com/gui/file/$sha"

    $state = Test-Report $sha
    if ($state -eq 'yes') {
        $had++
        Say '  VirusTotal already has a report for this file' 'Green'
        Say "  $gui" 'DarkGray'
        continue
    }
    if ($state -eq 'refused') {
        $failed += $item.Name
        Say '  VirusTotal refused the key. Check it in the account it came from; nothing was sent.' 'Red'
        continue
    }
    if ($state -eq 'limited') {
        $failed += $item.Name
        Say '  VirusTotal is rate limiting this key (four requests a minute on a free one), so this was not checked.' 'Red'
        Say '  Wait a minute and run this script again on its own.' 'Yellow'
        continue
    }
    if ($state -ne 'no') {
        $failed += $item.Name
        Say ('  VirusTotal answered something this does not understand: ' + $state.Substring(8)) 'Red'
        continue
    }

    Say '  VirusTotal has never seen this file, so the link on the site says item-not-found' 'Yellow'
    if ($CheckOnly) {
        $failed += $item.Name
        Say '  -CheckOnly, so nothing was sent.' 'DarkGray'
        continue
    }
    if ($item.Length -gt ($MaxUploadMB * 1MB)) {
        $tooBig += $item.Name
        Say ("  and it is {0:N1} GB, past the {1} MB the public API takes, so no report can exist for it." -f ($item.Length / 1GB), $MaxUploadMB) 'Yellow'
        Say '  The pair build is the one whose Downloads link works: a small setup exe beside its payload zip,' 'DarkGray'
        Say '  which is what Package-Thornswood.ps1 makes without -OneFile.' 'DarkGray'
        continue
    }

    $url = 'https://www.virustotal.com/api/v3/files'
    if ($item.Length -gt 32MB) {
        try { $url = Get-UploadUrl } catch { $url = '' }
        if (-not $url) {
            $failed += $item.Name
            Say '  VirusTotal would not give an upload url for a file this size, so nothing was sent.' 'Red'
            continue
        }
        Say ("  {0:N1} MB, so it goes through an upload url" -f ($item.Length / 1MB)) 'DarkGray'
    }
    $answer = $null
    try { $answer = Send-File $path $url }
    catch {
        $failed += $item.Name
        Say ('  the upload stopped: ' + $_.Exception.Message) 'Red'
        continue
    }
    if ($answer.Code -ge 200 -and $answer.Code -lt 300) {
        $sent++
        Say '  sent. The report fills in over the next minute or two.' 'Green'
        Say "  $gui" 'DarkGray'
    } else {
        $failed += $item.Name
        Say ("  VirusTotal answered $($answer.Code) to the upload, so it was not accepted.") 'Red'
    }
}

Head 'Done'
Say ("$had file(s) already had a report, $sent sent.") $(if ($failed.Count) { 'Yellow' } else { 'Green' })
if ($tooBig.Count) {
    Say ("$($tooBig.Count) file(s) are past what the public API takes, so the site's link for them stays item-not-found:") 'Yellow'
    foreach ($t in $tooBig) { Say "  $t" 'DarkGray' }
}
if ($failed.Count) {
    Say ("$($failed.Count) file(s) have no report and this run could not get one:") 'Red'
    foreach ($f in $failed) { Say "  $f" 'Yellow' }
    Say '  The release itself is published and is fine. What is missing is the report the' 'DarkGray'
    Say '  Downloads page links, so somebody checking the file before running it reads' 'DarkGray'
    Say '  item-not-found. .\scripts\release\Publish-VirusTotal.ps1 puts that right on its own.' 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
if ($failed.Count) { exit 1 }
exit 0
