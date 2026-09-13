<#
  Chargen-Log.ps1 - what the server thinks is happening to your character.

  The gamemode logs every step of creation: which stage each character is at,
  every item it hands over, and every form it could not resolve. That log is on
  the VPS and it is the only place the whole story is written down. The client
  side plugin can only report what it can see in your pack, which is the last
  link in the chain rather than the first.

  Nothing is changed. This reads.
#>

[CmdletBinding()]
param(
  [string] $Vps  = '192.135.112.23',
  [string] $User = 'Administrator',
  [int]    $Lines = 60
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }

$remote = @'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\Thornswood-Server\server.log'
if (-not (Test-Path $log)) { 'no server.log on the VPS'; exit }

'=== who connected, and as what ==='
Get-Content $log | Select-String -Pattern 'logged as|Loading character|Connecting a user|disconnect' |
  Select-Object -Last 12 | ForEach-Object { $_.Line }

'=== every creation step the server took ==='
$c = Get-Content $log | Select-String -Pattern 'chargen' | Select-Object -Last LINES
if ($c) { $c | ForEach-Object { $_.Line } } else { 'the gamemode has not logged a single chargen line' }

'=== forms it could not resolve ==='
$m = Get-Content $log | Select-String -Pattern 'no form for|did not resolve|unresolved' | Select-Object -Last 20
if ($m) { $m | ForEach-Object { $_.Line } } else { 'none' }

'=== errors ==='
$e = Get-Content $log | Select-String -Pattern '\[error\]|threw' | Select-Object -Last 15
if ($e) { $e | ForEach-Object { $_.Line } } else { 'none' }
'@ -replace 'LINES', $Lines

$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
& ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$User@$Vps" "powershell -NoProfile -EncodedCommand $enc"
