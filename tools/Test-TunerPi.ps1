[CmdletBinding()]
param(
    [string]$PiHost = '10.42.0.1',
    [ValidateRange(15, 1800)][int]$TimeoutSeconds = 600,
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\test-results\tunerpi-remote.json')
)

$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$base = "http://$PiHost`:8088"
$report = [ordered]@{
    started = (Get-Date).ToUniversalTime().ToString('o')
    host = $PiHost
    checks = @()
}

function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:report.checks += [ordered]@{ name = $Name; passed = $Passed; detail = $Detail }
    $state = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} - {2}" -f $state, $Name, $Detail)
}

function Get-PiJson([string]$Path) {
    Invoke-RestMethod -Uri "$base$Path" -TimeoutSec 8 -Headers @{ Accept = 'application/json' }
}

do {
    try { $health = Get-PiJson '/api/health'; break } catch { Start-Sleep -Seconds 5 }
} while ((Get-Date) -lt $deadline)

if (-not $health) {
    Add-Check 'Pi health API' $false "No response from $base/api/health before timeout. Connect this computer to TunerPi-AA Wi-Fi."
    $report.finished = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    exit 1
}

Add-Check 'Pi health API' ($health.status -eq 'ok') "status=$($health.status)"
Add-Check 'Log API service' ($health.services.'tunerpi-logs-api.service' -eq 'active') "state=$($health.services.'tunerpi-logs-api.service')"
Add-Check 'Crankshaft core' ($health.services.'crankshaft-core.service' -eq 'active') "state=$($health.services.'crankshaft-core.service')"
Add-Check 'Bluetooth identity' ($health.bluetooth.alias -eq 'TunerPi BMW 325i') "alias=$($health.bluetooth.alias)"
Add-Check 'Bluetooth discoverable' ([bool]$health.bluetooth.discoverable) "discoverable=$($health.bluetooth.discoverable)"
Add-Check 'Bluetooth pairable' ([bool]$health.bluetooth.pairable) "pairable=$($health.bluetooth.pairable)"

try {
    $logs = Get-PiJson '/api/logs'
    Add-Check 'ECU log listing' ($null -ne $logs) "entries=$(@($logs).Count)"
} catch { Add-Check 'ECU log listing' $false $_.Exception.Message }

try {
    $vnc = Invoke-WebRequest -Uri "http://$PiHost`:6080/vnc.html" -TimeoutSec 8 -UseBasicParsing
    Add-Check 'Remote touch display' ($vnc.StatusCode -eq 200 -and $vnc.Content -match 'noVNC|vnc') "HTTP $($vnc.StatusCode)"
} catch { Add-Check 'Remote touch display' $false $_.Exception.Message }

$report.finished = (Get-Date).ToUniversalTime().ToString('o')
$report.passed = @($report.checks | Where-Object { -not $_.passed }).Count -eq 0
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
Write-Host "Report: $ReportPath"
if (-not $report.passed) { exit 1 }
