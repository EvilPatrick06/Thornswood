<#
  ShippedBytes.ps1

  The bytes a file of this checkout goes out as, the same from every machine
  (#2903). Dot-sourced by Go.ps1, Ship.ps1 and Publish-Update.ps1; defines
  functions and nothing else. ASCII, and Windows PowerShell 5.1 as well as 7.

  WHY. Git for Windows checks text files out with CRLF line endings, and
  .gitattributes says otherwise only for the content builders' outputs (#3029),
  so every text file a release carries from the repo (game\plugins, game\ui,
  skyhud.txt) has gone out with CRLF. Measured
  20 Oct on dev 20261020-111032-dev: all 26 of them are the CRLF form of the
  committed file, and the launcher fingerprint the feed holds (launcherInputs,
  #921) is the hash of the CRLF form of the launcher's 100 text files and its
  13 others. A Linux checkout has LF, so a Ship from the cloud (#2754) would
  send all 26 again to every machine with nothing changed, and never find the
  feed's launcher its own. So a text file is read as a Windows checkout holds
  it: every line ending CRLF. One's checkout already is, so nothing it ships or
  fingerprints changes. game\plugins\thornswood-front.js is one of those
  outputs and is checked out LF everywhere since #3029; it still goes out CRLF.

  Text is what git takes for text: no NUL byte in the first 8000. Anything
  else, the plugins, the pictures, the sounds, is its bytes as they are.
#>

function Get-ThornswoodShippedBytes([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    if ([Array]::IndexOf($b, [byte]0, 0, [Math]::Min($b.Length, 8000)) -ge 0) { return , $b }
    # ISO-8859-1 maps each byte to one character and back, so only the line
    # endings move, whatever the encoding of the text.
    $latin = [Text.Encoding]::GetEncoding(28591)
    $t = $latin.GetString($b).Replace("`r`n", "`n").Replace("`n", "`r`n")
    return , $latin.GetBytes($t)
}

# Lower case hex.
function Get-ThornswoodShippedSha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash((Get-ThornswoodShippedBytes $Path)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}

# Writes $Src to $Dst as it ships. What was there is removed first, never
# written through: in an own game folder it can be a hard link into the Steam
# copy (Go.ps1, the menu backdrop).
function Copy-ThornswoodShippedFile([string]$Src, [string]$Dst) {
    $bytes = Get-ThornswoodShippedBytes $Src
    if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Force }
    [IO.File]::WriteAllBytes($Dst, $bytes)
}
