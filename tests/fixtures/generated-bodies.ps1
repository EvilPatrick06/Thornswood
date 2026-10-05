<#
  generated-bodies.ps1, dot-sourced by the release harnesses that run the real
  Publish-Update.ps1 against a stand-in Thornswood root.

  Since d2519bb a publish needs the covered bodies Build-Generated.ps1 makes:
  Assert-ShipGeneratedBodies (scripts\release\Ship-Rules.ps1) wants every file
  $ShipGeneratedBodyFiles names in <Root>\Game, and <Root>\Profile\OwnGame\generated.txt
  listing each with its sha256, naming <Root>\Game as the folder it was built
  in, and current by Get-GeneratedState (scripts\mods\Generated.ps1). A
  stand-in without them is refused before the part a harness is about.

  New-GeneratedBodies gives a stand-in what a build leaves, made by the code's
  own pieces rather than a copy of the format: the body list out of
  Ship-Rules.ps1, the inputs out of Get-GeneratedInputs, and the record written
  by Write-GeneratedRecord. The bodies are a line of text each, since nothing
  here reads them as meshes. Call it once Profile\OwnGame\files.txt and
  plugins.txt are written, because the record holds their hash, and with the
  repository the publisher runs from, because the record holds the hash of its
  records\generated.json.
#>
function New-GeneratedBodies([string]$Root, [string]$Repo) {
    $game = Join-Path $Root 'Game'
    $bodies = & {
        . (Join-Path $Repo 'scripts\release\Ship-Rules.ps1')
        $ShipGeneratedBodyFiles
    }
    & {
        . (Join-Path $Repo 'scripts\mods\Generated.ps1')
        $outputs = @(foreach ($rel in $bodies) {
            $file = Join-Path $game $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            [IO.File]::WriteAllText($file, 'a covered body as Build-Generated.ps1 leaves it: ' + $rel)
            [pscustomobject]@{ Rel = $rel; Sha = (Get-GeneratedFileSha $file) }
        })
        $inputs = Get-GeneratedInputs $Root (Join-Path $Repo 'records\generated.json')
        Write-GeneratedRecord (Get-GeneratedRecordPath $Root) $game $inputs $outputs
    }
}
