<#
  test-3312-signing-runtime.ps1
      pwsh -NoProfile -File .\tests\test-3312-signing-runtime.ps1

  Issue #3312: release.yml's VPS fallback signs on runner 3 with Microsoft's
  signing client, which runs on .NET. Measured by the Cloud Desk on 23 Oct:
  the box had no .NET runtime and no winget, so the run note's winget line
  could not put one there.

  This holds the scripts to the fix:
    1. Bootstrap-VPS.ps1 -IncludeSigningRuntime installs one pinned .NET
       runtime release from Microsoft's download host, checks the SHA-512 and
       the Authenticode signature before it runs the installer, and only when
       asked.
    2. What it calls present is a runtime of 8 or later in the machine wide
       install, and a 6 is not; shown by running its check against planted
       folders.
    3. Install-Runner.ps1 asks a signing runner, and only a signing runner,
       for signtool and the runtime before it installs, and names the
       Bootstrap-VPS line that puts each there; its check is run against the
       same planted folders.
    4. The run note's step 2 runs that line.

  Read only, apart from planted folders under TEMP, which it removes.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$Repo = Split-Path -Parent $PSScriptRoot
$bootPath = Join-Path $Repo 'scripts\vps\Bootstrap-VPS.ps1'
$runnerPath = Join-Path $Repo 'scripts\deploy\Install-Runner.ps1'
$boot = [IO.File]::ReadAllText($bootPath)
$runner = [IO.File]::ReadAllText($runnerPath)
$note = [IO.File]::ReadAllText((Join-Path $Repo 'ops\claude-queue\3312-sign-runner.md'))
$ship = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\release\Setup-ShipMachine.ps1'))

$asts = @{}
foreach ($f in $bootPath, $runnerPath) {
    $errs = $null
    $asts[$f] = [Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    Yes "$(Split-Path $f -Leaf) parses" (@($errs).Count -eq 0)
}
function ParamDefault($ast, [string]$name) {
    $p = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name })
    if ($p.Count -ne 1 -or -not $p[0].DefaultValue) { return $null }
    $p[0].DefaultValue.SafeGetValue()
}

# ---- 1. Bootstrap-VPS.ps1 -IncludeSigningRuntime -----------------------------
Yes 'Bootstrap-VPS.ps1 takes -IncludeSigningRuntime' ($boot -match '\[switch\]\$IncludeSigningRuntime')
Yes '  and installs only when asked' ($boot -match 'if \(\$IncludeSigningRuntime\) \{')
$ver = ParamDefault $asts[$bootPath] 'DotnetRuntimeVersion'
$sha = ParamDefault $asts[$bootPath] 'DotnetRuntimeSha512'
Yes "  one pinned release ($ver)" ("$ver" -match '^\d+\.\d+\.\d+$')
Yes '  of 8 or later, what the signing client asks for' ("$ver" -match '^(\d+)\.' -and [int]$Matches[1] -ge 8)
Yes '  with a SHA-512, 128 hex digits' ("$sha" -match '^[0-9a-fA-F]{128}$')

$from = $boot.IndexOf('if ($IncludeSigningRuntime) {')
$to = $boot.IndexOf('# --- firewall', [Math]::Max(0, $from))
$block = if ($from -ge 0 -and $to -gt $from) { $boot.Substring($from, $to - $from) } else { '' }
Yes 'the runtime block is there, before the firewall' ($block.Length -gt 0)
Yes '  from Microsoft''s download host, at the pinned release' ($block -match [regex]::Escape('https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotnetRuntimeVersion/$name'))
Yes '  never from winget, which the box has not got' ($block -notmatch 'winget')
$hashAt = $block.IndexOf('Get-FileHash -LiteralPath $exe -Algorithm SHA512')
$sigAt = $block.IndexOf('Get-AuthenticodeSignature -LiteralPath $exe')
$runAt = $block.IndexOf('Start-Process -FilePath $exe')
Yes '  the SHA-512 is checked first' ($hashAt -gt 0 -and $sigAt -gt $hashAt)
Yes '  then the signature, both before the installer runs' ($runAt -gt $sigAt)
Yes '  a mismatch or a bad signature deletes the download unrun' (
    ([regex]::Matches($block, 'Remove-Item -LiteralPath \$exe').Count -eq 2) -and
    $block -match "\.Status\)`" -ne 'Valid' -or \`$who -ne \`$dotnetSigner")
# Measured on the box on 23 Oct: .NET's installers are signed by this
# subject, not by "CN=Microsoft Corporation" as Visual Studio's are, and
# #3373's check, which asked for that, refused the real file.
Yes '  by exactly the subject .NET''s installers are signed with' (
    $block -match [regex]::Escape("`$dotnetSigner = 'CN=.NET, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'"))
Yes '  installed quietly with no restart, into a named log' ($block -match "'/install', '/quiet', '/norestart', '/log'")
Yes '  and checked again after it ran' ($block -match '(?s)Start-Process.*\$rt = Test-SigningRuntime.*no runtime of 8 or later')
Yes 'the report says whether the box has a runtime' ($boot -match "'dotnet', \`$\(if \(\`$rt\.Versions\.Count\)")

# ---- 2. what counts as present -----------------------------------------------
$work = Join-Path ([IO.Path]::GetTempPath()) ('t3312rt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$shared = Join-Path $work 'dotnet\shared\Microsoft.NETCore.App'
$savedPf = $env:ProgramW6432
try {
    $fn = @($asts[$bootPath].FindAll({
        param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-SigningRuntime'
    }, $true))
    Yes 'Test-SigningRuntime is there' ($fn.Count -eq 1)
    $signNeedAst = @($asts[$runnerPath].FindAll({
        param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and
                  $n.Left.Extent.Text -eq '$signNeed' -and $n.Right.Extent.Text -like "@'*"
    }, $true))
    Yes 'Install-Runner.ps1 carries the signing runner''s needs as one script' ($signNeedAst.Count -eq 1)
    $signNeedText = if ($signNeedAst.Count -eq 1) { $signNeedAst[0].Right.Expression.Value } else { '' }

    if ($fn.Count -eq 1) {
        . ([scriptblock]::Create($fn[0].Extent.Text))
        $env:ProgramW6432 = $work

        $r = Test-SigningRuntime
        $said = @(& ([scriptblock]::Create($signNeedText)))
        Yes 'no dotnet folder: Bootstrap-VPS finds no runtime' ($r.Versions.Count -eq 0)
        Yes '  and Install-Runner says MISSING dotnet' ($said -contains 'MISSING dotnet')

        New-Item -ItemType Directory -Path (Join-Path $shared '6.0.36') -Force | Out-Null
        $r = Test-SigningRuntime
        $said = @(& ([scriptblock]::Create($signNeedText)))
        Yes 'only a 6: still no runtime the signing client can use' ($r.Versions.Count -eq 0)
        Yes '  and Install-Runner still says MISSING dotnet' ($said -contains 'MISSING dotnet')

        New-Item -ItemType Directory -Path (Join-Path $shared $ver) -Force | Out-Null
        $r = Test-SigningRuntime
        $said = @(& ([scriptblock]::Create($signNeedText)))
        Yes "the pinned ${ver}: Bootstrap-VPS finds it, and only it" ($r.Versions.Count -eq 1 -and $r.Versions[0] -eq $ver)
        Yes '  and Install-Runner says HAVE dotnet' ($said -contains "HAVE dotnet $ver")
    }
} finally {
    $env:ProgramW6432 = $savedPf
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Yes 'the same floor as Setup-ShipMachine.ps1 on One (8)' ($ship -match "\[int\]\`$m\.Groups\[1\]\.Value -ge 8")

# ---- 3. Install-Runner.ps1 asks a signing runner -----------------------------
Yes 'the signing needs go only to a signing runner' ($runner -match "(?s)\`$signNeed = ''\r?\nif \(\`$signs\) \{\r?\n  \`$signNeed = @'")
Yes '  inside the same check the build needs go in' ($runner -match "(?s)'MISSING wpf' \}\r?\n\`$signNeed\r?\n`"@")
Yes '  signtool looked for the way Sign-Artifact.ps1 looks' ($signNeedText -match 'Windows Kits\\10\\bin' -and $signNeedText -match "'signtool\.exe'" -and $signNeedText -match '\\\\x64\\\\')
Yes '  a missing runtime names Bootstrap-VPS -IncludeSigningRuntime' ($runner -match [regex]::Escape("if (`$missing -contains 'dotnet') { `$how += "".\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeSigningRuntime -SkipFirewall'"))
Yes '  a missing signtool names Bootstrap-VPS -IncludeEngineTools' ($runner -match [regex]::Escape("if (`$missing -contains 'signtool') { `$how += "".\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeEngineTools -SkipFirewall'"))

# ---- 4. the run note ---------------------------------------------------------
Yes 'the run note''s step 2 installs with Bootstrap-VPS, not winget' (
    $note -match [regex]::Escape(".\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeSigningRuntime -SkipFirewall'") -and
    $note -notmatch 'winget install')

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
