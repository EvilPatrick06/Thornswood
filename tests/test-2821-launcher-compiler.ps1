<#
  test-2821-launcher-compiler.ps1

      pwsh -NoProfile -File .\tests\test-2821-launcher-compiler.ps1

  Issue #2821. Seventeen harnesses compiled launcher or setup code with
  PowerShell's Add-Type or a CSharpCodeProvider, not the compiler the build
  runs. Under Windows PowerShell 5.1 that is the in-box .NET Framework csc,
  which stops at C# 5, so a harness refused a line the build takes, and five
  text checks held Secrets.cs, Swallow.cs, OwnGame*.cs and the Downgrade pin
  methods to C# 5 for them; under pwsh 7 it is .NET's Roslyn against .NET 8's
  libraries, so a harness passed code the build refuses on .NET Framework
  4.8.1. Each harness had copied the call from the one before it. Now they
  call Add-LauncherType (tests\Launcher-Csc.ps1), which compiles with
  $LauncherCsc at the project's LangVersion against the 4.8.1 reference
  assemblies. This fails on:
    1. a harness in tests\ that names launcher\app or installer\setup and
       hands Add-Type C# that is not a plain string written in the harness
       itself (a variable, a sum, a string with $ in it, or -Path): that is
       code lifted out of the launcher, compiled the wrong way;
    2. a harness in tests\ that makes a CSharpCodeProvider or calls
       CompileAssemblyFromSource or CompileAssemblyFromFile.
  A stand-in the harness writes out in full (a local server, a probe of a
  Windows call) is a plain string and is not a hit. The same reader is run
  over planted harnesses, so one that finds nothing anywhere cannot pass by
  accident. Then Add-LauncherType itself, on Windows: it takes C# past 5, it
  compiles against the .NET Framework 4.8.1 and not .NET, and a refusal comes
  back as a throw with the compiler's words.

  Read only, apart from the planted folder under TEMP, which it removes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# What one harness compiles the wrong way, as "line N: what", read from its
# syntax tree so a comment or the text of a script it writes is not a hit.
function Get-WrongCompile([string]$path) {
    $hits = New-Object System.Collections.Generic.List[string]
    $text = [IO.File]::ReadAllText($path)
    $tokens = $null; $errs = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errs)
    $names = $text -match '(?i)launcher[\\/]app|installer[\\/]setup'
    foreach ($c in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Type' }, $true)) {
        if (-not $names) { break }
        $at = 'line ' + $c.Extent.StartLineNumber + ': '
        $bound = [Management.Automation.Language.StaticParameterBinder]::BindCommand($c, $true)
        foreach ($p in 'TypeDefinition', 'MemberDefinition') {
            if (-not $bound.BoundParameters.ContainsKey($p)) { continue }
            $v = $bound.BoundParameters[$p].Value
            if ($v -isnot [Management.Automation.Language.StringConstantExpressionAst]) {
                $hits.Add($at + 'Add-Type -' + $p + ' ' + $v.Extent.Text.Split("`n")[0].Trim())
            }
        }
        foreach ($p in 'Path', 'LiteralPath') {
            if ($bound.BoundParameters.ContainsKey($p)) { $hits.Add($at + 'Add-Type -' + $p + ' ' + $bound.BoundParameters[$p].Value.Extent.Text) }
        }
    }
    foreach ($n in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -or
                                            $n -is [Management.Automation.Language.TypeExpressionAst] -or
                                            $n -is [Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
        $at = 'line ' + $n.Extent.StartLineNumber + ': '
        if ($n -is [Management.Automation.Language.InvokeMemberExpressionAst]) {
            $m = $n.Member.Extent.Text
            if ($m -match '^CompileAssemblyFrom(Source|File)$') { $hits.Add($at + 'CodeDom ' + $m) }
        }
        elseif ($n -is [Management.Automation.Language.TypeExpressionAst]) {
            if ($n.TypeName.FullName -match 'CSharpCodeProvider$') { $hits.Add($at + 'CodeDom ' + $n.TypeName.FullName) }
        }
        elseif ($n.Value -match '^(Microsoft\.CSharp\.)?CSharpCodeProvider$' -and $n.Parent -is [Management.Automation.Language.CommandAst]) {
            $hits.Add($at + 'CodeDom ' + $n.Value)
        }
    }
    , $hits
}

# ---- 1. every harness here --------------------------------------------------
$harnesses = @(Get-ChildItem -LiteralPath $Here -File -Filter '*.ps1' | Where-Object { $_.Name -ne (Split-Path -Leaf $PSCommandPath) })
Yes ('there are harnesses to read (' + $harnesses.Count + ')') ($harnesses.Count -gt 300)
$bad = 0
foreach ($h in $harnesses) {
    $hits = Get-WrongCompile $h.FullName
    if ($hits.Count) {
        $bad++
        Write-Host ('FAIL  ' + $h.Name + ' compiles C# another way; call Add-LauncherType (tests\Launcher-Csc.ps1):')
        foreach ($x in $hits) { Write-Host ('      ' + $x) }
    }
}
Yes 'every harness compiles launcher and setup code with Add-LauncherType, the compiler the build runs' ($bad -eq 0)

# ---- 2. the reader, over planted harnesses -----------------------------------
$plant = Join-Path ([IO.Path]::GetTempPath()) ('ts-2821-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($plant)
try {
    $app = "`$app = Join-Path `$root 'launcher\app'`r`n"
    $cases = [ordered]@{
        'Add-Type of a file read out of launcher\app' = @(($app + '$cs = [IO.File]::ReadAllText((Join-Path $app ''Swallow.cs''))' + "`r`n" + 'Add-Type -TypeDefinition $cs -Language CSharp'), 1)
        'the same, as its first argument' = @(($app + 'Add-Type $cs'), 1)
        'lifted methods added to a plain head' = @(($app + "Add-Type -TypeDefinition (@'`r`npublic static class T {`r`n'@ + `$start + '}')"), 1)
        'lifted methods inside a string with $ in it' = @(($app + "Add-Type -TypeDefinition @`"`r`npublic static class T { `$lifted }`r`n`"@"), 1)
        'the files themselves, by -Path' = @("Add-Type -Path (Join-Path `$root 'installer\setup\Bootstrap.cs')", 1)
        'a CSharpCodeProvider' = @(($app + '$provider = New-Object Microsoft.CSharp.CSharpCodeProvider' + "`r`n" + '$built = $provider.CompileAssemblyFromSource($cp, $src)'), 2)
        'a CSharpCodeProvider by its type' = @(($app + '$provider = [Microsoft.CSharp.CSharpCodeProvider]::new()'), 1)
        'a stand-in server written out in full' = @(($app + "Add-Type -TypeDefinition @'`r`npublic static class Server { public static int Port; }`r`n'@"), 0)
        'a probe of a Windows call, as members' = @(($app + "Add-Type -Name W -Namespace P -MemberDefinition '[DllImport(`"kernel32.dll`")] public static extern IntPtr GetConsoleWindow();'"), 0)
        'an assembly by name' = @(($app + 'Add-Type -AssemblyName System.IO.Compression'), 0)
        'Add-LauncherType' = @(($app + '$asm = Add-LauncherType -Source $cs'), 0)
        'history told in a comment' = @(($app + "# before #2821 this ran Add-Type -TypeDefinition `$cs and a CSharpCodeProvider`r`n`$x = 1"), 0)
        'Add-Type in the text of a script it writes' = @(($app + "`$stand = @'`r`nAdd-Type -TypeDefinition `$x`r`n'@"), 0)
        'a harness that never names launcher code' = @('Add-Type -TypeDefinition $probe', 0)
    }
    $k = 0
    foreach ($name in $cases.Keys) {
        $k++
        $f = Join-Path $plant ('test-plant-' + $k + '.ps1')
        [IO.File]::WriteAllText($f, $cases[$name][0])
        $n = (Get-WrongCompile $f).Count
        Yes ('planted, ' + $name + ': ' + $(if ($cases[$name][1]) { 'found' } else { 'not a hit' }) + ' (' + $n + ')') ($n -eq $cases[$name][1])
    }
} finally {
    Remove-Item -LiteralPath $plant -Recurse -Force
}

# ---- 3. Add-LauncherType itself ----------------------------------------------
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')
$said = ''
if (-not $OnWindows) {
    try { $null = Add-LauncherType -Source 'class A { }' } catch { $said = $_.Exception.Message }
    Yes 'off Windows, Add-LauncherType throws, saying the build''s compiler is only on Windows' ($said -match 'only Windows has')
    Write-Host 'SKIP  Add-LauncherType compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'
}
elseif (-not (Test-Path -LiteralPath $LauncherCsc)) {
    Yes ('the compiler the build runs is on this machine (' + $LauncherCsc + ')') $false
}
else {
    $ns = 'Ts2821' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $asm = $null
    # Past C# 5: an interpolated string, an expression body, a pattern.
    try { $asm = Add-LauncherType -Source ('namespace ' + $ns + ' { public static class A { public static string Say(object o) => o is string s ? $"said {s}" : "not text"; } }') }
    catch { Write-Host ('      ' + $_.Exception.Message) }
    Yes ('it compiles C# past 5, at the project''s LangVersion ' + $LauncherLangVersion) ($null -ne $asm)
    if ($asm) {
        Yes 'and gives back the assembly, loaded' ($asm.GetType($ns + '.A')::Say('x') -eq 'said x')
    }
    # String.Contains(char) is .NET's, not the .NET Framework 4.8.1's: Add-Type
    # under pwsh takes it, the build does not.
    $said = ''
    try { $null = Add-LauncherType -Source ('namespace ' + $ns + 'B { static class B { static bool M(string s) { return s.Contains(''x''); } } }') } catch { $said = $_.Exception.Message }
    Yes 'it compiles against the .NET Framework 4.8.1, so a call only .NET has is refused' ($said -match 'CS1503|CS1929|cannot convert')
    $said = ''
    try { $null = Add-LauncherType -Source 'class C { void M() { int x = "s"; } }' } catch { $said = $_.Exception.Message }
    Yes 'a refusal throws with what the compiler said' ($said -match 'CS0029')
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
