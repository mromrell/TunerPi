#!/bin/bash
set -euo pipefail

USER_NAME="tuner"
USER_HOME="/home/${USER_NAME}"
PAYLOAD="/boot/firmware/pi-tuner-payload"
INSTALL_ROOT="/opt/efi-analytics"
PROJECT_NAME="1989_BMW_325i_MicroSquirt"
PROJECT_ROOT="${USER_HOME}/TunerStudioProjects/${PROJECT_NAME}"

exec > >(tee -a /var/log/pi-tuner-firstboot.log /boot/firmware/TUNERPI-PROVISION.log) 2>&1

if [ ! -d "${PAYLOAD}" ]; then
  echo "Payload missing at ${PAYLOAD}"
  exit 1
fi

raspi-config nonint do_boot_behaviour B4
# Safe prerequisites for GPIO-connected touch panels.  The panel-specific
# overlay is intentionally installed separately after its controller is known.
raspi-config nonint do_spi 0
raspi-config nonint do_i2c 0
hostnamectl set-hostname tunerpi
systemctl enable ssh

# Raspberry Pi OS uses NetworkManager.  The original boot image does not
# consume cloud-init's network-config, so create the known update connection
# here and wait for Internet before touching apt.  Wireless Android Auto later
# takes over wlan0 only while projection is active.
rfkill unblock wifi || true
if command -v nmcli >/dev/null 2>&1; then
  nmcli --wait 15 device wifi connect 'OldEthelsPantaloons-2.4' password '1234internet4321' || true
  # Keep a fallback vehicle hotspot.  Its deliberately lower autoconnect
  # priority leaves the Pi on the home Wi-Fi when available, but brings up
  # TunerPi-AA automatically when the car is away from that network.
  nmcli connection delete TunerPi-AA >/dev/null 2>&1 || true
  nmcli connection add type wifi ifname wlan0 con-name TunerPi-AA ssid TunerPi-AA
  nmcli connection modify TunerPi-AA \
    connection.autoconnect yes connection.autoconnect-priority -999 \
    802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6 \
    ipv4.method shared ipv4.addresses 10.42.0.1/24 ipv6.method ignore \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk 'TunerPi-AA-325i'
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
  ca-certificates curl gpg python3-tk wmctrl openssh-server avahi-daemon libnss-mdns
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
curl -fsSL https://apt.opencardev.org/opencardev.gpg.key \
  | gpg --dearmor --yes --output /usr/share/keyrings/opencardev-archive-keyring.gpg
ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
printf 'deb [arch=%s signed-by=/usr/share/keyrings/opencardev-archive-keyring.gpg] https://apt.opencardev.org %s stable\n' \
  "${ARCH}" "${CODENAME}" > /etc/apt/sources.list.d/opencardev.list
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  crankshaft-core crankshaft-ui-slim libqt6sql6-sqlite
# Remote viewing is deliberately optional: logging and the local touchscreen
# remain usable if a package is unavailable on a future Pi OS mirror.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  novnc websockify wayvnc || echo 'Remote display packages unavailable; logs API will still be installed.'
# Gauges are the default dashboard.  Start Android Auto only from its touch
# tile so a nearby phone is not prompted to project on every Pi boot.
systemctl disable crankshaft-core.service || true
# The UI is started from the touch launcher.  Running it automatically would
# take exclusive control of the display and hide the TunerStudio controls.
systemctl disable crankshaft-ui-slim.service crankshaft-ui-slim-display-setup.service || true

install -d -m 0755 "${INSTALL_ROOT}" "${USER_HOME}/TunerStudioProjects"
install -d -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/Desktop"

# Remote administration is key-only.  The private half stays on the Windows
# workstation; this payload contains only its public key.
REMOTE_KEYS="${PAYLOAD}/tunerpi_admin_authorized_keys"
test -s "${REMOTE_KEYS}"
install -d -m 0700 -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/.ssh"
install -m 0600 -o "${USER_NAME}" -g "${USER_NAME}" "${REMOTE_KEYS}" "${USER_HOME}/.ssh/authorized_keys"
cat > /etc/ssh/sshd_config.d/90-tunerpi-remote.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers tuner
EOF
cat > /etc/sudoers.d/90-tunerpi-remote <<'EOF'
tuner ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/90-tunerpi-remote
visudo -cf /etc/sudoers.d/90-tunerpi-remote
sshd -t
systemctl enable --now ssh avahi-daemon
systemctl restart ssh

cat > /usr/local/bin/tunerpi-tailscale-connect <<'EOF'
#!/bin/bash
# Starts the one-time Tailscale authorization flow without weakening SSH.
set -euo pipefail
exec tailscale up --hostname=tunerpi
EOF
chmod 0755 /usr/local/bin/tunerpi-tailscale-connect

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
    sudo nmcli connection up TunerPi-AA || true
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
    sudo systemctl stop crankshaft-core.service || true
    sudo nmcli connection down TunerPi-AA || true
    sudo nmcli connection up netplan-wlan0-OldEthelsPantaloons-2.4 || true
    ;;
  *)
    echo "Usage: tunerpi-mode {android-auto|tunerstudio|logs|split|stop-android-auto}" >&2
    exit 64
    ;;
esac
EOF
chmod 0755 /usr/local/bin/tunerpi-mode

cat > /usr/local/bin/tunerpi-logs-api <<'EOF'
#!/usr/bin/env python3
"""Private-Wi-Fi API for listing and downloading BMW ECU logs."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse
import json
import mimetypes
import subprocess
from datetime import datetime, timezone

LOG_DIR = Path('/home/tuner/TunerStudioProjects/1989_BMW_325i_MicroSquirt/DataLogs')
ALLOWED = {'.msl', '.mlg', '.csv'}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def send_json(self, value):
        body = json.dumps(value).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/api/health':
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            def service_state(name):
                result = subprocess.run(['systemctl', 'is-active', name], text=True, capture_output=True, timeout=3)
                return result.stdout.strip() or 'unknown'
            bt = subprocess.run(['bluetoothctl', 'show'], text=True, capture_output=True, timeout=3).stdout
            return self.send_json({
                'status': 'ok',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'log_directory': str(LOG_DIR),
                'services': {name: service_state(name) for name in ('tunerpi-logs-api.service', 'crankshaft-core.service', 'tailscaled.service')},
                'bluetooth': {'alias': next((line.split(':', 1)[1].strip() for line in bt.splitlines() if 'Alias:' in line), 'unknown'), 'discoverable': 'Discoverable: yes' in bt, 'pairable': 'Pairable: yes' in bt}
            })
        if path == '/api/logs':
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            items = []
            for file in sorted(LOG_DIR.iterdir(), key=lambda item: item.stat().st_mtime, reverse=True):
                if file.is_file() and file.suffix.lower() in ALLOWED:
                    stat = file.stat()
                    items.append({'name': file.name, 'size': stat.st_size, 'modified': int(stat.st_mtime), 'url': '/logs/' + file.name})
            return self.send_json(items)
        if path.startswith('/logs/'):
            name = Path(unquote(path[len('/logs/'):])).name
            file = LOG_DIR / name
            if file.is_file() and file.suffix.lower() in ALLOWED:
                data = file.read_bytes()
                self.send_response(200); self.send_header('Content-Type', mimetypes.guess_type(file.name)[0] or 'application/octet-stream')
                self.send_header('Content-Disposition', 'attachment; filename="%s"' % file.name)
                self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data); return
        self.send_error(404)

ThreadingHTTPServer(('0.0.0.0', 8088), Handler).serve_forever()
EOF
chmod 0755 /usr/local/bin/tunerpi-logs-api

cat > /usr/local/bin/tunerpi-selftest <<'EOF'
#!/bin/bash
# Non-destructive local validation for the Android companion stack.
set -euo pipefail
host="${1:-127.0.0.1}"
for service in tunerpi-logs-api.service crankshaft-core.service tailscaled.service; do
  printf '%s: ' "$service"
  systemctl is-active "$service"
done
curl --fail --silent --show-error --connect-timeout 5 "http://${host}:8088/api/health" | python3 -m json.tool
curl --fail --silent --show-error --connect-timeout 5 "http://${host}:8088/api/logs" | python3 -m json.tool
if command -v ss >/dev/null; then ss -ltn | grep -E ':(5900|6080|8088)\\b' || true; fi
EOF
chmod 0755 /usr/local/bin/tunerpi-selftest

cat > /etc/systemd/system/tunerpi-logs-api.service <<'EOF'
[Unit]
Description=TunerPi private ECU log API
After=network-online.target
Wants=network-online.target

[Service]
User=tuner
ExecStart=/usr/local/bin/tunerpi-logs-api
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable tunerpi-logs-api.service

cat > /usr/local/bin/tunerpi-start-remote-display <<'EOF'
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
EOF
chmod 0755 /usr/local/bin/tunerpi-start-remote-display

cat > "${USER_HOME}/.config/autostart/tunerpi-remote-display.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=TunerPi Remote Display
Comment=Private Wi-Fi display mirror for TunerPi Remote
Exec=/usr/local/bin/tunerpi-start-remote-display
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

bluetoothctl system-alias 'TunerPi BMW 325i' || true
bluetoothctl discoverable on || true
bluetoothctl pairable on || true

cat > /usr/local/bin/tunerpi-enable-bluetooth <<'EOF'
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
EOF
chmod 0755 /usr/local/bin/tunerpi-enable-bluetooth

cat > /etc/systemd/system/tunerpi-bluetooth.service <<'EOF'
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
EOF
systemctl enable --now tunerpi-bluetooth.service

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
# The SPI framebuffer X server intentionally has no window manager.  Tk's
# fullscreen hint alone is therefore ignored; pin the dashboard to the exact
# physical framebuffer dimensions as well.
root.geometry(f'{root.winfo_screenwidth()}x{root.winfo_screenheight()}+0+0')
root.overrideredirect(True)
root.bind('<Escape>', lambda _event: root.attributes('-fullscreen', False))

screen_w, screen_h = root.winfo_screenwidth(), root.winfo_screenheight()
# GPIO 3.5-inch panels are normally 480x320.  Keep this launcher genuinely
# touchable there while retaining the richer three-column desktop layout.
compact = screen_w <= 800 or screen_h <= 500
pad_x, pad_y = (10, 7) if compact else (28, 18)
title_size, sub_size, status_size = (16, 8, 8) if compact else (24, 11, 11)
button_size, detail_size = (12, 7) if compact else (18, 10)
frame = tk.Frame(root, bg=BG, padx=pad_x, pady=pad_y)
frame.pack(fill='both', expand=True)
tk.Label(frame, text='TUNERPI  |  BMW 325i', font=('DejaVu Sans', title_size, 'bold'), bg=BG, fg=TEXT).pack(anchor='w')
if not compact:
    tk.Label(frame, text='GAUGES DEFAULT  |  Android Auto wireless  |  ECU logging armed', font=('DejaVu Sans', sub_size, 'bold'), bg=BG, fg=MUTED).pack(anchor='w', pady=(0, 12))
connection = tk.Label(frame, font=('DejaVu Sans', status_size, 'bold'), bg=PANEL, fg=TEXT, padx=8, pady=5, anchor='w')
connection.pack(fill='x', pady=(0, 5 if compact else 10))

def command(*args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=2).strip()
    except Exception:
        return ''

def update_connection():
    wifi = command('nmcli', '-t', '-f', 'ACTIVE,SSID,SIGNAL', 'device', 'wifi', 'list')
    active = next((line.split(':', 2) for line in wifi.splitlines() if line.startswith('yes:')), None)
    ip = command('nmcli', '-g', 'IP4.ADDRESS', 'device', 'show', 'wlan0').splitlines()
    wifi_text = 'Wi-Fi: offline'
    if active:
        wifi_text = f'Wi-Fi: {active[1]}  {active[2]}%'
    if ip:
        wifi_text += f'  {ip[0].split("/")[0]}'
    bt = command('bluetoothctl', 'show')
    powered = 'Powered: yes' in bt
    discoverable = 'Discoverable: yes' in bt
    bt_text = 'Bluetooth: ready' if powered and discoverable else 'Bluetooth: starting'
    connection.config(text=f'{wifi_text}    |    {bt_text}', fg='#7de3bb' if powered and active else AMBER)
    root.after(2000, update_connection)

update_connection()

buttons = tk.Frame(frame, bg=BG)
buttons.pack(fill='both', expand=True)
columns, rows = (2, 3) if compact else (3, 2)
for col in range(columns): buttons.grid_columnconfigure(col, weight=1)
for row in range(rows): buttons.grid_rowconfigure(row, weight=1)

def tile(label, detail, color, mode, row, col):
    box = tk.Frame(buttons, bg=PANEL, highlightbackground=color, highlightthickness=2)
    box.grid(row=row, column=col, sticky='nsew', padx=3 if compact else 7, pady=3 if compact else 7)
    tk.Button(box, text=label, font=('DejaVu Sans', button_size, 'bold'), bg=color, fg='white', relief='flat', command=lambda: run(mode)).pack(fill='both', expand=True, padx=4 if compact else 8, pady=(4 if compact else 8, 1 if compact else 2))
    if not compact:
        tk.Label(box, text=detail, font=('DejaVu Sans', detail_size), bg=PANEL, fg=MUTED, wraplength=260).pack(padx=8, pady=(2, 8))

if compact:
    tile('GAUGES', '', AMBER, 'tunerstudio', 0, 0)
    tile('ANDROID AUTO', '', BLUE, 'android-auto', 0, 1)
    tile('LOGS', '', '#435466', 'logs', 1, 0)
    tile('EXIT AA', '', '#435466', 'stop-android-auto', 1, 1)
    tk.Label(buttons, text='ECU logging armed  |  Hotspot: TunerPi-AA', font=('DejaVu Sans', 8, 'bold'), justify='left', bg=BG, fg=TEXT).grid(row=2, column=0, columnspan=2, sticky='nsew', padx=4, pady=4)
else:
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

# Do not mark the card provisioned unless the required runtime pieces are
# actually present.  This is intentionally local-only; phone pairing and touch
# calibration still require the installed hardware.
test -x /usr/bin/crankshaft-core
test -x /usr/bin/crankshaft-ui-slim
test -x /usr/local/bin/tunerpi-touch
test -f "${INSTALL_ROOT}/TunerStudioMS/TunerStudioMS.jar"
grep -q '^commPort=/dev/microsquirt$' "${PROPS}"
grep -q 'BMW_Wide_Touch.dash' "${PROPS}"
systemctl is-enabled crankshaft-core.service >/dev/null
systemctl is-enabled ssh avahi-daemon tailscaled >/dev/null
test -s "${USER_HOME}/.ssh/authorized_keys"
sshd -t
python3 - <<'PY'
import json
with open('/etc/crankshaft/profiles/host_profiles.json', encoding='utf-8') as handle:
    profile = json.load(handle)[0]
android_auto = next(item for item in profile['devices'] if item['type'] == 'AndroidAuto')
assert android_auto['useMock'] is False
assert android_auto['settings']['connectionMode'] == 'wireless'
assert android_auto['settings']['wireless.enabled'] is True
PY

touch /var/lib/pi-tuner-firstboot-complete
systemctl disable tunerpi-provision.service tunerpi-recovery.service tunerpi-recovery-v2.service || true
sync
systemctl reboot
