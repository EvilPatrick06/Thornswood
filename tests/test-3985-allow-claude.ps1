<#
  test-3985-allow-claude.ps1

      pwsh -NoProfile -File .\tests\test-3985-allow-claude.ps1

  scripts\dev\Allow-Claude.ps1 allows Sync-Client.ps1 only with -Check and
  Setup-SshKey.ps1 only with -Test, and takes out the any-arguments rule it
  wrote for each of them before.

  WHY. Issue #3985. Every script rule it wrote ended in :*, which Claude Code
  reads as "with any arguments". So "-Check only looks" and "-Test only
  looks" did not hold: Sync-Client without -Check copies the client into the
  game folder and can fetch the engine build from GitHub, and Setup-SshKey
  without -Test makes keys, edits the ssh config, and with -NewBox logs in to
  the box. A settings file the old script had already written kept the wide
  rule, so taking the :* off the new rule alone would have changed nothing on
  a machine that ran it.

  HOW. Runs the script against settings files in a temp folder with
  -SettingsPath, never the real one: an old file with the two wide rules and
  a rule of somebody else's, a file with neither, then the same file again,
  and a -Check run that must write nothing.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$allowClaude = Join-Path $repo 'scripts\dev\Allow-Claude.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$sync = 'pwsh -NoProfile -File ./scripts/release/Sync-Client.ps1'
$ssh  = 'pwsh -NoProfile -File ./scripts/vps/Setup-SshKey.ps1'
$wideSync = "Bash($sync" + ':*)'
$wideSsh  = "Bash($ssh" + ':*)'
$narrow = @("Bash($sync -Check)", "Bash($sync -Check -NoPause)", "Bash($ssh -Test)", "Bash($ssh -Test -NoPause)")
$theirs = 'Bash(git status:*)'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-3985-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $tmp -Force)

function Run([string]$settings, [string[]]$more = @()) {
    $out = @(& pwsh -NoProfile -File $allowClaude -SettingsPath $settings -NoPause @more 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}
function Allow([string]$settings) {
    return @(([IO.File]::ReadAllText($settings) | ConvertFrom-Json).permissions.allow | ForEach-Object { [string]$_ })
}
function Write-Settings([string]$path, [string[]]$allow) {
    $doc = [pscustomobject]@{ model = 'kept'; permissions = [pscustomobject]@{ allow = $allow; additionalDirectories = @() } }
    [IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
}

try {
    # A file the old script wrote: both wide rules, with somebody else's
    # rule between them.
    $old = Join-Path $tmp 'old.json'
    Write-Settings $old @($wideSync, $theirs, $wideSsh)

    $r = Run $old @('-Check')
    Yes '-Check exits 0' ($r.Code -eq 0)
    Yes '-Check says 2 would be removed' ($r.Out -match 'would be added and 2 removed')
    $a = Allow $old
    Yes '-Check wrote nothing' ((($a -join '|') -eq (@($wideSync, $theirs, $wideSsh) -join '|')))

    $r = Run $old
    Yes 'a real run exits 0' ($r.Code -eq 0)
    $a = Allow $old
    Yes 'the any-arguments Sync-Client rule is gone' ($a -notcontains $wideSync)
    Yes 'the any-arguments Setup-SshKey rule is gone' ($a -notcontains $wideSsh)
    foreach ($n in $narrow) { Yes "$n is allowed" ($a -contains $n) }
    Yes 'it says each rule it removed' ($r.Out -match [regex]::Escape($wideSync) -and $r.Out -match [regex]::Escape($wideSsh))
    Yes 'somebody else''s rule is kept, first' ($a[0] -eq $theirs)
    Yes 'no other rule names Sync-Client or Setup-SshKey' (@($a | Where-Object { ($_ -match 'Sync-Client|Setup-SshKey') -and ($narrow -notcontains $_) }).Count -eq 0)
    Yes 'every other script rule it adds still allows any arguments' (@($a | Where-Object { $_ -match 'Check-Build\.ps1:\*\)$' }).Count -eq 1)
    $doc = [IO.File]::ReadAllText($old) | ConvertFrom-Json
    Yes 'the file''s other keys are kept' ($doc.model -eq 'kept')
    Yes 'it kept the old file beside it' (@(Get-ChildItem -LiteralPath $tmp -Filter 'old.json.before-*').Count -eq 1)

    $r = Run $old
    Yes 'a second run changes nothing' ($r.Code -eq 0 -and $r.Out -match 'Nothing to change')
    Yes 'and leaves the rules as they were' ((Allow $old).Count -eq $a.Count)

    # A machine that never ran it.
    $new = Join-Path $tmp 'new.json'
    $r = Run $new
    Yes 'a new file is written' ($r.Code -eq 0 -and (Test-Path -LiteralPath $new))
    $a = Allow $new
    foreach ($n in $narrow) { Yes "a new file allows $n" ($a -contains $n) }
    Yes 'a new file has no any-arguments rule for either' ($a -notcontains $wideSync -and $a -notcontains $wideSsh)
    Yes 'the closing line no longer says nothing leaves this machine' ($r.Out -notmatch 'lets anything leave this machine')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Yes 'no em dash in this harness' (-not ([IO.File]::ReadAllText($PSCommandPath)).Contains([string][char]0x2014))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
