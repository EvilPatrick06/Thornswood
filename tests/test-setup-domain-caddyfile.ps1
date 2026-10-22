<#
  test-setup-domain-caddyfile.ps1

      pwsh -NoProfile -File .\tests\test-setup-domain-caddyfile.ps1

  Setup-Domain.ps1 sends scripts\deploy\Caddyfile rather than writing its own.

  WHY. It used to write a Caddyfile that proxied the domain to 3001 and
  nothing else. A full run on a new box would have taken the /voice and
  /voice-dev routes off the site, and voice from everybody (issue #543).

  HOW. Reads Setup-Domain.ps1 as text, and runs its own lines that build the
  file against the tracked Caddyfile, with and without -Domain and -Email.
#>
[CmdletBinding()]
param([string]$Repo)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $Repo) { $Repo = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$text = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\deploy\Setup-Domain.ps1'))
$cf = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\deploy\Caddyfile'))

Yes 'the tracked Caddyfile has the voice route' ($cf.Contains('handle_path /voice/*'))
Yes '  and the dev voice route' ($cf.Contains('handle_path /voice-dev/*'))
Yes '  and the site' ($cf.Contains('reverse_proxy 127.0.0.1:3001'))
Yes '  and the box bridge (#2753)' ($cf.Contains('handle_path /box/*') -and $cf.Contains('reverse_proxy 127.0.0.1:7790'))
Yes '  and the box admin App''s setup (#3107)' ($cf.Contains('handle_path /github-app/*') -and $cf.Contains('reverse_proxy 127.0.0.1:7791'))
Yes 'Setup-Domain sends no Caddyfile without the admin App''s route' ($text.Contains("'handle_path /github-app/*'"))
Yes 'Setup-Domain reads scripts\deploy\Caddyfile' ($text -match "Join-Path \`$Here 'Caddyfile'")
Yes '  and no longer writes a Caddyfile of its own' (-not ($text -match '(?m)^\$Domain, www\.\$Domain \{'))
Yes '  and keeps a Caddyfile already on the box before replacing it' ($text.Contains("'.before-'"))

# Run the lines that build the file: from "$Here = $PSScriptRoot" (the second
# one, in the caddy section) to the check for the three routes.
$start = $text.IndexOf('$tracked = Join-Path $Here')
$end = $text.IndexOf('$cfg64 =')
Yes 'the building lines are found' ($start -gt 0 -and $end -gt $start)
if ($start -gt 0 -and $end -gt $start) {
    $code = $text.Substring($start, $end - $start)
    function Build([string]$Domain, [string]$Email) {
        # Setup-Domain and the Caddyfile sit together in scripts\deploy.
        $Here = Join-Path $Repo 'scripts\deploy'
        . ([scriptblock]::Create($code))
        return $caddyfile
    }
    $a = Build 'thornswood.net' ''
    Yes 'with the defaults the file sent is the tracked one' ($a -eq $cf)
    $b = Build 'example.org' 'ops@example.org'
    Yes '  -Domain puts the new name in' ($b.Contains('example.org, www.example.org {') -and -not $b.Contains('thornswood.net'))
    Yes '  -Email replaces the address' ($b -match '(?m)^\s*email ops@example\.org\s*$')
    Yes '  and the voice routes survive both' ($b.Contains('handle_path /voice/*') -and $b.Contains('handle_path /voice-dev/*'))
    $threw = $false
    $saved = $cf
    try {
        $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('ts-caddy-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $tmpDir 'Caddyfile'), "thornswood.net {`n`treverse_proxy 127.0.0.1:3001`n}`n")
        $Tools2 = $tmpDir
        try { $Here = $Tools2; $Domain = 'thornswood.net'; $Email = ''; . ([scriptblock]::Create($code)) } catch { $threw = $true }
    }
    finally { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    Yes '  and a Caddyfile without the voice routes is refused' $threw
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
