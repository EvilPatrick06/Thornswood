<#
  test-virustotal-upload.ps1

      pwsh -NoProfile -File .\tests\test-virustotal-upload.ps1

  Publish-VirusTotal.ps1 sends a published file to VirusTotal, and nothing it
  can run into stops a release.

  WHY THIS EXISTS. The Downloads page has printed the installer's SHA-256 with
  a link to VirusTotal's report on that hash since 24 September, and nothing
  ever sent the file, so every one of those links landed on VirusTotal's
  "item not found" page. The upload is the missing half, and the half that
  matters here is the failure: it runs at the end of Publish-Installer, after
  a gigabyte has already gone to the VPS and the site is already serving it,
  so an upload that threw would report a failed publish for a publish that
  worked.

  So this runs the real script, in a child PowerShell, and reads what it did:

    no VT_API_KEY                    exit 0, "skipped (VT_API_KEY not set)"
    a VT_API_KEY of spaces           the same, because empty is not set
    a key and no file                exit 0, naming the path
    a key and nothing answering      exit 0, naming the report address
    a key and VirusTotal has it      exit 0, "already has this build"
    a key VirusTotal refuses (401)   exit 0, saying the key was refused
    a file it has not seen           sent, and what arrived is read
    a file over 32 MB                sent to the upload address it hands out
    a file over 650 MB               refused by the cap, nothing sent

  and that the key never appears in anything printed, on any of those paths.

  It also checks the small name=value outcome file Publish-VirusTotal writes
  when -OutcomePath is set, and the end-to-end mark Publish-Installer applies
  to a tip exe entry in files.json: sent / already-has set vtUrl and
  vtSubmittedAt (UTC ...Z) with no vtSkipReason; over-650mb and no-key set
  vtSkipReason and neither link field. The mark is applied by running the
  same remote script body locally against a scratch files.json, so nothing
  here talks to a real VPS or to VirusTotal.

  WHY IT IS SAFE TO RUN ANYWHERE. It never reaches VirusTotal. Every case
  points the script at -Api on 127.0.0.1, either at a port where nothing is
  listening or at a stand-in that answers the calls VirusTotal's API v3
  answers and writes down what it was sent. The key in every case is a made
  up string, and the files are made in a temp folder this removes. The two
  large files are sparse: they are the length the case needs and take no disk.

  It also reads Publish-Installer.ps1, which since #813 (27 September) must
  NOT call it: publish sends nothing to VirusTotal any more, code signing is
  the trust path, and this script is a manual tool run by hand.
#>
[CmdletBinding()]
param([string]$ScriptPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
$RepoRoot = $Here
if (-not $ScriptPath) { $ScriptPath = Join-Path $RepoRoot 'scripts\release\Publish-VirusTotal.ps1' }
$Installer = Join-Path $RepoRoot 'scripts\release\Publish-Installer.ps1'
$Readme = Join-Path $RepoRoot 'installer\setup\README.md'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# Made up, and never a real key's shape, so nothing here could be one by
# accident. What matters is that it comes back out of nothing printed.
$FakeKey = 'made-up-key-for-the-harness-only'

# The same PowerShell that runs this, so pwsh tests under pwsh and Windows
# PowerShell under itself.
$Shell = (Get-Process -Id $PID).Path

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-virustotal-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

# ------------------------------------------------------------------ the runs

# The script in a child PowerShell, with VT_API_KEY exactly as the case wants
# it: $null takes it out of the environment altogether.
function Invoke-Vt([object]$key, [string[]]$extra) {
    $had = $env:VT_API_KEY
    $oldEap = $ErrorActionPreference
    # Windows PowerShell turns a child's stderr into a terminating error under
    # Stop, and a case here is allowed to write one.
    $ErrorActionPreference = 'Continue'
    try {
        if ($null -eq $key) { Remove-Item Env:VT_API_KEY -ErrorAction SilentlyContinue }
        else { $env:VT_API_KEY = $key }
        $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + @($extra)
        $out = (& $Shell @argv 2>&1 | Out-String)
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
    }
    finally {
        $ErrorActionPreference = $oldEap
        if ($null -eq $had) { Remove-Item Env:VT_API_KEY -ErrorAction SilentlyContinue }
        else { $env:VT_API_KEY = $had }
    }
}

# Nothing printed on any path may carry the key. Checked on every run rather
# than on one, because the paths that print an error are the ones that would.
function NoKey([string]$what, $r) {
    Yes ($what + 'and the key is in nothing it printed') (-not $r.Out.Contains($FakeKey))
}

# ------------------------------------------------------------- the stand-in
#
# VirusTotal's API v3, as much of it as this script calls, on the loopback
# address in a background job. It answers GET /files/<hash> the way the case
# asks, hands out an upload address, takes a POST, and writes one line per
# request into a log the checks below read. It never writes the key it was
# sent, only whether the header was there and matched.
#
# A socket and HTTP written out by hand, rather than HttpListener, which is
# the obvious way and cannot be used here: on Windows it needs the URL
# reserved with netsh or the process elevated, and the nightly runner on the
# VPS is a plain local account that is neither. This needs nothing but a port
# on 127.0.0.1, which every machine gives anybody.
#
# It ends itself on a request to /stop rather than being killed. Measured
# while writing this: Stop-Job on a job sitting in an accept call does not
# always come back, and the harness hung there for as long as it was given.
# /ping is how the case below knows it is up, and neither of those two is
# counted or written down.
$Listener = {
    param([int]$port, [string]$mode, [string]$log, [string]$expectKey)

    # Latin-1 maps every byte to one character, so a multipart body of file
    # bytes reads as text without anything failing to decode.
    $latin = [Text.Encoding]::GetEncoding(28591)
    $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $port
    $l.Start()
    try {
        for ($served = 0; $served -lt 20; $served++) {
            $client = $l.AcceptTcpClient()
            $path = ''
            try {
                $ns = $client.GetStream()
                $ns.ReadTimeout = 30000
                $ns.WriteTimeout = 30000
                $buf = New-Object byte[] 65536

                # The head, to the blank line. Whatever of the body came with
                # it is kept, because one read can carry both.
                $head = ''
                while ($head.IndexOf("`r`n`r`n") -lt 0) {
                    $n = $ns.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $head += $latin.GetString($buf, 0, $n)
                }
                $cut = $head.IndexOf("`r`n`r`n")
                if ($cut -lt 0) { $served--; continue }
                $start = $latin.GetBytes($head.Substring($cut + 4))
                $lines = @($head.Substring(0, $cut) -split "`r`n")

                $verb = ''
                $path = ''
                if ($lines[0] -match '^(\S+)\s+(\S+)') { $verb = $Matches[1]; $path = $Matches[2] }
                $key = ''
                $want = 0
                $waits = $false
                foreach ($h in @($lines | Select-Object -Skip 1)) {
                    if ($h -match '^(?i)x-apikey:\s*(.+)$') { $key = $Matches[1].Trim() }
                    elseif ($h -match '^(?i)content-length:\s*(\d+)') { $want = [int]$Matches[1] }
                    elseif ($h -match '^(?i)expect:\s*100-continue') { $waits = $true }
                }

                # Answering, then reading, then answering again. Windows
                # PowerShell's HttpClient asks first and waits, and without
                # this the body arrives only after it gives up waiting.
                if ($waits) {
                    $go = $latin.GetBytes("HTTP/1.1 100 Continue`r`n`r`n")
                    $ns.Write($go, 0, $go.Length)
                    $ns.Flush()
                }

                # The body into memory rather than onto a string, because a
                # 33 MB one grown 64 KB at a time is minutes of copying.
                $ms = New-Object IO.MemoryStream
                try {
                    $ms.Write($start, 0, $start.Length)
                    while ($ms.Length -lt $want) {
                        $n = $ns.Read($buf, 0, [Math]::Min($buf.Length, [int]($want - $ms.Length)))
                        if ($n -le 0) { break }
                        $ms.Write($buf, 0, $n)
                    }
                    $len = $ms.Length
                    # Only the front of it is read: the part headers and the
                    # first of the file are both in there, and nothing here
                    # wants the rest.
                    $peek = $latin.GetString($ms.GetBuffer(), 0, [Math]::Min(4096, [int]$len))
                }
                finally { $ms.Dispose() }

                if ($path -eq '/ping' -or $path -eq '/stop') {
                    $text = '{}'
                    $code = '200 OK'
                }
                else {
                    # .NET Framework quotes the name in the Content-Disposition
                    # header and .NET Core does not, so both shapes are read
                    # rather than the harness passing under one and not both.
                    $name = ''
                    if ($peek -match 'filename=("?)([^";\r\n]+)\1') { $name = $Matches[2] }
                    Add-Content -LiteralPath $log -Value (
                        $verb + ' ' + $path +
                        ' key=' + $(if ($key -eq $expectKey) { 'ours' } elseif ($key) { 'other' } else { 'none' }) +
                        ' len=' + $len +
                        ' name=' + $name +
                        ' bytes=' + $(if ($peek.Contains('THORNSWOOD-HARNESS-BYTES')) { 'ours' } else { 'no' }))

                    $code = '200 OK'
                    $text = '{"data":{"type":"analysis","id":"made-up-analysis-id"}}'
                    if ($path.EndsWith('/upload_url')) {
                        $text = '{"data":"http://127.0.0.1:' + $port + '/one-time-upload"}'
                    }
                    elseif ($verb -eq 'GET') {
                        switch ($mode) {
                            'present' { $text = '{"data":{"id":"made-up-file-id"}}' }
                            'refused' {
                                $code = '401 Unauthorized'
                                $text = '{"error":{"code":"WrongCredentialsError","message":"Wrong API key"}}'
                            }
                            default {
                                $code = '404 Not Found'
                                $text = '{"error":{"code":"NotFoundError","message":"File not found"}}'
                            }
                        }
                    }
                }

                $payload = [Text.Encoding]::UTF8.GetBytes($text)
                $reply = $latin.GetBytes(
                    "HTTP/1.1 $code`r`n" +
                    "Content-Type: application/json`r`n" +
                    "Content-Length: $($payload.Length)`r`n" +
                    "Connection: close`r`n`r`n")
                $ns.Write($reply, 0, $reply.Length)
                $ns.Write($payload, 0, $payload.Length)
                $ns.Flush()
            }
            finally { $client.Close() }
            if ($path -eq '/stop') { break }
            if ($path -eq '/ping') { $served-- }
        }
    }
    finally { $l.Stop() }
}

function Get-FreePort {
    $t = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
    $t.Start()
    $p = $t.LocalEndpoint.Port
    $t.Stop()
    return $p
}

# One small call to the stand-in, for /ping and /stop. Any answer at all, and
# any refusal, is the answer; nothing here cares what it says.
function Test-Knock([string]$url) {
    try {
        $c = New-Object Net.Http.HttpClient
        try {
            $c.Timeout = [TimeSpan]::FromSeconds(5)
            $null = $c.GetAsync($url).GetAwaiter().GetResult()
            return $true
        }
        finally { $c.Dispose() }
    }
    catch { return $false }
}

# One case against the stand-in: start it, run the script, ask it to stop, and
# hand back what was printed and what arrived.
function Invoke-Against([string]$mode, [string]$file) {
    $port = Get-FreePort
    $root = 'http://127.0.0.1:' + $port + '/'
    $log = Join-Path $work ('requests-' + $mode + '-' + $port + '.txt')
    $job = Start-Job -ScriptBlock $Listener -ArgumentList $port, $mode, $log, $FakeKey
    try {
        # The listener is a child PowerShell and is not up the instant the job
        # is. The script's own first call would fail on a refused connection.
        $up = $false
        for ($i = 0; $i -lt 150 -and -not $up; $i++) {
            $up = Test-Knock ($root + 'ping')
            if (-not $up) { Start-Sleep -Milliseconds 100 }
        }
        $r = Invoke-Vt $FakeKey @('-Path', $file, '-Api', ($root + 'api/v3'))
        $seen = @()
        if (Test-Path -LiteralPath $log) { $seen = @([IO.File]::ReadAllLines($log)) }
        return [pscustomobject]@{ Code = $r.Code; Out = $r.Out; Up = $up; Seen = $seen }
    }
    finally {
        $null = Test-Knock ($root + 'stop')
        $null = Wait-Job $job -Timeout 15 -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

# A file with something in it this harness can recognise on the other side.
function New-File([string]$name, [int64]$length) {
    $p = Join-Path $work $name
    [IO.File]::WriteAllText($p, 'THORNSWOOD-HARNESS-BYTES')
    if ($length -gt 0) {
        # Sparse where the file system does that, so 651 MB costs no disk.
        $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Write)
        try { $fs.SetLength($length) } finally { $fs.Dispose() }
    }
    return $p
}

function Sha([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

try {
    # ======================================================== it is there

    Yes 'Publish-VirusTotal.ps1 is there' (Test-Path -LiteralPath $ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) { throw 'no Publish-VirusTotal.ps1, so nothing below could run' }

    $text = [IO.File]::ReadAllText($ScriptPath, (New-Object Text.UTF8Encoding($false)))
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, $ScriptPath, [ref]$tokens, [ref]$errors)
    Yes 'it parses' (@($errors).Count -eq 0)

    $declared = @()
    if ($ast.ParamBlock) { $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    # The contract Ship and Publish-Installer call, and nothing about a key on
    # a command line, where a shell would write it into its own history.
    Yes 'it takes -Path and -Sha256' ($declared -contains 'Path' -and $declared -contains 'Sha256')
    Yes 'and has no parameter for the key' (
        @($declared | Where-Object { $_ -match '(?i)key|apikey|token|secret' }).Count -eq 0)
    Yes 'the key is read from VT_API_KEY' ($text -match '\$env:VT_API_KEY')
    Yes 'and there is no key written into the script' (
        -not [regex]::IsMatch($text, '(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])'))

    $help = $ast.GetHelpContent()
    Yes 'Get-Help can read what it is for' ($null -ne $help -and ([string]$help.Synopsis).Trim().Length -gt 20)

    # ================================================= no key is not a fault

    $small = New-File 'harness-small.bin' 0
    $smallSha = Sha $small

    $r = Invoke-Vt $null @('-Path', $small)
    Yes 'with no VT_API_KEY it exits 0' ($r.Code -eq 0)
    Yes '  and says it skipped, and why' ($r.Out -match '(?m)VirusTotal: skipped \(VT_API_KEY not set\)')
    Yes '  and reaches nothing, so it says nothing else' ($r.Out -notmatch 'virustotal\.com/api')

    $r = Invoke-Vt '   ' @('-Path', $small)
    Yes 'with a VT_API_KEY of spaces it says the same thing' (
        $r.Code -eq 0 -and $r.Out -match '(?m)VirusTotal: skipped \(VT_API_KEY not set\)')

    # ==================================== a key, and something in the way

    # Nothing to upload. The exe is built before this is called, so this is
    # the wrong -OutDir or a build that did not finish.
    $r = Invoke-Vt $FakeKey @('-Path', (Join-Path $work 'not-here.exe'))
    Yes 'with a key and no file it exits 0' ($r.Code -eq 0)
    Yes '  and names the path it was given' ($r.Out -match 'not-here\.exe')
    NoKey '  ' $r

    # Nothing listening. A port that was free a moment ago and has nothing on
    # it, which is a dropped connection as far as the script is concerned.
    $dead = 'http://127.0.0.1:' + (Get-FreePort) + '/api/v3'
    $r = Invoke-Vt $FakeKey @('-Path', $small, '-Api', $dead)
    Yes 'with a key and nothing answering it exits 0' ($r.Code -eq 0)
    Yes '  and says it was not sent' ($r.Out -match '(?m)VirusTotal: not sent \(')
    Yes '  and names the report address for the file it hashed' (
        $r.Out.Contains('https://www.virustotal.com/gui/file/' + $smallSha))
    NoKey '  ' $r

    # A hash from the caller that is not this file's is said, not obeyed.
    $r = Invoke-Vt $FakeKey @('-Path', $small, '-Sha256', ('0' * 64), '-Api', $dead)
    Yes 'a -Sha256 that is not the file''s is reported' ($r.Out -match "(?m)the hash passed in is not this file's")
    Yes '  and the file''s own hash is what it uses' (
        $r.Code -eq 0 -and $r.Out.Contains('https://www.virustotal.com/gui/file/' + $smallSha))

    # ==================================================== against a stand-in

    $r = Invoke-Against 'present' $small
    Yes 'the stand-in came up' $r.Up
    Yes 'when VirusTotal already has the build it exits 0' ($r.Code -eq 0)
    Yes '  and says so, with the report address' (
        $r.Out -match '(?m)VirusTotal: already has this build' -and
        $r.Out.Contains('https://www.virustotal.com/gui/file/' + $smallSha))
    Yes '  having asked for that hash and sent nothing' (
        @($r.Seen).Count -eq 1 -and $r.Seen[0] -match ('^GET /api/v3/files/' + $smallSha + ' '))
    Yes '  with the key in the x-apikey header' (@($r.Seen).Count -ge 1 -and $r.Seen[0] -match ' key=ours ')
    Yes '  and no comment on an already-has path' (
        @($r.Seen | Where-Object { $_ -match '/comments' }).Count -eq 0)
    NoKey '  ' $r

    $r = Invoke-Against 'refused' $small
    Yes 'a key VirusTotal refuses exits 0' ($r.Code -eq 0)
    Yes '  and says the key was refused, not that the network is down' (
        $r.Out -match '(?m)VirusTotal: not sent \(VT_API_KEY was refused\)')
    Yes '  and nothing was sent' (@($r.Seen | Where-Object { $_ -match '^POST' }).Count -eq 0)
    NoKey '  ' $r

    $r = Invoke-Against 'missing' $small
    Yes 'a file VirusTotal has not seen is sent, and it exits 0' ($r.Code -eq 0)
    Yes '  saying it was sent, with the report address' (
        $r.Out -match '(?m)VirusTotal: sent ' -and
        $r.Out.Contains('https://www.virustotal.com/gui/file/' + $smallSha))
    $upload = @($r.Seen | Where-Object { $_ -match '^POST /api/v3/files ' })
    Yes '  to POST /files, once' (@($upload).Count -eq 1)
    Yes '  with the key in the x-apikey header' (@($upload).Count -eq 1 -and $upload[0] -match ' key=ours ')
    Yes '  and the file''s own bytes under its own name' (
        @($upload).Count -eq 1 -and $upload[0] -match ' name=harness-small\.bin ' -and $upload[0] -match ' bytes=ours$')
    $comment = @($r.Seen | Where-Object { $_ -match ('^POST /api/v3/files/' + $smallSha + '/comments ') })
    Yes '  and then comments on the report, once' (@($comment).Count -eq 1)
    Yes '  with the key on the comment too' (@($comment).Count -eq 1 -and $comment[0] -match ' key=ours ')
    Yes '  saying it commented' ($r.Out -match '(?m)VirusTotal: commented on ')
    NoKey '  ' $r

    # Over 32 MB, which every installer is, goes to the one-time address
    # VirusTotal hands out rather than to POST /files.
    $big = New-File 'harness-big.bin' (33MB)
    $bigSha = Sha $big
    $r = Invoke-Against 'missing' $big
    Yes 'a file over 32 MB exits 0' ($r.Code -eq 0)
    Yes '  having asked for an upload address' (
        @($r.Seen | Where-Object { $_ -match '^GET /api/v3/files/upload_url ' }).Count -eq 1)
    $upload = @($r.Seen | Where-Object { $_ -match '^POST /one-time-upload ' })
    Yes '  and sent it there, not to POST /files' (@($upload).Count -eq 1)
    Yes '  and said it was sent' ($r.Out -match '(?m)VirusTotal: sent ')
    $comment = @($r.Seen | Where-Object { $_ -match ('^POST /api/v3/files/' + $bigSha + '/comments ') })
    Yes '  and then comments on the report' (@($comment).Count -eq 1)
    NoKey '  ' $r

    # Over what VirusTotal takes at all. Its cap, not ours, and the one-file
    # installer has been over it, so this is an expected outcome.
    $huge = New-File 'harness-huge.bin' (651MB)
    $r = Invoke-Against 'missing' $huge
    Yes 'a file over 650 MB exits 0' ($r.Code -eq 0)
    Yes '  saying it was not sent, and naming the cap' (
        $r.Out -match '(?m)VirusTotal: not sent \(' -and $r.Out -match '650 MB')
    Yes '  and nothing was sent' (@($r.Seen | Where-Object { $_ -match '^POST' }).Count -eq 0)
    NoKey '  ' $r

    # ===================================== outcome file + files.json mark

    function Read-Outcome([string]$p) {
        $o = @{ status = ''; sha256 = ''; reportUrl = ''; skipReason = '' }
        if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]$o }
        foreach ($line in [IO.File]::ReadAllLines($p)) {
            if ($line -match '^(?i)status=(.*)$') { $o.status = $Matches[1].Trim() }
            elseif ($line -match '^(?i)sha256=(.*)$') { $o.sha256 = $Matches[1].Trim() }
            elseif ($line -match '^(?i)reportUrl=(.*)$') { $o.reportUrl = $Matches[1].Trim() }
            elseif ($line -match '^(?i)skipReason=(.*)$') { $o.skipReason = $Matches[1].Trim() }
        }
        return [pscustomobject]$o
    }

    # Same remote mark body Publish-Installer sends over ssh, run here against
    # a scratch files.json. No ssh, no VPS. Mark fields arrive as name=value
    # lines (base64), never as JSON, so vtSubmittedAt stays a string with Z.
    function Invoke-MarkLocal([string]$filesJson, [string]$exeName, [string]$markText) {
        $markB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($markText))
        $fjEsc = $filesJson.Replace("'", "''")
        $nameEsc = $exeName.Replace("'", "''")
        $script = @"
`$f = '$fjEsc'
`$all = @{}
try {
  (Get-Content `$f -Raw | ConvertFrom-Json).PSObject.Properties |
    ForEach-Object { `$all[`$_.Name] = `$_.Value }
} catch { throw 'files.json unread' }
`$name = '$nameEsc'
if (-not `$all.ContainsKey(`$name)) { throw 'no tip exe entry' }
`$entry = `$all[`$name]
`$raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$markB64'))
`$mark = @{}
foreach (`$line in (`$raw -split [char]10)) {
  `$line = `$line.Trim()
  if (-not `$line) { continue }
  `$eq = `$line.IndexOf('=')
  if (`$eq -lt 1) { continue }
  `$mark[`$line.Substring(0, `$eq)] = `$line.Substring(`$eq + 1)
}
function Set-Note(`$obj, [string]`$n, `$v) {
  if (`$obj -is [hashtable]) { `$obj[`$n] = `$v; return `$obj }
  `$p = `$obj.PSObject.Properties[`$n]
  if (`$p) { `$p.Value = `$v } else { `$obj | Add-Member NoteProperty `$n `$v -Force }
  return `$obj
}
function Clear-Note(`$obj, [string]`$n) {
  if (`$obj -is [hashtable]) { `$obj.Remove(`$n); return `$obj }
  if (`$obj.PSObject.Properties[`$n]) { `$obj.PSObject.Properties.Remove(`$n) }
  return `$obj
}
if (`$mark.ContainsKey('vtUrl')) {
  `$entry = Set-Note `$entry 'vtUrl' `$mark['vtUrl']
  `$entry = Set-Note `$entry 'vtSubmittedAt' `$mark['vtSubmittedAt']
  `$entry = Clear-Note `$entry 'vtSkipReason'
} elseif (`$mark.ContainsKey('vtSkipReason')) {
  `$entry = Set-Note `$entry 'vtSkipReason' `$mark['vtSkipReason']
  `$entry = Clear-Note `$entry 'vtUrl'
  `$entry = Clear-Note `$entry 'vtSubmittedAt'
}
`$all[`$name] = `$entry
[IO.File]::WriteAllText(`$f, (`$all | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding(`$false)))
"@
        $tmp = Join-Path $work ('mark-' + [Guid]::NewGuid().ToString('N') + '.ps1')
        [IO.File]::WriteAllText($tmp, $script, (New-Object Text.UTF8Encoding($false)))
        try {
            & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp
            if ($LASTEXITCODE -ne 0) { throw "mark script exited $LASTEXITCODE" }
        }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }

    function Get-EntryField([string]$filesJson, [string]$exeName, [string]$field) {
        # Read the string out of the JSON text. Windows PowerShell's
        # ConvertFrom-Json turns an ISO-8601 value into a DateTime, which is
        # the bug the mark path avoids; the harness must not reintroduce it
        # when checking the file it just wrote.
        $raw = [IO.File]::ReadAllText($filesJson)
        $blockRe = '"' + [regex]::Escape($exeName) + '"\s*:\s*\{([\s\S]*?)\n\s*\}'
        $bm = [regex]::Match($raw, $blockRe)
        if (-not $bm.Success) { return $null }
        $block = $bm.Groups[1].Value
        $fm = [regex]::Match($block, '"' + [regex]::Escape($field) + '"\s*:\s*"([^"]*)"')
        if ($fm.Success) { return $fm.Groups[1].Value }
        return $null
    }

    function New-FilesJson([string]$exeName, [string]$sha) {
        $p = Join-Path $work ('files-' + [Guid]::NewGuid().ToString('N') + '.json')
        $obj = [ordered]@{}
        $obj[$exeName] = [ordered]@{
            label   = 'Thornswood installer'
            version = '9-27-2026 8:00 AM'
            sha256  = $sha
            note    = 'tip'
        }
        [IO.File]::WriteAllText($p, ($obj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
        return $p
    }

    # --- outcome: no-key
    $outNoKey = Join-Path $work 'outcome-nokey.txt'
    $r = Invoke-Vt $null @('-Path', $small, '-OutcomePath', $outNoKey)
    $o = Read-Outcome $outNoKey
    Yes 'no-key outcome status is skipped' ($r.Code -eq 0 -and $o.status -eq 'skipped')
    Yes '  skipReason is no-key' ($o.skipReason -eq 'no-key')
    Yes '  and has no reportUrl' ([string]::IsNullOrEmpty($o.reportUrl))

    # --- outcome: already-has
    $outHave = Join-Path $work 'outcome-have.txt'
    $port = Get-FreePort
    $root = 'http://127.0.0.1:' + $port + '/'
    $log = Join-Path $work ('requests-outcome-have-' + $port + '.txt')
    $job = Start-Job -ScriptBlock $Listener -ArgumentList $port, 'present', $log, $FakeKey
    try {
        $up = $false
        for ($i = 0; $i -lt 150 -and -not $up; $i++) {
            $up = Test-Knock ($root + 'ping')
            if (-not $up) { Start-Sleep -Milliseconds 100 }
        }
        $r = Invoke-Vt $FakeKey @('-Path', $small, '-Api', ($root + 'api/v3'), '-OutcomePath', $outHave)
    }
    finally {
        $null = Test-Knock ($root + 'stop')
        $null = Wait-Job $job -Timeout 15 -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    $o = Read-Outcome $outHave
    Yes 'already-has outcome status is already-has' ($r.Code -eq 0 -and $o.status -eq 'already-has')
    Yes '  with sha256 and reportUrl' (
        $o.sha256 -eq $smallSha -and
        $o.reportUrl -eq ('https://www.virustotal.com/gui/file/' + $smallSha))
    Yes '  and no skipReason' ([string]::IsNullOrEmpty($o.skipReason))

    # --- outcome: sent
    $outSent = Join-Path $work 'outcome-sent.txt'
    $port = Get-FreePort
    $root = 'http://127.0.0.1:' + $port + '/'
    $log = Join-Path $work ('requests-outcome-sent-' + $port + '.txt')
    $job = Start-Job -ScriptBlock $Listener -ArgumentList $port, 'missing', $log, $FakeKey
    try {
        $up = $false
        for ($i = 0; $i -lt 150 -and -not $up; $i++) {
            $up = Test-Knock ($root + 'ping')
            if (-not $up) { Start-Sleep -Milliseconds 100 }
        }
        $r = Invoke-Vt $FakeKey @('-Path', $small, '-Api', ($root + 'api/v3'), '-OutcomePath', $outSent)
    }
    finally {
        $null = Test-Knock ($root + 'stop')
        $null = Wait-Job $job -Timeout 15 -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    $o = Read-Outcome $outSent
    Yes 'sent outcome status is sent' ($r.Code -eq 0 -and $o.status -eq 'sent')
    Yes '  with sha256 and reportUrl' (
        $o.sha256 -eq $smallSha -and
        $o.reportUrl -eq ('https://www.virustotal.com/gui/file/' + $smallSha))
    Yes '  and no skipReason' ([string]::IsNullOrEmpty($o.skipReason))

    # --- outcome: over-650mb
    $outHuge = Join-Path $work 'outcome-huge.txt'
    $port = Get-FreePort
    $root = 'http://127.0.0.1:' + $port + '/'
    $log = Join-Path $work ('requests-outcome-huge-' + $port + '.txt')
    $job = Start-Job -ScriptBlock $Listener -ArgumentList $port, 'missing', $log, $FakeKey
    try {
        $up = $false
        for ($i = 0; $i -lt 150 -and -not $up; $i++) {
            $up = Test-Knock ($root + 'ping')
            if (-not $up) { Start-Sleep -Milliseconds 100 }
        }
        $r = Invoke-Vt $FakeKey @('-Path', $huge, '-Api', ($root + 'api/v3'), '-OutcomePath', $outHuge)
    }
    finally {
        $null = Test-Knock ($root + 'stop')
        $null = Wait-Job $job -Timeout 15 -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    $o = Read-Outcome $outHuge
    Yes 'over-650 outcome status is skipped' ($r.Code -eq 0 -and $o.status -eq 'skipped')
    Yes '  skipReason is over-650mb' ($o.skipReason -eq 'over-650mb')

    # --- end-to-end mark on a scratch files.json (ssh stand-in = local body)
    $exeName = 'Thornswood-Setup-20260927-0830.exe'
    $vtUrl = 'https://www.virustotal.com/gui/file/' + $smallSha

    $fj = New-FilesJson $exeName $smallSha
    $vtAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    Invoke-MarkLocal $fj $exeName (('vtUrl=' + $vtUrl) + [char]10 + ('vtSubmittedAt=' + $vtAt) + [char]10 + 'clearSkip=1')
    $gotUrl = Get-EntryField $fj $exeName 'vtUrl'
    $gotAt = Get-EntryField $fj $exeName 'vtSubmittedAt'
    $gotSkip = Get-EntryField $fj $exeName 'vtSkipReason'
    Yes 'mark success sets vtUrl from measured sha' ($gotUrl -eq $vtUrl)
    Yes '  and vtSubmittedAt as UTC Z' (
        $gotAt -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -and $gotAt -eq $vtAt)
    Yes '  and no vtSkipReason' ($null -eq $gotSkip)
    $rawJson = [IO.File]::ReadAllText($fj)
    Yes '  and the JSON keeps the Z on vtSubmittedAt' ($rawJson -match ('"vtSubmittedAt"\s*:\s*"' + [regex]::Escape($vtAt) + '"'))

    $fj2 = New-FilesJson $exeName $smallSha
    Invoke-MarkLocal $fj2 $exeName 'vtSkipReason=over-650mb'
    Yes 'mark over-650 sets vtSkipReason' ((Get-EntryField $fj2 $exeName 'vtSkipReason') -eq 'over-650mb')
    Yes '  and sets neither vtUrl nor vtSubmittedAt' (
        $null -eq (Get-EntryField $fj2 $exeName 'vtUrl') -and
        $null -eq (Get-EntryField $fj2 $exeName 'vtSubmittedAt'))

    $fj3 = New-FilesJson $exeName $smallSha
    Invoke-MarkLocal $fj3 $exeName 'vtSkipReason=no-key'
    Yes 'mark no-key sets vtSkipReason' ((Get-EntryField $fj3 $exeName 'vtSkipReason') -eq 'no-key')
    Yes '  and sets neither vtUrl nor vtSubmittedAt' (
        $null -eq (Get-EntryField $fj3 $exeName 'vtUrl') -and
        $null -eq (Get-EntryField $fj3 $exeName 'vtSubmittedAt'))

    $fj4 = New-FilesJson $exeName $smallSha
    Invoke-MarkLocal $fj4 $exeName 'vtSkipReason=upload-failed'
    Invoke-MarkLocal $fj4 $exeName (('vtUrl=' + $vtUrl) + [char]10 + ('vtSubmittedAt=' + $vtAt))
    Yes 'mark already-has/success clears vtSkipReason' ($null -eq (Get-EntryField $fj4 $exeName 'vtSkipReason'))
    Yes '  and keeps vtUrl + vtSubmittedAt' (
        (Get-EntryField $fj4 $exeName 'vtUrl') -eq $vtUrl -and
        (Get-EntryField $fj4 $exeName 'vtSubmittedAt') -eq $vtAt)


    # ============================================ Publish-Installer calls it

    # Publish-VirusTotal leaves a comment after a successful upload only.
    Yes 'Publish-VirusTotal.ps1 calls Add-VirusTotalComment.ps1 after a send' (
        $text -match "(?s)Write-Outcome -Status 'sent'.{0,800}Add-VirusTotalComment\.ps1")
    Yes '  with the same -Path and measured sha' (
        $text -match [regex]::Escape('-Path $file.FullName -Sha256 $sha'))
    Yes '  fail-soft in try/catch so a comment failure still exits 0' (
        $text -match "(?s)try \{.{0,200}Add-VirusTotalComment\.ps1.{0,200}catch")
    Yes '  and the already-has path does not call it' (
        -not [regex]::IsMatch($text, "(?s)already has this build.{0,400}Add-VirusTotalComment"))

    # Since #813 (27 September) publish sends nothing to VirusTotal: code
    # signing (#390) is the trust path, and Publish-VirusTotal.ps1 is a
    # manual tool somebody runs by hand. So Publish-Installer must not call
    # it, and must not reach for the key; what it still does is measure the
    # hash the Downloads page prints and say where the manual tool is.
    Yes 'Publish-Installer.ps1 is there' (Test-Path -LiteralPath $Installer)
    $pub = [IO.File]::ReadAllText($Installer, (New-Object Text.UTF8Encoding($false)))
    $pubCode = ($pub -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    Yes 'it does not call Publish-VirusTotal.ps1, since publish sends nothing there (#813)' (
        $pubCode -notmatch 'Publish-VirusTotal\.ps1')
    Yes '  nor Add-VirusTotalComment.ps1' ($pubCode -notmatch 'Add-VirusTotalComment\.ps1')
    Yes '  and reads no VT_API_KEY' ($pubCode -notmatch 'VT_API_KEY')
    Yes '  and still measures the SHA-256 the Downloads page prints' (
        $pubCode -match 'Get-FileHash -LiteralPath \$exeItem\.FullName -Algorithm SHA256')
    Yes '  and its comments say where the manual tool is' (
        $pub -match 'scripts\\release\\Publish-VirusTotal\.ps1')

    # ================================================= and it is written down

    Yes 'installer\setup\README.md is there' (Test-Path -LiteralPath $Readme)
    $doc = [IO.File]::ReadAllText($Readme, (New-Object Text.UTF8Encoding($false)))
    Yes '  and says the upload needs VT_API_KEY' ($doc -match 'VT_API_KEY')
    Yes '  and that publish no longer sends anything, so it is a manual tool' (
        $doc -match 'Publish no longer sends the installer to VirusTotal' -and $doc -match 'optional\s+manual tools')
    Yes '  and gives the two ways to run it by hand' (
        $doc -match 'Publish-VirusTotal\.ps1 -Path <file>\s' -and
        $doc -match 'Publish-VirusTotal\.ps1 -Path <file> -Sha256 <hex>')
}
catch {
    # Anything that stops the run part way is a failure, said as one, and the
    # count below still prints.
    Yes ('the rest ran: ' + $_.Exception.Message) $false
}
finally {
    Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
