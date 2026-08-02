# SD-card provisioner

The deployable provisioner is `firstboot-install.sh`. Copy it, together with the existing TunerStudio payload, to `/boot/firmware/pi-tuner-payload/` before the Pi's first boot.

It installs the signed OpenCarDev packages, configures a real (non-mock) wireless Android Auto profile, enables `crankshaft-core`, and installs the `tunerpi-touch` mode launcher. The Slim UI intentionally remains disabled until the user selects **Android Auto**, because its physical-display renderer has exclusive display ownership.

## 52Pi 3.5-inch Display-G

For the 480x320 SPI display with the XPT2046 resistive controller, run
`sudo tools/install-52pi-display-g.sh` on the Pi and reboot. It installs the
`tft35a` / ILI9486 framebuffer overlay, preserves the existing OS and remote
access configuration, and creates a dated boot-config backup in
`/opt/tunerpi-backups/display/`.

The provisioner also retains the existing MicroSquirt USB serial/automatic TunerStudio configuration. No GPIO connections are used.
