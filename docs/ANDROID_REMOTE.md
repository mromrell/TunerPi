# TunerPi Remote for Android

`android-companion/` builds the Fold-optimized companion APK. It discovers and pairs with the Pi over Bluetooth, then uses the private `TunerPi-AA` Wi-Fi network for two high-bandwidth functions:

- the noVNC display mirror and touch control at `http://10.42.0.1:6080`;
- ECU log listing/download at `http://10.42.0.1:8088/api/logs`.

The app deliberately uses Wi-Fi for video and files: Bluetooth is suitable for discovery/pairing but not a responsive live display.

The Pi provisioner starts `wayvnc` and noVNC from the logged-in desktop session. This mirrors the TunerStudio/dashboard desktop. Crankshaft Android Auto uses a direct EGLFS renderer; it may not be capturable by the desktop VNC server on every Pi/display combination. Android Auto itself remains available directly on the phone.

The local TunerPi touch launcher includes a live status bar for the joined Wi-Fi
SSID/signal/IP address and Bluetooth readiness. It refreshes every two seconds.

The log API is intended only for the WPA2-protected TunerPi-AA vehicle network. Do not expose port 8088 or port 6080 to an untrusted network.

## Automated acceptance test

After the Pi has completed its first-boot install and this computer is joined to
`TunerPi-AA`, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\tools\Test-TunerPi.ps1
```

When both machines are on the household Wi-Fi, use `-PiHost tunerpi.local`.

## Remote maintenance

The provisioner creates a key-only `tuner@tunerpi.local` account with passwordless
`sudo`, while the private key remains on this Windows computer. After first boot:

```powershell
& .\tools\Connect-TunerPi.ps1 -RemoteCommand 'sudo apt-get update'
& .\tools\Connect-TunerPi.ps1 -RemoteCommand 'sudo reboot'
& .\tools\Test-TunerPi.ps1 -PiHost tunerpi.local
```

On the TunerPi-AA hotspot, use `-PiHost 10.42.0.1` instead. SSH password login
and root login are disabled; the generated key is required.

Tailscale is installed and running but must be authorized into the desired
tailnet once. From the local network, run:

```powershell
& .\tools\Connect-TunerPi.ps1 -RemoteCommand 'sudo tunerpi-tailscale-connect'
```

Open the one-time URL that Tailscale prints, approve the device, then connect
from any tailnet device using its Tailscale IP or the approved machine name.

## APK download link

The companion APK is privately served to tailnet devices at:

`https://tunerpi.taila595a0.ts.net/TunerPiRemote-debug.apk`

To replace it after a future build, run `tools/Publish-TunerPiApk.ps1`. This
link is Tailscale Serve, not a public Funnel endpoint, so the phone must be
connected to the same tailnet.

The script waits for the Pi, verifies the health/log APIs, the configured
Bluetooth identity and state, and loads noVNC's touch-display page. It writes a
machine-readable report under `test-results/`. `Test-TunerPiBluetooth.ps1`
separately confirms that the Windows Bluetooth adapter is present and reports
whether the Pi is already paired.
# Pi provisioning recovery

If the SD card was removed before first boot provisioning finished, use the
boot-partition recovery trigger supplied in `install/tunerpi-recovery-v2.sh`.
It clears only the TunerPi completion marker, registers the installer as a
network-aware one-time service, and leaves all Raspberry Pi OS data intact.
The recovery script also removes its one-time kernel command-line target before
rebooting, so normal graphical boot resumes afterward.
