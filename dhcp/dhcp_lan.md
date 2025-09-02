# Raspberry Pi — DHCP & Connectivity 

---

## Overview

- Purpose: Provide DHCP (and local DNS caching) on the **LAN** interface while WAN access remains on the default interface.
- Stack: **NetworkManager** to bring up links, **dnsmasq** to serve DHCP/DNS.
- Root cause fixed earlier: `dnsmasq` started **before** `eth1` existed at boot → “unknown interface eth1” → no DHCP/DNS.  
  **Fix**: Start `dnsmasq` **after** `NetworkManager-wait-online.service` and `network-online.target`.

---

## Files & Configuration

### 1) dnsmasq

**Config file**: `/etc/dnsmasq.d/lan.conf`

```ini
# Bind only to the LAN NIC and avoid clashes
interface=eth1
bind-interfaces
except-interface=lo
except-interface=eth0
```

_Note: These ensure dnsmasq binds only to the LAN NIC and avoids conflicts with other interfaces._

**Systemd override**: `/etc/systemd/system/dnsmasq.service.d/override.conf`

```ini
[Unit]
After=NetworkManager-wait-online.service network-online.target
Wants=NetworkManager-wait-online.service network-online.target
```

Enable wait-online so the override actually does something:

```bash
sudo systemctl enable NetworkManager-wait-online.service
```

Control & logs during troubleshooting:

```bash
sudo systemctl restart dnsmasq
sudo systemctl status dnsmasq --no-pager
journalctl -u dnsmasq -n 50 --no-pager
```

---

### 2) NetworkManager (LAN profile)

Connection: `LAN-[REDACTED IP]` bound to `eth1` (USB NIC).  
Autoconnect & stability tweaks:

```bash
nmcli connection modify LAN-[REDACTED IP] connection.autoconnect yes
nmcli connection modify LAN-[REDACTED IP] connection.autoconnect-priority 10
nmcli connection modify LAN-[REDACTED IP] connection.wait-device-timeout 30
```

Useful checks:

```bash
nmcli connection show
nmcli device status
ip -br addr
```

The corresponding system connection file (managed by NetworkManager, reference only):

```
/etc/NetworkManager/system-connections/LAN-[REDACTED IP].nmconnection
```

---

### 3) (Optional) Fallback self-heal

Use only if the race persists even with the override above.

**Script**: `/usr/local/bin/fix-lan.sh`

```bash
#!/bin/bash
set -euo pipefail
sleep 10
nmcli con up LAN-[REDACTED IP] || true
systemctl restart dnsmasq || true
```

**Unit**: `/etc/systemd/system/fix-lan.service`

```ini
[Unit]
Description=Fix eth1 + dnsmasq after boot
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-lan.sh

[Install]
WantedBy=multi-user.target
```

---

## Packages

- `dnsmasq` — DHCP server & caching DNS for the LAN.
- (Optional, diagnostics) `dnsutils` — provides `dig` / `nslookup` if you want on-box DNS tests.

---

## Operational Commands

Service & interface health:

```bash
# dnsmasq
systemctl status dnsmasq --no-pager
journalctl -u dnsmasq -n 50 --no-pager

# NetworkManager / device state
nmcli connection show
nmcli device status
ip -br addr
```

Manual restarts after configuration changes:

```bash
sudo systemctl restart NetworkManager
sudo systemctl restart dnsmasq
```

DNS tests (from the Pi):

```bash
# Install if needed:
#   sudo apt install -y dnsutils
dig @127.0.0.1 google.com   # via dnsmasq on the Pi
dig @1.1.1.1 google.com     # direct to upstream, bypass dnsmasq
```

Connectivity sanity from a Windows client on the LAN:

```batch
ipconfig /renew                :: obtain DHCP lease from the Pi
ping [REDACTED IP]             :: Pi LAN IP
ping 1.1.1.1                   :: raw internet (NAT check)
ping google.com                :: DNS + connectivity
```

---

## Outcome

- **Root cause**: `dnsmasq` started before `eth1` was ready at boot.
- **Resolution**: Added systemd override so `dnsmasq` starts _after_ `NetworkManager-wait-online.service` / `network-online.target`; set the LAN profile to autoconnect with priority & wait timeout.
- **Result**: After reboot, LAN clients obtain DHCP leases on **[REDACTED IP]/24** and DNS resolves via `dnsmasq` without manual intervention.

---
