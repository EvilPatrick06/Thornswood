<#
  OnBox.ps1

  The two scripts Run-OnBox.ps1 sends to the box (issue #2899): the keeper,
  which makes the run's folder and removes it, and the run. Kept apart so
  tests\test-2899-run-on-box.ps1 runs the same text under Windows PowerShell
  5.1 against a stand-in folder. Defines functions and nothing else.

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
`$run = '$run'
# The run's folder is in use while its lock is held (the keeper, below), and
# this holds it too for as long as the tool runs, so even with the keeper's
# session gone no other run's sweep takes the folder from under the tool. The
# handle goes when this process ends, however it ends.
try { `$hold = New-Object IO.FileStream((`$run + '.lock'), 'Open', 'ReadWrite', 'ReadWrite') }
catch { 'STOP. the run''s folder could not be held through its lock, so nothing ran: ' + `$_.Exception.GetBaseException().Message; exit 2 }
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

# The run's folder lives as long as one ssh session, the keeper's (#2999).
# Until 21 Oct 2026 the folder was made by one ssh call and removed by
# another at the end, so a run cut before that call (a bridge reset, the
# machine running it going away) left the folder on the box for good, with
# its 383 MB copy of the plugins, and nothing there ever removed it. Now:
#
#   - <run>.lock, beside the folder, is held for as long as the run is going:
#     by this script from before the folder exists until it is removed, and by
#     the run itself (above) while the tool runs. Windows lets go of a handle
#     when its process ends however it ends, killed with its session included.
#   - When this script's standard input closes, which is how Run-OnBox.ps1
#     says it is finished and also what a dropped session does, it removes
#     the folder itself and says GONE.
#   - A folder whose lock nobody holds belongs to a run that is over, so before
#     it makes its own, this removes every such thornswood-onbox-* folder
#     beside it: the ones a run killed with its session could not remove, and
#     a folder from before the lock (it has none). A folder whose lock is held
#     is a run still going, and is left alone. No age and no time limit decide
#     it: only whether the process that owns the folder is still there.
#
# Removing takes the lock alone (shared for deleting only, so it can delete
# the lock while it holds it; Windows lets the file go when the handle
# closes), so the run and its keeper, and two runs sweeping at once, never
# remove a folder another holds. Lines out: GONE <folder>, HELD
# <folder>: why (still in use), LEFT <folder>: why (could not be removed),
# and MADE <folder> once this run's own is there. Each is written and flushed
# as it happens, because Run-OnBox.ps1 waits for MADE while this waits for
# its input to close. Short enough for the command line on purpose
# (Start-ThornswoodRemote): a script sent as a file first would be one more
# thing on the box a cut session leaves.
function Get-ThornswoodOnBoxKeepScript([Parameter(Mandatory = $true)][string]$Run) {
    return @"
`$ErrorActionPreference = 'Stop'
`$run = '$Run'
`$top = Split-Path -Parent `$run
function Say([string]`$l) { [Console]::Out.WriteLine(`$l); [Console]::Out.Flush() }
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
[void][Console]::In.ReadToEnd()
`$own.Dispose()
Drop `$run
"@
}
