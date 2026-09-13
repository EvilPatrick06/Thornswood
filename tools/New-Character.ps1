<#
  New-Character.ps1

  Throws the test character away so the next connect builds a fresh one.

  Reset-Appearance.ps1 keeps the character and reopens the race menu, which is
  right when you care about the character. While the creation flow itself is
  what is being tested, you do not: you want the face menu, the trade menu and
  the town menu every single launch, and you want nothing carried over from the
  last attempt.

  So this deletes the player change forms outright. The server then has no actor
  for your profile, takes its create path, and the whole flow runs from the top.
  World objects are left alone.

  THE SERVER MUST BE STOPPED. It holds change forms in memory and writes them on
  its own schedule, so deleting them underneath a running server just gets them
  written straight back.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$World = 'C:\Thornswood-Dev\skymp\build\dist\server\world\changeForms',
    [switch]$NoBackup
)

if (-not (Test-Path -LiteralPath $World)) { throw "not found: $World" }

if (Get-Process -Name node -ErrorAction SilentlyContinue) {
    Write-Host 'A node process is running. If that is the Thornswood server, stop it first or this will be undone.' -ForegroundColor Yellow
}

# Player change forms are the numerically named ones. Everything else is a world
# object keyed by form id and plugin, like 13164_JKs Whiterun.esp.json.
$players = Get-ChildItem -LiteralPath $World -Filter '*.json' |
           Where-Object { $_.BaseName -match '^\d+$' }

if (-not $players) {
    Write-Host 'No player change forms. The next connect already builds a fresh character.' -ForegroundColor Green
    return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bin = Join-Path $World "_discarded-$stamp"
$gone = 0

foreach ($f in $players) {
    $name = 'unnamed'
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        if ($j.appearanceDump -and $j.appearanceDump.name) { $name = $j.appearanceDump.name }
        $profile = $j.profileId
    } catch { $profile = '?' }

    if (-not $PSCmdlet.ShouldProcess("$($f.Name) (profile $profile, '$name')", 'discard')) { continue }

    if ($NoBackup) {
        Remove-Item -LiteralPath $f.FullName -Force
    } else {
        if (-not (Test-Path -LiteralPath $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $bin $f.Name) -Force
    }
    Write-Host ("  discarded {0}  profile {1}  '{2}'" -f $f.Name, $profile, $name) -ForegroundColor Cyan
    $gone++
}

Write-Host ''
if ($gone -gt 0) {
    Write-Host "$gone character(s) gone. The next connect runs creation from the top." -ForegroundColor Green
    if (-not $NoBackup) { Write-Host "  the old ones are in $bin if you ever want them" -ForegroundColor DarkGray }
} else {
    Write-Host 'nothing changed.' -ForegroundColor Yellow
}
