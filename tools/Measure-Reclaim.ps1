<#
  Measure-Reclaim.ps1

  How much disk deleting a folder would ACTUALLY free.

      .\tools\Measure-Reclaim.ps1 -Path C:\Thornswood\Game-old-20260917-1623
      .\tools\Measure-Reclaim.ps1 -Path C:\Thornswood\_dist -Detail

  WHY THIS EXISTS. Thornswood's game folder is built from Vortex's deployment
  with the big files as HARD LINKS, so the collection is not stored twice. A
  hard link is not a shortcut: it is a second name for the same bytes, and the
  bytes go only when the LAST name goes. So Get-ChildItem adds up an apparent
  size that has nothing to do with what you would get back.

  On 22 September C:\Thornswood held two old game folders reading 41,880.9 MB
  each, on a drive with 23.7 GB free. Deleting them on that number would have
  been a guess in both directions: they might free almost nothing, or they
  might be the only thing standing between the machine and a full disk. This
  answers it.

  It counts the names on each file. One name means those bytes are this
  folder's alone and go when it does. More than one name means another folder
  holds the same bytes and deleting this one frees nothing for that file.

  fsutil hardlink list is the obvious way and is far too slow: it is a process
  per file, and these folders hold thirty thousand. This asks Windows directly
  through GetFileInformationByHandle, which is one open per file and runs in
  seconds rather than an afternoon.

  Read only. It opens files for metadata and never writes, moves or deletes.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Path,
  [switch]$Detail,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

if (-not (Test-Path -LiteralPath $Path)) {
  Say "  Nothing at $Path" 'Red'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 1
}

# NumberOfLinks out of BY_HANDLE_FILE_INFORMATION. One open per file, no child
# process. FILE_FLAG_BACKUP_SEMANTICS is not needed for files, and the share
# mode is everything so a file the game or Vortex holds open is still readable.
if (-not ([System.Management.Automation.PSTypeName]'Thornswood.Links').Type) {
  Add-Type -Namespace Thornswood -Name Links -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct BY_HANDLE_FILE_INFORMATION {
  public uint FileAttributes;
  public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
  public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
  public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
  public uint VolumeSerialNumber;
  public uint FileSizeHigh;
  public uint FileSizeLow;
  public uint NumberOfLinks;
  public uint FileIndexHigh;
  public uint FileIndexLow;
}

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr CreateFileW(string name, uint access, uint share,
  System.IntPtr sec, uint disposition, uint flags, System.IntPtr template);

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetFileInformationByHandle(System.IntPtr h, out BY_HANDLE_FILE_INFORMATION info);

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(System.IntPtr h);

public static uint Names(string path) {
  System.IntPtr h = CreateFileW(path, 0, 7, System.IntPtr.Zero, 3, 0x02000000, System.IntPtr.Zero);
  if (h == new System.IntPtr(-1)) { return 0; }
  try {
    BY_HANDLE_FILE_INFORMATION info;
    if (!GetFileInformationByHandle(h, out info)) { return 0; }
    return info.NumberOfLinks;
  } finally { CloseHandle(h); }
}
'@
}

Write-Host ''
Write-Host "  THORNSWOOD  -  what deleting $Path would really free" -ForegroundColor White

Head 'Counting'
$files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
Say ("  {0:N0} files" -f $files.Count) 'DarkGray'

$sole = 0L; $soleN = 0
$shared = 0L; $sharedN = 0
$unknown = 0L; $unknownN = 0
$biggest = New-Object Collections.Generic.List[object]

$i = 0
foreach ($f in $files) {
  $i++
  if (($i % 2000) -eq 0) { Write-Progress -Activity 'Counting names per file' -Status "$i of $($files.Count)" -PercentComplete (100 * $i / [Math]::Max(1, $files.Count)) }
  $n = [Thornswood.Links]::Names($f.FullName)
  if ($n -eq 0) { $unknown += $f.Length; $unknownN++; continue }
  if ($n -le 1) {
    $sole += $f.Length; $soleN++
    if ($f.Length -gt 20MB) { [void]$biggest.Add($f) }
  } else {
    $shared += $f.Length; $sharedN++
  }
}
Write-Progress -Activity 'Counting names per file' -Completed

Head 'What it holds'
Say ("  {0,10:N1} MB  in {1,7:N0} file(s) with ONE name. This is what you get back." -f ($sole / 1MB), $soleN) 'Green'
Say ("  {0,10:N1} MB  in {1,7:N0} file(s) with more than one name. Another folder holds the same bytes." -f ($shared / 1MB), $sharedN) 'DarkGray'
if ($unknownN) {
  Say ("  {0,10:N1} MB  in {1,7:N0} file(s) that could not be opened, so they are not counted either way." -f ($unknown / 1MB), $unknownN) 'Yellow'
}
Say ("  {0,10:N1} MB  apparent size, which is the number to ignore." -f ((($sole + $shared + $unknown)) / 1MB)) 'DarkGray'

if ($Detail -and $biggest.Count) {
  Head 'The largest files that are this folder''s alone'
  foreach ($b in ($biggest | Sort-Object Length -Descending | Select-Object -First 15)) {
    Say ("  {0,8:N1} MB  {1}" -f ($b.Length / 1MB), $b.FullName.Substring([Math]::Min($Path.Length + 1, $b.FullName.Length))) 'DarkGray'
  }
}

$drive = (Get-Item -LiteralPath $Path).PSDrive
if ($drive) {
  Head 'The drive'
  $free = (Get-PSDrive $drive.Name).Free
  Say ("  {0:N1} GB free now, {1:N1} GB after, if this folder goes." -f ($free / 1GB), (($free + $sole) / 1GB))
}

Write-Host ''
Write-Host ('  ' + ('=' * 68)) -ForegroundColor DarkGray
Say ("  Deleting $Path frees {0:N1} MB." -f ($sole / 1MB)) 'White'
Say '  Nothing has been deleted. This only counted.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
