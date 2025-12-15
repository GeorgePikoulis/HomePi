# Daily Reboot at 03:00 — Raspberry Pi (systemd)

This document describes how to configure a **headless Raspberry Pi** (including Pi 5 booting from a USB SSD) to **reboot automatically every day at 03:00** using **systemd**.

This method is clean, robust, and safe for USB-attached SSDs.

---

## Overview

We create:

* a **systemd service** that performs a reboot
* a **systemd timer** that triggers the service daily at 03:00

This is functionally identical to running `sudo reboot`, but fully managed by systemd.

---

## 1. Create the reboot service

Create `/etc/systemd/system/daily-reboot.service`:

```bash
sudo tee /etc/systemd/system/daily-reboot.service >/dev/null <<'EOF'
[Unit]
Description=Daily reboot

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
EOF
```

---

## 2. Create the timer (03:00 daily)

Create `/etc/systemd/system/daily-reboot.timer`:

```bash
sudo tee /etc/systemd/system/daily-reboot.timer >/dev/null <<'EOF'
[Unit]
Description=Reboot daily at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

### Notes

* `OnCalendar=*-*-* 03:00:00` → every day at 03:00 (24h format)
* `Persistent=true` → if the Pi was off at 03:00, it will reboot once on next boot

---

## 3. Enable the timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now daily-reboot.timer
```

---

## 4. Verify scheduling

```bash
systemctl list-timers --all | grep daily-reboot
```

Expected output example:

```
Tue 2025-12-16 03:00:00 EET  16h  -  -  daily-reboot.timer  daily-reboot.service
```

---

## 5. Check configuration (optional)

```bash
systemctl status daily-reboot.timer
systemctl cat daily-reboot.timer
```

---

## SSD & USB Safety

* Uses `systemctl reboot`, which:

  * stops services cleanly
  * syncs filesystems
  * unmounts disks safely
* Safe for **USB SSD root filesystems (ext4)**
* Much safer than power cuts or forced reboots

No additional `sync` commands are required.

---

## Disable or remove

Disable the timer:

```bash
sudo systemctl disable --now daily-reboot.timer
```

Remove files:

```bash
sudo rm /etc/systemd/system/daily-reboot.service
sudo rm /etc/systemd/system/daily-reboot.timer
sudo systemctl daemon-reload
```

---

## End

This setup is distro-agnostic (Debian / Raspberry Pi OS / Ubuntu Server) and suitable for long-running headless systems.
