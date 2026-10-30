<#
  CloudflareRanges.ps1

  Dot-sourced. Reads scripts\deploy\cloudflare-ranges.txt, the addresses
  Cloudflare's proxy reaches the box from, and says whether an address is
  inside them (#2995). Setup-Domain.ps1 uses it to accept a name that points
  at Cloudflare, Set-WebFirewall.ps1 to send the list to the box.

  The box script (vps-web-firewall.ps1) and Watch-Outside.ps1 run with
  nothing beside them, so each carries its own few lines of the same rule;
  tests\test-2995-cloudflare-front.ps1 holds all three to the same answers.
#>

# The ranges in the file, in its order. Throws, naming the line, when an
# entry is not an address and a prefix length, and when there are none.
function Read-ThornswoodCloudflareRanges([string]$Path = '') {
    if (-not $Path) { $Path = Join-Path $PSScriptRoot 'cloudflare-ranges.txt' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "There is no $Path." }
    $out = @()
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $n++
        $t = ($line -replace '#.*$', '').Trim()
        if (-not $t) { continue }
        if (-not (ConvertTo-ThornswoodRange $t)) { throw ("Line $n of $Path, '" + $t + "', is not an address and a prefix length.") }
        $out += $t
    }
    if (-not $out.Count) { throw "$Path lists no ranges." }
    return , $out
}

# An address and a prefix length as its bytes and the bits that must match,
# or $null.
function ConvertTo-ThornswoodRange([string]$Text) {
    $parts = $Text.Trim().Split('/')
    if ($parts.Count -ne 2 -or $parts[1] -notmatch '^\d{1,3}$') { return $null }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($parts[0], [ref]$ip)) { return $null }
    if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $parts[0] -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $null }
    $bytes = $ip.GetAddressBytes()
    $bits = [int]$parts[1]
    if ($bits -lt 1 -or $bits -gt $bytes.Length * 8) { return $null }
    return [pscustomobject]@{ Bytes = $bytes; Bits = $bits; Text = $Text.Trim() }
}

function Test-ThornswoodInRanges([string]$Address, $Ranges) {
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and $ip.IsIPv4MappedToIPv6) { $ip = $ip.MapToIPv4() }
    $b = $ip.GetAddressBytes()
    foreach ($t in @($Ranges)) {
        $r = ConvertTo-ThornswoodRange ('' + $t)
        if (-not $r -or $r.Bytes.Length -ne $b.Length) { continue }
        $left = $r.Bits
        $same = $true
        for ($i = 0; $i -lt $b.Length -and $left -gt 0; $i++) {
            $take = [Math]::Min(8, $left)
            $mask = [byte]((0xFF -shl (8 - $take)) -band 0xFF)
            if (($b[$i] -band $mask) -ne ($r.Bytes[$i] -band $mask)) { $same = $false; break }
            $left -= $take
        }
        if ($same) { return $true }
    }
    return $false
}
