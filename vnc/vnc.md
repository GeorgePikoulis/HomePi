# Raspberry Pi VNC Setup Summary

This document summarizes the configuration for enabling VNC access to a lightweight PIXEL desktop on Raspberry Pi.

---

## Scripts / Systemd Units

### Created
- **`remote-desktop.target`**  
  A custom target to start both the PIXEL desktop session (LightDM) and WayVNC together.

- **`/etc/systemd/system/remote-desktop.target`**
  ```ini
  [Unit]
  Description=Remote Desktop (PIXEL + VNC)
  Requires=lightdm.service wayvnc.service
  After=lightdm.service wayvnc.service
  ```

- **`/etc/systemd/system/remote-desktop-start.sh`**  
  Helper script to start the desktop + VNC.
  ```bash
  #!/bin/bash
  sudo systemctl start remote-desktop.target
  ```

- **`/etc/systemd/system/remote-desktop-stop.sh`**  
  Helper script to stop the desktop + VNC.
  ```bash
  #!/bin/bash
  sudo systemctl stop remote-desktop.target
  ```

### Modified
- **`/etc/systemd/system/lightdm.service.d/remote.conf`**
  ```ini
  [Service]
  ExecStart=
  ExecStart=/usr/sbin/lightdm
  ```

- **`/etc/systemd/system/wayvnc.service.d/remote.conf`**
  ```ini
  [Service]
  ExecStart=
  ExecStart=/usr/sbin/wayvnc-run.sh
  ```

- **`/etc/wayvnc/config`**
  ```ini
  address=0.0.0.0
  port=5900
  enable_auth=true
  enable_pam=true
  rsa_private_key_file=rsa_key.pem
  private_key_file=tls_key.pem
  certificate_file=tls_cert.pem
  ```

---

## System File Changes

- Created drop-in directories for `lightdm.service` and `wayvnc.service` under `/etc/systemd/system/.../`.
- Configured **PIXEL session** via LightDM (`LXDE-pi-wayfire`).
- Adjusted **WayVNC** config to listen on port 5900 with authentication enabled.

---

## Packages Installed

- **PIXEL Desktop Environment**  
  (`raspberrypi-ui-mods`, `lxsession`, `lxappearance`, `lxpanel`, etc.)

- **LightDM Display Manager**  
  (`lightdm`, `pi-greeter`, `lightdm-gtk-greeter`)

- **WayVNC Server**  
  (`wayvnc`)

- **Supporting tools**  
  (`dbus-x11`, `xserver-xorg`, `policykit-1`)

---

## Usage

- **Start remote desktop:**
  ```bash
  sudo systemctl start remote-desktop.target
  ```

- **Stop remote desktop:**
  ```bash
  sudo systemctl stop remote-desktop.target
  ```

Then connect from any VNC client (RealVNC Viewer, TigerVNC, Android/iOS apps) to:

```
<raspberrypi-ip>:5900
```

Authentication and TLS are enabled.
