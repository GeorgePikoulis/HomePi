# Pi Zero W → Snapcast Client Setup (rpi-snap-livingroom)

**Project:** HomePi / Snapserver  
**Host:** `rpi-snap-livingroom` (Pi Zero W)  
**Date:** 2025-10-04 23:29:09 UTC+03:00  
**Author:** ChatGPT (with George)

This document captures the exact steps and decisions we took to turn a **Raspberry Pi Zero W** into a **Snapcast client**, make the audio device selection robust, and clone the setup for more rooms. It includes troubleshooting we hit (daemonizing under systemd) and the final hardened configuration.

---

## 1) OS, SSH, Wi‑Fi, and Console Autologin

1. **Flash Raspberry Pi OS Lite (Bookworm, 32‑bit)** to microSD.
2. **Enable SSH** by placing an empty `ssh` file on the boot partition.
3. **Wi‑Fi for first boot:** create `wpa_supplicant.conf` on boot partition:
   ```conf
   country=GR
   ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
   update_config=1

   network={
       ssid="YOUR_WIFI_SSID"
       psk="YOUR_WIFI_PASSWORD"
       key_mgmt=WPA-PSK
   }
   ```
4. Boot, then SSH in (initially `raspberrypi.local` unless you already set hostname).
5. **Enable NetworkManager** (Bookworm default, but verify):
   ```bash
   systemctl is-active NetworkManager && systemctl is-enabled NetworkManager
   sudo systemctl enable --now NetworkManager
   sudo systemctl disable --now dhcpcd || true
   ```
6. **Ensure Wi‑Fi autoconnect via nmcli**:
   ```bash
   nmcli connection show
   sudo nmcli connection modify "<CON_NAME>" connection.autoconnect yes connection.autoconnect-priority 100
   # Optional: prefer 2.4 GHz on Pi Zero W
   sudo nmcli connection modify "<CON_NAME>" wifi.band bg
   nmcli -f NAME,TYPE,AUTOCONNECT,DEVICE connection show
   ```
7. **Console autologin on tty1 (no GUI):**
   ```bash
   sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
   sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<'EOF'
   [Service]
   ExecStart=
   ExecStart=-/sbin/agetty --autologin %I --noclear %I $TERM
   EOF

   # Alternatively (recommended one-liner):
   sudo raspi-config nonint do_boot_behaviour B2
   ```

> _Note on `initramfs.conf`: no changes required for Snapcast. Defaults are fine._

---

## 2) Audio Device Discovery & Stable Selection

Install tools:
```bash
sudo apt update
sudo apt install -y alsa-utils mpg123
```

Discover devices:
```bash
aplay -l
aplay -L | sed -n '1,120p'
for p in /sys/class/sound/card*/id; do echo "$(basename "$(dirname "$p")") -> $(cat "$p")"; done
```

### Avoid ALSA index pinning (important)

Do **not** force `snd-usb-audio` to a fixed ALSA card index (e.g. `index=0`). On Raspberry Pi, HDMI audio often claims `card0` early; pinning USB to `0` can prevent the USB DAC from registering at all (you’ll see errors like `cannot create card instance 0 ... error: -16`), and then anything that targets `CARD=UsbAudio` will fail because the card never appears.

Instead: keep everything **name-based** (`CARD=UsbAudio`) and let ALSA assign the card numbers dynamically.

If you ever created an override like this, **remove it**:

- `/etc/modprobe.d/alsa-usb-first.conf` containing `options snd-usb-audio index=0`

Fix:

```bash
sudo rm -f /etc/modprobe.d/alsa-usb-first.conf
sudo reboot
```

### Make USB audio the stable default (name-based)

**ALSA default to USB by NAME** (not by number):
```bash
USBCARDID="UsbAudio"    # from /sys/class/sound/card*/id

sudo tee /etc/asound.conf >/dev/null <<EOF
pcm.!default {
  type plug
  slave.pcm "sysdefault:CARD=${USBCARDID}"
}
ctl.!default {
  type hw
  card "${USBCARDID}"
}
EOF

sudo alsactl init || true
```

**Test**:
```bash
aplay -D "sysdefault:CARD=UsbAudio" /usr/share/sounds/alsa/Front_Center.wav
aplay /usr/share/sounds/alsa/Front_Center.wav
```

> Card numbering can vary (`card0`, `card1`, …). This setup never depends on the number.

---

## 3) Install & Configure Snapclient (systemd-safe)

Install:
```bash
sudo apt update
sudo apt install -y snapclient
```

Create a **systemd override** (do **not** daemonize with `-d` under systemd) and pin to the USB device **by name**. We used `plughw` initially for maximum compatibility; `sysdefault` is also fine.

```bash
sudo mkdir -p /etc/systemd/system/snapclient.service.d
sudo tee /etc/systemd/system/snapclient.service.d/override.conf >/dev/null <<'EOF'
[Service]
# Let systemd supervise; do NOT daemonize.
ExecStart=
# Choose one of the soundcard args below:

# A) Compatible (what we used in production first):
ExecStart=/usr/bin/snapclient --player alsa --soundcard 'plughw:CARD=UsbAudio,DEV=0' --latency 200 --host rpi-media-server.local

# B) Alternatively (cleaner), use the sysdefault name path:
# ExecStart=/usr/bin/snapclient --player alsa --soundcard 'sysdefault:CARD=UsbAudio' --latency 200 --host rpi-media-server.local

# Provide a runtime dir if snapclient ever needs it
RuntimeDirectory=snapclient
RuntimeDirectoryMode=0755
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now snapclient
```

> **Troubleshoot:** We originally added `-d` which caused: `Exception: Could not open PID lock file "/var/run/snapclient/pid"`. Removing `-d` fixed it.

**Optional network wait**:
```bash
sudo tee /etc/systemd/system/snapclient.service.d/network.conf >/dev/null <<'EOF'
[Unit]
Wants=network-online.target
After=network-online.target
EOF
sudo systemctl daemon-reload
sudo systemctl restart snapclient
```

---

## 4) Volume Strategy (Server‑side control)

Set the USB DAC to 100% once, then control per-room volume from Snapserver/Snapweb.

```bash
amixer -c UsbAudio scontrols
amixer -c UsbAudio sset PCM 100% unmute || true
amixer -c UsbAudio sset Speaker 100% unmute || true
amixer -c UsbAudio sset Master 100% unmute || true
sudo alsactl store
```

Server API examples:
```bash
# List clients with volumes
curl -s http://rpi-media-server.local:1780/jsonrpc   -H 'Content-Type: application/json'   -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | jq -r '.result.server.clients[] | "\(.id)  \(.host.name)  vol=\(.config.volume.percent)% muted=\(.config.volume.muted)"'

# Set volume (replace <CLIENT_ID>)
curl -s http://rpi-media-server.local:1780/jsonrpc   -H 'Content-Type: application/json'   -d '{"id":2,"jsonrpc":"2.0","method":"Server.SetClientVolume","params":{"id":"<CLIENT_ID>","volume":{"percent":60,"muted":false}}}'
```

---

## 5) Optional Polishing

- Persist mixer volume: `alsamixer` → set → `sudo alsactl store`  
- Friendly client name (shows in Snapweb):
  ```bash
  sudo sed -i "s|/usr/bin/snapclient |/usr/bin/snapclient --name 'Living Room' |"   /etc/systemd/system/snapclient.service.d/override.conf
  sudo systemctl daemon-reload && sudo systemctl restart snapclient
  ```
- Silence HDMI audio forever (if not needed):
  ```bash
  sudo tee /etc/modprobe.d/disable-hdmi-audio.conf >/dev/null <<'EOF'
  blacklist snd_bcm2835
  EOF
  ```

---

## 6) Cloning This SD for New Rooms (and making each unique)

### A) Clone the SD

**GUI (Pi Imager):** `⋯ → Clone card` (source SD → target SD).  
**Linux CLI:**
```bash
lsblk -p
sudo dd if=/dev/sdX of=/dev/sdY bs=4M conv=fsync,status=progress
sync
```

### B) Make the clone unique (on the **new** Pi)

1. **Hostname:**
   ```bash
   sudo hostnamectl set-hostname rpi-snap-<room>
   sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1 rpi-snap-<room>/" /etc/hosts
   ```

2. **Machine ID:**
   ```bash
   sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
   sudo systemd-machine-id-setup
   ```

3. **SSH host keys:**
   ```bash
   sudo rm -f /etc/ssh/ssh_host_*
   sudo dpkg-reconfigure openssh-server
   sudo systemctl restart ssh
   ```

4. **NetworkManager Wi‑Fi profile (optional rename & autoconnect):**
   ```bash
   nmcli connection show
   sudo nmcli connection modify "<YOUR_WIFI_CON_NAME>" connection.id "wifi-<room>"
   sudo nmcli connection modify "wifi-<room>" connection.autoconnect yes connection.autoconnect-priority 100
   ```

5. **Snapclient name (per room):**
   ```bash
   sudo sed -i "s|/usr/bin/snapclient |/usr/bin/snapclient --name '<Room Name>' |"    /etc/systemd/system/snapclient.service.d/override.conf
   sudo systemctl daemon-reload && sudo systemctl restart snapclient
   ```

6. **Volume to 100%, then store:** see §4.

7. **(If static IP was hard-coded) update NM IPv4 settings** or rely on DHCP reservation.

8. **Reboot & verify:**
   ```bash
   sudo reboot
   # after boot
   hostname
   systemctl status --no-pager snapclient
   ```

---

## 7) Quick Troubleshooting Notes

- **Service crash loop with “Could not open PID lock file /var/run/snapclient/pid”**  
  → You’re probably running with `-d` under systemd. Remove `-d` in the override.  
- **No audio or wrong output**  
  → Use `sysdefault:CARD=UsbAudio` or `plughw:CARD=UsbAudio,DEV=0` in the ExecStart.  
- **Wi‑Fi reconnect delays on boot**  
  → Add the `network-online.target` drop-in (see §3).  
- **Stutter on 2.4 GHz**  
  → Increase latency to `--latency 250..500` and check Wi‑Fi RSSI.

---

## 8) Final State (our working config)

- ALSA card IDs (**example**; numbers can vary and we never pin them):
  - `vc4hdmi` (HDMI)
  - `UsbAudio` (USB DAC)
- Unit override in production (first stable run):
  ```ini
  [Service]
  ExecStart=
  ExecStart=/usr/bin/snapclient --player alsa --soundcard 'plughw:CARD=UsbAudio,DEV=0' --latency 200 --host rpi-media-server.local
  RuntimeDirectory=snapclient
  RuntimeDirectoryMode=0755
  ```

---

### Appendix: Useful one-liners

```bash
# Service health
systemctl status --no-pager snapclient
journalctl -u snapclient -n 50 --no-pager

# List ALSA devices
aplay -l
aplay -L | sed -n '1,120p'

# Server: list clients & volumes
curl -s http://rpi-media-server.local:1780/jsonrpc   -H 'Content-Type: application/json'   -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | jq -r '.result.server.clients[] | "\(.id)  \(.host.name)  vol=\(.config.volume.percent)% muted=\(.config.volume.muted)"'
```

---

