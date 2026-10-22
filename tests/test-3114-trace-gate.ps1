<#
  test-3114-trace-gate.ps1

      pwsh -NoProfile -File .\tests\test-3114-trace-gate.ps1

  Issue #3114. scripts\dev\Trace-Gate.ps1 traces one run of the pull request
  gate on the VPS, so the read map that picks a pull request's harnesses is
  measured where the gate runs. Nothing here starts a trace: it holds the
  three parts to each other and to build.yml.

    1. .github\workflows\trace-gate.yml starts only by dispatch, reads the
       repository and nothing more, runs on a build runner, and runs the gate
       with the same list, share, throttle and budget as build.yml's gate
       step, with -StartLog, keeping the start log as the artifact
       Trace-Gate.ps1 downloads;
    2. Trace-Gate.ps1 runs the self-test first, stops the session in a
       finally, deletes a trace that was refused or not read, and pushes
       only to a claude/3114-trace-<run> branch it makes;
    3. scripts\dev\Trace-Gate-Box.ps1 parses, its C# compiles as C# 5 (what
       Windows PowerShell 5.1 builds) against stand-ins for the event log
       reader, it keeps the trace in a folder only administrators and the
       system can open, refuses a trace that lost events, and deletes the
       trace once read.

  Writes nothing.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
function Text([string]$rel) { [IO.File]::ReadAllText((Join-Path $repo $rel)) }

# ---- 1. the workflow -----------------------------------------------------------
$y = Text '.github\workflows\trace-gate.yml'
$b = Text '.github\workflows\build.yml'
Yes 'trace-gate.yml starts only by dispatch' ($y -match '(?m)^on:\s*\r?\n  workflow_dispatch:\s*$' -and $y -notmatch '(?m)^  (push|pull_request|pull_request_target|schedule|workflow_run):')
Yes '  reads the repository and nothing more' ($y -match '(?m)^permissions:\s*\r?\n  contents: read\s*$' -and $y -notmatch '(?m)^\s+permissions:')
Yes '  on a build runner, as the gate runs' ($y -match '(?m)^\s+runs-on: \[self-hosted, Windows, thornswood-vps, thornswood-build\]\s*$')
$want = [regex]::Match($b, '(?m)^\s+\.\\scripts\\dev\\Nightly-Harnesses\.ps1 -Only \(\$gate -join '' ''\) -Throttle \d+ -Share \$share -BudgetSeconds \d+\s*$').Value.Trim()
$got = [regex]::Match($y, '(?m)^\s+\.\\scripts\\dev\\Nightly-Harnesses\.ps1 -Only .*$').Value.Trim()
Yes ('  the gate step''s own run, with -StartLog (' + $got + ')') ($want -and $got.StartsWith($want + ' -StartLog '))
$share = '$share = [Math]::Min(6, [Math]::Max(1, [Math]::Floor([Environment]::ProcessorCount / [Math]::Max(1, $builds))))'
Yes '  the same share of the cores' ($b.Contains($share) -and $y.Contains($share) -and $y.Contains('$gate = @(& .\scripts\dev\Gate-Harnesses.ps1)'))
Yes '  every tracked file checked out again first, as build.yml does' ($y -match 'git rm -r -q --cached \.' -and $y -match 'git reset -q --hard HEAD')
Yes '  and the start log kept, even when a harness fails, as gate-trace' ($y -match '(?ms)- name: Keep the start log\s*\r?\n\s+if: always\(\)\s*\r?\n\s+uses: actions/upload-artifact@[0-9a-f]{40} # v\d+\s*\r?\n\s+with:\s*\r?\n\s+name: gate-trace\s*$')

# ---- 2. the script on the shipping machine --------------------------------------
$t = Text 'scripts\dev\Trace-Gate.ps1'
$e = $null; $null = [Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$e)
Yes 'Trace-Gate.ps1 parses' (-not $e.Count)
$self = $t.IndexOf("Invoke-Box 'selftest'"); $start = $t.IndexOf("Invoke-Box 'start'")
Yes '  runs the self-test before it starts the session' ($self -gt 0 -and $start -gt $self -and $t -match "if \(\`$b\.Code -ne 0\) \{ Die \('the self-test did not pass")
Yes '  dispatches trace-gate.yml and downloads its gate-trace artifact' ($t -match 'workflow run trace-gate\.yml' -and $t -match 'run download \$run\.databaseId --repo \$Repo -n gate-trace')
Yes '  stops the session in a finally, whatever the run did' ($t -match "(?s)\} finally \{\s*Head '3\. The session stopped'\s*\`$s = Invoke-Box 'stop'")
Yes '  deletes the trace when there is no finished run, a refusal, or no read' (@([regex]::Matches($t, "\`$null = Invoke-Box 'clean'; Die")).Count -eq 3)
Yes '  pushes only to the branch it names for the run' (@([regex]::Matches($t, 'git -C \$RepoRoot push')).Count -eq 1 -and $t -match "\`$branch = 'claude/3114-trace-' \+ \`$run\.databaseId" -and $t -match "\(\`$commit \+ ':refs/heads/' \+ \`$branch\)")
Yes '  with the plumbing, so the checkout it runs in is not touched' ($t -match 'hash-object -w' -and $t -match 'mktree' -and $t -match 'commit-tree' -and $t -notmatch 'git -C \$RepoRoot (checkout|switch|commit |add |reset|stash)')

# ---- 3. the script on the box ---------------------------------------------------
$x = Text 'scripts\dev\Trace-Gate-Box.ps1'
$e = $null; $null = [Management.Automation.Language.Parser]::ParseInput($x, [ref]$null, [ref]$e)
Yes 'Trace-Gate-Box.ps1 parses' (-not $e.Count)
$cs = [regex]::Match($x, "(?s)Add-Type -ReferencedAssemblies System\.Core -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
# Stand-ins for the event log reader, which only Windows has, so the C# is
# compiled everywhere, as C# 5, the language Windows PowerShell 5.1 builds.
$stub = @'
namespace TraceStub {
  using System; using System.Collections.Generic;
  public enum PathType { LogName, FilePath }
  public class EventLogQuery { public EventLogQuery(string p, PathType t) {} }
  public class EventProperty { public object Value { get { return null; } } }
  public class EventRecord : IDisposable { public int Id { get { return 0; } } public byte? Version { get { return 0; } } public DateTime? TimeCreated { get { return null; } } public Guid? ProviderId { get { return null; } } public int? ProcessId { get { return null; } } public IList<EventProperty> Properties { get { return null; } } public void Dispose() {} }
  public class EventLogReader : IDisposable { public EventLogReader(EventLogQuery q) {} public EventRecord ReadEvent() { return null; } public void Dispose() {} }
  public class EventKeyword { public string Name { get { return null; } } public long Value { get { return 0; } } }
  public class EventMetadata { public long Id { get { return 0; } } public byte Version { get { return 0; } } public string Template { get { return null; } } }
  public class ProviderMetadata { public ProviderMetadata(string n) {} public Guid Id { get { return Guid.Empty; } } public IList<EventKeyword> Keywords { get { return null; } } public IEnumerable<EventMetadata> Events { get { return null; } } }
}
'@
$compiled = ''
if ($cs) {
    $src = $cs.Replace('using System.Diagnostics.Eventing.Reader;', 'using TraceStub;').Replace('public static class ThornswoodTrace', 'public static class ThornswoodTraceTest' + [Guid]::NewGuid().ToString('N')) + "`n" + $stub
    try { Add-Type -TypeDefinition $src -CompilerOptions '-langversion:5' -ErrorAction Stop } catch { $compiled = $_.Exception.Message }
} else { $compiled = 'no C# found' }
Yes ('  its C# compiles as C# 5' + $(if ($compiled) { ': ' + $compiled.Substring(0, [Math]::Min(300, $compiled.Length)) } else { '' })) (-not $compiled)
Yes '  the trace folder is closed to all but administrators and the system' ($x -match [regex]::Escape("icacls.exe `$traceRoot /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F'"))
Yes '  a trace that lost events is refused' ($x -match "(?s)'stop' \{\s*Stop-TraceSession \`$sessionName\s*if \(\`$script:lost\) \{ 'REFUSED: '.*?exit 1 \}")
Yes '  the trace is deleted once read, and only paths in the checkout leave' ($x -match "(?s)'END'\s*Remove-Item -LiteralPath \`$etl -Force" -and $x -match 'if \(!inside\) continue;')
Yes '  every mode Trace-Gate.ps1 asks for is there' (@('selftest', 'start', 'stop', 'read', 'clean' | Where-Object { $x -notmatch ("(?m)^    '" + $_ + "' \{") }).Count -eq 0)

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
