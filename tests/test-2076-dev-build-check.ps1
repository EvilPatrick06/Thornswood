# test-2076-dev-build-check.ps1
#
#     pwsh -NoProfile -File .\tests\test-2076-dev-build-check.ps1
#
# Deploy-DevGamemode.ps1 sends a gamemode only onto the server build its
# commit records (#2076), the comparison Deploy-Server -GamemodeOnly makes for
# live (#1089). Main since #2060 records engine 9fd1f69b and its gamemode no
# longer handles drops (#1719); both servers ran 720a5f7c, so a dev deploy from
# main would have lost every dropped extra on dev.
#
# Get-ThornswoodBoxBuildProblem (ServerBuild.ps1) is called with stand-in
# record sums, and the script is read for where it asks: before the artifact
# leaves this machine, and not on -PutBack, which sends no gamemode.
# Read only. Nothing connects to anything.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\deploy\ServerBuild.ps1')

$pass = 0; $fail = 0
function Yes([string]$what, [bool]$cond) {
  if ($cond) { $script:pass++; Write-Host ('PASS  ' + $what) }
  else { $script:fail++; Write-Host ('FAIL  ' + $what) }
}

$old = ('a' * 64); $new = ('b' * 64)
$put = 'scripts\release\Publish-Server.ps1 -Channel dev'
$same = Get-ThornswoodBoxBuildProblem $new '9fd1f69b6c3893e47511fd3f49ce914737d5d633' $new '9fd1f69b6c3893e47511fd3f49ce914737d5d633' 'dev server' $put
Yes 'the build the commit records: no problem' ($null -eq $same)
$other = Get-ThornswoodBoxBuildProblem $old '3a32e961aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' $new '9fd1f69b6c3893e47511fd3f49ce914737d5d633' 'dev server' $put
Yes 'another build: refused, naming both commits and how to put the right one on' (
  $other -and $other -match 'commit 720a5f7c' -and $other -match 'commit 9fd1f69b' -and $other.Contains($put))
$none = Get-ThornswoodBoxBuildProblem 'none' '' $new '9fd1f69b' 'dev server' $put
Yes 'no record on the box: refused' ($none -and $none -match 'no server-build.json')
$silent = Get-ThornswoodBoxBuildProblem '' '' $new '9fd1f69b' 'dev server' $put
Yes 'no answer from the box: refused' ($silent -and $silent -match 'did not say')
$unread = Get-ThornswoodBoxBuildProblem $old '' $new '9fd1f69b' 'dev server' $put
Yes 'another build whose commit cannot be read: still refused' ($unread -and $unread -match 'an unreadable one')

# The record sum ignores line endings, as on the box.
$lf = [Text.Encoding]::UTF8.GetBytes("{`n  ""a"": 1`n}`n")
$crlf = [Text.Encoding]::UTF8.GetBytes("{`r`n  ""a"": 1`r`n}`r`n")
Yes 'a record sums the same with either line ending' ((Get-ThornswoodRecordSum $lf) -eq (Get-ThornswoodRecordSum $crlf))

$src = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Deploy-DevGamemode.ps1')).Replace("`r`n", "`n")
$guard = $src.IndexOf("if (-not `$PutBack) {`n`$alsoSends")
$ask = $src.IndexOf('Get-ThornswoodBoxBuildProblem $devBoxSum')
$send = $src.IndexOf('Send-ThornswoodArtifact -Artifact $artifact')
Yes 'Deploy-DevGamemode asks the dev box which build it runs' ($ask -gt 0)
Yes 'after the -PutBack guard, so -PutBack, which sends no gamemode, is not asked' ($guard -gt 0 -and $ask -gt $guard)
Yes 'before the artifact is sent, so a refusal sends nothing' ($send -gt $ask)
Yes 'and a refusal stops the run' ($src.IndexOf("throw 'The dev server does not run the server build this gamemode is written for.", $ask) -gt $ask)

Write-Host ''
Write-Host ("$pass passed, $fail failed")
if ($fail) { exit 1 }
