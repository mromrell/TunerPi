[CmdletBinding()]
param([string]$ExpectedName = 'TunerPi BMW 325i')

$adapters = Get-PnpDevice -Class Bluetooth -Status OK -ErrorAction SilentlyContinue
if (-not $adapters) { throw 'No enabled Bluetooth adapter is available on this computer.' }
"Bluetooth adapter(s):"; $adapters | Select-Object -ExpandProperty FriendlyName
$paired = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like "*$ExpectedName*" }
if ($paired) { "PASS: paired Pi found: $($paired.FriendlyName -join ', ')"; exit 0 }
"INFO: this Windows host has Bluetooth but no paired '$ExpectedName' device. Pairing is exercised from the Android app during device testing."; exit 0
