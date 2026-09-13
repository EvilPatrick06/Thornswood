<#
  Find-MissingMasters.ps1

  Reads the TES4 header of every plugin in Data and reports any master that is
  no longer present. A missing master is an instant crash at load, so this is
  the check to run after pulling plugins out of the load order.

  Only the first 8 KB of each file is read. MAST fields always live in the TES4
  record, which is the first record in the file.
#>
param([string]$Data = 'C:\SkyrimTogether\Game\Data')

$present = @{}
Get-ChildItem -LiteralPath $Data -File |
    Where-Object { $_.Extension -in '.esp','.esm','.esl' } |
    ForEach-Object { $present[$_.Name.ToLower()] = $true }

$enabled = @{}
$pl = 'C:\SkyrimTogether\Profile\Default\plugins.txt'
if (Test-Path $pl) {
    Get-Content $pl | Where-Object { $_ -match '^\*' } |
        ForEach-Object { $enabled[$_.TrimStart('*').Trim().ToLower()] = $true }
}

$problems = @()
foreach ($f in (Get-ChildItem -LiteralPath $Data -File |
                Where-Object { $_.Extension -in '.esp','.esm','.esl' } | Sort-Object Name)) {

    $fs = [IO.File]::OpenRead($f.FullName)
    $buf = New-Object byte[] ([Math]::Min(8192, $fs.Length))
    [void]$fs.Read($buf, 0, $buf.Length)
    $fs.Close()

    # scan the header bytes for MAST fields: 'MAST' + uint16 size + zstring
    $masters = @()
    for ($i = 0; $i -lt $buf.Length - 6; $i++) {
        if ($buf[$i] -eq 0x4D -and $buf[$i+1] -eq 0x41 -and $buf[$i+2] -eq 0x53 -and $buf[$i+3] -eq 0x54) {
            $sz = [BitConverter]::ToUInt16($buf, $i + 4)
            if ($sz -gt 0 -and $sz -lt 260 -and ($i + 6 + $sz) -le $buf.Length) {
                $s = [Text.Encoding]::GetEncoding(1252).GetString($buf, $i + 6, $sz).TrimEnd([char]0)
                if ($s -match '\.es[pml]$') { $masters += $s }
            }
        }
    }

    foreach ($m in ($masters | Select-Object -Unique)) {
        if (-not $present.ContainsKey($m.ToLower())) {
            $problems += [pscustomobject]@{
                Plugin  = $f.Name
                Missing = $m
                State   = if ($enabled.ContainsKey($f.Name.ToLower())) { 'ENABLED' } else { 'disabled' }
            }
        }
    }
}

Write-Host ''
if (-not $problems) {
    Write-Host "no missing masters. every plugin's dependencies are present." -ForegroundColor Green
} else {
    $live = @($problems | Where-Object State -eq 'ENABLED')
    $problems | Sort-Object State, Plugin | Format-Table -AutoSize
    if ($live) {
        Write-Host ("{0} ENABLED plugin(s) have a missing master. That crashes at load." -f $live.Count) -ForegroundColor Red
    } else {
        Write-Host "all affected plugins are already disabled. nothing will crash." -ForegroundColor Yellow
    }
}
