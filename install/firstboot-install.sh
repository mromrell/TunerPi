#!/bin/bash
set -euo pipefail

USER_NAME="tuner"
USER_HOME="/home/${USER_NAME}"
PAYLOAD="/boot/firmware/pi-tuner-payload"
INSTALL_ROOT="/opt/efi-analytics"
PROJECT_NAME="1989_BMW_325i_MicroSquirt"
PROJECT_ROOT="${USER_HOME}/TunerStudioProjects/${PROJECT_NAME}"

exec > >(tee -a /var/log/pi-tuner-firstboot.log) 2>&1

if [ ! -d "${PAYLOAD}" ]; then
  echo "Payload missing at ${PAYLOAD}"
  exit 1
fi

raspi-config nonint do_boot_behaviour B4
systemctl enable ssh

# Raspberry Pi OS uses NetworkManager.  The original boot image does not
# consume cloud-init's network-config, so create the known update connection
# here and wait for Internet before touching apt.  Wireless Android Auto later
# takes over wlan0 only while projection is active.
rfkill unblock wifi || true
if command -v nmcli >/dev/null 2>&1; then
  nmcli --wait 15 device wifi connect 'OldEthelsPantaloons-2.4' password '1234internet4321' || true
fi
for attempt in $(seq 1 60); do
  if nmcli -t -f STATE general 2>/dev/null | grep -qx connected; then
    break
  fi
  if [ "${attempt}" -eq 60 ]; then
    echo 'Internet connection unavailable after 5 minutes; provisioning will retry next boot.' >&2
    exit 75
  fi
  sleep 5
done

# Install the supported, current Crankshaft packages for Raspberry Pi OS
# (Debian/Trixie arm64).  This is the Android Auto runtime used by TunerPi.
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl gpg python3-tk wmctrl
curl -fsSL https://apt.opencardev.org/opencardev.gpg.key \
  | gpg --dearmor --yes --output /usr/share/keyrings/opencardev-archive-keyring.gpg
ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
printf 'deb [arch=%s signed-by=/usr/share/keyrings/opencardev-archive-keyring.gpg] https://apt.opencardev.org %s stable\n' \
  "${ARCH}" "${CODENAME}" > /etc/apt/sources.list.d/opencardev.list
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  crankshaft-core crankshaft-ui-slim
systemctl enable crankshaft-core.service
# The UI is started from the touch launcher.  Running it automatically would
# take exclusive control of the display and hide the TunerStudio controls.
systemctl disable crankshaft-ui-slim.service crankshaft-ui-slim-display-setup.service || true

install -d -m 0755 "${INSTALL_ROOT}" "${USER_HOME}/TunerStudioProjects"
install -d -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/Desktop"

tar -xzf "${PAYLOAD}/TunerStudioMS_v3.3.01.tar.gz" -C "${INSTALL_ROOT}"
tar -xzf "${PAYLOAD}/OpenJDK11U-jre_aarch64_linux_hotspot_11.0.32_9.tar.gz" -C "${INSTALL_ROOT}"
dpkg -i "${PAYLOAD}/librxtx-java_2.2pre2+dfsg1-2_arm64.deb"
JRE_DIR="$(find "${INSTALL_ROOT}" -maxdepth 1 -type d -name 'jdk-11*' | head -n 1)"
ln -sfn "${JRE_DIR}" "${INSTALL_ROOT}/java"

cp -a "${PAYLOAD}/${PROJECT_NAME}" "${USER_HOME}/TunerStudioProjects/"
install -d -m 0755 "${USER_HOME}/.efiAnalytics"
cp -a "${PAYLOAD}/efiAnalytics/." "${USER_HOME}/.efiAnalytics/"

PROPS="${PROJECT_ROOT}/projectCfg/project.properties"
sed -i \
  -e 's#^commPort=.*#commPort=/dev/microsquirt#' \
  -e 's#^CommSettingCom\\ Port=.*#CommSettingCom\\ Port=/dev/microsquirt#' \
  -e 's#^MS2-Extra_commPort=.*#MS2-Extra_commPort=/dev/microsquirt#' \
  -e "s#^logFileDir=.*#logFileDir=${PROJECT_ROOT}/DataLogs#" \
  -e "s#^tuneFileDir=.*#tuneFileDir=${PROJECT_ROOT}#" \
  "${PROPS}"

USER_PROPS="${USER_HOME}/.efiAnalytics/tsUser.properties"
sed -i \
  -e "s#^projectsDir=.*#projectsDir=${USER_HOME}/TunerStudioProjects#" \
  -e "s#^lastProjectPath=.*#lastProjectPath=${PROJECT_ROOT}#" \
  -e "s#^recentlyOpenedProject_0=.*#recentlyOpenedProject_0=${PROJECT_ROOT}#" \
  -e "s#^lastFileDir=.*#lastFileDir=${PROJECT_ROOT}/DataLogs/#" \
  "${USER_PROPS}"

cat > /etc/udev/rules.d/99-microsquirt.rules <<'EOF'
SUBSYSTEM=="tty", KERNEL=="ttyUSB[0-9]*", SYMLINK+="microsquirt", GROUP="dialout", MODE="0660"
SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", SYMLINK+="microsquirt", GROUP="dialout", MODE="0660"
EOF

usermod -aG dialout "${USER_NAME}"

cat > /usr/local/bin/start-bmw-tunerstudio <<'EOF'
#!/bin/bash
set -euo pipefail
PROJECT="/home/tuner/TunerStudioProjects/1989_BMW_325i_MicroSquirt"
LOG_DIR="${PROJECT}/DataLogs"
mkdir -p "${LOG_DIR}"
while [ ! -e /dev/microsquirt ]; do sleep 1; done
cd /opt/efi-analytics/TunerStudioMS
exec /opt/efi-analytics/java/bin/java \
  -Xms128m -Xmx768m \
  -Duser.home=/home/tuner \
  -Dfile.encoding=UTF8 \
  -Djava.library.path=/usr/lib/jni:/opt/efi-analytics/TunerStudioMS/lib \
  -jar TunerStudioMS.jar \
  "$PROJECT"
EOF
chmod 0755 /usr/local/bin/start-bmw-tunerstudio

install -d -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/.config/autostart"
cat > "${USER_HOME}/.config/autostart/bmw-tunerstudio.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=BMW TunerStudio
Comment=Start the BMW MicroSquirt project when the USB serial adapter is present
Exec=/usr/local/bin/start-bmw-tunerstudio
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

install -d -m 0755 /etc/crankshaft/profiles
cat > /etc/crankshaft/profiles/host_profiles.json <<'EOF'
[
  {
    "id": "{d3eb4bca-3251-4e89-b001-000000000001}",
    "name": "BMW TunerPi Wireless Android Auto",
    "description": "Wireless Android Auto plus BMW MicroSquirt logging",
    "isActive": true,
    "cpuModel": "Raspberry Pi 4",
    "ramMB": 4096,
    "osVersion": "Raspberry Pi OS",
    "properties": {},
    "devices": [
      {
        "name": "AndroidAuto",
        "type": "AndroidAuto",
        "enabled": true,
        "useMock": false,
        "description": "Wireless Android Auto projection",
        "settings": {
          "connectionMode": "wireless",
          "wireless.enabled": true,
          "wireless.port": 5277,
          "wireless.hotspot.auto_start": true,
          "wireless.hotspot.ssid": "TunerPi-AA",
          "wireless.hotspot.password": "TunerPi-AA-325i",
          "wireless.hotspot.channel": 0,
          "video.transport_mode": "webrtc",
          "resolution": "1280x480",
          "fps": 30,
          "channels.video": true,
          "channels.mediaAudio": true,
          "channels.systemAudio": true,
          "channels.speechAudio": true,
          "channels.microphone": true,
          "channels.input": true,
          "channels.sensor": true,
          "channels.bluetooth": true
        }
      },
      { "name": "Bluetooth", "type": "Bluetooth", "enabled": true, "useMock": false, "description": "Phone pairing" },
      { "name": "WiFi", "type": "WiFi", "enabled": true, "useMock": false, "description": "Android Auto hotspot" }
    ]
  }
]
EOF

cat > /usr/local/bin/tunerpi-mode <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  android-auto)
    sudo systemctl start crankshaft-core.service
    sudo systemctl start crankshaft-ui-slim-display-setup.service
    sudo systemctl start crankshaft-ui-slim.service
    ;;
  tunerstudio)
    sudo systemctl stop crankshaft-ui-slim.service || true
    if ! pgrep -f '[T]unerStudioMS.jar' >/dev/null; then
      /usr/local/bin/start-bmw-tunerstudio &
    fi
    wmctrl -a 'TunerStudio' || true
    ;;
  logs)
    xdg-open /home/tuner/TunerStudioProjects/1989_BMW_325i_MicroSquirt/DataLogs
    ;;
  split)
    # Best-effort XWayland/X11 split mode.  The regular AA mode stays the
    # reliable full-screen option; this mode is intentionally recoverable.
    sudo systemctl stop crankshaft-ui-slim.service || true
    if ! pgrep -f '[T]unerStudioMS.jar' >/dev/null; then
      /usr/local/bin/start-bmw-tunerstudio &
    fi
    sleep 3
    sudo -u tuner env DISPLAY=:0 XAUTHORITY=/home/tuner/.Xauthority \
      QT_QPA_PLATFORM=xcb /usr/bin/crankshaft-ui-slim &
    sleep 5
    wmctrl -r 'Crankshaft Slim UI - AndroidAuto' -e 0,0,0,640,480 || true
    wmctrl -r 'TunerStudio' -e 0,640,0,640,480 || true
    ;;
  stop-android-auto)
    sudo systemctl stop crankshaft-ui-slim.service || true
    ;;
  *)
    echo "Usage: tunerpi-mode {android-auto|tunerstudio|logs|split|stop-android-auto}" >&2
    exit 64
    ;;
esac
EOF
chmod 0755 /usr/local/bin/tunerpi-mode

cat > /usr/local/bin/tunerpi-touch <<'EOF'
#!/usr/bin/env python3
"""Touch-first launcher for the BMW TunerPi display."""
import subprocess
import tkinter as tk

BG, PANEL, BLUE, AMBER, TEXT, MUTED = '#10151c', '#1c2633', '#1f78d1', '#d98922', '#eef5ff', '#9caec2'

def run(mode):
    subprocess.Popen(['/usr/local/bin/tunerpi-mode', mode], start_new_session=True)
    if mode == 'android-auto':
        root.after(1500, root.iconify)

root = tk.Tk()
root.title('TunerPi')
root.configure(bg=BG)
root.attributes('-fullscreen', True)
root.bind('<Escape>', lambda _event: root.attributes('-fullscreen', False))

frame = tk.Frame(root, bg=BG, padx=28, pady=18)
frame.pack(fill='both', expand=True)
tk.Label(frame, text='TUNERPI  |  BMW 325i', font=('DejaVu Sans', 24, 'bold'), bg=BG, fg=TEXT).pack(anchor='w')
tk.Label(frame, text='GAUGES DEFAULT  |  Android Auto wireless  |  ECU logging armed', font=('DejaVu Sans', 11, 'bold'), bg=BG, fg=MUTED).pack(anchor='w', pady=(0, 12))

buttons = tk.Frame(frame, bg=BG)
buttons.pack(fill='both', expand=True)
for col in range(3): buttons.grid_columnconfigure(col, weight=1)
for row in range(2): buttons.grid_rowconfigure(row, weight=1)

def tile(label, detail, color, mode, row, col):
    box = tk.Frame(buttons, bg=PANEL, highlightbackground=color, highlightthickness=2)
    box.grid(row=row, column=col, sticky='nsew', padx=7, pady=7)
    tk.Button(box, text=label, font=('DejaVu Sans', 18, 'bold'), bg=color, fg='white', relief='flat', command=lambda: run(mode)).pack(fill='both', expand=True, padx=8, pady=(8, 2))
    tk.Label(box, text=detail, font=('DejaVu Sans', 10), bg=PANEL, fg=MUTED, wraplength=260).pack(padx=8, pady=(2, 8))

tile('GAUGES', 'BMW MicroSquirt live dash and automatic logging', AMBER, 'tunerstudio', 0, 0)
tile('ANDROID AUTO', 'Wireless Maps, Spotify, calls, and apps', BLUE, 'android-auto', 0, 1)
tile('LOGS', 'Review and copy ECU data logs', '#435466', 'logs', 0, 2)
tile('EXIT ANDROID AUTO', 'Return to this launcher', '#435466', 'stop-android-auto', 1, 0)
tile('SPLIT VIEW', 'Experimental: AA left, gauges right', '#435466', 'split', 1, 1)
tk.Label(buttons, text='ECU USB detected: TunerStudio launches automatically.\nAndroid Auto hotspot: TunerPi-AA', font=('DejaVu Sans', 12), justify='left', bg=BG, fg=TEXT).grid(row=1, column=2, sticky='nsew', padx=18, pady=16)

root.mainloop()
EOF
chmod 0755 /usr/local/bin/tunerpi-touch

cat > "${USER_HOME}/.config/autostart/tunerpi-touch.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=TunerPi Touch Launcher
Comment=Touch launcher for Android Auto, TunerStudio, and logs
Exec=/usr/local/bin/tunerpi-touch
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

cat > /etc/systemd/system/bmw-log-backup.service <<'EOF'
[Unit]
Description=Flush BMW TunerStudio logs before shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/bin/sync
TimeoutStartSec=30

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF
systemctl enable bmw-log-backup.service

install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/20-sd-card-wear.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF

cat > /etc/logrotate.d/bmw-tunerstudio <<'EOF'
/home/tuner/TunerStudioProjects/1989_BMW_325i_MicroSquirt/DataLogs/*.msl {
  size 100M
  rotate 50
  compress
  missingok
  notifempty
  copytruncate
}
EOF

cat > "${USER_HOME}/Desktop/README-BMW-TUNER.txt" <<'EOF'
BMW TunerStudio Pi

- Plug the existing MicroSquirt USB serial cable into any Raspberry Pi USB port.
- TunerStudio starts automatically when /dev/microsquirt appears.
- Project: /home/tuner/TunerStudioProjects/1989_BMW_325i_MicroSquirt
- Logs: project DataLogs folder.
- Serial: 115200 baud.
- No GPIO pins are required.
- TunerPi touch launcher: Android Auto, TunerStudio dashboard, and logs.
- Android Auto is wireless through hotspot TunerPi-AA (password: TunerPi-AA-325i).
- The Pi joins OldEthels when Android Auto is not using its Wi-Fi radio.
- Android Auto and TunerStudio are separate full-screen renderers; use the
  TunerPi launcher to switch modes. TunerStudio still logs in the background.
- Split View is an experimental XWayland mode: Android Auto left, TunerStudio
  right. If it does not arrange windows on the attached display, use either
  full-screen mode instead.

In TunerStudio Pro, verify Data Logging > Automatic Logging is enabled with:
Start: RPM > 0
Stop: RPM = 0 for 5 seconds
EOF

chown -R "${USER_NAME}:${USER_NAME}" \
  "${USER_HOME}/TunerStudioProjects" \
  "${USER_HOME}/.efiAnalytics" \
  "${USER_HOME}/.config" \
  "${USER_HOME}/Desktop"

touch /var/lib/pi-tuner-firstboot-complete
sync
systemctl reboot
