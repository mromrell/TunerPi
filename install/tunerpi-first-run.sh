#!/bin/bash
set -euo pipefail

LOG=/boot/firmware/TUNERPI-FIRST-BOOT.log
exec > >(tee -a "$LOG") 2>&1
echo "TunerPi provisioner registered $(date -Is)"

# This early hook intentionally does no network work.  It registers a normal
# systemd service that runs only after NetworkManager is available.
cat > /etc/systemd/system/tunerpi-provision.service <<'EOF'
[Unit]
Description=TunerPi first-boot provisioner
Wants=network-online.target
After=NetworkManager.service network-online.target
ConditionPathExists=!/var/lib/pi-tuner-firstboot-complete

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/pi-tuner-payload/firstboot-install.sh
TimeoutStartSec=20min

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tunerpi-provision.service

sed -i 's/ systemd.run=[^ ]*//g; s/ systemd.run_success_action=[^ ]*//g; s/ systemd.unit=[^ ]*//g' /boot/firmware/cmdline.txt
rm -f /boot/firmware/tunerpi-first-run.sh
sync
