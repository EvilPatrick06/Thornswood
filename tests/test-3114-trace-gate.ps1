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
       only to a claude/3114-trace-<run> branch it makes, from an index of
       its own with nothing piped into git; -PushRun pushes a kept read;
    3. scripts\dev\Trace-Gate-Box.ps1 parses, its C# compiles as C# 5 (what
       Windows PowerShell 5.1 builds) against stand-ins for the event log
       reader, it keeps the trace in a folder only administrators and the
       system can open, refuses a trace that lost events, and deletes the
       trace once read.
    4. Trace-Gate.ps1's push, run for real against a scratch repository and
       a bare one standing in for GitHub: the branch holds the four files
       byte for byte, the scratch checkout's index, HEAD and files are as
       they were, and the kept folder is gone. This is the step the first
       gate trace stopped at (run 39731778532, 22 Oct: what pwsh piped into
       git mktree ended in a blank line, which git refused).

  Writes only its scratch folder, in the system's temp folder, and deletes it.
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
Yes '  pushes only to the branch it names for the run' (@([regex]::Matches($t, 'git -C \$RepoRoot push')).Count -eq 1 -and $t -match "\`$branch = 'claude/3114-trace-' \+ \`$runId" -and $t -match "\(\`$commit \+ ':refs/heads/' \+ \`$branch\)" -and $t -match 'Push-Trace \$run\.databaseId \$work' -and $t -match 'Push-Trace \$PushRun \$work')
Yes '  with the plumbing, in an index of its own, so the checkout it runs in is not touched' ($t -match 'hash-object -w' -and $t -match "\`$env:GIT_INDEX_FILE = \`$index" -and $t -match 'update-index --add --cacheinfo' -and $t -match 'write-tree' -and $t -match 'commit-tree' -and $t -notmatch 'git -C \$RepoRoot (checkout|switch|commit |add |reset|stash)')
Yes '  and nothing piped into git, whose bytes depend on the PowerShell' ($t -notmatch '\|\s*&\s*git\b' -and $t -notmatch '& git -C \$RepoRoot mktree')

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
Yes '  the trace is deleted once read, and only paths in the checkout leave' ($x -match "(?s)'END'\s*Remove-Item -LiteralPath \`$etl, \(\`$etl \+ '\.procs'\) -Force" -and $x -match 'if \(!inside\) continue;')
Yes '  every mode Trace-Gate.ps1 asks for is there' (@('selftest', 'start', 'stop', 'read', 'clean' | Where-Object { $x -notmatch ("(?m)^    '" + $_ + "' \{") }).Count -eq 0)

# ---- 4. the push, for real -------------------------------------------------------
$fn = [Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Push-Trace' }, $true) | Select-Object -First 1
Yes 'Trace-Gate.ps1 has its push as Push-Trace' ($null -ne $fn)
if ($fn) {
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('trace-push-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $scratch
    try {
        function GitOk { $o = @(& git @args 2>&1); if ($LASTEXITCODE -ne 0) { throw ('git ' + ($args -join ' ') + ': ' + ($o -join ' ')) }; $o }
        $bare = Join-Path $scratch 'github.git'; $RepoRoot = Join-Path $scratch 'clone'
        $null = GitOk init -q --bare $bare
        $null = GitOk init -q $RepoRoot
        [IO.File]::WriteAllText((Join-Path $RepoRoot 'kept.txt'), "as it was`n")
        $null = GitOk -C $RepoRoot add kept.txt
        $null = GitOk -C $RepoRoot -c user.name=t -c user.email=t@t commit -q -m one
        $null = GitOk -C $RepoRoot remote add origin $bare
        $headBefore = (GitOk -C $RepoRoot rev-parse HEAD) -join ''
        $indexBefore = (Get-FileHash -LiteralPath (Join-Path $RepoRoot '.git/index')).Hash
        $work = Join-Path $RepoRoot 'temp-trace-gate-7'
        $null = New-Item -ItemType Directory -Path $work
        $want = @{
            'traces.jsonl.gz' = [byte[]](31, 139, 8, 0, 0, 0, 0, 0, 0, 3, 75, 4, 0, 67, 190, 183, 232, 1, 0, 0, 0)
            'starts.jsonl' = [Text.Encoding]::UTF8.GetBytes("{`"name`":`"test-a.js`",`"pid`":4,`"start`":`"2026-10-22T06:05:00.0000000Z`"}`n")
            'run.json' = [Text.Encoding]::UTF8.GetBytes('{"commit":"' + ('a' * 40) + '","workspace":"C:\\w"}')
            'summary.txt' = [Text.Encoding]::UTF8.GetBytes("Gate trace`nline two`n")
        }
        foreach ($k in $want.Keys) { [IO.File]::WriteAllBytes((Join-Path $work $k), $want[$k]) }
        function Say($m, $c) { }
        function Die($m) { throw $m }
        $died = ''
        try { & ([ScriptBlock]::Create($fn.Extent.Text + "`nPush-Trace '7' '" + $work.Replace("'", "''") + "'")) } catch { $died = $_.Exception.Message }
        Yes ('  pushes the run''s branch' + $(if ($died) { ': ' + $died } else { '' })) (-not $died -and ((GitOk --git-dir $bare branch --list) -join '') -match 'claude/3114-trace-7')
        $same = $true
        foreach ($k in $want.Keys) {
            if ($died) { $same = $false; break }
            $tmp = Join-Path $scratch ('want-' + $k)
            [IO.File]::WriteAllBytes($tmp, $want[$k])
            if (((GitOk --git-dir $bare rev-parse ('claude/3114-trace-7:' + $k)) -join '') -ne ((GitOk hash-object $tmp) -join '')) { $same = $false }
        }
        Yes '  with the four files byte for byte, and only those' ($same -and @(GitOk --git-dir $bare ls-tree --name-only claude/3114-trace-7).Count -eq 4)
        Yes '  and the checkout it ran in has its own HEAD, index and files as they were' (((GitOk -C $RepoRoot rev-parse HEAD) -join '') -eq $headBefore -and (Get-FileHash -LiteralPath (Join-Path $RepoRoot '.git/index')).Hash -eq $indexBefore -and ((GitOk -C $RepoRoot status --porcelain) -join '') -eq '' -and -not (Test-Path Env:\GIT_INDEX_FILE))
        Yes '  and the kept folder is gone once pushed' (-not (Test-Path -LiteralPath $work))
    } finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
