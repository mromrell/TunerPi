#!/bin/bash
set -euo pipefail

LOG=/boot/firmware/TUNERPI-FIRST-BOOT.log
exec > >(tee -a "$LOG") 2>&1
echo "TunerPi recovery provisioner registered $(date -Is)"

# The earlier provisioning attempt did not finish.  Clear its completion
# marker, replace its service with a retry service, and let normal boot bring
# NetworkManager up before package installation starts.
rm -f /var/lib/pi-tuner-firstboot-complete
systemctl disable tunerpi-provision.service 2>/dev/null || true

cat > /etc/systemd/system/tunerpi-recovery.service <<'EOF'
[Unit]
Description=TunerPi recovery provisioner
Wants=network-online.target
After=NetworkManager.service network-online.target
ConditionPathExists=!/var/lib/pi-tuner-firstboot-complete

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/pi-tuner-payload/firstboot-install.sh
TimeoutStartSec=25min

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tunerpi-recovery.service

sed -i 's/ systemd.run=[^ ]*//g; s/ systemd.run_success_action=[^ ]*//g; s/ systemd.unit=[^ ]*//g' /boot/firmware/cmdline.txt
rm -f /boot/firmware/tunerpi-recovery.sh
sync
