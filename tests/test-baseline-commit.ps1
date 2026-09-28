<#
  test-baseline-commit.ps1

  A Ship commits the baseline it moves, so the next Ship can pull.

  MEASURED 27 SEPTEMBER. Publish-Update writes published.json after its push,
  on purpose, and nothing committed it. The 18:55 dev release left it
  modified in Thornswood-Releases-dev, and the 19:02 Ship stopped on
  "cannot pull with rebase: You have unstaged changes" with nothing published.

  This lifts the block between the baseline commit markers out of the real
  Publish-Update.ps1 and runs it against a throwaway clone and remote:
    1. after a release, published.json is committed as "Baseline <id>" and pushed
    2. a clone left that way by an older Ship is committed before the pull
    3. any other change in the clone is left alone, so the pull still stops
    4. -NoPush touches nothing

  Read only apart from its own temp folder.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$src = Get-Content -Raw (Join-Path $PSScriptRoot '..\scripts\release\Publish-Update.ps1')

$pass = 0; $fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$m = [regex]::Match($src, '(?s)# ==== thornswood baseline commit ====.*?# ==== end thornswood baseline commit ====')
Yes 'the baseline commit block is in Publish-Update.ps1' $m.Success
Yes 'it runs after the release is saved' ($src -match '(?s)Save-State\s+Clear-Pending \$StateFile\s+Push-Baseline \$Id')
Yes 'and before the feed is pulled' ($src -match "Push-Baseline '' -Left\s+\`$pulled = & git -C \`$ReleaseDir pull --rebase")

function Say($m, $c = 'Gray') { }
if ($m.Success) { . ([scriptblock]::Create($m.Value)) }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('baseline-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
function G { & git @args 2>&1 | Out-Null }
try {
    $remote = Join-Path $tmp 'remote.git'
    G init -q --bare $remote
    $ReleaseDir = Join-Path $tmp 'clone'
    G clone -q $remote $ReleaseDir
    G -C $ReleaseDir config user.email t@example.com
    G -C $ReleaseDir config user.name t
    Set-Content (Join-Path $ReleaseDir 'published.json') '{"a":1}'
    Set-Content (Join-Path $ReleaseDir 'version.json') '{}'
    G -C $ReleaseDir add -A
    G -C $ReleaseDir commit -q -m start
    G -C $ReleaseDir push -q origin HEAD
    $NoPush = $false
    function Head-Of { (& git -C $ReleaseDir log -1 --format=%s) }
    function Remote-Head { (& git --git-dir $remote log -1 --format=%s) }
    function Clean { -not (& git -C $ReleaseDir status --porcelain) }

    # 1. after a release
    Set-Content (Join-Path $ReleaseDir 'published.json') '{"a":2}'
    Push-Baseline '20260927-1902-dev'
    Yes 'after a release the baseline is committed as that release' ((Head-Of) -eq 'Baseline 20260927-1902-dev')
    Yes 'and pushed' ((Remote-Head) -eq 'Baseline 20260927-1902-dev')
    Yes 'and the clone is clean for the next pull' (Clean)

    # 2. left by an older Ship
    Set-Content (Join-Path $ReleaseDir 'published.json') '{"a":3}'
    Push-Baseline '' -Left
    Yes 'a baseline an older Ship left is committed before the pull' ((Head-Of) -eq 'Baseline left by an earlier Ship')
    Yes 'without pushing ahead of the pull' ((Remote-Head) -eq 'Baseline 20260927-1902-dev')
    Yes 'so the pull can run' (Clean)

    # 3. anything else is left alone
    Set-Content (Join-Path $ReleaseDir 'published.json') '{"a":4}'
    Set-Content (Join-Path $ReleaseDir 'version.json') '{"hand":1}'
    $before = Head-Of
    Push-Baseline '' -Left
    Yes 'a hand edit beside it is not committed' ((Head-Of) -eq $before -and -not (Clean))
    G -C $ReleaseDir checkout -- version.json
    Push-Baseline '' -Left

    # 4. -NoPush
    $NoPush = $true
    Set-Content (Join-Path $ReleaseDir 'published.json') '{"a":5}'
    $before = Head-Of
    Push-Baseline 'x'
    Yes '-NoPush commits nothing' ((Head-Of) -eq $before)
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
