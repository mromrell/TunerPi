[CmdletBinding()]
param(
    [string]$PiHost = '100.98.130.40',
    [string]$ApkPath = "$env:USERPROFILE\Downloads\TunerPiRemote-debug.apk",
    [string]$IdentityFile = "$env:USERPROFILE\.ssh\tunerpi_ed25519"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ApkPath)) { throw "APK not found: $ApkPath" }
$scp = 'C:\Windows\System32\OpenSSH\scp.exe'
$ssh = 'C:\Windows\System32\OpenSSH\ssh.exe'
& $scp -i $IdentityFile -o BatchMode=yes $ApkPath "tuner@${PiHost}:/tmp/TunerPiRemote-debug.apk"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $ssh -i $IdentityFile -o BatchMode=yes "tuner@$PiHost" 'sudo install -m 0644 -o tuner -g tuner /tmp/TunerPiRemote-debug.apk /opt/tunerpi-downloads/TunerPiRemote-debug.apk; rm -f /tmp/TunerPiRemote-debug.apk; sha256sum /opt/tunerpi-downloads/TunerPiRemote-debug.apk'
exit $LASTEXITCODE
