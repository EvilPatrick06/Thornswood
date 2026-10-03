$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\mods\LoadOrder.ps1')
. (Join-Path $repo 'scripts\release\Release-Name.ps1')
$publisher = Join-Path $repo 'scripts\release\Publish-Update.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($publisher, [ref]$null, [ref]$null)
foreach ($name in 'Val', 'Set-Prop', 'Get-ReferenceInServerOrder', 'Get-ActiveOrderKey', 'Update-DevNewsChannels') {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if ($null -eq $fn) { throw "Publisher lacks $name" }
    Invoke-Expression $fn.Extent.Text
}
function Say($message, $color) {}
function Die($message) { throw $message }
function Assert($condition, $message) { if (-not $condition) { throw $message }; Write-Host "PASS $message" }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-parity-' + [guid]::NewGuid().ToString('N'))
$Root = $tmp; $DistDir = Join-Path $tmp 'dist'; $GameDir = Join-Path $tmp 'Game'
[IO.Directory]::CreateDirectory($DistDir) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $GameDir 'Data')) | Out-Null
function Get-LoadOrderManifestUrl($root) { 'fixture' }
function Get-LoadOrderManifest($url) { return ,@('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', 'Thornswood-Content.esp') }
foreach ($name in (Get-LoadOrderManifest 'fixture') + @('FNIS.esp')) {
    $b = [byte[]]::new(24)
    [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($b, 0)
    if ($name -eq 'FNIS.esp') { [BitConverter]::GetBytes([uint32]0x200).CopyTo($b, 8) }
    [IO.File]::WriteAllBytes((Join-Path $GameDir "Data\$name"), $b)
}
$list = Join-Path $tmp 'plugins.txt'
[IO.File]::WriteAllLines($list, @('*Thornswood-Content.esp', '*FNIS.esp', 'CBBE 3BA Vanilla Outfits.esp'))
$original = [IO.File]::ReadAllText($list)
$packed = Get-ReferenceInServerOrder $list
Assert (([IO.File]::ReadAllLines($packed)) -contains '*FNIS.esp') 'Existing light plugins remain enabled'
Assert ([IO.File]::ReadAllText($list) -eq $original) 'Packing never modifies the source list'
$key = Get-ActiveOrderKey $list (Join-Path $GameDir 'Data')
[IO.File]::WriteAllLines($list, @('*Thornswood-Content.esp', '*FNIS.esp', '*CBBE 3BA Vanilla Outfits.esp'))
Assert ((Get-ActiveOrderKey $list (Join-Path $GameDir 'Data')) -eq $key) 'Removing an absent plugin reference cannot require a new character'
[IO.File]::WriteAllLines($list, @('*FNIS.esp', '*Thornswood-Content.esp'))
Assert ((Get-ActiveOrderKey $list (Join-Path $GameDir 'Data')) -ne $key) 'Changing the installed plugin order still changes the save warning key'
foreach ($channel in 'main', 'dev') {
    foreach ($missing in 'CBBE 3BA Vanilla Outfits.esp', 'Thornswood-Content.esp') {
        $file = Join-Path $GameDir "Data\$missing"
        $saved = if ([IO.File]::Exists($file)) { [IO.File]::ReadAllBytes($file) } else { $null }
        if ($saved) { [IO.File]::Delete($file) }
        [IO.File]::WriteAllLines($list, @('*Thornswood-Content.esp', '*FNIS.esp', "*$missing"))
        $refused = $false
        try { $null = Get-ReferenceInServerOrder $list } catch { $refused = $_.Exception.Message -like "*missing*" }
        Assert $refused "$channel refuses an enabled missing plugin: $missing"
        if ($saved) { [IO.File]::WriteAllBytes($file, $saved) }
    }
}
# Use actual git ancestry in a disposable repository, with one unfinished Dev commit.
$gitDir = Join-Path $tmp 'repo'; [IO.Directory]::CreateDirectory($gitDir) | Out-Null
& git -C $gitDir init -q
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm base --allow-empty
$base = (& git -C $gitDir rev-parse HEAD).Trim()
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm main --allow-empty
$main = (& git -C $gitDir rev-parse HEAD).Trim()
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm unfinished --allow-empty
$unfinished = (& git -C $gitDir rev-parse HEAD).Trim()
$mainDoc = [pscustomobject]@{ launcherVersion='1.1.105'; release=[pscustomobject]@{commit=$main;uncommitted=0}; news=@() }
$doc = [pscustomobject]@{ release=[pscustomobject]@{commit=$base;uncommitted=0}; mainVersion='1.1.103' }
$notes = @([pscustomobject]@{title='Renamed Main feature';channel='dev';sourceCommit=$base},
    [pscustomobject]@{title='Legacy feature';channel='dev'},
    [pscustomobject]@{title='Unfinished Dev work';channel='dev';sourceCommit=$unfinished},
    [pscustomobject]@{title='New dirty work';channel='dev';sourceCommit=''})
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[0].channel -eq '') 'A published ancestor is promoted despite a different news title'
Assert ($notes[1].channel -eq '') 'Legacy notes clear only when their recorded Dev source is published on Main'
Assert ($notes[2].channel -eq 'dev') 'Unmerged Dev work remains marked Dev'
Assert ($notes[3].channel -eq 'dev') 'A new dirty note cannot borrow an earlier clean release source'
$doc.release.uncommitted = 1; $notes[1].channel = 'dev'
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[1].channel -eq 'dev') 'Dirty legacy releases cannot be declared promoted'
$notes[0].channel = 'dev'; $before = $notes | ConvertTo-Json -Depth 5 -Compress
$null = Update-DevNewsChannels $doc $notes $null $gitDir
Assert (($notes | ConvertTo-Json -Depth 5 -Compress) -eq $before) 'An unreadable Main feed preserves news marks'
Assert ($doc.mainVersion -eq '1.1.103') 'An unreadable Main feed preserves the last known Main version'
[IO.Directory]::CreateDirectory((Join-Path $gitDir 'game')) | Out-Null
[IO.File]::WriteAllText((Join-Path $gitDir 'game\untracked-plugin.js'), 'new work')
Assert ((Get-ReleaseSource $gitDir).Uncommitted -eq 1) 'Untracked shipping inputs prevent source parity claims'
Write-Host 'PASS reference publication and source-based news promotion'
