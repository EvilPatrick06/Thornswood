<#
.SYNOPSIS
  Takes what each picture and recording already in the site's uploads says about where and when it was made out of it, the way the site now does to every upload as it lands (#3648).

.DESCRIPTION
  Runs ON the VPS, as Administrator, sent there by Remote.ps1:

      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Strip-Uploads.ps1

  WHY. Until #3648 the site kept every gallery picture and recording byte for
  byte and served it to anyone at /shot/<name>, so a phone or camera picture
  went out with its Exif, GPS position included. The site and the launcher
  now take those blocks out before a file is kept or sent; this does the
  same to the files sent before that. It runs the deployed site's own code,
  `node server.js --strip-metadata uploads`, so there is one copy of the
  rules (stripMedia in site\server.js), and the site keeps running: each file
  is written beside itself and renamed over it.

  It prints one line for each file it changed (its name, the kinds of block
  taken out, and whether one held a position, never what a block said) or
  could not walk, then the counts: files looked at, files changed, files that
  held a position, files that could not be cleaned. It exits 0 when every
  file is clean now and 1 when one is not, which is left as it was and
  named, for staff to look at.

  Run it again after a nightly backup from before #3648 is put back
  (Restore-Box.ps1), since that brings back the files as they were. The
  backups themselves are not rewritten; they go when their keeping time on
  the privacy page is up.

  It refuses, and changes nothing, when the site at -Root has no
  --strip-metadata (a site deployed before #3648): run against that,
  node server.js would start a second site instead.

.PARAMETER Root
  The site's folder, with server.js and uploads in it.
#>
[CmdletBinding()]
param([string]$Root = 'C:\Thornswood-Docs')

$ErrorActionPreference = 'Stop'
$server = Join-Path $Root 'server.js'
$uploads = Join-Path $Root 'uploads'
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
    Write-Host "No site at ${Root}: there is no server.js there. Nothing was changed."
    exit 1
}
if (-not (Select-String -LiteralPath $server -SimpleMatch -Pattern "'--strip-metadata'" -Quiet)) {
    Write-Host "The site at $Root is from before #3648 and has no --strip-metadata. Deploy the site first (Deploy-Docs.ps1 -Site). Nothing was changed."
    exit 1
}
if (-not (Test-Path -LiteralPath $uploads -PathType Container)) {
    Write-Host "The site at $Root has no uploads folder, so there is nothing to clean."
    exit 0
}
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host 'node is not on the PATH. Nothing was changed.'
    exit 1
}

& $nodeCmd.Source $server --strip-metadata $uploads
exit $LASTEXITCODE
