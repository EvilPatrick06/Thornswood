<#
  Show-EslCascade.ps1

  Answers one question: if the server load order drops every ESL-flagged plugin,
  how much else has to go with it?

  SkyMP computes a form id as loadOrderIndex * 0x01000000 + shortId and has no
  FE space, so a server list containing light plugins cannot line up with the
  game. Dropping them lines it up exactly, because Skyrim gives a light plugin
  no normal index either. The cost is that anything mastering to a dropped
  plugin can no longer load, and that can cascade.

  Reads only the TES4 header of each plugin. Changes nothing.
#>
param(
    # Was the old build folder until 23 September, which is a folder neither
    # machine has had for weeks: this read an empty list and said so in a way
    # that looked like an answer.
    [string]$Data    = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Game\Data'),
    [string]$Plugins = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Profile\Default\plugins.txt')
)

function Read-Header([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    $len = [Math]::Min(16384, $fs.Length)
    $b = New-Object byte[] $len
    [void]$fs.Read($b, 0, $len)
    $fs.Close()

    $light = ($path -match '\.esl$')
    if ([Text.Encoding]::ASCII.GetString($b,0,4) -eq 'TES4') {
        if (([BitConverter]::ToUInt32($b,8) -band 0x200) -ne 0) { $light = $true }
    }

    $masters = @()
    for ($i = 0; $i -lt $b.Length - 6; $i++) {
        if ($b[$i] -eq 0x4D -and $b[$i+1] -eq 0x41 -and $b[$i+2] -eq 0x53 -and $b[$i+3] -eq 0x54) {
            $sz = [BitConverter]::ToUInt16($b, $i+4)
            if ($sz -gt 0 -and $sz -lt 260 -and ($i+6+$sz) -le $b.Length) {
                $s = [Text.Encoding]::GetEncoding(1252).GetString($b, $i+6, $sz).TrimEnd([char]0)
                if ($s -match '\.es[pml]$') { $masters += $s }
            }
        }
    }
    [pscustomobject]@{ Light = $light; Masters = ($masters | Select-Object -Unique) }
}

$implicit = 'Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm'
$enabled  = Get-Content -LiteralPath $Plugins |
            Where-Object { $_ -match '^\*' } |
            ForEach-Object { $_.TrimStart('*').Trim() }
$order = @($implicit | Where-Object { $enabled -notcontains $_ }) + $enabled

$info = @{}
foreach ($p in $order) {
    $full = Join-Path $Data $p
    if (Test-Path -LiteralPath $full) { $info[$p] = Read-Header $full }
}

$dropped = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($p in $order) { if ($info[$p] -and $info[$p].Light) { [void]$dropped.Add($p) } }
$directLight = $dropped.Count

# cascade: anything mastering to something already dropped has to go too
$because = @{}
do {
    $added = $false
    foreach ($p in $order) {
        if (-not $info[$p] -or $dropped.Contains($p)) { continue }
        foreach ($m in $info[$p].Masters) {
            if ($dropped.Contains($m)) {
                [void]$dropped.Add($p); $because[$p] = $m; $added = $true; break
            }
        }
    }
} while ($added)

$survivors = @($order | Where-Object { $info[$_] -and -not $dropped.Contains($_) })

Write-Host ''
Write-Host ("enabled plugins on disk    {0}" -f $info.Count)
Write-Host ("ESL-flagged                {0}" -f $directLight) -ForegroundColor Yellow
Write-Host ("dragged down with them     {0}" -f ($dropped.Count - $directLight)) -ForegroundColor Yellow
Write-Host ("would survive              {0}" -f $survivors.Count) -ForegroundColor Green
Write-Host ''

if ($because.Count) {
    Write-Host 'not light themselves, but master to something that is:' -ForegroundColor Yellow
    foreach ($k in ($because.Keys | Sort-Object)) {
        Write-Host ("    {0,-52} needs {1}" -f $k, $because[$k]) -ForegroundColor DarkGray
    }
    Write-Host ''
}

$tw = 'Thornswood-Content.esp'
if ($dropped.Contains($tw)) {
    Write-Host "Thornswood-Content.esp would be dropped too. This route is out." -ForegroundColor Red
} else {
    $i = [Array]::IndexOf($survivors, $tw)
    Write-Host ("Thornswood-Content.esp survives, at index {0} (0x{0:X2})" -f $i) -ForegroundColor Green
}
Write-Host ''
Write-Host 'The survivors, in order, are what a matching server load order would be.' -ForegroundColor DarkGray
