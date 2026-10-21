<#
  OnBox.ps1

  The two scripts Run-OnBox.ps1 sends to the box (issue #2899): the keeper,
  which makes the run's folder and removes it, and the run. Kept apart so
  tests\test-2899-run-on-box.ps1 runs the same text under Windows PowerShell
  5.1 against a stand-in folder. Defines functions and nothing else.

  The keeper's folder is the one way a script here lands files on the box or
  makes them there to bring back (#3035): Open-ThornswoodOnBoxFolder and
  Close-ThornswoodOnBoxFolder, below, for Run-OnBox.ps1 and Backup-Server.ps1
  alike. A script that only needs its text run there sends it through
  Send-Script.ps1 instead, whose run deletes a long one's copy before it runs.

  The far side runs under Windows PowerShell 5.1: ASCII, and .NET for the
  hashes, not Get-FileHash (ServerContent.ps1 says why).
#>

# Skyrim's own archives the content tools read (Patrick, 20 Oct 2026, A on
# #2899): Interface for the string tables and the menus, Meshes and Textures
# for the notice board and Check-FromGame. Kept on the box in one folder of
# their own, SYSTEM's and Administrators' only, each file read only to
# everyone but SYSTEM, and every one of them the bytes records\skyrim-files.json
# names. scripts\mods\Send-GameArchives.ps1 puts them there, and with them,
# under Strings, the loose string tables records\game-strings.json names: a
# localized master whose names are in no archive (RaceCompatibility.esm,
# measured 20 Oct) stops Build-LastPlugin without them.
$ThornswoodGameArchiveStore = 'C:\Thornswood-GameData'
$ThornswoodGameArchives = @('Skyrim - Interface.bsa', 'Skyrim - Meshes0.bsa', 'Skyrim - Meshes1.bsa') +
    @(0..8 | ForEach-Object { 'Skyrim - Textures' + $_ + '.bsa' })

# Text for the box: makes a file readable, and linkable, and nothing more to
# everyone but SYSTEM. A run reaches the archives through hard links, which
# share the file's rules, so a tool that opens one to write is refused and
# the store keeps its bytes; deleting the link needs only the run folder's
# own rules. Making a hard link opens the file for its attributes, so the
# account that links needs WriteAttributes: measured 20 Oct, the build
# runner's account (not elevated) was refused "Access is denied" at the link
# with read alone (run 39470283490), where Administrator on the box was not
# refused. Attributes are not the bytes: writing still needs
# WriteData, which nobody but SYSTEM has.
function Get-ThornswoodArchiveReadOnlyScript {
    return @'
function Set-ThornswoodArchiveReadOnly([string]$Path) {
  $acl = New-Object Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true, $false)
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-18')), 'FullControl', 'Allow')))
  foreach ($s in @('S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($s)), 'ReadAndExecute, WriteAttributes, Synchronize', 'Allow')))
  }
  (Get-Item -LiteralPath $Path -Force).SetAccessControl($acl)
}
'@
}

# Text for the box: names the run's folder $run and holds it through its lock
# for as long as the process that runs this lives. The folder is in use while
# its lock is held (the keeper, below), and a run holds it too, so even with
# the keeper's session gone no other run's sweep takes the folder from under
# what is running in it. The handle goes when the process ends, however it
# ends. A folder no keeper made has no lock, and nothing runs in it.
function Get-ThornswoodOnBoxHoldScript([Parameter(Mandatory = $true)][string]$Run) {
    return @"
`$run = '$Run'
try { `$hold = New-Object IO.FileStream((`$run + '.lock'), 'Open', 'ReadWrite', 'ReadWrite') }
catch { 'STOP. the run''s folder could not be held through its lock, so nothing ran: ' + `$_.Exception.GetBaseException().Message; exit 2 }
"@
}

# -Run is the run's own folder on the box, holding tools.zip; -ServerRoot the
# game server whose plugins folder is copied; -Tool the repository path of
# the Python tool; -Arguments what it is run with, '{data}' and '{repo}'
# standing for the data and repository folders of the run.
function Get-ThornswoodOnBoxScript {
    param(
        [Parameter(Mandatory = $true)][string]$Run,
        [Parameter(Mandatory = $true)][string]$ServerRoot,
        [Parameter(Mandatory = $true)][string]$Tool,
        [string[]]$Arguments = @(),
        [string]$ArchiveStore = $ThornswoodGameArchiveStore
    )
    $argText = (@($Arguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ', ')
    return @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
$(Get-ThornswoodOnBoxHoldScript -Run $Run)
`$repo = Join-Path `$run 'repo'
`$data = Join-Path `$run 'data'
`$plugins = '$serverRoot\plugins'
if (-not (Test-Path -LiteralPath `$plugins)) { 'STOP. there is no ' + `$plugins + ' on the box.'; exit 2 }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path `$run 'tools.zip'), `$repo)
New-Item -ItemType Directory -Force -Path `$data | Out-Null
`$ours = @(Get-ChildItem -LiteralPath (Join-Path `$repo 'game\content') -File | ForEach-Object { `$_.Name.ToLowerInvariant() })
foreach (`$f in @(Get-ChildItem -LiteralPath `$plugins -File)) {
  if (`$ours -notcontains `$f.Name.ToLowerInvariant()) { Copy-Item -LiteralPath `$f.FullName -Destination `$data }
}
foreach (`$f in @(Get-ChildItem -LiteralPath (Join-Path `$repo 'game\content') -File)) { Copy-Item -LiteralPath `$f.FullName -Destination `$data }
'data      ' + @(Get-ChildItem -LiteralPath `$data -File).Count + ' plugin(s): ' + `$plugins + ', with this commit''s own in place of the server''s'
`$store = '$ArchiveStore'
`$linked = 0
if (Test-Path -LiteralPath `$store) {
  foreach (`$f in @(Get-ChildItem -LiteralPath `$store -File -Filter '*.bsa')) {
    `$null = New-Item -ItemType HardLink -Path (Join-Path `$data `$f.Name) -Value `$f.FullName
    `$linked++
  }
}
if (`$linked) { 'archives  ' + `$linked + ' from ' + `$store + ', linked, read only' } else { 'archives  none: ' + `$store + ' holds no Skyrim archive, so a tool that reads one stops' }
`$storeStrings = Join-Path `$store 'Strings'
`$linkedStrings = 0
if (Test-Path -LiteralPath `$storeStrings) {
  `$dataStrings = Join-Path `$data 'Strings'
  New-Item -ItemType Directory -Force -Path `$dataStrings | Out-Null
  foreach (`$f in @(Get-ChildItem -LiteralPath `$storeStrings -File)) {
    `$null = New-Item -ItemType HardLink -Path (Join-Path `$dataStrings `$f.Name) -Value `$f.FullName
    `$linkedStrings++
  }
}
if (`$linkedStrings) { 'strings   ' + `$linkedStrings + ' loose string table(s) from ' + `$storeStrings + ', linked, read only' }

`$sha = [Security.Cryptography.SHA256]::Create()
function Hashes {
  `$h = @{}
  foreach (`$top in 'game', 'records') {
    `$d = Join-Path `$repo `$top
    if (-not (Test-Path -LiteralPath `$d)) { continue }
    foreach (`$f in @(Get-ChildItem -LiteralPath `$d -File -Recurse)) {
      `$rel = `$f.FullName.Substring(`$repo.Length + 1).Replace('\', '/')
      `$s = [IO.File]::OpenRead(`$f.FullName)
      try { `$h[`$rel] = [BitConverter]::ToString(`$sha.ComputeHash(`$s)) } finally { `$s.Close() }
    }
  }
  return `$h
}
`$before = Hashes

# python.exe itself, named by the py launcher: run through py, a quoted
# path arrived with a space in front of it and Python could not open it.
`$launcher = Get-Command py -CommandType Application -EA SilentlyContinue | Select-Object -First 1
if (-not `$launcher) { 'STOP. there is no Python launcher (py) on the box.'; exit 2 }
`$python = (& `$launcher.Source -3 -c 'import sys; print(sys.executable)' | Select-Object -First 1)
if (-not `$python -or -not (Test-Path -LiteralPath `$python)) { 'STOP. py -3 named no Python on the box.'; exit 2 }
`$given = @($argText)
`$words = @('"' + (Join-Path `$repo '$($tool.Replace('/', '\'))') + '"')
foreach (`$a in `$given) { `$words += '"' + `$a.Replace('{data}', `$data).Replace('{repo}', `$repo) + '"' }
`$env:THORNSWOOD_DATA = `$data
`$env:PYTHONUTF8 = '1'
`$env:PYTHONIOENCODING = 'utf-8'
`$env:PYTHONDONTWRITEBYTECODE = '1'
`$out = Join-Path `$run 'out.txt'
`$err = Join-Path `$run 'err.txt'
`$p = Start-Process -FilePath `$python -ArgumentList `$words -WorkingDirectory `$repo -NoNewWindow -PassThru -RedirectStandardOutput `$out -RedirectStandardError `$err
# Taking the handle now is what keeps ExitCode: without it, a process
# Start-Process started reports none once it has ended.
`$null = `$p.Handle
try { `$p.PriorityClass = 'BelowNormal' } catch { 'priority left as it was: ' + `$_.Exception.Message }
`$p.WaitForExit()
`$code = `$p.ExitCode
'-------- $tool --------'
Get-Content -LiteralPath `$out -Encoding UTF8
Get-Content -LiteralPath `$err -Encoding UTF8
'-------- end --------'

`$after = Hashes
`$changed = @(`$after.Keys | Where-Object { `$before[`$_] -ne `$after[`$_] } | Sort-Object)
if (`$changed.Count) {
  `$zip = [IO.Compression.ZipFile]::Open((Join-Path `$run 'back.zip'), 'Create')
  try { foreach (`$c in `$changed) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(`$zip, (Join-Path `$repo `$c.Replace('/', '\')), `$c) } } finally { `$zip.Dispose() }
}
foreach (`$c in `$changed) { 'CHANGED ' + `$c }
'EXIT ' + `$code
"@
}

# The run's folder lives as long as one far process, the keeper's (#2999).
# Until 21 Oct 2026 the folder was made by one ssh call and removed by
# another at the end, so a run cut before that call (a bridge reset, the
# machine running it going away) left the folder on the box for good, with
# its 383 MB copy of the plugins, and nothing there ever removed it. Now:
#
#   - <run>.lock, beside the folder, is held for as long as the run is going:
#     by this script from before the folder exists until it is removed, and by
#     the run itself (above) while the tool runs. Windows lets go of a handle
#     when its process ends however it ends.
#   - The keeper waits on a named event of its own, $End, made here (a name
#     somebody made first is refused before anything else is done). When it
#     is set, which Close-ThornswoodOnBoxFolder does from a second ssh
#     session, it removes the folder itself and says GONE. Until 21 Oct it
#     waited for its standard input to close, and on the box that never
#     came: sshd passes on nothing written or closed after a session starts
#     (#2912, #3059), so every Close waited for good (#3063). The named
#     event is how the secret proof's watcher is stopped there (#2912).
#   - A folder whose lock nobody holds belongs to a run that is over, so before
#     it makes its own, this removes every such thornswood-onbox-* folder
#     beside it: a folder whose keeper was ended (the box restarting), and
#     one from before the lock (it has none). A folder whose lock is held
#     is a run still going, and is left alone. No age and no time limit decide
#     it: only whether the process that owns the folder is still there.
#   - Not yet covered: a keeper whose caller went away without setting the
#     event. A far process outlives its ssh session on the box (#3059), so
#     that keeper holds its folder until something tells it its caller has
#     gone, and what on the box can tell it is still being measured (#3063).
#
# Removing takes the lock alone (shared for deleting only, so it can delete
# the lock while it holds it; Windows lets the file go when the handle
# closes), so the run and its keeper, and two runs sweeping at once, never
# remove a folder another holds. Lines out: GONE <folder>, HELD
# <folder>: why (still in use), LEFT <folder>: why (could not be removed),
# MADE <folder> once this run's own is there, and TAKEN <name> when its event
# was made by somebody else first. Each is written and flushed as it happens,
# because Run-OnBox.ps1 waits for MADE while this waits for its end. Short
# enough for the command line on purpose
# (Start-ThornswoodRemote): a script sent as a file first would be one more
# thing on the box a cut session leaves.
function Get-ThornswoodOnBoxKeepScript([Parameter(Mandatory = $true)][string]$Run, [Parameter(Mandatory = $true)][string]$End) {
    if ($End -notmatch '^Global\\Thornswood-OnBoxEnd-[0-9a-f]{32}$') { throw ('not a keeper''s end event: ' + $End) }
    return @"
`$ErrorActionPreference = 'Stop'
`$run = '$Run'
`$top = Split-Path -Parent `$run
function Say([string]`$l) { [Console]::Out.WriteLine(`$l); [Console]::Out.Flush() }
`$made = `$false
`$end = [Threading.EventWaitHandle]::new(`$false, [Threading.EventResetMode]::ManualReset, '$End', [ref]`$made)
if (-not `$made) { Say ('TAKEN $End'); exit 2 }
function Drop([string]`$d) {
  try { `$h = New-Object IO.FileStream((`$d + '.lock'), 'OpenOrCreate', 'ReadWrite', 'Delete') }
  catch { Say ('HELD ' + `$d + ': ' + `$_.Exception.GetBaseException().Message); return }
  try {
    if (Test-Path -LiteralPath `$d) { Remove-Item -LiteralPath `$d -Recurse -Force }
    [IO.File]::Delete(`$d + '.lock')
    Say ('GONE ' + `$d)
  } catch { Say ('LEFT ' + `$d + ': ' + `$_.Exception.Message) } finally { `$h.Dispose() }
}
`$seen = @{}
foreach (`$f in @(Get-ChildItem -LiteralPath `$top -Filter 'thornswood-onbox-*' -Force)) {
  if (`$f.Name -notmatch '^(thornswood-onbox-[0-9a-f]{12})(\.lock)?`$') { continue }
  `$d = Join-Path `$top `$Matches[1]
  if (`$d -eq `$run -or `$seen[`$d]) { continue }
  `$seen[`$d] = 1
  Drop `$d
}
`$own = New-Object IO.FileStream((`$run + '.lock'), 'CreateNew', 'ReadWrite', 'ReadWrite')
New-Item -ItemType Directory -Path `$run | Out-Null
Say ('MADE ' + `$run)
[void]`$end.WaitOne()
`$own.Dispose()
Drop `$run
`$end.Dispose()
"@
}

# What the second ssh session runs to end a keeper: sets its event. Says END
# SET, or END GONE when no keeper holds that event any more.
function Get-ThornswoodOnBoxEndScript([Parameter(Mandatory = $true)][string]$End) {
    if ($End -notmatch '^Global\\Thornswood-OnBoxEnd-[0-9a-f]{32}$') { throw ('not a keeper''s end event: ' + $End) }
    return "`$e = `$null; if ([Threading.EventWaitHandle]::TryOpenExisting('$End', [ref]`$e)) { [void]`$e.Set(); `$e.Dispose(); 'END SET' } else { 'END GONE' }"
}

# A folder of its own on the box for one run, held by its keeper until
# Close-ThornswoodOnBoxFolder ends it (above). Needs Send-Script.ps1 loaded.
# Hands back Run (the folder, Windows form), Far (with forward slashes, for
# scp), Made, Keeper (the ssh process), Said (what the keeper's sweep of
# earlier folders said before MADE), and End, Target and SshArgs for the
# close. Made false means there is no folder: the caller stops, and still
# hands this to Close-ThornswoodOnBoxFolder.
function Open-ThornswoodOnBoxFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [string[]]$SshArgs = @()
    )
    $run = 'C:\Windows\Temp\thornswood-onbox-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
    # A name nobody can know ahead of the run, so nobody makes it first.
    $end = 'Global\Thornswood-OnBoxEnd-' + [Guid]::NewGuid().ToString('N')
    # The keeper first: it removes what earlier runs left, then makes this
    # run's folder and holds it until its event is set.
    $keeper = Start-ThornswoodRemote -Target $Target -SshArgs $SshArgs -Script (Get-ThornswoodOnBoxKeepScript -Run $run -End $end)
    $said = @()
    $made = $false
    while ($null -ne ($l = $keeper.StandardOutput.ReadLine())) {
        $l = $l.Trim()
        if ($l -eq ('MADE ' + $run)) { $made = $true; break }
        if ($l) { $said += $l }
    }
    return [pscustomobject]@{ Run = $run; Far = $run.Replace('\', '/'); Made = $made; Keeper = $keeper; Said = $said; End = $end; Target = $Target; SshArgs = $SshArgs }
}

# Tells the keeper the run is over: a second ssh session sets its event, and
# it removes the folder, says GONE and ends, and its ssh with it. The event is
# set even when the keeper's ssh here has already ended, since on the box the
# keeper outlives its session (#3059). When it could not be set, nothing will
# end that keeper's ssh here, so it is ended, and what the set said is handed
# back with the rest. Hands back Gone (the keeper said its folder is gone, or
# there was none), Told (the event was set, or no keeper holds it any more)
# and Said (the keeper's last lines, then the set's).
function Close-ThornswoodOnBoxFolder([Parameter(Mandatory = $true)]$Folder) {
    $k = $Folder.Keeper
    $told = @(Invoke-ThornswoodRemote -Target $Folder.Target -SshArgs $Folder.SshArgs -Script (Get-ThornswoodOnBoxEndScript -End $Folder.End) 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if (-not $k.HasExited -and -not ($told -contains 'END SET')) {
        # With the bridge's node under it on One: the whole tree where .NET
        # can (PowerShell 7), the ssh alone where it cannot (5.1).
        try { $k.Kill($true) } catch { try { $k.Kill() } catch { } }
    }
    $said = @($k.StandardOutput.ReadToEnd() -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $k.WaitForExit()
    return [pscustomobject]@{ Gone = ((-not $Folder.Made) -or ($said -contains ('GONE ' + $Folder.Run))); Told = (($told -contains 'END SET') -or ($told -contains 'END GONE')); Said = @($said + @($told | Where-Object { $_ -ne 'END SET' })) }
}
