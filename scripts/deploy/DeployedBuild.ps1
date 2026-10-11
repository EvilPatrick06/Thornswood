<#
  DeployedBuild.ps1

  What each server actually runs, where the site can read it. After a
  successful server deploy (or put-back), Deploy-Server.ps1 calls
  Save-ThornswoodDeployedBuild. On the box, that reads the server root's own
  server-build.json (the record that went up with the files) and sets that
  channel's entry in the docs app's data\deployed-build.json:

    { "live": { "commit": "<40 hex>", "binary": "...", "sha256": "...", "at": "<UTC>" },
      "dev":  { ... } }

  site/server.js reads that file each time /credits is served and fills the
  "Both servers still run" sentence from it. With no file, or one it cannot
  read, the page keeps its hand-written text.

  Writing it never fails a deploy: the server is already swapped in and
  answering by then, so a problem here is printed and the deploy goes on.
#>

# The far side. Kept as text so it runs on the box through
# Invoke-ThornswoodArtifactRemote, and a test can run the same text locally.
$ThornswoodDeployedBuildText = @'
function Write-ThornswoodDeployedBuild([string]$RecordPath, [string]$OutPath, [string]$Channel, [string]$At) {
  if ($Channel -ne 'live' -and $Channel -ne 'dev') { 'DEPLOYED BUILD NOT WRITTEN: no channel ' + $Channel; return }
  if (-not (Test-Path -LiteralPath $RecordPath)) { 'DEPLOYED BUILD NOT WRITTEN: there is no ' + $RecordPath; return }
  try { $rec = [IO.File]::ReadAllText($RecordPath) -replace '^\uFEFF', '' | ConvertFrom-Json }
  catch { 'DEPLOYED BUILD NOT WRITTEN: ' + $RecordPath + ' is not JSON'; return }
  $commit = ''
  if ($rec.PSObject.Properties['source'] -and $rec.source -and $rec.source.PSObject.Properties['commit']) { $commit = [string]$rec.source.commit }
  if ($commit -notmatch '^[0-9a-f]{40}$') { 'DEPLOYED BUILD NOT WRITTEN: ' + $RecordPath + ' names no 40-character commit'; return }
  # Only where the site is: a box (or a test machine) with no docs app gets
  # no folder made for it.
  $app = Split-Path -Parent (Split-Path -Parent $OutPath)
  if (-not (Test-Path -LiteralPath (Join-Path $app 'server.js'))) { 'DEPLOYED BUILD NOT WRITTEN: there is no site at ' + $app; return }
  $doc = [ordered]@{}
  if (Test-Path -LiteralPath $OutPath) {
    try {
      $old = [IO.File]::ReadAllText($OutPath) -replace '^\uFEFF', '' | ConvertFrom-Json
      foreach ($k in 'live', 'dev') { if ($old.PSObject.Properties[$k] -and $old.$k) { $doc[$k] = $old.$k } }
    } catch { }
  }
  $doc[$Channel] = [ordered]@{ commit = $commit; binary = [string]$rec.binary; sha256 = [string]$rec.sha256; at = $At }
  $dir = Split-Path -Parent $OutPath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = $OutPath + '.new'
  [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
  Move-Item -LiteralPath $tmp -Destination $OutPath -Force
  'DEPLOYED BUILD WRITTEN ' + $Channel + ' ' + $commit
}
'@

# The dev server lives in a root ending -Dev (C:/Thornswood-Server-Dev).
function Get-ThornswoodDeployedChannel([string]$Root) {
  if ($Root.Replace('\', '/').TrimEnd('/') -match '-Dev$') { return 'dev' }
  return 'live'
}

function Get-ThornswoodDeployedBuildScript([string]$Root, [string]$DocsRoot = 'C:/Thornswood-Docs', [string]$At = '') {
  if (-not $At) { $At = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
  $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
  $rootWin = $Root.Replace('/', '\').TrimEnd('\')
  $docsWin = $DocsRoot.Replace('/', '\').TrimEnd('\')
  return $ThornswoodDeployedBuildText + "`r`n" +
    ('Write-ThornswoodDeployedBuild ' + (& $q ($rootWin + '\server-build.json')) + ' ' +
     (& $q ($docsWin + '\data\deployed-build.json')) + ' ' + (& $q (Get-ThornswoodDeployedChannel $Root)) + ' ' + (& $q $At)) + "`r`n"
}

function Save-ThornswoodDeployedBuild([string]$Target, [string[]]$SshArgs, [string]$Root, [string]$DocsRoot = 'C:/Thornswood-Docs') {
  $said = @()
  try { $said = @(Invoke-ThornswoodArtifactRemote $Target $SshArgs (Get-ThornswoodDeployedBuildScript $Root $DocsRoot)) }
  catch { $said = @('DEPLOYED BUILD NOT WRITTEN: ' + $_.Exception.Message) }
  $ok = @($said | Where-Object { "$_" -like 'DEPLOYED BUILD WRITTEN *' })
  if ($ok.Count) { Write-Host ('  the site now reads that the ' + (Get-ThornswoodDeployedChannel $Root) + ' server runs ' + ($ok[0] -split ' ')[-1].Substring(0, 8)) -ForegroundColor DarkGray }
  else {
    $why = @($said | Where-Object { "$_" -like 'DEPLOYED BUILD NOT WRITTEN*' })
    Write-Host ('  the site''s deployed-build.json was not updated (' + $(if ($why.Count) { $why[0] } else { 'no answer' }) + '); the credits page keeps what it said') -ForegroundColor Yellow
  }
  return $said
}
