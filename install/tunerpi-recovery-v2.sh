#!/bin/bash
# Runs once from the Pi boot partition, restores a clean provision state, and
# registers the real installer as a network-aware systemd job on the ext4 root.
set -euo pipefail

exec >>/boot/firmware/TUNERPI-FIRST-BOOT.log 2>&1
echo "TunerPi recovery v2 registered $(date -Is)"

rm -f /var/lib/pi-tuner-firstboot-complete
systemctl disable tunerpi-provision.service tunerpi-recovery.service tunerpi-recovery-v2.service || true

cat >/etc/systemd/system/tunerpi-recovery-v2.service <<'UNIT'
[Unit]
Description=TunerPi complete provisioning and Android companion services
Wants=network-online.target
After=NetworkManager.service network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/pi-tuner-payload/firstboot-install.sh
TimeoutStartSec=45min

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable tunerpi-recovery-v2.service
rm -f /boot/firmware/tunerpi-recovery-v2.sh
sync
