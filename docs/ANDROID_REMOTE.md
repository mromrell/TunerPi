# TunerPi Remote for Android

`android-companion/` builds the Fold-optimized companion APK. It discovers and pairs with the Pi over Bluetooth, then uses the private `TunerPi-AA` Wi-Fi network for two high-bandwidth functions:

- the noVNC display mirror and touch control at `http://10.42.0.1:6080`;
- ECU log listing/download at `http://10.42.0.1:8088/api/logs`.

The app deliberately uses Wi-Fi for video and files: Bluetooth is suitable for discovery/pairing but not a responsive live display.

The Pi provisioner starts `wayvnc` and noVNC from the logged-in desktop session. This mirrors the TunerStudio/dashboard desktop. Crankshaft Android Auto uses a direct EGLFS renderer; it may not be capturable by the desktop VNC server on every Pi/display combination. Android Auto itself remains available directly on the phone.

The log API is intended only for the WPA2-protected TunerPi-AA vehicle network. Do not expose port 8088 or port 6080 to an untrusted network.
