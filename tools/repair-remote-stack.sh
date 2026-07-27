#!/bin/bash
# Apply the non-destructive remote-stack repair to an already provisioned Pi.
set -euo pipefail

apt-get update -qq
apt-get install -y --no-install-recommends wayvnc novnc websockify rfkill bluez

cat >/usr/local/bin/tunerpi-start-remote-display <<'SCRIPT'
#!/bin/bash
set -u
pkill -x wayvnc || true
pkill -x websockify || true
sleep 2
if ! command -v wayvnc >/dev/null || ! command -v websockify >/dev/null; then exit 0; fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
wayvnc 0.0.0.0 5900 > /tmp/tunerpi-wayvnc.log 2>&1 &
for _ in $(seq 1 20); do nc -z 127.0.0.1 5900 && break; sleep 1; done
websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 > /tmp/tunerpi-novnc.log 2>&1 &
SCRIPT
chmod 0755 /usr/local/bin/tunerpi-start-remote-display

cat >/usr/local/bin/tunerpi-enable-bluetooth <<'SCRIPT'
#!/bin/bash
set -u
/usr/sbin/rfkill unblock bluetooth || true
for _ in $(seq 1 20); do
  /usr/bin/bluetoothctl power on || true
  if /usr/bin/bluetoothctl show | grep -q 'Powered: yes'; then
    /usr/bin/bluetoothctl system-alias 'TunerPi BMW 325i'
    /usr/bin/bluetoothctl discoverable-timeout 0
    /usr/bin/bluetoothctl discoverable on
    /usr/bin/bluetoothctl pairable on
    exit 0
  fi
  sleep 2
done
exit 1
SCRIPT
chmod 0755 /usr/local/bin/tunerpi-enable-bluetooth

cat >/etc/systemd/system/tunerpi-bluetooth.service <<'UNIT'
[Unit]
Description=Enable TunerPi Bluetooth discovery and pairing
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tunerpi-enable-bluetooth
Restart=on-failure
RestartSec=5
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now tunerpi-bluetooth.service
uid=$(id -u tuner)
sudo -u tuner XDG_RUNTIME_DIR="/run/user/${uid}" WAYLAND_DISPLAY=wayland-0 /usr/local/bin/tunerpi-start-remote-display || true
