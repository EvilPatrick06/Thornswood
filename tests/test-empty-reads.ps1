<#
  test-empty-reads.ps1

      powershell -NoProfile -File .\tests\test-empty-reads.ps1
      pwsh -NoProfile -File .\tests\test-empty-reads.ps1

  Get-Content -Raw hands back $null for an empty file, not '', so
  (Get-Content x -Raw).Trim() throws "You cannot call a method on a
  null-valued expression", and under Stop that ends the script before the
  message written for an empty file. Each case puts an empty file where a
  script reads one:
    Restore-Backup.ps1 and vps-nightly-backup.ps1  the passphrase file
    Set-DevNews.ps1 -Check                         bot\dev-channel.txt
    Discord-Hook.ps1 -Check                        the local webhook copy
    Publish-News.ps1                               news-from.txt (lifted)
    Source-Notice.ps1 Get-SourceNoticeEntries      client-build.json
    Package-Thornswood.ps1 Get-SourceNotice        both build records (lifted)
  Scratch folders and scratch copies only; the VPS is a stub that answers
  NOHOOK, and nothing reaches the network.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Shell = (Get-Process -Id $PID).Path
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-empty-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($T)
function Empty([string]$p) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p)); [IO.File]::WriteAllBytes($p, [byte[]]@()); return $p }
function Child([string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $o = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File @a 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $o }
}
$null_ = 'null-valued'
try {
    # ---- the passphrase files ----------------------------------------------------
    $key = Empty (Join-Path $T 'key.txt')
    $enc = Join-Path $T 'backup.enc'; [IO.File]::WriteAllBytes($enc, [byte[]](1..64))
    $r = Child @((Join-Path $Repo 'scripts\vps\Restore-Backup.ps1'), '-Backup', $enc, '-KeyFile', $key, '-Work', (Join-Path $T 'work'), '-NoPause')
    Yes 'Restore-Backup: an empty passphrase file says it is empty' ($r.Code -eq 1 -and $r.Out -match 'passphrase file at .* is empty' -and $r.Out -notmatch $null_)
    $out = Join-Path $T 'backup-out'
    $r = Child @((Join-Path $Repo 'scripts\vps\vps-nightly-backup.ps1'), '-KeyFile', $key, '-Out', $out)
    Yes 'vps-nightly-backup: an empty passphrase file says it is empty' ($r.Code -ne 0 -and $r.Out -match 'backup passphrase file is empty' -and $r.Out -notmatch $null_)
    Yes '  and makes no archive folder' (-not (Test-Path -LiteralPath $out))

    # ---- Set-DevNews -Check, from a scratch copy ----------------------------------
    $sd = Join-Path $T 'sd'
    [void][IO.Directory]::CreateDirectory((Join-Path $sd 'scripts\ops'))
    [IO.File]::Copy((Join-Path $Repo 'scripts\ops\Set-DevNews.ps1'), (Join-Path $sd 'scripts\ops\Set-DevNews.ps1'))
    $null = Empty (Join-Path $sd 'bot\dev-channel.txt')
    $r = Child @((Join-Path $sd 'scripts\ops\Set-DevNews.ps1'), '-Check', '-NoPause')
    Yes 'Set-DevNews -Check: an empty dev-channel.txt reads as no channel id' ($r.Out -match 'no channel id in bot' -and $r.Out -notmatch $null_)

    # ---- Discord-Hook -Check, from a scratch copy, VPS stubbed -------------------
    $dh = Join-Path $T 'dh'
    foreach ($d in 'scripts\ops', 'scripts\vps') { [void][IO.Directory]::CreateDirectory((Join-Path $dh $d)) }
    [IO.File]::Copy((Join-Path $Repo 'scripts\ops\Discord-Hook.ps1'), (Join-Path $dh 'scripts\ops\Discord-Hook.ps1'))
    foreach ($f in 'Send-Secret.ps1', 'Send-Script.ps1', 'Vps.ps1') { [IO.File]::Copy((Join-Path $Repo "scripts\vps\$f"), (Join-Path $dh "scripts\vps\$f")) }
    $stub = Join-Path $dh 'remote-stub.ps1'
    [IO.File]::WriteAllText($stub, "param([string]`$Body, `$Secret)`n'NOHOOK'`nexit 0`n")
    $null = Empty (Join-Path $dh 'bot\dev-webhook.txt')
    $r = Child @((Join-Path $dh 'scripts\ops\Discord-Hook.ps1'), '-Name', 'dev', '-Check', '-RemoteScript', $stub)
    Yes 'Discord-Hook -Check: an empty local copy reads as no webhook' ($r.Code -eq 0 -and $r.Out -match 'no dev webhook on the VPS yet' -and $r.Out -notmatch $null_)

    # ---- Publish-News, its news-from.txt read lifted out --------------------------
    $pn = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'scripts\ops\Publish-News.ps1'), [ref]$null, [ref]$null)
    $ifFrom = $pn.Find({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '-not $From' }, $true)
    Yes 'the news-from.txt read lifted out of Publish-News.ps1' ($null -ne $ifFrom)
    $Here = Join-Path $T 'pn'; $null = Empty (Join-Path $Here ('news-from' + '.txt'))   # built: the file is Publish-News's, not the repository's; $From = ''
    $threw = ''
    try { & { $ErrorActionPreference = 'Stop'; . ([scriptblock]::Create($ifFrom.Extent.Text)); $script:gotFrom = $From } } catch { $threw = $_.Exception.Message }
    Yes ("Publish-News: an empty news-from.txt is no cut-off, not an error ({0})" -f $threw) (-not $threw -and $script:gotFrom -eq '')

    # ---- the build records ---------------------------------------------------------
    . (Join-Path $Repo 'scripts\release\Source-Notice.ps1')
    $client = Empty (Join-Path $T 'records\client-build.json')
    $one = [string]@($SourceNoticeFiles.Keys)[0]
    $threw = ''
    try { $null = Get-SourceNoticeEntries $client @($one) 'runtime' (Join-Path $T 'lic') } catch { $threw = $_.Exception.Message }
    Yes ("Source-Notice: an empty client-build.json is named as empty ({0})" -f $threw) ($threw -eq "$client is empty")
    [IO.File]::WriteAllText($client, "  `r`n")
    $threw = ''
    try { $null = Get-SourceNoticeEntries $client @($one) 'runtime' (Join-Path $T 'lic') } catch { $threw = $_.Exception.Message }
    Yes '  and so is one holding only white space' ($threw -eq "$client is empty")

    $pk = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'scripts\release\Package-Thornswood.ps1'), [ref]$null, [ref]$null)
    $fn = $pk.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-SourceNotice' }, $true)
    Yes 'Get-SourceNotice lifted out of Package-Thornswood.ps1' ($null -ne $fn)
    . ([scriptblock]::Create($fn.Extent.Text))
    $server = Join-Path $T 'records\server-build.json'
    [IO.File]::Copy((Join-Path $Repo 'records\server-build.json'), $server)
    [IO.File]::WriteAllBytes($client, [byte[]]@())
    $threw = ''
    try { & { Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'; $null = Get-SourceNotice $client $server (Join-Path $T 'payload') } } catch { $threw = $_.Exception.Message }
    Yes ("Package-Thornswood: an empty client record is named as empty ({0})" -f $threw) ($threw -eq "$client is empty")
    [IO.File]::Copy((Join-Path $Repo 'records\client-build.json'), $client, $true)
    [IO.File]::WriteAllBytes($server, [byte[]]@())
    $threw = ''
    try { & { Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'; $null = Get-SourceNotice $client $server (Join-Path $T 'payload') } } catch { $threw = $_.Exception.Message }
    Yes ("  and so is an empty server record ({0})" -f $threw) ($threw -eq "$server is empty")
}
finally { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }