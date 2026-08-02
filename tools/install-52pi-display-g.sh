#!/bin/bash
# Install the 52Pi 3.5-inch Display-G overlay without replacing the Pi image.
set -euo pipefail

BOOT=/boot/firmware
OVERLAY_URL=https://raw.githubusercontent.com/goodtft/LCD-show/master/usr/tft35a-overlay.dtb
STAMP=$(date +%Y%m%d-%H%M%S)

test -d "$BOOT"
install -d -m 0755 "/opt/tunerpi-backups/display/$STAMP" /opt/tunerpi-display/vendor
cp -a "$BOOT/config.txt" "$BOOT/cmdline.txt" "/opt/tunerpi-backups/display/$STAMP/"
curl -fsSL "$OVERLAY_URL" -o /opt/tunerpi-display/vendor/tft35a-overlay.dtb
install -m 0644 /opt/tunerpi-display/vendor/tft35a-overlay.dtb "$BOOT/overlays/tft35a.dtbo"
sed -i '/^# TUNERPI 52PI 3.5 DISPLAY-G BEGIN$/,/^# TUNERPI 52PI 3.5 DISPLAY-G END$/d' "$BOOT/config.txt"
cat >> "$BOOT/config.txt" <<'EOF'

# TUNERPI 52PI 3.5 DISPLAY-G BEGIN
# 480x320 ILI9486 SPI panel with XPT2046/ADS7846 resistive touch.
dtparam=spi=on
dtparam=i2c_arm=on
dtoverlay=tft35a:rotate=90
# TUNERPI 52PI 3.5 DISPLAY-G END
EOF
sync
echo '52Pi Display-G staged. Reboot to activate.'
