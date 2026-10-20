<#
  OnBox.ps1

  The two scripts Run-OnBox.ps1 sends to the box (issue #2899): the run, and
  the clean-up of its folder. Kept apart so tests\test-2899-run-on-box.ps1
  runs the same text under Windows PowerShell 5.1 against a stand-in folder.
  Defines functions and nothing else.

  The far side runs under Windows PowerShell 5.1: ASCII, and .NET for the
  hashes, not Get-FileHash (ServerContent.ps1 says why).
#>

# Skyrim's own archives the content tools read (Patrick, 20 Oct 2026, A on
# #2899): Interface for the string tables and the menus, Meshes and Textures
# for the notice board and Check-FromGame. Kept on the box in one folder of
# their own, SYSTEM's and Administrators' only, each file read only to
# everyone but SYSTEM, and every one of them the bytes records\skyrim-files.json
# names. scripts\mods\Send-GameArchives.ps1 puts them there.
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

function Get-ThornswoodOnBoxCleanScript([Parameter(Mandatory = $true)][string]$Run) {
    return @"
Remove-Item -LiteralPath '$run' -Recurse -Force -EA SilentlyContinue
if (Test-Path -LiteralPath '$run') { 'LEFT ' + '$run' } else { 'GONE' }
"@
}
