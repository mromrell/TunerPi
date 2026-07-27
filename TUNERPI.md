# TunerPi BMW integration

This fork adds the Raspberry Pi 4 integration for a BMW 325i MicroSquirt:

- current Crankshaft Android Auto packages from the OpenCarDev signed apt repository;
- a wireless Android Auto profile (`TunerPi-AA` hotspot);
- a touch-first 3:1 launcher for Android Auto, the wide TunerStudio dashboard, and ECU logs;
- TunerStudio's existing USB serial logging flow, with no GPIO required.

## Operating model

`crankshaft-core` starts at boot and hosts wireless Android Auto. The Slim UI is deliberately launched from the touch screen, because its EGLFS renderer takes exclusive ownership of the display. Select **Android Auto** for Maps/Spotify; select **TunerStudio** for the ECU dashboard; select **Open Logs** to browse data logs. **Split View** is included as a best-effort XWayland mode (Android Auto left, TunerStudio right); use either full-screen mode if a particular display compositor does not arrange it.

TunerStudio retains its automatic USB launch and automatic logging configuration. It can log while Android Auto is shown.

The 6x2-inch touch layout makes **Gauges** and **Android Auto** the two primary actions. Repeated touch input is idempotent: the launcher does not start a second TunerStudio instance when one is already logging.

## First boot

The SD-card provisioner installs `crankshaft-core`, `crankshaft-ui-slim`, and Python Tk on the Pi. It verifies OpenCarDev's signing key before installing packages. The wireless hotspot is:

- SSID: `TunerPi-AA`
- password: `TunerPi-AA-325i`

On a Pi 4, the single onboard Wi-Fi radio is normally dedicated to the Android Auto hotspot while wireless projection is active. The previously provisioned OldEthels connection remains available when the hotspot is not active.

## Validation on the Pi

```bash
systemctl is-enabled crankshaft-core
systemctl status crankshaft-core --no-pager
journalctl -u crankshaft-core -n 100 --no-pager
```

Runtime projection and physical touch calibration require the actual phone and display; they cannot be verified from a Windows SD-card staging machine.
