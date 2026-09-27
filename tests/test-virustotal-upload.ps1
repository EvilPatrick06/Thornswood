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

  WHY IT IS SAFE TO RUN ANYWHERE. It never reaches VirusTotal. Every case
  points the script at -Api on 127.0.0.1, either at a port where nothing is
  listening or at a stand-in that answers the calls VirusTotal's API v3
  answers and writes down what it was sent. The key in every case is a made
  up string, and the files are made in a temp folder this removes. The two
  large files are sparse: they are the length the case needs and take no disk.

  It also reads Publish-Installer.ps1 for the call, because a helper nothing
  calls publishes nothing.
#>
[CmdletBinding()]
param([string]$ScriptPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
$RepoRoot = Split-Path -Parent $Here
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
# It ends itself on a request to /stop rather than being killed. Measured
# while writing this: Stop-Job on a job sitting in HttpListener.GetContext
# does not always come back, and the harness hung there for as long as it was
# given. /ping is how the case below knows it is up, and neither of those two
# is counted or written down.
$Listener = {
    param([int]$port, [string]$mode, [string]$log, [string]$expectKey)

    $prefix = 'http://127.0.0.1:' + $port + '/'
    $l = New-Object Net.HttpListener
    $l.Prefixes.Add($prefix)
    $l.Start()
    try {
        for ($served = 0; $served -lt 20; $served++) {
            $ctx = $l.GetContext()
            $req = $ctx.Request
            $path = $req.Url.AbsolutePath
            if ($path -eq '/ping' -or $path -eq '/stop') {
                $ctx.Response.StatusCode = 204
                $ctx.Response.ContentLength64 = 0
                $ctx.Response.Close()
                if ($path -eq '/stop') { break }
                $served--
                continue
            }
            $key = [string]$req.Headers['x-apikey']
            # Latin-1, so a multipart body of file bytes decodes without loss.
            $body = ''
            if ($req.HasEntityBody) {
                $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::GetEncoding(28591))
                try { $body = $sr.ReadToEnd() } finally { $sr.Dispose() }
            }
            # .NET Framework quotes the name in the Content-Disposition header
            # and .NET Core does not, so both shapes are read here rather than
            # the harness passing under one PowerShell and not the other.
            $name = ''
            if ($body -match 'filename=("?)([^";\r\n]+)\1') { $name = $Matches[2] }
            Add-Content -LiteralPath $log -Value (
                $req.HttpMethod + ' ' + $req.Url.AbsolutePath +
                ' key=' + $(if ($key -eq $expectKey) { 'ours' } elseif ($key) { 'other' } else { 'none' }) +
                ' len=' + $body.Length +
                ' name=' + $name +
                ' bytes=' + $(if ($body.Contains('THORNSWOOD-HARNESS-BYTES')) { 'ours' } else { 'no' }))

            $code = 200
            $text = '{"data":{"type":"analysis","id":"made-up-analysis-id"}}'
            if ($req.Url.AbsolutePath.EndsWith('/upload_url')) {
                $text = '{"data":"' + $prefix + 'one-time-upload"}'
            }
            elseif ($req.HttpMethod -eq 'GET') {
                switch ($mode) {
                    'present' { $text = '{"data":{"id":"made-up-file-id"}}' }
                    'refused' {
                        $code = 401
                        $text = '{"error":{"code":"WrongCredentialsError","message":"Wrong API key"}}'
                    }
                    default {
                        $code = 404
                        $text = '{"error":{"code":"NotFoundError","message":"File not found"}}'
                    }
                }
            }
            $buf = [Text.Encoding]::UTF8.GetBytes($text)
            $ctx.Response.StatusCode = $code
            $ctx.Response.ContentType = 'application/json'
            $ctx.Response.ContentLength64 = $buf.Length
            $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
            $ctx.Response.Close()
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
    $post = @($r.Seen | Where-Object { $_ -match '^POST ' })
    Yes '  to POST /files, once' (@($post).Count -eq 1 -and $post[0] -match '^POST /api/v3/files ')
    Yes '  with the key in the x-apikey header' (@($post).Count -eq 1 -and $post[0] -match ' key=ours ')
    Yes '  and the file''s own bytes under its own name' (
        @($post).Count -eq 1 -and $post[0] -match ' name=harness-small\.bin ' -and $post[0] -match ' bytes=ours$')
    NoKey '  ' $r

    # Over 32 MB, which every installer is, goes to the one-time address
    # VirusTotal hands out rather than to POST /files.
    $big = New-File 'harness-big.bin' (33MB)
    $r = Invoke-Against 'missing' $big
    Yes 'a file over 32 MB exits 0' ($r.Code -eq 0)
    Yes '  having asked for an upload address' (
        @($r.Seen | Where-Object { $_ -match '^GET /api/v3/files/upload_url ' }).Count -eq 1)
    $post = @($r.Seen | Where-Object { $_ -match '^POST ' })
    Yes '  and sent it there, not to POST /files' (
        @($post).Count -eq 1 -and $post[0] -match '^POST /one-time-upload ')
    Yes '  and said it was sent' ($r.Out -match '(?m)VirusTotal: sent ')
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

    # ============================================ Publish-Installer calls it

    Yes 'Publish-Installer.ps1 is there' (Test-Path -LiteralPath $Installer)
    $pub = [IO.File]::ReadAllText($Installer, (New-Object Text.UTF8Encoding($false)))
    Yes 'it calls Publish-VirusTotal.ps1' ($pub -match "Publish-VirusTotal\.ps1'\)\s*-Path\b")
    Yes '  with the exe and the hash it measured' (
        $pub -match "Publish-VirusTotal\.ps1'\)\s+-Path\s+\`$exeItem\.FullName\s+-Sha256\s+\`$exeSha")
    Yes '  and still prints the report address itself' (
        $pub -match 'VirusTotal: https://www\.virustotal\.com/gui/file/')
    # After the exe and the payload are on the VPS and files.json is written.
    # A publish that has happened is not undone by a report that is missing.
    $at = $pub.IndexOf('& (Join-Path $Here ''Publish-VirusTotal.ps1'')')
    Yes '  after the scp, so the file is published before it is sent' (
        $at -gt 0 -and $at -gt $pub.IndexOf('scp failed'))
    Yes '  and nothing from there on can stop the publish' (
        $at -gt 0 -and $pub.Substring($at) -notmatch '(?m)\bthrow\b|\bexit 1\b')
    Yes '  and its header says the key is VT_API_KEY on the machine that ships' (
        $pub -match 'VT_API_KEY')

    # ================================================= and it is written down

    Yes 'installer\setup\README.md is there' (Test-Path -LiteralPath $Readme)
    $doc = [IO.File]::ReadAllText($Readme, (New-Object Text.UTF8Encoding($false)))
    Yes '  and says the upload needs VT_API_KEY' ($doc -match 'VT_API_KEY')
    Yes '  and that a machine without it skips' ($doc -match 'skipped \(VT_API_KEY not set\)')
    Yes '  and gives the two ways Ship calls it' (
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
