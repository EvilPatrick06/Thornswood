<#
  test-2862-send-backups-acl.ps1

  Issue #2862. Send-Backups.ps1 -Install ran on the box under pwsh and
  stopped at its first lock: "Method invocation failed because
  [System.IO.DirectoryInfo] does not contain a method named
  'SetAccessControl'" (gate run 20261101-221646-90a39e, 1 Nov 2026). .NET
  (pwsh) has no SetAccessControl on DirectoryInfo or FileInfo; it is
  [IO.FileSystemAclExtensions]::SetAccessControl there, and the method only in
  .NET Framework (Windows PowerShell 5.1). Held here:
    - every .SetAccessControl( a script under scripts\ calls on an item sits
      inside an if that asks $PSVersionTable for the edition, so it runs on
      both (strings sent to another PowerShell are not code here, so they
      are not read);
    - Send-Backups.ps1 locks its folder through FileSystemAclExtensions on
      pwsh;
    - the guarded call, run for real on a scratch folder in this PowerShell,
      leaves SYSTEM and the Administrators alone on it.
  Windows only: the last check prints SKIP elsewhere. Under ten seconds.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# ---- every item's SetAccessControl asks for the edition --------------------------
$bare = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath (Join-Path $Repo 'scripts') -Recurse -Filter *.ps1 | ForEach-Object {
    $file = $_.FullName
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
    $calls = $ast.FindAll({ param($n)
        $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and -not $n.Static -and
        $n.Member.Extent.Text -eq 'SetAccessControl' }, $true)
    foreach ($c in $calls) {
        $p = $c.Parent; $asked = $false
        while ($p) {
            if ($p -is [Management.Automation.Language.IfStatementAst] -and
                $p.Clauses[0].Item1.Extent.Text -match 'PSEdition') { $asked = $true; break }
            $p = $p.Parent
        }
        if (-not $asked) { $bare.Add(('{0}:{1}' -f $file.Substring($Repo.Length + 1), $c.Extent.StartLineNumber)) }
    }
}
Yes ("every item.SetAccessControl( under scripts\ asks `$PSVersionTable.PSEdition first" +
     $(if ($bare.Count) { ' (not: ' + ($bare -join ', ') + ')' })) ($bare.Count -eq 0)

# ---- Send-Backups.ps1 itself ------------------------------------------------------
$send = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\vps\Send-Backups.ps1'))
Yes 'Send-Backups.ps1 locks its folder through [IO.FileSystemAclExtensions]::SetAccessControl on pwsh' (
    $send.Contains("[IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]") -and
    $send.Contains("`$PSVersionTable.PSEdition -eq 'Core'"))

# ---- the guarded call, for real ---------------------------------------------------
if ($IsLinux -or $IsMacOS) {
    Write-Host 'SKIP  the lock on a scratch folder (Windows only)'
} else {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('tw-2862-acl-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $dir -Force)
    try {
        $acl = Get-Acl -LiteralPath $dir
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($r in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) { [void]$acl.RemoveAccessRuleSpecific($r) }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        # The current user too, so the scratch folder can be removed again.
        foreach ($sid in 'S-1-5-18', 'S-1-5-32-544', $me) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        }
        $item = Get-Item -LiteralPath $dir -Force
        $err = ''
        try {
            if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$acl) }
            else { $item.SetAccessControl($acl) }
        } catch { $err = $_.Exception.Message }
        Yes ("the guarded call sets the lock in this PowerShell ($($PSVersionTable.PSEdition))" + $(if ($err) { ": $err" })) (-not $err)
        $after = Get-Acl -LiteralPath $dir
        $sids = @($after.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
        Yes 'the folder then holds only SYSTEM, the Administrators (and here this user), nothing inherited' (
            $after.AreAccessRulesProtected -and -not (Compare-Object $sids (@('S-1-5-18', 'S-1-5-32-544', $me) | Sort-Object -Unique)))
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
