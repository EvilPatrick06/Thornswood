<#
  test-remote-command-map.ps1

      pwsh -NoProfile -File .\tests\test-remote-command-map.ps1
      powershell -NoProfile -File .\tests\test-remote-command-map.ps1

  Every call under scripts\ that reaches the VPS is in
  records\remote-commands.json, with what it does and the class it needs: a
  gate verb (stage, swap, putback, feed-send, task-start-stop, read-status),
  admin, or transport (a helper that only carries what its caller hands it,
  where the caller is the row that counts). Issue #2182, section 5 step 1 of
  docs\DEPLOY-IDENTITIES.md.

  WHY THIS EXISTS. Section 2 of that doc was first read off script names, not
  off the commands each script sends. A deploy identity built from a list like
  that either breaks (a deploy path sends something only admin may do) or is
  given more than any script uses. The record is the checked list, and this
  keeps it true: a new remote call with no row fails here, and so does a row
  whose call is gone.

  HOW. Parses every .ps1 and .psm1 under scripts\ with the PowerShell parser
  (comments and the text of scripts sent to the box are not commands, so they
  never count) and finds each command named ssh, scp, ssh-keyscan,
  Invoke-ThornswoodRemote, Invoke-ThornswoodSecretRemote,
  Invoke-ThornswoodArtifactRemote, Send-ThornswoodArtifactFile or Remote, and
  each call of Remote.ps1 by path. A call is keyed by script, the function it
  sits in (<top> outside one), the command, and its number among calls with
  that same script, function and command. Line numbers are not part of the
  key, so an edit above a call does not break it. Nothing is run and nothing
  leaves this machine.
#>
[CmdletBinding()]
param([string]$Record)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Record) { $Record = Join-Path $Repo 'records\remote-commands.json' }

$pass = 0; $fail = 0
function Ok([bool]$cond, [string]$what) {
    if ($cond) { $script:pass++ } else { $script:fail++; Write-Host ('FAIL ' + $what) -ForegroundColor Red }
}

$names = @('Invoke-ThornswoodRemote', 'Invoke-ThornswoodSecretRemote', 'Invoke-ThornswoodArtifactRemote',
    'Send-ThornswoodArtifactFile', 'Remote', 'ssh', 'scp', 'ssh-keyscan')
$classes = @('stage', 'swap', 'putback', 'feed-send', 'task-start-stop', 'read-status', 'admin', 'transport')

function Get-RemoteCalls([string]$Root) {
    $found = New-Object System.Collections.Generic.List[string]
    $files = Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Recurse -File |
        Where-Object { $_.Extension -eq '.ps1' -or $_.Extension -eq '.psm1' } | Sort-Object FullName
    foreach ($f in $files) {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
        $rel = $f.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $count = @{}
        $cmds = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true) |
            Sort-Object { $_.Extent.StartOffset }
        foreach ($c in $cmds) {
            $n = $c.GetCommandName()
            if ($n) { $n = $n -replace '(?i)\.exe$', '' }
            $via = $null
            if ($n -and ($names -contains $n)) { $via = $n }
            elseif ($c.CommandElements[0].Extent.Text -match 'Remote\.ps1') { $via = 'Remote.ps1' }
            if (-not $via) { continue }
            $scope = '<top>'
            $p = $c.Parent
            while ($p) {
                if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $scope = $p.Name; break }
                $p = $p.Parent
            }
            $k = $rel + '|' + $scope + '|' + $via
            $count[$k] = 1 + [int]$count[$k]
            $found.Add($k + '#' + $count[$k])
        }
    }
    return , $found
}

$calls = Get-RemoteCalls $Repo
Ok ($calls.Count -gt 0) 'the scan found no remote calls at all, so the scan itself is broken'

if (-not (Test-Path -LiteralPath $Record)) {
    Ok $false ('there is no record at ' + $Record + '; every remote call is unmapped (' + $calls.Count + ')')
} else {
    $doc = Get-Content -LiteralPath $Record -Raw | ConvertFrom-Json
    $rows = @($doc.calls)
    $keys = @{}
    foreach ($r in $rows) {
        $k = $r.script + '|' + $r.scope + '|' + $r.via + '#' + $r.n
        Ok (-not $keys.ContainsKey($k)) ('the record has ' + $k + ' twice')
        $keys[$k] = $r
        Ok ($classes -contains $r.class) ($k + ' has class ' + $r.class + ', not one of ' + ($classes -join ', '))
        Ok ([bool]([string]$r.does).Trim()) ($k + ' says nothing about what it does')
        Ok ([bool]([string]$r.reason).Trim()) ($k + ' gives no reason for its class')
    }
    $seen = @{}
    foreach ($c in $calls) {
        $seen[$c] = $true
        Ok ($keys.ContainsKey($c)) ('remote call not in the record: ' + $c)
    }
    foreach ($k in $keys.Keys) {
        Ok ($seen.ContainsKey($k)) ('the record maps a call that is no longer there: ' + $k)
    }
    $scripts = @($calls | ForEach-Object { $_.Split('|')[0] } | Sort-Object -Unique)
    Ok ([int]$doc.scriptCount -eq $scripts.Count) ('the record says ' + $doc.scriptCount + ' scripts, the scan finds ' + $scripts.Count)
    Ok ([int]$doc.callCount -eq $calls.Count) ('the record says ' + $doc.callCount + ' calls, the scan finds ' + $calls.Count)
}

Write-Host ('{0} passed, {1} failed' -f $pass, $fail)
if ($fail) { exit 1 }
exit 0