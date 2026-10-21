<#
  test-2899-run-on-box.ps1

      pwsh -NoProfile -File .\tests\test-2899-run-on-box.ps1

  scripts\mods\Run-OnBox.ps1 runs a repository Python tool on the box against
  a game server's plugins and brings back what it wrote under game\ and
  records\ (issue #2899). This holds it to that:

  1. A path that is not a Python tool under scripts\mods or scripts\dev, a
     tool that is not there, and an argument with a double quote in it are
     refused before anything is built or sent.
  2. The far side text (scripts\mods\OnBox.ps1) is ASCII and parses, and the
     server's plugins folder is only ever read from.
  3. On Windows, the far side text runs under Windows PowerShell 5.1, as on
     the box, against a stand-in server and a stand-in artifact: the data
     folder is the server's plugins with the commit's own Thornswood plugins
     in their place, '{data}' reaches the tool as that folder, a tool that
     writes into the data folder leaves the server's files as they were,
     only what changed under game\ and records\ is listed and zipped back,
     the tool's exit code comes back, and the keeper removes the run's folder
     when its input closes. Skyrim's archives in the store are linked into the data folder,
     and a tool that opens one to write is refused, the store keeping its
     bytes; the loose string tables in the store's Strings are linked into
     the data folder's Strings, where the tools look for them. Off Windows
     there is no powershell.exe and no py, and this part says so and is
     skipped; the Windows runner runs it.
  5. The run's folder lives as long as its keeper's session (#2999): the
     keeper's text is ASCII, parses and fits on the command line;
     Start-ThornswoodRemote refuses a weaker host key check, a script too
     long for the command line and a word with a double quote, and hands the
     far side its words whole and its input until it is closed. On Windows,
     under Windows PowerShell 5.1: a keeper removes the folders whose lock
     nobody holds (one from before the lock, an orphaned lock) and leaves
     one that is held and anything not named like a run's; a keeper killed
     as a dropped session kills it leaves its folder, and the next keeper
     removes it; a keeper whose run still holds the folder leaves it, says
     so, and the next keeper removes it once the run let go; the run refuses
     to start in a folder no keeper holds.
  4. scripts\mods\Send-GameArchives.ps1 refuses archives that are missing or
     not the bytes records\skyrim-files.json names, before it asks the box
     anything, and its far side text is ASCII and parses. Every file
     records\game-strings.json names is a loose string table under Strings,
     with its size and sha256.

  Nothing here reaches the box.
#>
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$runOnBox = Join-Path $Repo 'scripts\mods\Run-OnBox.ps1'
$lib = Join-Path $Repo 'scripts\mods\OnBox.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

function Refused([string[]]$words) {
    $out = (& pwsh -NoProfile -File $runOnBox @words -VpsHost 127.0.0.1 -VpsUser nobody 2>&1 | Out-String)
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}

# ---- 1. refused before anything is built or sent -------------------------
$r = Refused @('scripts/vps/Remote.ps1')
Yes 'a path that is not a Python tool is refused' ($r.Code -ne 0 -and $r.Text -match 'is not a Python tool' -and $r.Text -match 'Nothing was sent' -and $r.Text -notmatch 'artifact ')
$r = Refused @('scripts/mods/No-Such-Tool.py')
Yes 'a tool that is not in the checkout is refused' ($r.Code -ne 0 -and $r.Text -match 'There is no scripts/mods/No-Such-Tool.py' -and $r.Text -notmatch 'artifact ')
$r = Refused @('scripts/mods/../vps/x.py')
Yes 'a path that climbs out of scripts/mods is refused' ($r.Code -ne 0 -and $r.Text -match 'is not a Python tool')
$r = Refused @('scripts/mods/Add-ContentRecords.py', '--note', 'say "hi"')
Yes 'an argument with a double quote in it is refused' ($r.Code -ne 0 -and $r.Text -match 'double quote' -and $r.Text -notmatch 'artifact ')

# ---- 1b. the artifact carries what the chain's Python builders touch ----
# Until #2962 it held scripts, game\content, game\data, records and
# layout.json only, so a builder that writes into game\gamemode.js stopped on
# the box. The lines that make $paths are lifted out of Run-OnBox.ps1 by the
# parser and run here with its $Here.
$ast = [Management.Automation.Language.Parser]::ParseFile($runOnBox, [ref]$null, [ref]$null)
$top = @($ast.EndBlock.Statements)
$from = @($top | Where-Object { $_.Extent.Text -like '$paths = @(*' })
$upTo = @($top | Where-Object { $_.Extent.Text -like 'foreach ($s in @($chainFiles.steps*' })
Yes 'Run-OnBox.ps1 makes $paths once and adds the chain''s files to it once' ($from.Count -eq 1 -and $upTo.Count -eq 1)
$Here = Join-Path $Repo 'scripts\mods'
$paths = $null
foreach ($st in $top) {
    if ($st.Extent.StartOffset -lt $from[0].Extent.StartOffset -or $st.Extent.StartOffset -gt $upTo[0].Extent.StartOffset) { continue }
    . ([scriptblock]::Create($st.Extent.Text))
}
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$chain = Get-Content -LiteralPath (Join-Path $Repo 'scripts\mods\content-tables.json') -Raw | ConvertFrom-Json
$need = @($chain.steps | Where-Object { $_.tool -like '*.py' } | ForEach-Object { @($_.reads) + @($_.readsBack) + @($_.writes) } | Where-Object { $_ } | Sort-Object -Unique)
$left = @($need | Where-Object { $n = [string]$_; -not @($paths | Where-Object { $n -eq $_ -or $n.StartsWith($_ + '/') }).Count })
Yes ('every file a Python builder of the chain reads or writes goes up (' + $need.Count + ')' + $(if ($left.Count) { ': not ' + ($left -join ', ') } else { '' })) (
    $need.Count -gt 0 -and $left.Count -eq 0)
Yes '  game\gamemode.js among them' ($paths -contains 'game/gamemode.js')

# ---- 4. Send-GameArchives refuses what is not the pinned build -----------
$send = Join-Path $Repo 'scripts\mods\Send-GameArchives.ps1'
$empty = Join-Path ([IO.Path]::GetTempPath()) ('ts-2899-empty-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $empty | Out-Null
try {
    $out = (& pwsh -NoProfile -File $send -Data $empty -VpsHost 127.0.0.1 -VpsUser nobody 2>&1 | Out-String)
    Yes 'Send-GameArchives refuses a Data folder without the archives, before asking the box' (
        $LASTEXITCODE -ne 0 -and $out -match 'STOP  Skyrim - Interface.bsa is not there' -and $out -match 'nothing was sent' -and $out -notmatch 'On the box')
    [IO.File]::WriteAllText((Join-Path $empty 'Skyrim - Interface.bsa'), 'not the archive')
    $out = (& pwsh -NoProfile -File $send -Data $empty -VpsHost 127.0.0.1 -VpsUser nobody 2>&1 | Out-String)
    Yes 'and an archive that is not the recorded bytes' ($LASTEXITCODE -ne 0 -and $out -match 'STOP  Skyrim - Interface.bsa is 15 bytes, the record says 105,799,354' -and $out -notmatch 'On the box')
} finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }
$sendText = Get-Content -LiteralPath $send -Raw
Yes 'it sends only the archives OnBox.ps1 names, each held to records\skyrim-files.json' ($sendText -match 'foreach \(\$n in \$ThornswoodGameArchives\)' -and $sendText -match "records\\skyrim-files.json")
Yes 'and the string tables records\game-strings.json names, each held to its sha256' ($sendText -match "records\\game-strings.json" -and $sendText -match "Algo = 'sha256'")
$gs = Get-Content -LiteralPath (Join-Path $Repo 'records\game-strings.json') -Raw | ConvertFrom-Json
$gsFiles = @($gs.files.PSObject.Properties)
Yes 'records\game-strings.json names loose string tables under Strings, each with its size and sha256' (
    $gsFiles.Count -gt 0 -and -not @($gsFiles | Where-Object {
        $_.Name -notmatch '^Strings\\[^\\]+\.(STRINGS|DLSTRINGS|ILSTRINGS)$' -or [long]$_.Value.bytes -le 0 -or [string]$_.Value.sha256 -notmatch '^[0-9a-f]{64}$' }).Count)

# ---- 2. the far side text ------------------------------------------------
. $lib
$far = Get-ThornswoodOnBoxScript -Run 'C:\Windows\Temp\thornswood-onbox-test' -ServerRoot 'C:\Thornswood-Server-Dev' -Tool 'scripts/mods/Add-ContentRecords.py' -Arguments @('--check', '--masters', '{data}', "it's")
$keep = Get-ThornswoodOnBoxKeepScript -Run 'C:\Windows\Temp\thornswood-onbox-0123456789ab'
Yes 'the far side text is ASCII, as Windows PowerShell 5.1 reads it' (-not ($far + $keep).ToCharArray().Where({ [int]$_ -gt 127 }, 'First'))
$errs = $null
[void][Management.Automation.Language.Parser]::ParseInput($far, [ref]$null, [ref]$errs)
Yes 'and it parses' (-not $errs -or $errs.Count -eq 0)
Yes 'the server''s plugins folder is only read from: nothing is copied, moved or written to it' (
    $far -match "plugins = 'C:\\Thornswood-Server-Dev\\plugins'" -and
    $far -notmatch '(?i)-Destination\s+`\$plugins' -and $far -notmatch '(?i)(Remove-Item|Move-Item|Set-Content|Out-File)[^\r\n]*`\$plugins')
Yes 'the tool runs below normal priority, beside the game servers' ($far -match "PriorityClass = 'BelowNormal'")
Yes 'an argument with a single quote in it is carried whole' ($far -match [regex]::Escape("@('--check', '--masters', '{data}', 'it''s')"))
$ro = Get-ThornswoodArchiveReadOnlyScript
$errs = $null
[void][Management.Automation.Language.Parser]::ParseInput($ro, [ref]$null, [ref]$errs)
Yes 'the archives'' read-only rule is ASCII and parses' (-not $ro.ToCharArray().Where({ [int]$_ -gt 127 }, 'First') -and (-not $errs -or $errs.Count -eq 0))
Yes 'twelve archives: Interface, Meshes0-1 and Textures0-8, Patrick''s A on #2899' ($ThornswoodGameArchives.Count -eq 12 -and $ThornswoodGameArchives[0] -eq 'Skyrim - Interface.bsa' -and $ThornswoodGameArchives[11] -eq 'Skyrim - Textures8.bsa')
$errs = $null
[void][Management.Automation.Language.Parser]::ParseInput($keep, [ref]$null, [ref]$errs)
Yes 'the keeper''s text parses' (-not $errs -or $errs.Count -eq 0)
$keepLine = 'powershell -NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($keep))
Yes ('and fits on the command line, so nothing is sent ahead of it as a file (' + $keepLine.Length + ' of 6000)') ($keepLine.Length -le 6000)
Yes 'the run holds its folder''s lock while it runs, and stops when it cannot' ($far.Contains("New-Object IO.FileStream((`$run + '.lock'), 'Open', 'ReadWrite', 'ReadWrite')") -and $far -match 'could not be held through its lock')
$runText = Get-Content -LiteralPath $runOnBox -Raw
Yes 'Run-OnBox.ps1 starts the keeper, sends the run into its folder and no longer removes the folder by a call of its own' (
    $runText -match 'Start-ThornswoodRemote -Target \$target -SshArgs \$ssh -Script \(Get-ThornswoodOnBoxKeepScript -Run \$run\)' -and
    $runText -match "\(\`$runFar \+ '/run\.ps1'\)" -and $runText -match "StandardInput\.Close\(\)" -and
    $runText -notmatch 'OnBoxCleanScript' -and $runText -notmatch 'Invoke-ThornswoodArtifactRemote \$target \$ssh \$farRun')
Yes 'and its own scratch folder here is not named like a run folder on the box' ($runText -match "'thornswood-runonbox-'" -and $runText -notmatch "GetTempPath\(\)\) \('thornswood-onbox-'")

# ---- 5. Start-ThornswoodRemote -------------------------------------------
. (Join-Path $Repo 'scripts\vps\Send-Script.ps1')
function Refusal([scriptblock]$b) { try { & $b | Out-Null; return '' } catch { return $_.Exception.Message } }
$m = Refusal { Start-ThornswoodRemote -Target 'nobody@box.invalid' -SshArgs @('-o', 'StrictHostKeyChecking=no') -Script "'hi'" }
Yes 'Start-ThornswoodRemote refuses a weaker host key check, before sending anything' ($m -match 'host key checking turned down' -and $m -match 'Nothing was sent')
$m = Refusal { Start-ThornswoodRemote -Target 'nobody@box.invalid' -Script ("'" + ('x' * 3000) + "'") }
Yes 'and a script too long for the command line, rather than sending it as a file' ($m -match 'over 6000' -and $m -match 'Nothing was sent')
$m = Refusal { Start-ThornswoodRemote -Target 'nobody@box.invalid' -SshArgs @('-o', 'User="x"') -Script "'hi'" }
Yes 'and an ssh word with a double quote in it' ($m -match 'double quote' -and $m -match 'Nothing was sent')
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    Write-Host 'SKIP  Start-ThornswoodRemote against a stand-in ssh: ssh is ssh.exe here, and a stand-in would have to be one too (the Linux runs check it)'
} else {
    $bin = Join-Path ([IO.Path]::GetTempPath()) ('ts-2999-bin-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $savedPath = $env:PATH
    try {
        $fake = Join-Path $bin 'ssh'
        [IO.File]::WriteAllText($fake, "#!/bin/sh`nfor a in `"`$@`"; do echo `"ARG `$a`"; done`necho READY`ncat`necho EOF`n")
        & chmod +x $fake
        $env:PATH = $bin + [IO.Path]::PathSeparator + $savedPath
        $p = Start-ThornswoodRemote -Target 'nobody@box.invalid' -SshArgs @('-o', 'BatchMode=yes') -Script "'hi there'"
        $first = @()
        while ($null -ne ($l = $p.StandardOutput.ReadLine())) { if ($l -eq 'READY') { break }; $first += $l }
        $p.StandardInput.WriteLine('a line in')
        $p.StandardInput.Close()
        $rest = @($p.StandardOutput.ReadToEnd() -split '\r?\n' | Where-Object { $_ })
        $p.WaitForExit()
        $want = @('ARG -o', 'ARG BatchMode=yes', 'ARG -o', 'ARG StrictHostKeyChecking=yes', 'ARG nobody@box.invalid',
            ('ARG powershell -NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("'hi there'"))))
        Yes 'ssh is handed its words whole, host key checking on, the script on the command line' (($first -join '|') -eq ($want -join '|'))
        Yes 'and the far side reads its input until it is closed, then ends' (($rest -join '|') -eq 'a line in|EOF' -and $p.ExitCode -eq 0)
    } finally {
        $env:PATH = $savedPath
        Remove-Item -LiteralPath $bin -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- 3. run as on the box, under Windows PowerShell 5.1 ------------------
. (Join-Path $PSScriptRoot 'Windows.ps1')

# A keeper as the box runs one: Windows PowerShell 5.1, the script on the
# command line, its standard input and output pipes. Start-Keeper reads up to
# its MADE line; Stop-Keeper closes its input and reads what it says after.
# Each read gives up after a minute, so a keeper that never answers fails the
# check rather than holding the build.
function Read-KeeperLine($p) {
    $t = $p.StandardOutput.ReadLineAsync()
    if (-not $t.Wait(60000)) { $p.Kill(); throw 'a keeper said nothing for a minute' }
    return $t.Result
}
function Start-Keeper([string]$Run) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $ps51
    $psi.Arguments = '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-ThornswoodOnBoxKeepScript -Run $Run)))
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi)
    $said = @()
    while ($null -ne ($l = Read-KeeperLine $p)) {
        $said += $l.Trim()
        if ($l.Trim() -like 'MADE *') { break }
    }
    # What it said, so a red check here names its cause in the log.
    foreach ($l in $said) { Write-Host ('  keeper: ' + $l) }
    return [pscustomobject]@{ P = $p; Said = $said }
}
function Stop-Keeper($k) {
    $k.P.StandardInput.Close()
    $said = @()
    while ($null -ne ($l = Read-KeeperLine $k.P)) { if ($l.Trim()) { $said += $l.Trim() } }
    $k.P.WaitForExit()
    foreach ($l in $said) { Write-Host ('  keeper: ' + $l) }
    return $said
}
$py = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $OnWindows) {
    Write-Host 'SKIP  the run under Windows PowerShell 5.1: this is not Windows, which is the only place 5.1 runs (the Windows runner runs it)'
} elseif (-not $py) {
    Write-Host 'SKIP  the run under Windows PowerShell 5.1: no py on this machine (the Windows runner runs it)'
} else {
    $ps51 = Get-WindowsPowerShell
    $work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2899-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $server = Join-Path $work 'server'
        $plugins = Join-Path $server 'plugins'
        $run = Join-Path $work 'thornswood-onbox-0123456789ab'
        New-Item -ItemType Directory -Force -Path $plugins | Out-Null
        # The run's folder, made and held by its keeper as on the box.
        $runKeeper = Start-Keeper $run
        Yes 'the keeper makes the run''s folder and holds its lock' (($runKeeper.Said -contains ('MADE ' + $run)) -and (Test-Path -LiteralPath $run) -and (Test-Path -LiteralPath ($run + '.lock')))
        [IO.File]::WriteAllText((Join-Path $plugins 'Skyrim.esm'), 'vanilla')
        [IO.File]::WriteAllText((Join-Path $plugins 'Thornswood-Content.esp'), 'server copy')
        $store = Join-Path $work 'store'
        New-Item -ItemType Directory -Force -Path $store | Out-Null
        $archive = Join-Path $store 'Skyrim - Interface.bsa'
        [IO.File]::WriteAllText($archive, 'archive bytes')
        New-Item -ItemType Directory -Force -Path (Join-Path $store 'Strings') | Out-Null
        $table = Join-Path $store 'Strings\RaceCompatibility_English.STRINGS'
        [IO.File]::WriteAllText($table, 'table bytes')
        $roFile = Join-Path $work 'ro.ps1'
        [IO.File]::WriteAllText($roFile, ((Get-ThornswoodArchiveReadOnlyScript) + "`r`nSet-ThornswoodArchiveReadOnly '" + $archive + "'`r`n'RO'"), (New-Object Text.UTF8Encoding($true)))
        $ro = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $roFile 2>&1 | ForEach-Object { "$_" })
        Yes 'the read-only rule goes on under Windows PowerShell 5.1' ($ro -contains 'RO')

        # The stand-in artifact: a tool, our own plugin and a table.
        $src = Join-Path $work 'src'
        New-Item -ItemType Directory -Force -Path (Join-Path $src 'scripts\mods'), (Join-Path $src 'game\content'), (Join-Path $src 'game\data') | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'game\content\Thornswood-Content.esp'), 'repo copy')
        [IO.File]::WriteAllText((Join-Path $src 'game\data\keep.json'), '{"a":1}')
        [IO.File]::WriteAllText((Join-Path $src 'game\data\same.json'), '{"b":2}')
        $tool = @'
import os, sys
data = sys.argv[2]
print('ARGS ' + '|'.join(sys.argv[1:]))
print('ENV ' + os.environ.get('THORNSWOOD_DATA', ''))
print('CONTENT ' + open(os.path.join(data, 'Thornswood-Content.esp')).read())
open(os.path.join(data, 'Skyrim.esm'), 'w').write('written by the tool')
print('ARCHIVE ' + open(os.path.join(data, 'Skyrim - Interface.bsa')).read())
print('TABLE ' + open(os.path.join(data, 'Strings', 'racecompatibility_english.strings')).read())
try:
    open(os.path.join(data, 'Skyrim - Interface.bsa'), 'w').write('changed')
    print('ARCHIVE WRITE went through')
except PermissionError:
    print('ARCHIVE WRITE refused')
open(os.path.join('game', 'data', 'keep.json'), 'w').write('{"a":2}')
open(os.path.join('game', 'data', 'new.json'), 'w').write('{"c":3}')
open(os.path.join('scripts', 'mods', 'stray.txt'), 'w').write('not ours to bring back')
sys.stderr.write('to stderr\n')
sys.exit(3)
'@
        [IO.File]::WriteAllText((Join-Path $src 'scripts\mods\t.py'), $tool)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($src, (Join-Path $run 'tools.zip'))

        $text = Get-ThornswoodOnBoxScript -Run $run -ServerRoot $server -Tool 'scripts/mods/t.py' -Arguments @('--data', '{data}', 'it''s here') -ArchiveStore $store
        $file = Join-Path $work 'far.ps1'
        # As Send-Script.ps1 sends a long script: UTF-8 with a byte order mark.
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($true)))
        $lines = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { "$_" })
        # What the far side said, so a red check here names its cause in the log.
        Write-Host '  the far side said:'
        foreach ($l in $lines) { Write-Host ('    ' + $l) }
        Write-Host ('  as ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name + ', elevated: ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        $data = Join-Path $run 'data'
        Yes 'the data folder holds the server''s plugins, our own from the commit' (
            ($lines -match '^data\s+2 plugin\(s\)').Count -eq 1 -and
            [IO.File]::ReadAllText((Join-Path $data 'Thornswood-Content.esp')) -eq 'repo copy' -and
            ($lines -contains 'CONTENT repo copy'))
        Yes '{data} reaches the tool as the data folder, and THORNSWOOD_DATA names it' (
            ($lines -contains ('ARGS --data|' + $data + '|it''s here')) -and ($lines -contains ('ENV ' + $data)))
        Yes 'Skyrim''s archives in the store are linked into the data folder' (($lines -match '^archives\s+1 from ').Count -eq 1 -and ($lines -contains 'ARCHIVE archive bytes'))
        Yes 'the loose string tables in the store are linked into the data folder''s Strings' (($lines -match '^strings\s+1 loose string table').Count -eq 1 -and ($lines -contains 'TABLE table bytes'))
        Yes 'a tool opening an archive to write is refused, and the store keeps its bytes' (($lines -contains 'ARCHIVE WRITE refused') -and [IO.File]::ReadAllText($archive) -eq 'archive bytes')
        Yes 'a tool writing into the data folder leaves the server''s own files as they were' (
            [IO.File]::ReadAllText((Join-Path $plugins 'Skyrim.esm')) -eq 'vanilla' -and
            [IO.File]::ReadAllText((Join-Path $plugins 'Thornswood-Content.esp')) -eq 'server copy')
        $changed = @($lines | Where-Object { $_ -like 'CHANGED *' })
        Yes 'only what changed under game/ and records/ is listed' (($changed -join ',') -eq 'CHANGED game/data/keep.json,CHANGED game/data/new.json')
        $back = Join-Path $run 'back.zip'
        $names = @()
        if (Test-Path -LiteralPath $back) { $z = [IO.Compression.ZipFile]::OpenRead($back); try { $names = @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() } }
        Yes 'and only that is zipped to come back' ((($names | Sort-Object) -join ',') -eq 'game/data/keep.json,game/data/new.json')
        Yes 'the tool''s output and its errors are shown' (($lines -contains 'to stderr') -and (($lines -match '^-------- scripts/mods/t.py --------$').Count -eq 1))
        Yes 'the tool''s exit code comes back' ($lines -contains 'EXIT 3')

        $gone = Stop-Keeper $runKeeper
        Yes 'the keeper removes the run''s folder and its lock when its input closes, and the archive stays in the store' (
            ($gone -contains ('GONE ' + $run)) -and -not (Test-Path -LiteralPath $run) -and -not (Test-Path -LiteralPath ($run + '.lock')) -and [IO.File]::ReadAllText($archive) -eq 'archive bytes')
    } finally {
        if ($runKeeper -and -not $runKeeper.P.HasExited) { $runKeeper.P.Kill() }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- 5b. the keeper, as on the box, under Windows PowerShell 5.1 ---------
if (-not $OnWindows) {
    Write-Host 'SKIP  the keeper under Windows PowerShell 5.1: this is not Windows, which is the only place 5.1 runs (the Windows runner runs it)'
} else {
    $ps51 = Get-WindowsPowerShell
    $top = Join-Path ([IO.Path]::GetTempPath()) ('ts-2999-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $held = @()
    $keepers = @()
    try {
        New-Item -ItemType Directory -Force -Path $top | Out-Null
        function Folder([string]$id) { Join-Path $top ('thornswood-onbox-' + $id) }
        function Hold([string]$d) { New-Object IO.FileStream(($d + '.lock'), 'OpenOrCreate', 'ReadWrite', 'ReadWrite') }
        $before = Folder 'aaaaaaaaaaaa'
        New-Item -ItemType Directory -Force -Path (Join-Path $before 'data') | Out-Null
        [IO.File]::WriteAllText((Join-Path $before 'data\Skyrim.esm'), 'left by a cut run')
        $orphan = Folder 'bbbbbbbbbbbb'
        [IO.File]::WriteAllText($orphan + '.lock', '')
        $busy = Folder 'cccccccccccc'
        New-Item -ItemType Directory -Force -Path $busy | Out-Null
        $busyHold = Hold $busy
        $held += $busyHold
        $other = Join-Path $top 'thornswood-onbox-notarun'
        New-Item -ItemType Directory -Force -Path $other | Out-Null

        $k = Start-Keeper (Folder 'dddddddddddd')
        $keepers += $k
        Yes 'a keeper removes a run folder from before the lock, which nobody holds' (($k.Said -contains ('GONE ' + $before)) -and -not (Test-Path -LiteralPath $before) -and -not (Test-Path -LiteralPath ($before + '.lock')))
        Yes 'and an orphaned lock' (($k.Said -contains ('GONE ' + $orphan)) -and -not (Test-Path -LiteralPath ($orphan + '.lock')))
        Yes 'and leaves a folder a run still holds, saying so' (@($k.Said | Where-Object { $_ -like ('HELD ' + $busy + ':*') }).Count -eq 1 -and (Test-Path -LiteralPath $busy))
        Yes 'and anything not named like a run''s folder' (Test-Path -LiteralPath $other)
        Yes 'then makes its own' (($k.Said[-1] -eq ('MADE ' + (Folder 'dddddddddddd'))) -and (Test-Path -LiteralPath (Folder 'dddddddddddd')))
        $m = @(Stop-Keeper $k)
        Yes 'and removes it when its input closes' (($m -contains ('GONE ' + (Folder 'dddddddddddd'))) -and -not (Test-Path -LiteralPath (Folder 'dddddddddddd')))

        # A dropped session: the keeper is killed and can remove nothing.
        $cut = Folder 'eeeeeeeeeeee'
        $k = Start-Keeper $cut
        $keepers += $k
        $k.P.Kill()
        $k.P.WaitForExit()
        Yes 'a keeper killed with its session leaves its folder' ((Test-Path -LiteralPath $cut))
        # A keeper whose run still holds the folder when its input closes.
        $still = Folder 'ffffffffffff'
        $k = Start-Keeper $still
        $keepers += $k
        $runHold = New-Object IO.FileStream(($still + '.lock'), 'Open', 'ReadWrite', 'ReadWrite')
        $held += $runHold
        $m = @(Stop-Keeper $k)
        Yes 'a keeper whose run still holds the folder leaves it, and says so' (@($m | Where-Object { $_ -like ('HELD ' + $still + ':*') }).Count -eq 1 -and (Test-Path -LiteralPath $still))
        $runHold.Dispose()
        $busyHold.Dispose()

        $next = Folder '0123456789ab'
        $k = Start-Keeper $next
        $keepers += $k
        Yes 'the next keeper removes the killed keeper''s folder' (($k.Said -contains ('GONE ' + $cut)) -and -not (Test-Path -LiteralPath $cut) -and -not (Test-Path -LiteralPath ($cut + '.lock')))
        Yes 'and the ones whose runs have let go' (($k.Said -contains ('GONE ' + $still)) -and ($k.Said -contains ('GONE ' + $busy)) -and -not (Test-Path -LiteralPath $still) -and -not (Test-Path -LiteralPath $busy))

        # The run refuses a folder no keeper holds.
        $loose = Folder '123456789abc'
        New-Item -ItemType Directory -Force -Path $loose | Out-Null
        $file = Join-Path $top 'far.ps1'
        [IO.File]::WriteAllText($file, (Get-ThornswoodOnBoxScript -Run $loose -ServerRoot $top -Tool 'scripts/mods/t.py'), (New-Object Text.UTF8Encoding($true)))
        $lines = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        Yes 'the run stops in a folder no keeper holds, before anything is unpacked' ($code -eq 2 -and @($lines | Where-Object { $_ -like 'STOP. the run''s folder could not be held*' }).Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $loose 'repo')))
        Remove-Item -LiteralPath $loose -Recurse -Force

        $m = @(Stop-Keeper $k)
        $left = @(Get-ChildItem -LiteralPath $top -Force | Where-Object { $_.Name -ne 'far.ps1' } | ForEach-Object { $_.Name })
        Yes ('and when the last keeper is done, only what is not a run''s is left' + $(if ($left.Count -ne 1) { ': ' + ($left -join ', ') } else { '' })) (($m -contains ('GONE ' + $next)) -and ($left -join ',') -eq 'thornswood-onbox-notarun')
    } finally {
        foreach ($h in $held) { $h.Dispose() }
        foreach ($k in $keepers) { if (-not $k.P.HasExited) { $k.P.Kill() } }
        Remove-Item -LiteralPath $top -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
