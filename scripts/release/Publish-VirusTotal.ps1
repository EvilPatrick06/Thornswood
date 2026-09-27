<#
.SYNOPSIS
  Sends a built installer to VirusTotal and leaves a comment on the report saying what it is.

.DESCRIPTION
  The Downloads page prints the SHA-256 of the installer with a link to
  VirusTotal's report on that hash, so somebody who wants to know what they are
  about to run can read a report instead of uploading half a gigabyte
  themselves (site\public\home.html:1315). A hash nobody has ever sent to
  VirusTotal has no report, and that link lands on a page saying so. This is
  what sends it.

  It also leaves one community comment on the report. That matters more than it
  sounds. The setup program is not signed yet, issue #390, and the engines that
  flag it are machine learning verdicts and hash intelligence rather than
  signatures for anything known: 5 of 71 on 27 September, one of them McAfeeD's
  ti!<hash>, which is a lookup in a feed that reads VirusTotal itself. A report
  that says what the file is, who publishes it and where it comes from is the
  one piece of signal we can add to that loop without a certificate.
  docs\VIRUSTOTAL-FALSE-POSITIVE.md is the whole picture and the checklist for
  the vendors that need a form filled in.

  IT NEVER STOPS A RELEASE. No key on this machine, VirusTotal rate limiting the
  free tier, a comment that will not post: each says so and exits 0. The only
  thing it treats as a failure is being pointed at a file that is not there and
  an upload that VirusTotal actively refuses.

  THE KEY. VT_API_KEY in this machine's environment, from the API key page of
  the VirusTotal account. It never goes in the repository, in a config file
  under it, or on a command line that lands in a shell history.

      [Environment]::SetEnvironmentVariable('VT_API_KEY', '<the key>', 'User')

  The free tier allows four requests a minute and five hundred a day, which is
  far more than a release needs: a lookup, an upload for a hash VirusTotal has
  never seen, and a comment.

.PARAMETER Path
  The file to send. Thornswood-Setup.exe out of Package-Thornswood.ps1, or the
  dated copy Publish-Installer.ps1 put on the site.

.PARAMETER Sha256
  The hash of that file, when the caller already measured it. Hex, either case.
  Measured here when it is not passed, and a value that does not match the file
  is refused rather than used, since commenting on the wrong report is worse
  than not commenting.

.PARAMETER ApiKey
  The VirusTotal key. VT_API_KEY from the environment by default. Passing it
  here is for a test harness; on a real machine let the environment hold it.

.PARAMETER NoComment
  Upload and look up, and leave no comment.

.PARAMETER Comment
  Different comment text. The default names Thornswood Setup, thornswood.net
  and what the program does, which is what the vendors read.

.EXAMPLE
  .\Publish-VirusTotal.ps1 -Path .\out\dist\Thornswood\_dist\Thornswood-Setup.exe

  Looks the hash up, uploads the file if VirusTotal has never seen it, comments
  on the report, and prints the report address.

.EXAMPLE
  .\Publish-VirusTotal.ps1 -Path .\Thornswood-Setup.exe -NoComment
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$Sha256,
    [string]$ApiKey = $env:VT_API_KEY,
    [switch]$NoComment,
    [string]$Comment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Api = 'https://www.virustotal.com/api/v3'
$Gui = 'https://www.virustotal.com/gui/file/'
# VirusTotal takes a file this big on the ordinary endpoint. Anything larger
# needs a one time address asked for first, which is the one file build's case.
$DirectLimit = 32MB

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# The status code off a failed Invoke-RestMethod, or 0 when there is not one.
# Windows PowerShell and PowerShell 7 hand back different exception types and
# both carry the response the same way.
function Get-Status($err) {
    try {
        $r = $err.Exception.Response
        if ($null -eq $r) { return 0 }
        return [int]$r.StatusCode
    } catch { return 0 }
}

# 429 is the free tier's four a minute, and 401 is a key that is not a key.
# Neither is a reason to stop a release, and both are worth saying out loud.
function Stop-Soft([string]$why) {
    Say ('  not sending to VirusTotal: ' + $why) 'Yellow'
    exit 0
}

# ------------------------------------------------------------------ the file
if (-not (Test-Path -LiteralPath $Path)) {
    Say ('  there is no file at ' + $Path) 'Red'
    exit 1
}
$file = Get-Item -LiteralPath $Path
$measured = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Sha256) {
    if ($Sha256.Trim().ToLowerInvariant() -ne $measured) {
        Say ('  -Sha256 is not the hash of that file. Measured ' + $measured) 'Red'
        exit 1
    }
}
$sha = $measured
$report = $Gui + $sha

'{0,-30} {1:N0} bytes' -f $file.Name, $file.Length | Write-Host
Say ('  sha256  ' + $sha) 'DarkGray'
Say ('  report  ' + $report) 'DarkGray'

# ------------------------------------------------------------------- the key
# Djinn's machine, a pull request build and anybody who has never set this up
# all reach this line, and none of them should see a failure for it.
if (-not $ApiKey) {
    Stop-Soft 'no VT_API_KEY on this machine, so nothing was uploaded and no comment was left'
}

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor 3072   # Tls12
} catch { }
$head = @{ 'x-apikey' = $ApiKey }

# --------------------------------------------------------------- the lookup
# A hash VirusTotal already holds is not uploaded again. Re-uploading changes
# nothing about the verdicts and spends the day's quota.
$known = $false
try {
    $null = Invoke-RestMethod -Uri ($Api + '/files/' + $sha) -Headers $head -Method Get -TimeoutSec 60
    $known = $true
    Say '  VirusTotal already has this file' 'DarkGray'
} catch {
    $code = Get-Status $_
    if ($code -eq 404) { Say '  VirusTotal has never seen this file' 'DarkGray' }
    elseif ($code -eq 401 -or $code -eq 403) { Stop-Soft 'VirusTotal refused the key in VT_API_KEY' }
    elseif ($code -eq 429) { Stop-Soft 'VirusTotal is rate limiting this key, so try again in a minute' }
    else { Stop-Soft ('the report could not be read: ' + $_.Exception.Message) }
}

# --------------------------------------------------------------- the upload
# Multipart through HttpClient rather than Invoke-RestMethod -Form, because
# -Form is PowerShell 7 only and the release scripts run under both.
function Send-File([string]$full, [string]$url, [string]$key) {
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
    $client = New-Object System.Net.Http.HttpClient
    $body = $null
    $stream = $null
    try {
        $client.Timeout = [TimeSpan]::FromMinutes(30)
        $client.DefaultRequestHeaders.Add('x-apikey', $key)
        $body = New-Object System.Net.Http.MultipartFormDataContent
        $stream = [IO.File]::OpenRead($full)
        $part = New-Object System.Net.Http.StreamContent $stream
        $part.Headers.ContentType =
            [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
        $body.Add($part, 'file', [IO.Path]::GetFileName($full))
        $resp = $client.PostAsync($url, $body).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return [pscustomobject]@{ Code = [int]$resp.StatusCode; Body = $text }
    } finally {
        if ($null -ne $body) { $body.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

if (-not $known) {
    $url = $Api + '/files'
    if ($file.Length -gt $DirectLimit) {
        # Over the ordinary endpoint's size, so VirusTotal hands out an address
        # for this one upload.
        try {
            $big = Invoke-RestMethod -Uri ($Api + '/files/upload_url') -Headers $head -Method Get -TimeoutSec 60
            $url = [string]$big.data
        } catch {
            $code = Get-Status $_
            if ($code -eq 429) { Stop-Soft 'VirusTotal is rate limiting this key, so try again in a minute' }
            Stop-Soft ('VirusTotal would not hand out an upload address: ' + $_.Exception.Message)
        }
    }

    Say ('  sending ' + [Math]::Round($file.Length / 1MB, 1) + ' MB') 'Gray'
    $sent = $null
    try { $sent = Send-File $file.FullName $url $ApiKey }
    catch { Stop-Soft ('the upload did not finish: ' + $_.Exception.Message) }

    if ($sent.Code -eq 429) { Stop-Soft 'VirusTotal is rate limiting this key, so try again in a minute' }
    if ($sent.Code -eq 401 -or $sent.Code -eq 403) { Stop-Soft 'VirusTotal refused the key in VT_API_KEY' }
    if ($sent.Code -lt 200 -or $sent.Code -ge 300) {
        Say ('  VirusTotal refused the upload, HTTP ' + $sent.Code) 'Red'
        Say ('  ' + $sent.Body) 'DarkGray'
        exit 1
    }
    Say '  uploaded. The report takes a minute or two to fill in.' 'Green'
}

# -------------------------------------------------------------- the comment
# What the vendors read when somebody picks this file out of their queue. It
# names the program, the company and the site the way the version resource in
# installer\setup\Bootstrap.cs:35-39 does, says what it does, and says it is
# not signed yet rather than leaving that to be discovered.
function Get-DefaultComment() {
    return @(
        'Thornswood Setup, the first-run installer for Thornswood, a private modded Skyrim',
        'multiplayer server at https://thornswood.net (company Thornswood, product Thornswood Setup).',
        'It downloads the Thornswood payload from thornswood.net, checks it against the SHA-256',
        'the site publishes beside the download, unpacks it and runs the Setup.bat inside it.',
        'Nothing in it is packed or obfuscated; the high entropy is the icon and logo in .rsrc.',
        'It is not Authenticode signed yet, which is what the machine learning verdicts here are',
        'reading. Published by us and only from https://thornswood.net under Downloads.'
    ) -join ' '
}

if ($NoComment) {
    Say '  -NoComment, so no comment was left' 'DarkGray'
    Say ('  ' + $report) 'Green'
    exit 0
}

if (-not $Comment) { $Comment = Get-DefaultComment }

# Soft on purpose, all of it. A comment that will not post is worth a line and
# nothing more: the upload above is the part that had to happen, and the same
# text can be pasted into the report by hand in ten seconds.
try {
    $payload = @{ data = @{ type = 'comment'; attributes = @{ text = $Comment } } } |
               ConvertTo-Json -Depth 5 -Compress
    $null = Invoke-RestMethod -Uri ($Api + '/files/' + $sha + '/comments') -Headers $head -Method Post `
                              -ContentType 'application/json' -Body $payload -TimeoutSec 60
    Say '  commented on the report' 'Green'
} catch {
    $code = Get-Status $_
    if ($code -eq 409) { Say '  that comment is already on the report' 'DarkGray' }
    elseif ($code -eq 429) { Say '  the comment did not post: VirusTotal is rate limiting this key' 'Yellow' }
    else { Say ('  the comment did not post: ' + $_.Exception.Message) 'Yellow' }
    Say '  Paste it in by hand if it matters, the text is in this script.' 'DarkGray'
}

Say ('  ' + $report) 'Green'
exit 0
