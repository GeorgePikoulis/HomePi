# Raspberry Pi 5 Remote Desktop (PIXEL + WayVNC) Setup

This document summarizes the steps taken to install and configure a **lightweight PIXEL desktop** with **on-demand VNC access** on Raspberry Pi OS (Bookworm).

---

## 📦 Packages Installed
```bash
sudo apt update
sudo apt install -y raspberrypi-ui-mods lightdm realvnc-vnc-server realvnc-vnc-viewer
```

Later we disabled RealVNC (X11) and switched to **WayVNC** (already shipped with Bookworm).

---

## 📝 System Files Created / Modified

### 1. Systemd Target — `/etc/systemd/system/remote-desktop.target`
```ini
[Unit]
Description=Remote Desktop (PIXEL + WayVNC) on-demand target
Wants=lightdm.service wayvnc.service
After=network-online.target

[Install]
WantedBy=multi-user.target
```

### 2. Drop-in for LightDM — `/etc/systemd/system/lightdm.service.d/remote.conf`
```ini
[Unit]
PartOf=remote-desktop.target
```

### 3. Drop-in for WayVNC — `/etc/systemd/system/wayvnc.service.d/remote.conf`
```ini
[Unit]
PartOf=remote-desktop.target
```

### 4. WayVNC Config — `/home/george/.config/wayvnc/config`
```ini
address=0.0.0.0
port=5900
enable-auth=true
credentials-file=/home/george/.local/share/wayvnc/passwd
```

### 5. Kernel HDMI Settings — `/boot/firmware/config.txt`
(ensures headless resolution)
```
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=82   # 1920x1080 @ 60Hz
```

---

## 🔑 Password Setup
```bash
mkdir -p ~/.local/share/wayvnc
wayvnc --gen-password > ~/.local/share/wayvnc/passwd
```

---

## ▶️ Usage

### Start remote desktop:
```bash
sudo systemctl start remote-desktop.target
```

### Stop remote desktop:
```bash
sudo systemctl stop remote-desktop.target
```

### Check logs if needed:
```bash
systemctl status wayvnc lightdm -l
journalctl -u wayvnc -u lightdm -b --no-pager
```

---

## ✅ Result
- Lightweight **PIXEL desktop** installed.  
- **WayVNC** configured for secure access.  
- On-demand systemd **target** allows starting/stopping the desktop and VNC server together with a single command.  
