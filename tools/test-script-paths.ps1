<#
  test-script-paths.ps1

      pwsh -NoProfile -File .\tools\test-script-paths.ps1

  Every path a script builds from its own folder or the repository points at
  something that is in the repository, apart from the files that are made at
  run time or kept out of git on purpose, which are listed below with why.

  WHY. The repository is being reorganised in phases (issue #440 on the
  board), and the scripts that build a release find what they ship by joining
  a path onto their own folder. Build-Launcher, Package-Thornswood and Go.ps1
  only warn in yellow when one of those files is not there, and carry on, so
  a move that missed one path would ship a launcher without its art or a
  pack without its overlays, and nobody would notice until a tester did. This
  turns that into a failed check before anything is built.

  HOW. Every tools\*.ps1 is read as text for Join-Path $Here, $PSScriptRoot,
  $Tools, $RepoDir or $Repo with a single quoted path, which is how every
  script here names its neighbours. A path with a variable or a wildcard in it
  is not followed. Read only.
#>
[CmdletBinding()]
param([string]$Tools)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Tools) { $Tools = $Here }
$repo = Split-Path -Parent $Tools

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# Not in git on purpose, by path from the repository root, and why.
$notInGit = @{
    '.claude/settings.json'         = 'written by Allow-Claude.ps1 on the machine it runs on'
    '.git'                          = 'the repository itself'
    'version.json'                  = 'the releases clone''s feed; the scripts that name it are pointed at that clone'
    'tools/mod-audit.json'          = 'what Audit-Mods.ps1 writes, ignored by git'
    'tools/setup-stub.exe'          = 'built by Build-Launcher.ps1, ignored with every exe'
    'tools/setup-stub.new.exe'      = 'Build-Launcher.ps1''s scratch copy while it builds the stub'
    'tools/signing.json'            = 'a machine''s signing settings, ignored by git'
    'tools/backup-key.txt'          = 'the backup passphrase, a secret kept out of git'
    'tools/thornswood-front.zip'    = 'the front build, made outside the repository and dropped beside Go.ps1'
    'bot/announced.json'  = 'what Publish-Discord.ps1 has posted, written on the machine that ships'
    'bot/dev-webhook.txt' = 'a webhook, a secret kept out of git'
    'bot/news-webhook.txt'= 'a webhook, a secret kept out of git'
    'tools/asked.txt'               = 'a test''s own scratch file'
    'tools/app/app.ico'             = 'the second place the icon lookups try; the icon is tools/app.ico'
}
# Setup-Thornswood.ps1 runs inside an unpacked installer, where its own folder
# is the installer's, not tools, so its paths are the installer's layout.
$skipScripts = @('Setup-Thornswood.ps1')

$tracked = @{}
foreach ($t in (& git -C $repo ls-files)) {
    $tracked[$t] = $true
    $p = $t
    while ($p.Contains('/')) { $p = $p.Substring(0, $p.LastIndexOf('/')); $tracked[$p] = $true }
}
Yes ('git lists the tracked files ({0})' -f $tracked.Count) ($tracked.Count -gt 100)

$rx = [regex]"Join-Path\s+\`$(Here|PSScriptRoot|Tools|RepoDir|Repo)\s+'([^'`$``*]+)'"
$found = 0
$missing = @()
$allowedSeen = @{}
foreach ($f in Get-ChildItem -LiteralPath $Tools -Filter *.ps1 -File) {
    if ($skipScripts -contains $f.Name) { continue }
    $text = [IO.File]::ReadAllText($f.FullName)
    foreach ($m in $rx.Matches($text)) {
        $rel = $m.Groups[2].Value.Replace('\', '/').Trim('/')
        $full = if ($m.Groups[1].Value -in 'RepoDir', 'Repo') { $rel } else { 'tools/' + $rel }
        # tools/../bot/x is bot/x: a script beside tools reaches the rest of the
        # repository that way since the folders began to move.
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($seg in $full.Split('/')) {
            if ($seg -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) } }
            elseif ($seg -and $seg -ne '.') { $parts.Add($seg) }
        }
        $full = $parts -join '/'
        if ($tracked.ContainsKey($full)) { $found++; continue }
        if ($notInGit.ContainsKey($full)) { $allowedSeen[$full] = $true; continue }
        $missing += ('{0} (named in {1})' -f $full, $f.Name)
    }
}
$missing = @($missing | Sort-Object -Unique)
foreach ($m in $missing) { Write-Host "      not in the repository: $m" }
Yes ("every path the scripts build is in the repository ($found found)") ($missing.Count -eq 0)
Yes ('the scripts still build a few hundred such paths, so the pattern still matches how they are written') ($found -ge 200)
$stale = @($notInGit.Keys | Where-Object { -not $allowedSeen.ContainsKey($_) } | Sort-Object)
foreach ($s in $stale) { Write-Host "      nothing names this any more, take it off the list: $s" }
Yes 'every entry on the not-in-git list is still named by a script' ($stale.Count -eq 0)

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
