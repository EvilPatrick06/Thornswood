<#
  test-virustotal-publish.ps1

      pwsh -NoProfile -File .\tests\test-virustotal-publish.ps1

  Publish-VirusTotal.ps1 keeps its contract and never stops a release.

  WHY THIS EXISTS. The Downloads page prints the installer's SHA-256 with a
  link to VirusTotal's report on that hash, and a hash nobody ever sent to
  VirusTotal has no report behind that link. Publish-VirusTotal.ps1 sends it
  and leaves one community comment saying what the file is, which is the only
  signal we can add to the machine learning verdicts while signing is deferred
  (issue #390, docs\VIRUSTOTAL-FALSE-POSITIVE.md).

  Two failures are worth a harness. One is a release script that stops a
  release: no key on this machine, VirusTotal rate limiting the free tier, or a
  comment that will not post are all ordinary and none of them is a reason for
  a red build, so each has to exit 0. The other is commenting on the wrong
  report, which is worse than not commenting, so a -Sha256 that is not the hash
  of the file is refused.

  What runs here never touches the network. The three behaviours it runs for
  real all stop before the first request: no key, no file, and a hash that does
  not match. The rest is read off the script's own text.

  Read only. Writes one small file into the temp folder and removes it.
#>
[CmdletBinding()]
param([string]$ScriptPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# This test lives in tests\; repo root is one level up.
$repoRoot = Split-Path -Parent $Here
if (-not $ScriptPath) { $ScriptPath = Join-Path $repoRoot 'scripts\release\Publish-VirusTotal.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

Yes 'Publish-VirusTotal.ps1 is where this expects it' (Test-Path -LiteralPath $ScriptPath)
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    exit 1
}
$Utf8 = New-Object Text.UTF8Encoding($false)
$src = [IO.File]::ReadAllText($ScriptPath, $Utf8)

# ---- 1. it parses, and its contract is the one the callers were given ------
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, $ScriptPath, [ref]$tokens, [ref]$errors)
Yes 'it parses' (@($errors).Count -eq 0)
$declared = @()
if ($ast.ParamBlock) { $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
Yes 'it takes -Path' ($declared -contains 'Path')
Yes 'and -Sha256, for a caller that already measured it' ($declared -contains 'Sha256')
$help = $ast.GetHelpContent()
Yes 'it has a help block PowerShell recognises' ($null -ne $help)
Yes 'with a synopsis, which is the row scripts\README.md carries' (
    $null -ne $help -and ([string]$help.Synopsis).Trim().Length -gt 0)
$documented = @()
if ($null -ne $help) {
    foreach ($k in $help.Parameters.Keys) {
        if (([string]$help.Parameters[$k]).Trim()) { $documented += $k.ToUpperInvariant() }
    }
}
$missing = @($declared | Where-Object { $documented -notcontains $_.ToUpperInvariant() })
Yes ('every parameter has a .PARAMETER of its own' +
     $(if ($missing.Count) { ', missing: ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
Yes 'the key comes from VT_API_KEY in the environment' ($src -match '\$env:VT_API_KEY')
Yes 'and the key itself is never printed' (-not ($src -match 'Say[^\r\n]*\$ApiKey'))

# ---- 2. what it does with no key, no file, and the wrong hash -------------
# The host this harness is running in, so the child is the same PowerShell.
$hostExe = ''
try { $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $hostExe = '' }
if (-not $hostExe) {
    $c = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $c) { $c = Get-Command powershell -ErrorAction SilentlyContinue }
    if ($c) { $hostExe = $c.Source }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('vt-test-' + [Guid]::NewGuid().ToString('N') + '.bin')
[IO.File]::WriteAllText($tmp, 'not an installer, just something to hash', $Utf8)
$gone = Join-Path ([IO.Path]::GetTempPath()) ('vt-missing-' + [Guid]::NewGuid().ToString('N') + '.bin')

function Invoke-Child([string[]]$sArgs) {
    $was = $env:VT_API_KEY
    $env:VT_API_KEY = ''
    try {
        $out = & $hostExe -NoProfile -File $ScriptPath @sArgs 2>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
    } finally { $env:VT_API_KEY = $was }
}

if (-not $hostExe) {
    Write-Host 'SKIP  no PowerShell host to run the script in, so only its text was read'
} else {
    try {
        $noKey = Invoke-Child @('-Path', $tmp)
        Yes 'with no VT_API_KEY it exits 0, so a release carries on' ($noKey.Code -eq 0)
        Yes 'and says that is why nothing was sent' ($noKey.Out -match '(?i)no VT_API_KEY')
        Yes 'and says nothing was uploaded and no comment was left' (
            $noKey.Out -match '(?i)nothing was uploaded' -and $noKey.Out -match '(?i)no comment')
        Yes 'it still prints the hash and the report address' (
            $noKey.Out -match '[0-9a-f]{64}' -and
            $noKey.Out -match 'https://www\.virustotal\.com/gui/file/[0-9a-f]{64}')

        $missingFile = Invoke-Child @('-Path', $gone)
        Yes 'a file that is not there is a real failure, exit 1' ($missingFile.Code -eq 1)
        Yes 'and it says which file' ($missingFile.Out -match [regex]::Escape((Split-Path $gone -Leaf)))

        $wrongHash = Invoke-Child @('-Path', $tmp, '-Sha256', ('0' * 64))
        Yes 'a -Sha256 that is not the hash of the file is refused, exit 1' ($wrongHash.Code -eq 1)
        Yes 'and it prints what the file actually measured' ($wrongHash.Out -match '(?i)measured [0-9a-f]{64}')
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# ---- 3. the soft failures, read off the script ----------------------------
# Everything from the comment onwards is soft: the upload is the part that had
# to happen, and a comment that will not post is worth a line and nothing more.
$iComment = $src.IndexOf('# -------------------------------------------------------------- the comment')
Yes 'the comment section is marked off' ($iComment -gt 0)
if ($iComment -gt 0) {
    $tail = $src.Substring($iComment)
    Yes 'nothing after it exits non-zero' (-not ($tail -match '(?m)^\s*exit 1\s*$'))
    Yes 'it posts the comment through the v3 comments endpoint' ($tail -match "/comments")
    Yes 'the post is wrapped in a try' ($tail -match '(?s)try \{.{0,800}?/comments')
    Yes 'and a comment that will not post says so and carries on' (
        $tail -match '(?i)the comment did not post')
    Yes 'a comment already on the report is not an error either' ($tail -match '409')
    Yes 'the script ends on exit 0' ($src.TrimEnd().EndsWith('exit 0'))
}
Yes 'rate limiting is soft everywhere it can happen' (
    @([regex]::Matches($src, '429')).Count -ge 3)
Yes 'a key VirusTotal refuses is soft too' ($src -match '(?i)refused the key')
Yes 'the soft exits all exit 0' (
    $src -match '(?s)function Stop-Soft.{0,300}?exit 0')

# ---- 4. what the comment says ---------------------------------------------
# The vendors read this. It has to name the program, the site and the state of
# the signing, in the same words as the version resource in Bootstrap.cs.
$iText = $src.IndexOf('function Get-DefaultComment')
Yes 'there is a default comment' ($iText -gt 0)
if ($iText -gt 0) {
    $text = $src.Substring($iText, [Math]::Min(1600, $src.Length - $iText))
    Yes 'it names Thornswood Setup, as the version resource does' ($text -match 'Thornswood Setup')
    Yes 'it names thornswood.net' ($text -match 'thornswood\.net')
    Yes 'it says this is the first-run installer' ($text -match '(?i)first-run installer')
    Yes 'and that it is not signed yet' ($text -match '(?i)not Authenticode signed yet')
}
Yes 'the script has no em dash in it' (-not $src.Contains([string][char]0x2014))

# ---- 5. the page it belongs to --------------------------------------------
$page = Join-Path $repoRoot 'docs\VIRUSTOTAL-FALSE-POSITIVE.md'
Yes 'docs\VIRUSTOTAL-FALSE-POSITIVE.md is there' (Test-Path -LiteralPath $page)
if (Test-Path -LiteralPath $page) {
    $doc = [IO.File]::ReadAllText($page, $Utf8)
    Yes 'and it names this script as the way the comment gets posted' (
        $doc.Contains('Publish-VirusTotal.ps1'))
}
# scripts\README.md is generated from the scripts, so a new one that is not in
# it fails test-script-index.ps1 on the nightly run. Caught here beside the
# script instead, where it is obvious what to do about it.
$index = Join-Path $repoRoot 'scripts\README.md'
Yes 'scripts\README.md lists it' (
    (Test-Path -LiteralPath $index) -and
    ([IO.File]::ReadAllText($index, $Utf8)).Contains('release/Publish-VirusTotal.ps1'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
