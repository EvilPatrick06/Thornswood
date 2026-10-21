<#
  Run-OnBox.ps1

  Runs one of the repository's Python tools on the VPS box, against the game
  plugins a game server there already holds, and brings back what the tool
  wrote into the repository's game\ and records\ folders. Issue #2899.

      pwsh scripts/mods/Run-OnBox.ps1 scripts/mods/Add-ContentRecords.py --check --masters '{data}'
      pwsh scripts/mods/Run-OnBox.ps1 scripts/mods/Add-ContentRecords.py --masters '{data}'
      pwsh scripts/mods/Run-OnBox.ps1 scripts/mods/Build-WoodworkerTrailOverrides.py --check --masters '{data}' -Server main

  WHY. Patrick, 20 Oct 2026: "let's make the content plugin available in the
  cloud". The content plugin's tools read the game's Data folder, which was
  only on One (C:\Thornswood\Game\Data). Measured 20 Oct from a cloud
  session: both game servers on the box hold every plugin of the load order
  in their plugins folder (103 files, 383 MB), because a server loads them,
  and the box has Python 3.12. So the tool goes to the plugins, and no
  Bethesda or mod author's file is copied anywhere it was not already. What
  the box does not hold is Skyrim's own archives (.bsa): a tool that reads
  string tables, meshes or the interface stops there with its own sentence,
  and where those may go is Patrick's question on #2899.

  WHAT GOES UP. The commit, never the working tree: the tools, the plugins
  and the tables they read (scripts\mods, scripts\dev, game\content,
  game\data, records, layout.json, and every other file a Python builder of
  scripts\mods\content-tables.json reads or writes, game\gamemode.js among
  them) as one artifact (Artifact.ps1, #459), so
  an uncommitted change under those folders refuses the run before the box
  is asked anything. Commit it first; what ran is then a commit anyone can
  name.

  ON THE BOX, one folder of the run's own under C:\Windows\Temp. It lives
  as long as one ssh session, the keeper's (scripts\mods\OnBox.ps1, #2999):
  the keeper makes it, holds it for the whole run and removes it when this
  says the run is over or the session drops. A keeper killed with its session
  cannot remove anything, but it stops holding the folder when it dies, and
  the next run's keeper removes every folder nobody holds before it makes its
  own. So nothing stays on the box past the next run, however a run ended:
    repo\   the artifact, laid out like the repository; the tool runs here
    data\   a copy of the server's plugins folder, with this commit's own
            Thornswood plugins in place of the ones the server runs. A copy,
            not links, so a tool given --data {data} that writes can never
            reach the server's own files
  '{data}' in an argument is the data folder and '{repo}' the repository
  folder, both on the box. THORNSWOOD_DATA names the data folder too, for
  the tools that read it. The tool runs at below normal priority, because
  the box is also where both game servers run.

  WHAT COMES BACK. Every file under game\ and records\ that the tool wrote
  or changed, by sha256 against what was sent, and nothing else. It is put
  into this checkout at the same path, and listed, so git diff shows what
  the run did. A tool that changed nothing brings nothing back.

  The tools themselves are unchanged: run on One, they read
  C:\Thornswood\Game\Data as before.
#>
[CmdletBinding()]
param(
    # The tool, as a repository path: scripts/mods/<name>.py or scripts/dev/<name>.py.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,

    # What the tool is run with, as it would be typed after its name.
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @(),

    # Whose plugins: the dev server's (the load order dev runs) or live's.
    [ValidateSet('dev', 'main')]
    [string]$Server = 'dev',

    [string]$VpsHost = '',
    [string]$VpsUser = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\deploy\Artifact.ps1')
. (Join-Path $Here 'OnBox.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$repo = (Resolve-Path -LiteralPath (Join-Path $Here '..\..')).ProviderPath
$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# Only a tool of the repository's, named as the artifact will hold it.
$tool = $Script.Replace('\', '/').TrimStart('.', '/')
if ($tool -notmatch '^scripts/(mods|dev)/[A-Za-z0-9_.-]+\.py$') {
    throw "$Script is not a Python tool under scripts/mods or scripts/dev. Nothing was sent."
}
if (-not (Test-Path -LiteralPath (Join-Path $repo $tool))) { throw "There is no $tool in this checkout. Nothing was sent." }
foreach ($a in $Arguments) {
    # The far side quotes each argument for Windows; a double quote or a line
    # break inside one would end it early.
    if ($a -match '["\r\n]') { throw "An argument holds a double quote or a line break: $a. Nothing was sent." }
}

$serverRoot = $(if ($Server -eq 'main') { 'C:\Thornswood-Server' } else { 'C:\Thornswood-Server-Dev' })
$paths = @('scripts/mods', 'scripts/dev', 'game/content', 'game/data', 'records', 'layout.json')
# And whatever else a Python builder of the content chain reads or writes
# (scripts\mods\content-tables.json). Until #2962 the artifact held only the
# folders above, so every builder that writes its table into game\gamemode.js
# (the building holds, the woodworking benches, the doors and five more)
# stopped on the box with "No such file" for gamemode.js, and the one that
# reads docs\systems\cut-items.json would have too.
$chainFiles = [IO.File]::ReadAllText((Join-Path $Here 'content-tables.json')) | ConvertFrom-Json
foreach ($s in @($chainFiles.steps | Where-Object { $_.tool -like '*.py' })) {
    foreach ($p in @(@($s.reads) + @($s.readsBack) + @($s.writes) | Where-Object { $_ })) {
        $p = [string]$p
        if (-not @($paths | Where-Object { $p -eq $_ -or $p.StartsWith($_ + '/') }).Count) { $paths += $p }
    }
}
$artifact = New-ThornswoodArtifact -Component tools -RepoDir $repo -Paths $paths
Say ('artifact ' + (Format-ThornswoodArtifact $artifact)) 'DarkGray'

# Not named like the box's run folders, so a run on a machine whose temp
# folder is C:\Windows\Temp is never taken for one of them.
$local = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-runonbox-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
New-Item -ItemType Directory -Force -Path $local | Out-Null
$box = $null
$code = 1
try {
    # The run's folder, held by its keeper until the finally below (OnBox.ps1).
    $box = Open-ThornswoodOnBoxFolder -Target $target -SshArgs $ssh
    $run = $box.Run
    $runFar = $box.Far
    foreach ($l in $box.Said) { Say ('box  ' + $l) 'DarkGray' }
    if (-not $box.Made) { throw ('could not make ' + $run + ' on the box. What ssh said is above.') }
    $farRun = Get-ThornswoodOnBoxScript -Run $run -ServerRoot $serverRoot -Tool $tool -Arguments $Arguments
    # The run's own script goes into its folder, so it goes with the folder.
    $farFile = Join-Path $local 'run.ps1'
    [IO.File]::WriteAllText($farFile, $farRun, (New-Object Text.UTF8Encoding($true)))
    Send-ThornswoodArtifactFile $artifact.Zip $target $ssh ($runFar + '/tools.zip')
    Send-ThornswoodArtifactFile $farFile $target $ssh ($runFar + '/run.ps1')
    Say ("running $tool on the box, against the $Server server's plugins") 'Cyan'
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $lines = @(Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Bypass -Script ("& '" + $run + "\run.ps1'") | Where-Object { $_ -is [string] } | ForEach-Object { $_.Trim() }) } finally { $ErrorActionPreference = $eap }
    $changed = @()
    $exit = $null
    foreach ($l in $lines) {
        if ($l -match '^CHANGED (.+)$') { $changed += $Matches[1].Trim(); continue }
        if ($l -match '^EXIT (-?\d+)\s*$') { $exit = [int]$Matches[1]; continue }
        Write-Host $l
    }
    if ($null -eq $exit) { throw 'the box did not say how the tool ended, so nothing was brought back.' }
    $code = $exit

    if ($changed.Count) {
        $back = Join-Path $local 'back.zip'
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { Invoke-ThornswoodNative { & scp @ssh ($target + ':' + $runFar + '/back.zip') $back } 2>&1 | Out-Null; $got = $LASTEXITCODE } finally { $ErrorActionPreference = $eap }
        if ($got -ne 0) { throw ('scp could not bring back what the tool wrote (' + $changed.Count + ' file(s)). This checkout was not changed.') }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($back)
        try {
            # Only what the box listed, and only under game/ and records/.
            foreach ($e in $zip.Entries) {
                $p = $e.FullName.Replace('\', '/')
                if ($changed -notcontains $p -or $p -notmatch '^(game|records)/' -or $p -match '(^|/)\.\.(/|$)') {
                    throw ("the box sent back $p, which it did not list as written under game/ or records/. This checkout was not changed.")
                }
            }
            Say ''
            Say ('the tool wrote ' + $changed.Count + ' file(s), now in this checkout:') 'Green'
            foreach ($e in $zip.Entries) {
                $dest = Join-Path $repo $e.FullName
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                Say ('  ' + $e.FullName)
            }
        } finally { $zip.Dispose() }
    } else {
        Say ''
        Say 'the tool wrote nothing under game/ or records/' 'DarkGray'
    }
} finally {
    if ($box) {
        $shut = Close-ThornswoodOnBoxFolder $box
        if (-not $shut.Gone) {
            $then = $(if ($shut.Told) { 'The next run removes it once nothing holds it.' } else { 'Its keeper could not be told to end, so it still holds it (#3063).' })
            Write-Host ($box.Run + ' is still on the box (' + $(if ($shut.Said.Count) { $shut.Said -join ' ' } else { 'the keeper''s session ended without a word' }) + '). ' + $then) -ForegroundColor Yellow
        }
    }
    Remove-Item -LiteralPath $local -Recurse -Force -ErrorAction SilentlyContinue
}
Say ('the tool exited ' + $code) $(if ($code -eq 0) { 'Green' } else { 'Yellow' })
exit $code
