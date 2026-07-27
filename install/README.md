# SD-card provisioner

The deployable provisioner is `firstboot-install.sh`. Copy it, together with the existing TunerStudio payload, to `/boot/firmware/pi-tuner-payload/` before the Pi's first boot.

It installs the signed OpenCarDev packages, configures a real (non-mock) wireless Android Auto profile, enables `crankshaft-core`, and installs the `tunerpi-touch` mode launcher. The Slim UI intentionally remains disabled until the user selects **Android Auto**, because its physical-display renderer has exclusive display ownership.

The provisioner also retains the existing MicroSquirt USB serial/automatic TunerStudio configuration. No GPIO connections are used.
