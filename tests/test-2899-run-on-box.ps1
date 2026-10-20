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
     the tool's exit code comes back, and the clean-up removes the run's
     folder. Skyrim's archives in the store are linked into the data folder,
     and a tool that opens one to write is refused, the store keeping its
     bytes. Off Windows there is no powershell.exe and no py, and this part
     says so and is skipped; the Windows runner runs it.
  4. scripts\mods\Send-GameArchives.ps1 refuses archives that are missing or
     not the bytes records\skyrim-files.json names, before it asks the box
     anything, and its far side text is ASCII and parses.

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

# ---- 2. the far side text ------------------------------------------------
. $lib
$far = Get-ThornswoodOnBoxScript -Run 'C:\Windows\Temp\thornswood-onbox-test' -ServerRoot 'C:\Thornswood-Server-Dev' -Tool 'scripts/mods/Add-ContentRecords.py' -Arguments @('--check', '--masters', '{data}', "it's")
$clean = Get-ThornswoodOnBoxCleanScript -Run 'C:\Windows\Temp\thornswood-onbox-test'
Yes 'the far side text is ASCII, as Windows PowerShell 5.1 reads it' (-not ($far + $clean).ToCharArray().Where({ [int]$_ -gt 127 }, 'First'))
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
Yes 'the clean-up removes the run''s folder and says whether it went' ($clean -match "Remove-Item -LiteralPath 'C:\\Windows\\Temp\\thornswood-onbox-test' -Recurse" -and $clean -match "'GONE'")

# ---- 3. run as on the box, under Windows PowerShell 5.1 ------------------
$ps51 = $null
if ($env:SystemRoot) { $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
$py = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ps51 -or -not (Test-Path -LiteralPath $ps51) -or -not $py) {
    Write-Host 'SKIP  the run under Windows PowerShell 5.1: no powershell.exe or py on this machine (the Windows runner runs it)'
} else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2899-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $server = Join-Path $work 'server'
        $plugins = Join-Path $server 'plugins'
        $run = Join-Path $work 'run'
        New-Item -ItemType Directory -Force -Path $plugins, $run | Out-Null
        [IO.File]::WriteAllText((Join-Path $plugins 'Skyrim.esm'), 'vanilla')
        [IO.File]::WriteAllText((Join-Path $plugins 'Thornswood-Content.esp'), 'server copy')
        $store = Join-Path $work 'store'
        New-Item -ItemType Directory -Force -Path $store | Out-Null
        $archive = Join-Path $store 'Skyrim - Interface.bsa'
        [IO.File]::WriteAllText($archive, 'archive bytes')
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

        $cleanText = Get-ThornswoodOnBoxCleanScript -Run $run
        $cleanFile = Join-Path $work 'clean.ps1'
        [IO.File]::WriteAllText($cleanFile, $cleanText, (New-Object Text.UTF8Encoding($true)))
        $gone = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $cleanFile 2>&1 | ForEach-Object { "$_".Trim() })
        Yes 'the clean-up removes the run''s folder, and the archive stays in the store' (($gone -contains 'GONE') -and -not (Test-Path -LiteralPath $run) -and [IO.File]::ReadAllText($archive) -eq 'archive bytes')
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
