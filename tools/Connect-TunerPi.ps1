[CmdletBinding()]
param(
    [string]$PiHost = 'tunerpi.local',
    [string]$IdentityFile = "$env:USERPROFILE\.ssh\tunerpi_ed25519",
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemoteCommand
)

$ErrorActionPreference = 'Stop'
$ssh = 'C:\Windows\System32\OpenSSH\ssh.exe'
if (-not (Test-Path -LiteralPath $IdentityFile)) { throw "TunerPi SSH key not found: $IdentityFile" }
$args = @('-i', $IdentityFile, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', "tuner@$PiHost")
if ($RemoteCommand) { $args += ($RemoteCommand -join ' ') }
& $ssh @args
exit $LASTEXITCODE
