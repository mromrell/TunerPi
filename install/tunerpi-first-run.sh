#!/bin/bash
set -euo pipefail

LOG=/boot/firmware/TUNERPI-FIRST-BOOT.log
exec > >(tee -a "$LOG") 2>&1
echo "TunerPi provisioning started $(date -Is)"

/bin/bash /boot/firmware/pi-tuner-payload/firstboot-install.sh

touch /boot/firmware/TUNERPI-PROVISIONED
sed -i 's/ systemd.run=[^ ]*//g; s/ systemd.run_success_action=[^ ]*//g; s/ systemd.unit=[^ ]*//g' /boot/firmware/cmdline.txt
rm -f /boot/firmware/tunerpi-first-run.sh
sync
