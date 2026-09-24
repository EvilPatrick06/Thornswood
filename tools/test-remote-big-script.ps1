<#
  test-remote-big-script.ps1

  A 10 KB script reaches the VPS whole, from every helper that sends one.

  WHY THIS EXISTS. sshd on Windows hands the command to cmd.exe, which stops
  at 8,191 characters, and base64 of UTF-16 is about 2.7 times the script. So
  anything past about 3 KB used to arrive cut in half, and the far end
  complained about a brace in a script nobody could see. Deploy-Docs.ps1 hit
  it on 17 September; sixteen scripts were given a guard on 20 September that
  sends a long script as a file instead. Entry 197 on the To Do List asks for
  "the remote helper survives a 10 KB script".

  test-remote-length.ps1 reads the scripts and measures their blocks. This
  one sends. Each Remote function is lifted out of its script by text and
  called with a 10 KB script, and Remote.ps1, the helper that takes any
  script at all, is run whole with one. ssh and scp are stand-ins defined
  here that write down what they were given, so what is measured is the exact
  command line that would have gone out, and the exact file that would have
  been copied up.

  A helper without the guard is skipped by name: those send only their own
  short blocks, and test-remote-length.ps1 measures every one of them.

  NEVER CONNECTS. It checks that ssh and scp resolve to the stand-ins before
  anything is sent, and stops if they do not. Every host it names ends in
  .invalid, which no resolver answers, so even a stand-in that failed to take
  would reach nothing.
#>
[CmdletBinding()]
param([string]$ToolsPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ToolsPath) { $ToolsPath = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Remove-Item -Path function:global:ssh, function:global:scp -ErrorAction SilentlyContinue
    Remove-Variable -Name TsRemoteCalls -Scope Global -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# What cmd.exe will carry.
$Limit = 8191

# ---- the stand-ins -----------------------------------------------------------
$global:TsRemoteCalls = New-Object System.Collections.ArrayList
function global:ssh {
    [void]$global:TsRemoteCalls.Add([pscustomobject]@{ Tool = 'ssh'; Line = (@($args) -join ' '); Sent = '' })
    $global:LASTEXITCODE = 0
}
function global:scp {
    # The local file is the argument that exists on disk. Read now, because
    # the helper deletes it as soon as the copy returns.
    $sent = ''
    foreach ($a in $args) {
        $s = [string]$a
        $isFile = $false
        try { $isFile = [IO.File]::Exists($s) } catch { }
        if ($isFile) { $sent = [IO.File]::ReadAllText($s) }
    }
    [void]$global:TsRemoteCalls.Add([pscustomobject]@{ Tool = 'scp'; Line = (@($args) -join ' '); Sent = $sent })
    $global:LASTEXITCODE = 0
}
Yes 'ssh is the stand-in here, so nothing can reach a server' ((Get-Command ssh).CommandType -eq 'Function')
Yes 'and so is scp' ((Get-Command scp).CommandType -eq 'Function')
if ($script:fail) { Done }

# What the helpers read to know where to send. None of it resolves.
$ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1')
$User = 'nobody'
$Vps = 'thornswood-test.invalid'
$VpsUser = $User
$VpsHost = $Vps
$target = "$User@$Vps"

# ---- the scripts --------------------------------------------------------------
$lines = New-Object System.Collections.Generic.List[string]
$n = 0
while (($lines -join "`r`n").Length -lt 10240) {
    $n++
    $lines.Add(("Write-Output 'line {0:d4} of a script too long for one command line'" -f $n))
}
$big = ($lines -join "`r`n")
$short = "Write-Output 'short and sent inline'"

function Get-Encoded([string]$line) {
    $m = [regex]::Match($line, 'EncodedCommand\s+(\S+)')
    if (-not $m.Success) { return '' }
    try { return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } catch { return '' }
}

function Measure-Send([scriptblock]$send) {
    $global:TsRemoteCalls.Clear()
    $null = & $send
    $calls = @($global:TsRemoteCalls)
    $longest = 0
    foreach ($c in $calls) { if ($c.Line.Length -gt $longest) { $longest = $c.Line.Length } }
    return [pscustomobject]@{
        Ssh     = @($calls | Where-Object { $_.Tool -eq 'ssh' })
        Scp     = @($calls | Where-Object { $_.Tool -eq 'scp' })
        Longest = $longest
    }
}

function Test-Sends([string]$name, [scriptblock]$sendBig, [scriptblock]$sendShort) {
    $r = Measure-Send $sendBig
    Yes "$name sends a 10 KB script on no command line longer than $Limit" ($r.Longest -gt 0 -and $r.Longest -le $Limit)
    Yes '  as a file it copies up once' ($r.Scp.Count -eq 1)
    Yes '  holding the whole script' ($r.Scp.Count -eq 1 -and $r.Scp[0].Sent.Contains($big))
    Yes '  runs that file' (@($r.Ssh | Where-Object { $_.Line -match "-File '[^']+'" }).Count -eq 1)
    Yes '  and removes it afterwards' (@($r.Ssh | Where-Object { $_.Line -match 'Remove-Item' }).Count -eq 1)

    $r = Measure-Send $sendShort
    Yes '  and a short one still goes inline, in one call' ($r.Scp.Count -eq 0 -and $r.Ssh.Count -eq 1)
    Yes '  whole' ($r.Ssh.Count -eq 1 -and (Get-Encoded $r.Ssh[0].Line).Contains($short))
}

# ---- Remote.ps1, which takes any script --------------------------------------
$remotePs1 = Join-Path $ToolsPath 'Remote.ps1'
Yes 'Remote.ps1 is there' (Test-Path -LiteralPath $remotePs1)
if (Test-Path -LiteralPath $remotePs1) {
    Test-Sends 'Remote.ps1 -Script' {
        & $remotePs1 -Script $big -VpsHost $VpsHost -VpsUser $VpsUser
    } {
        & $remotePs1 -Script $short -VpsHost $VpsHost -VpsUser $VpsUser
    }

    $bigFile = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-big-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    try {
        [IO.File]::WriteAllText($bigFile, $big)
        $r = Measure-Send { & $remotePs1 -File $bigFile -VpsHost $VpsHost -VpsUser $VpsUser }
        Yes "Remote.ps1 -File with a 10 KB script sends no command line longer than $Limit" ($r.Longest -gt 0 -and $r.Longest -le $Limit)
        Yes '  and copies up the whole script' ($r.Scp.Count -eq 1 -and $r.Scp[0].Sent.Contains($big))
    }
    finally { Remove-Item -LiteralPath $bigFile -Force -ErrorAction SilentlyContinue }
}

# ---- the Remote function in every script that has one -------------------------
#
# Found by the parser, not by counting braces: two of these quote PowerShell's
# own "Missing closing '}'" in their comments, which is exactly the message
# the guard exists to prevent, and a brace counter stops there.
function Get-FunctionText([string]$path, [string]$name) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    $all = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $all) {
        if ($fn.Name -eq $name) { return $fn.Extent.Text }
    }
    return ''
}

$helpers = 0
foreach ($f in (Get-ChildItem -Path $ToolsPath -Filter *.ps1 -File | Where-Object { $_.Name -notlike 'test-*' } | Sort-Object Name)) {
    $fn = Get-FunctionText $f.FullName 'Remote'
    if (-not $fn) { continue }
    if ($fn -notmatch '\$cmd\.Length -(le|gt) \d+') {
        Write-Host ("SKIP  {0}: its Remote has no guard; it sends only its own blocks, which test-remote-length.ps1 measures" -f $f.Name)
        continue
    }
    $helpers++
    try { Invoke-Expression $fn } catch { Yes ("the Remote in {0} can be lifted" -f $f.Name) $false; continue }
    Test-Sends $f.Name { Remote $big } { Remote $short }
}
Yes 'the guarded helpers were found and sent to' ($helpers -ge 10)

Done
