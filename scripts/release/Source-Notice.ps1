<#
.SYNOPSIS
  The note and licence texts that go inside every download on the update feed that carries SkyMP files.

.DESCRIPTION
  Source-Notice.ps1

  Publish-Update.ps1 dot-sources this. It puts a note saying where the source
  is, and the GNU GPL and AGPL texts, inside the client runtime zip and inside
  every pack that carries a SkyMP file.

  WHY IT EXISTS. Issue #421. The six files in records\client-build.json are
  SkyMP, under the GNU GPL version 3 (MpClientPlugin.dll under the AGPL), and
  both licences ask that a copy of the licence and directions to the source go
  with the files. The installer does that (SOURCE CODE.txt and the texts,
  Package-Thornswood.ps1). The feed did not: on 28 September the dev feed's
  client-runtime-8fb4673a.zip and the live feed's client-runtime-ccf71644.zip
  held the six files and nothing else, and a pack that carried one of them
  said nothing either. Those are the downloads the launcher takes the files
  from, so they are what hands them on.

  THE LAUNCHER IGNORES WHAT THIS ADDS. ClientRuntime.cs takes out of the
  client runtime zip only the six paths the record names, and Updater.Install
  unpacks only game\ and profile\ entries of a pack (and reads delete.txt). So
  a note and two texts at the top of either zip travel with the download and
  change nothing a launcher does.

  $SourceNoticeVersion goes into the feed's clientRuntime entry. A client
  runtime already on the feed without it (or with an older one) is published
  again even though its commit did not move, so the zip that carries the note
  replaces the one that did not.

  The folder and licence of each file are the same as Get-SourceNotice in
  Package-Thornswood.ps1 says in the installer's SOURCE CODE.txt, and
  tests\test-source-offer.ps1 holds the two to each other.
#>

$SourceNoticeVersion = 1

# Each SkyMP file the feed can carry, by its path in the game folder. Built:
# from the fork at the commit client-build.json names. Front: build.js, which
# every Ship builds from the fork's skymp5-front at the pin since #2931 and
# holds to front-build.json beside the client record. Not built: taken from
# upstream SkyMP, with no recorded commit (THIRD-PARTY.md, "From upstream
# SkyMP, not built here").
$SourceNoticeFiles = [ordered]@{
    'Data\SKSE\Plugins\MpClientPlugin.dll'                                     = @('skymp5-server',   'GNU AGPL version 3', 'built')
    'Data\SKSE\Plugins\SkyrimPlatform.dll'                                     = @('skyrim-platform', 'GNU GPL version 3',  'built')
    'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll'    = @('skyrim-platform', 'GNU GPL version 3',  'built')
    'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden' = @('skyrim-platform', 'GNU GPL version 3', 'built')
    'Data\Platform\Plugins\skymp5-client.js'                                   = @('skymp5-client',   'GNU GPL version 3',  'built')
    'Data\Scripts\TESModPlatform.pex'                                          = @('skyrim-platform', 'GNU GPL version 3',  'built')
    'Data\Platform\UI\build.js'                                                = @('skymp5-front',    'GNU GPL version 3',  'front')
    'Data\Platform\Modules\skyrimPlatform.ts'                                  = @('skyrim-platform', 'GNU GPL version 3',  'upstream')
    'Data\Scripts\MpClientPlugin.pex'                                          = @('client-deps',     'no LICENSE file in that folder', 'upstream')
}

<#
  The files to put at the top of a download that carries $Carried (paths in
  the game folder), as a list of @{ Name; Bytes }. Empty when none of them is
  a SkyMP file, so a pack of our own files gets nothing.

  $Kind 'runtime' is the client runtime zip: its note is README.txt and says
  what the download is. 'pack' is an update pack: its note is SOURCE CODE.txt,
  the name the installer gives the same note.

  Throws when a recorded file has no known source folder, so a new file in
  client-build.json stops the release until somebody says where it is from.

  build.js counts as built when $FrontRecord (front-build.json beside the
  client record, unless named) is there, and throws when that record is the
  build of another commit than the client record's, so the note never names
  one commit for files built from two. With no front record it is said as
  SkyMP's own, with no commit, as before #2931.
#>
function Get-SourceNoticeEntries([string]$ClientRecord, [string[]]$Carried, [string]$Kind, [string]$LicenceDir, [string]$FrontRecord) {
    if ($Kind -ne 'runtime' -and $Kind -ne 'pack') { throw "Kind is runtime or pack, not $Kind" }
    $any = $false
    foreach ($x in @($Carried)) { if ($x -and $SourceNoticeFiles.Contains($x)) { $any = $true; break } }
    if (-not $any) { return @() }
    if (-not (Test-Path -LiteralPath $ClientRecord)) { throw "$ClientRecord is missing" }
    # An empty record reads as $null; say so, rather than a method call on $null.
    $raw = "$(Get-Content -LiteralPath $ClientRecord -Raw)"
    if (-not $raw.Trim([char]0xFEFF, ' ', [char]9, [char]13, [char]10)) { throw "$ClientRecord is empty" }
    $c = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json
    $fork = ([string]$c.fork).TrimEnd('/')
    if (-not $fork -or -not $c.forkCommit) { throw 'client-build.json names no fork or no commit' }
    $recorded = @($c.files.PSObject.Properties.Name)
    foreach ($r in $recorded) {
        if (-not $SourceNoticeFiles.Contains($r)) { throw "client-build.json lists $r, which has no known source folder" }
    }

    if (-not $FrontRecord) { $FrontRecord = Join-Path (Split-Path -Parent $ClientRecord) 'front-build.json' }
    $frontBuilt = $false
    if (Test-Path -LiteralPath $FrontRecord) {
        $fRaw = "$(Get-Content -LiteralPath $FrontRecord -Raw)"
        if (-not $fRaw.Trim([char]0xFEFF, ' ', [char]9, [char]13, [char]10)) { throw "$FrontRecord is empty" }
        $fc = ([string]($fRaw.TrimStart([char]0xFEFF) | ConvertFrom-Json).forkCommit).ToLowerInvariant()
        $cc = ([string]$c.forkCommit).ToLowerInvariant()
        if (-not $fc -or -not ($fc.StartsWith($cc) -or $cc.StartsWith($fc))) {
            throw "$FrontRecord is the build of $fc and client-build.json of $cc. The note names one commit for what Thornswood built."
        }
        $frontBuilt = $true
    }

    $built = @(); $upstream = @()
    foreach ($k in $SourceNoticeFiles.Keys) {
        $has = $false
        foreach ($x in @($Carried)) { if ($x -and $x.Equals($k, [StringComparison]::OrdinalIgnoreCase)) { $has = $true; break } }
        if (-not $has) { continue }
        $v = $SourceNoticeFiles[$k]
        $leaf = $k.Substring($k.LastIndexOf('\') + 1)
        $row = ('  {0,-34}{1,-18}{2}' -f $leaf, $v[0], $v[1])
        if (($v[2] -eq 'built' -and ($recorded -contains $k)) -or ($v[2] -eq 'front' -and $frontBuilt)) { $built += $row } else { $upstream += $row }
    }
    if (-not $built.Count -and -not $upstream.Count) { return @() }

    $ub = [string]$c.upstreamBase
    $base = if ($ub -match '^[0-9a-f]{7,40}$') { 'SkyMP commit ' + $ub } else { 'SkyMP, at a commit the build record does not name' }

    if ($Kind -eq 'runtime') {
        $note = 'README.txt'
        $lines = @(
            'THORNSWOOD CLIENT RUNTIME',
            '=========================',
            '',
            'This download is the SkyMP files the Thornswood launcher puts into your',
            'Skyrim folder. The launcher fetches it by itself when one of them is',
            'missing or is not the build it expects, takes them out, and deletes the',
            'download. Nothing here needs copying by hand.',
            '',
            'WHERE THE SOURCE CODE IS',
            ''
        )
    } else {
        $note = 'SOURCE CODE.txt'
        $lines = @(
            'THORNSWOOD: WHERE THE SOURCE CODE IS',
            '====================================',
            '',
            'This update from the Thornswood launcher carries SkyMP files, listed below.',
            ''
        )
    }
    $lines += @(
        'SkyMP is free software. Anybody can read its source or download it, with no',
        'account.',
        ''
    )
    if ($built.Count) {
        $lines += @(
            'These are built from Thornswood''s public copy of SkyMP, with Thornswood''s',
            'changes on top:',
            ('  commit    ' + $c.forkCommit + ', branch ' + $c.forkBranch),
            ('  source    ' + $fork + '/tree/' + $c.forkCommit),
            ('  based on  ' + $base),
            '',
            'Each file, the folder of SkyMP it is built from, and the licence in that',
            'folder''s LICENSE file:',
            ''
        ) + $built + @('')
    }
    if ($upstream.Count) {
        $lines += @(
            'These come from SkyMP itself. Thornswood did not build them, and nobody',
            'recorded which version of SkyMP they came from, so no commit is named for',
            'them here. Their source is SkyMP''s own, at the address below. Each file,',
            'the folder of SkyMP it belongs to, and that folder''s licence:',
            ''
        ) + $upstream + @('')
    }
    $lines += @(
        'SkyMP itself is https://github.com/skyrim-multiplayer/skymp',
        '',
        'The full licence texts are beside this note:',
        '  GPL-3.0.txt     GNU GPL version 3 (skymp5-client, skyrim-platform, skymp5-front)',
        '  AGPL-3.0.txt    GNU AGPL version 3 (skymp5-server, which MpClientPlugin.dll is built from)',
        '',
        'https://thornswood.net/credits#source says where the source of everything',
        'Thornswood hands out is.',
        ''
    )

    $utf8 = New-Object Text.UTF8Encoding($false)
    $out = @(@{ Name = $note; Bytes = $utf8.GetBytes(($lines -join "`r`n")) })
    foreach ($lic in @('GPL-3.0.txt', 'AGPL-3.0.txt')) {
        $p = Join-Path $LicenceDir $lic
        if (-not (Test-Path -LiteralPath $p)) { throw "$p is missing. The GPL and AGPL texts have to go with the SkyMP files (#421)." }
        $out += @{ Name = $lic; Bytes = [IO.File]::ReadAllBytes($p) }
    }
    return $out
}

# Writes those entries at the top of an open ZipArchive.
function Add-SourceNoticeToZip($Zip, $Entries) {
    foreach ($n in @($Entries)) {
        if ($null -eq $n) { continue }
        $e = $Zip.CreateEntry($n.Name, [IO.Compression.CompressionLevel]::Optimal)
        $s = $e.Open()
        try { $s.Write($n.Bytes, 0, $n.Bytes.Length) } finally { $s.Dispose() }
    }
}
