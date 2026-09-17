<#
  New-GameFolder.ps1

  Makes, or brings up to date, a Skyrim folder of its own for another server,
  so Keizaal Online or Daedric Online stops sharing a Skyrim with Thornswood.
  Thornswood makes its own folder in the launcher (Settings, Maintenance); this
  is the same thing for the others.

      .\tools\New-GameFolder.ps1 -Server Keizaal
      .\tools\New-GameFolder.ps1 -Server Daedric
      .\tools\New-GameFolder.ps1 -Server Keizaal -Path E:\Skyrim-Keizaal

  First, in Vortex, enable that server's profile and let it deploy. The folder
  is made from what Vortex has deployed at that moment:

    - Skyrim itself and the script extender,
    - every file Vortex deployed (that server's collection),
    - the SkyMP runtime every server's client uses,
    - that server's own client files, where they can be told apart.

  Left out: Thornswood's files, other servers' files, sign-in data with tokens
  in it, and Vortex's own records. The server's launcher puts its client back
  when it plays, the way it does after any update.

  Big files are hard links to Vortex's copies, so the collection is not on the
  disk twice. A link is the same file under a second name, so settings files,
  scripts, programs, the client folders, the game's master files and anything
  another launcher is known to replace are copied instead. Those are what gets
  rewritten in place.

  Afterwards, point that server's launcher at the new folder in its own
  settings. Run this again after that server's collection updates in Vortex:
  new and changed files come in, dropped ones go, and anything the server's
  launcher has replaced in the folder since is left as it is.

  The record of what came from where is kept in
  %LOCALAPPDATA%\Thornswood\GameFolders\<Server>. Nothing in the Steam copy or
  in Vortex is changed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Path,
    [string]$Source,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

if ($Server -match '^\s*thornswood') {
    Die "Thornswood makes its own folder from the launcher: Settings, Maintenance, Thornswood's own Skyrim folder."
}
if ($Server -notmatch '^[A-Za-z0-9 _-]+$') { Die "Use a plain name for -Server, like Keizaal or Daedric." }
$Server = $Server.Trim()
$isKeizaal = $Server -match 'keizaal'
$isDaedric = $Server -match 'daedric'

# ---------------------------------------------------------------- where
function Get-SkyrimPath {
    $roots = @()
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
        try { $sp = (Get-ItemProperty -Path $k -EA Stop).SteamPath; if ($sp) { $roots += ($sp -replace '/', '\') } } catch { }
    }
    foreach ($r in @($roots)) {
        $vdf = Join-Path $r 'config\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $roots += ($Matches[1] -replace '\\\\', '\') }
            }
        }
    }
    foreach ($r in $roots) {
        $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
        if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { return $g }
    }
    return ''
}

# The launcher's install, for its shipped plugin list. Same search Ship uses.
function Find-Root {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return ''
}

Head "A Skyrim folder of its own for $Server"

if (-not $Source) { $Source = Get-SkyrimPath }
if (-not $Source -or -not (Test-Path -LiteralPath (Join-Path $Source 'SkyrimSE.exe'))) {
    Die 'No Skyrim to make it from. Steam does not list one; give -Source the folder Vortex deploys into.'
}
$Source = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
if (-not $Path) { $Path = Join-Path ([IO.Path]::GetPathRoot($Source)) "Skyrim-$Server" }
$Path = [IO.Path]::GetFullPath($Path).TrimEnd('\')
Say "  from  $Source"
Say "  into  $Path"

if ($Path -ieq $Source) { Die 'The new folder cannot be the folder it is made from.' }
if ([IO.Path]::GetPathRoot($Path) -ine [IO.Path]::GetPathRoot($Source)) {
    Die ("Links only work inside one drive. Skyrim is on {0}, so the folder has to be on {0} as well." -f [IO.Path]::GetPathRoot($Source))
}
if (Get-Process -Name SkyrimSE, skse64_loader -ErrorAction SilentlyContinue) {
    Die 'Skyrim is running. Close it first.'
}

$vm = Join-Path $Source 'Data\vortex.deployment.json'
if (-not (Test-Path -LiteralPath $vm)) {
    Die "Vortex has nothing deployed in $Source. In Vortex, enable the $Server profile and let it deploy, then run this again."
}

# Refuse Thornswood's collection under another server's name: if every plugin
# Thornswood's build expects is sitting in Data, Vortex has Thornswood on.
$root = Find-Root
if ($root) {
    $shipped = Join-Path $root 'Profile\Default\plugins.txt'
    if (Test-Path -LiteralPath $shipped) {
        $want = @(Get-Content -LiteralPath $shipped | Where-Object { $_ -like '[*]*' } | ForEach-Object { $_.Substring(1).Trim() })
        if ($want.Count -gt 0) {
            $there = @($want | Where-Object { Test-Path -LiteralPath (Join-Path $Source "Data\$_") }).Count
            if ($there -eq $want.Count) {
                Die "Vortex has the Thornswood profile deployed, not $Server's. In Vortex, enable the $Server profile and let it deploy, then run this again."
            }
        }
    }
}

$livePlugins = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition\plugins.txt'
if (Test-Path -LiteralPath $livePlugins) {
    $on = @(Get-Content -LiteralPath $livePlugins | Where-Object { $_ -like '[*]*' }).Count
    Say "  Vortex's active profile has $on plugins switched on. Make sure that is $Server's." 'DarkGray'
}

$recordDir = Join-Path $env:LOCALAPPDATA "Thornswood\GameFolders\$Server"
$recordFile = Join-Path $recordDir 'files.txt'
$null = New-Item -ItemType Directory -Force -Path $recordDir

# ---------------------------------------------------------------- links
if (-not ([System.Management.Automation.PSTypeName]'Thornswood.HardLink').Type) {
    Add-Type -Namespace Thornswood -Name HardLink -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, System.IntPtr lpSecurityAttributes);
'@
}

# ---------------------------------------------------------------- what goes
$deployed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($pair in @(@{ Dir = (Join-Path $Source 'Data'); Prefix = 'Data\' }, @{ Dir = $Source; Prefix = '' })) {
    foreach ($f in @(Get-ChildItem -LiteralPath $pair.Dir -Filter 'vortex.deployment*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $doc = ((Get-Content -LiteralPath $f.FullName -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
            foreach ($e in @($doc.files)) {
                $r = [string]$e.relPath
                if ($r) { [void]$deployed.Add($pair.Prefix + ($r -replace '/', '\').TrimStart('\')) }
            }
        } catch {
            Die "Vortex's record $($f.FullName) could not be read: $($_.Exception.Message)"
        }
    }
}
Say ("  Vortex deployed {0:n0} files" -f $deployed.Count) 'DarkGray'

$vanillaRootFiles = @('SkyrimSE.exe','SkyrimSELauncher.exe','steam_api64.dll','bink2w64.dll','Skyrim.ccc','installscript.vdf','Skyrim_Default.ini','High.ini','Low.ini','Medium.ini','Ultra.ini')
$vanillaDataFiles = @('Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm','_ResourcePack.esl','_ResourcePack.bsa')
$vanillaDataPatterns = @('Skyrim - *.bsa','cc*.esm','cc*.esl','cc*.esp','cc*.bsa')
$masters = @('Data\Skyrim.esm','Data\Update.esm','Data\Dawnguard.esm','Data\HearthFires.esm','Data\Dragonborn.esm','Data\_ResourcePack.esl')

function Test-Vanilla([string]$rel) {
    $parts = $rel -split '\\'
    if ($parts.Count -eq 1) { return ($vanillaRootFiles -contains $parts[0]) -or ($parts[0] -like 'skse64_*') }
    if ($parts[0] -ne 'Data') { return $false }
    if ($parts.Count -ge 3 -and ($parts[1] -in 'Video', 'Strings')) { return $true }
    if ($parts.Count -eq 2) {
        if ($vanillaDataFiles -contains $parts[1]) { return $true }
        foreach ($p in $vanillaDataPatterns) { if ($parts[1] -like $p) { return $true } }
    }
    return $false
}

# The client every SkyMP server runs. Identical whichever server installed it.
function Test-SkyMpRuntime([string]$rel) {
    if ($rel -match '^Data\\Platform\\(Distribution|Fonts|Images|Modules)\\') { return $true }
    if ($rel -match '^Data\\SKSE\\Plugins\\(MpClientPlugin|SkyrimPlatform|NirnLabUIPlugin)\.dll$') { return $true }
    if ($rel -ieq 'Data\Scripts\MpClientPlugin.pex') { return $true }
    return $false
}

# Thornswood's, by name or by what its own page and client say inside them.
function Test-Thornswood([string]$rel, [string]$full) {
    $leaf = Split-Path $rel -Leaf
    if ($leaf -like 'thornswood*') { return $true }
    if ($rel -ieq 'Data\SKSE\Plugins\Thornswood.ini') { return $true }
    if ($rel -ieq 'Data\SKSE\Plugins\po3_StartOnSave.ini') { return $true }
    if ($rel -match '^Data\\Interface\\(startmenu|loadwaitspinner)\.swf$') { return $true }
    if ($rel -ieq 'Data\Platform\UI\build.js') { return $true }
    if ($rel -match '^Data\\Platform\\(voice-[^\\]+\.txt|overlay-boot\.count)$') { return $true }
    if ($rel -ieq 'Data\Platform\UI\index.html' -or $rel -ieq 'Data\Platform\Plugins\skymp5-client.js') {
        try { return ([IO.File]::ReadAllText($full) -match 'thornswood') } catch { return $true }
    }
    return $false
}

# This server's own client files, where they can be told apart from the rest.
function Test-ServerOwn([string]$rel) {
    $leaf = Split-Path $rel -Leaf
    if ($isKeizaal) {
        if ($rel -match '^keizaal-backup-[^\\]*\\') { return $true }
        if ($rel -ieq 'VERSION') { return $true }
        if ($rel -match '^Data\\Video\\Interface\\(startmenu|loadwaitspinner)\.swf$') { return $true }
        if ($rel -match '^Data\\(Keizaal|Kzl)[^\\]*\.(esp|esm|esl|bsa)$') { return $true }
        if ($rel -match '^Data\\(Meshes|Textures)\\(Keizaal|kzlcustommeshs)\\') { return $true }
        if ($rel -match '^Data\\Meshes\\weapons\\kzl\\') { return $true }
        if ($rel -match '^Data\\Scripts\\Kzl[^\\]*\.pex$') { return $true }
        if ($rel -match '^Data\\Platform\\UI\\(assets\\|app\.js$|vite\.svg$|keizaal)') { return $true }
    }
    if ($isDaedric) {
        if ($rel -match '^DaedricData\\') { return $true }
        if ($leaf -like 'DaedricItemUseProbe*') { return $true }
        if ($rel -match '^Data\\Platform\\UI\\[^\\]*daedric') { return $true }
    }
    # NirnLab UI Platform, which is another server's interface framework and
    # the one thing Thornswood's own folder must not be given.
    #
    # SkyrimPlatform will not start on its own tilted backend while NirnLab is
    # in the folder. NirnLab puts its directory on the process PATH, its
    # libcef.dll is then loaded instead of the one in
    # Data\Platform\Distribution, and SkyrimPlatform stops with "Your PATH
    # environment variable contains incompatible entries" before the game
    # draws anything. Measured on 17 Sep in a folder this script had built.
    #
    # Leaving it out is also what stops CEFSubprocess.exe being here at all.
    # That is the second program Windows Firewall asks about, and no server
    # that draws its own interface in process ever asks anybody that.
    #
    # Nothing in the plugins this game loads asks for NirnLab.
    # Package-Thornswood keeps it out of the installer and Clean-OtherServers
    # calls it another roleplay server's. The copy in the Steam folder is not
    # touched, because that one is Vortex's.
    if ($rel -match '^Data\\NirnLabUIPlatform(\\|$)') { return $true }
    if ($leaf -ieq 'NirnLabUIPlugin.dll') { return $true }
    # Another plugin beside the client that is not Thornswood's. Said out loud
    # below, because the folder alone cannot say which server it came from.
    if ($rel -match '^Data\\Platform\\Plugins\\[^\\]+\.js$' -and $leaf -notlike 'thornswood-*' -and $leaf -ine 'skymp5-client.js') { return $true }
    return $false
}

function Test-Clutter([string]$rel) {
    $leaf = Split-Path $rel -Leaf
    if ($leaf -like 'vortex.deployment*') { return $true }
    if ($leaf -eq '__folder_managed_by_vortex') { return $true }
    if ($leaf -like '*.vortex_backup' -or $leaf -like '*.thornswood-off*') { return $true }
    if ($leaf -like '*.log' -or $leaf -like '*.pdb') { return $true }
    if ($rel -match '(^|\\)Claude outputs\\' -or $rel -like '_to_delete\*' -or $rel -like '.sentry-native\*') { return $true }
    # Sign-in data. It holds an access token, and a token is never duplicated.
    if ($rel -like 'Data\Platform\PluginsNoLoad\*') { return $true }
    return $false
}

$replaced = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($b in @(Get-ChildItem -LiteralPath $Source -Directory -Filter 'keizaal-backup-*' -ErrorAction SilentlyContinue)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $b.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        [void]$replaced.Add($f.FullName.Substring($b.FullName.Length + 1))
    }
}
$copyTypes = @('.ini','.json','.toml','.txt','.cfg','.xml','.yaml','.yml','.js','.html','.htm','.css','.dll','.exe','.asi','.bat','.cmd','.ps1','.count','.bak','.ess','.skse','.md','.csv','.jslot')
function Test-MustCopy([string]$rel) {
    if ($rel -notmatch '\\') { return $true }
    if ($rel -match '^Data\\(Platform|SKSE|MCM|Video)\\') { return $true }
    if ($masters -contains $rel) { return $true }
    if ($replaced.Contains($rel)) { return $true }
    if ($rel -match '^keizaal-backup-') { return $true }
    return ($copyTypes -contains ([IO.Path]::GetExtension($rel).ToLowerInvariant()))
}

# ---------------------------------------------------------------- the record
$old = @{}
$madeFile = Join-Path $recordDir 'made.txt'
$recordFor = ''
if (Test-Path -LiteralPath $madeFile) {
    $hit = @(Get-Content -LiteralPath $madeFile | Where-Object { $_ -like 'path=*' })
    if ($hit.Count) { $recordFor = $hit[0].Substring(5) }
}
if ((Test-Path -LiteralPath $recordFile) -and (Test-Path -LiteralPath $Path) -and ($recordFor -ieq $Path)) {
    foreach ($line in [IO.File]::ReadLines($recordFile)) {
        $p = $line.Split([char[]]'|', 5)
        if ($p.Count -eq 5) { $old[$p[4]] = [pscustomobject]@{ Kind = $p[0]; Origin = $p[1]; Size = [long]$p[2]; Ticks = [long]$p[3] } }
    }
    Say ("  bringing the existing folder up to date ({0:n0} files on record)" -f $old.Count) 'DarkGray'
} elseif (Test-Path -LiteralPath $Path) {
    if (@(Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1).Count) {
        Die "$Path already exists and was not made by this script. Pick another -Path, or empty that folder yourself first."
    }
}

# ---------------------------------------------------------------- walk
Head 'Making it'
$prefix = $Source + '\'
$lines = New-Object 'System.Collections.Generic.List[string]'
$left = New-Object 'System.Collections.Generic.List[string]'
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$added = 0; $changed = 0; $kept = 0; $theirs = 0; $removed = 0; $linked = 0; $copied = 0; $copiedBytes = 0L
$others = New-Object 'System.Collections.Generic.List[string]'
$n = 0

foreach ($f in Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue) {
    $rel = $f.FullName.Substring($prefix.Length)
    $n++
    if ($n % 5000 -eq 0) { Say ("  {0:n0} files looked at" -f $n) 'DarkGray' }

    if (Test-Clutter $rel) { continue }
    $origin = if ($deployed.Contains($rel)) { 'V' } else { 'O' }
    $take = $false
    if ($origin -eq 'V') { $take = $true }
    elseif (Test-Thornswood $rel $f.FullName) { $left.Add("$rel  (Thornswood's)"); continue }
    elseif (Test-Vanilla $rel) { $take = $true }
    elseif (Test-SkyMpRuntime $rel) { $take = $true }
    elseif (Test-ServerOwn $rel) {
        $take = $true
        if ($rel -match '^Data\\Platform\\Plugins\\') { $others.Add($rel) }
    }
    if (-not $take) { $left.Add("$rel  (not Skyrim's, not Vortex's, not $Server's)"); continue }
    [void]$seen.Add($rel)

    $dest = Join-Path $Path $rel
    $rec = $old[$rel]
    if (Test-Path -LiteralPath $dest) {
        $d = Get-Item -LiteralPath $dest -Force
        if ($rec -and ($d.Length -ne $rec.Size -or $d.LastWriteTimeUtc.Ticks -ne $rec.Ticks)) {
            # The server's launcher replaced it after this folder was made.
            $lines.Add(('{0}|{1}|{2}|{3}|{4}' -f $rec.Kind, $rec.Origin, $rec.Size, $rec.Ticks, $rel))
            $theirs++
            continue
        }
        if ($rec -and $rec.Size -eq $f.Length -and $rec.Ticks -eq $f.LastWriteTimeUtc.Ticks) {
            $lines.Add(('{0}|{1}|{2}|{3}|{4}' -f $rec.Kind, $origin, $f.Length, $f.LastWriteTimeUtc.Ticks, $rel))
            $kept++
            continue
        }
        if (-not $rec) {
            # In the folder but never placed by this script: the launcher put it
            # there. Left alone.
            $theirs++
            continue
        }
        Remove-Item -LiteralPath $dest -Force
        $changed++
    } else {
        $added++
    }

    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)
    $kind = 'C'
    if (-not (Test-MustCopy $rel)) {
        if ([Thornswood.HardLink]::CreateHardLink($dest, $f.FullName, [IntPtr]::Zero)) { $kind = 'L' }
    }
    if ($kind -eq 'C') {
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $copied++; $copiedBytes += $f.Length
    } else { $linked++ }
    $lines.Add(('{0}|{1}|{2}|{3}|{4}' -f $kind, $origin, $f.Length, $f.LastWriteTimeUtc.Ticks, $rel))
}

# Vortex no longer deploys these. Taken out only where the folder still holds
# exactly what this script put there.
foreach ($rel in @($old.Keys)) {
    if ($seen.Contains($rel)) { continue }
    $rec = $old[$rel]
    $dest = Join-Path $Path $rel
    if ($rec.Origin -ne 'V' -or -not (Test-Path -LiteralPath $dest)) { continue }
    $d = Get-Item -LiteralPath $dest -Force
    if ($d.Length -eq $rec.Size -and $d.LastWriteTimeUtc.Ticks -eq $rec.Ticks) {
        Remove-Item -LiteralPath $dest -Force
        $removed++
    }
}

[IO.File]::WriteAllLines($recordFile, $lines)
[IO.File]::WriteAllLines((Join-Path $recordDir 'left-out.txt'), $left)
[IO.File]::WriteAllLines($madeFile, @("source=$Source", "path=$Path", "at=$((Get-Date).ToString('o'))"))

# ---------------------------------------------------------------- said
Head 'Done'
Say ("  {0:n0} new, {1:n0} changed, {2:n0} unchanged, {3:n0} taken out" -f $added, $changed, $kept, $removed) 'Green'
Say ("  {0:n0} linked, {1:n0} copied ({2:n0} MB)" -f $linked, $copied, ($copiedBytes / 1MB)) 'Green'
if ($theirs) { Say ("  {0:n0} files the $Server launcher replaced were left as they are" -f $theirs) 'DarkGray' }
Say ("  {0:n0} files left out; the list is in {1}" -f $left.Count, (Join-Path $recordDir 'left-out.txt')) 'DarkGray'
foreach ($o in $others) { Say "  brought in as $Server's, because it is not Thornswood's: $o" 'Yellow' }
Write-Host ''
Say "  Now open the $Server launcher and point it at:" 'White'
Say "    $Path" 'White'
Say '  It puts its own client into that folder the first time it plays.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
