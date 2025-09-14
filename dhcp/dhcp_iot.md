# DHCP on IoT Wi‑Fi (wlan0, 2.4 GHz) — Raspberry Pi 5 Router

_Last updated: 2025-09-14 13:23._

This document defines the **minimal, stable** setup for **IoT SSID (10.0.72.0/24)** on `wlan0` with **dnsmasq** for DHCP/DNS and **policy‑routing** pinned to the **main** table to avoid interference from services like Tailscale.

---

## Target

- **Interface:** `wlan0` (AP, 2.4 GHz)  
- **SSID:** `RPI‑IoT‑2G` (example)  
- **Subnet:** `10.0.72.0/24`  
- **Router (Pi):** `10.0.72.1`  
- **DNS handed to clients:** `10.0.72.1`  
- **WAN:** `eth0` (default route lives here)

---

## 1) NetworkManager profile (`IoT-10.0.72`)

Create/modify the AP profile for `wlan0`:

```bash
sudo nmcli c modify "IoT-10.0.72"   802-11-wireless.mode ap   802-11-wireless.band bg   802-11-wireless.channel 6   ipv4.method manual   ipv4.addresses "10.0.72.1/24"   ipv4.never-default yes   ipv4.route-metric 600   ipv6.method disabled   connection.autoconnect yes
```

### WPA2‑PSK (example)
```bash
sudo nmcli c modify "IoT-10.0.72" wifi-sec.key-mgmt wpa-psk   wifi-sec.psk 'ChangeMeStrong123!'
```

### Policy routing — pin IoT to the **main** table (254)

This prevents table 52 (e.g. Tailscale) from hijacking IoT traffic:

```bash
sudo nmcli c modify "IoT-10.0.72"   ipv4.routing-rules "priority 60 from 10.0.72.0/24 table 254"
sudo nmcli c modify "IoT-10.0.72"   +ipv4.routing-rules "priority 85 iif wlan0 table 254"

# Apply without touching WAN
sudo nmcli c down "IoT-10.0.72" ; sleep 2 ; sudo nmcli c up "IoT-10.0.72"

# Verify
ip rule show | sed -n '1,200p'
ip -4 route get 8.8.8.8 from 10.0.72.50 iif wlan0
```

Expected route decision:
```
8.8.8.8 from 10.0.72.50 via 192.168.1.1 dev eth0
```

---

## 2) dnsmasq (per‑interface scoping)

**Use interface‑scoped directives** to prevent DHCP options from the LAN leaking into IoT.

`/etc/dnsmasq.d/iot.conf`
```conf
# IoT DHCP/DNS on wlan0
interface=wlan0
bind-interfaces

# Serve only on wlan0 (IoT)
dhcp-range=interface:wlan0,10.0.72.50,10.0.72.199,255.255.255.0,12h
dhcp-option=interface:wlan0,option:router,10.0.72.1
dhcp-option=interface:wlan0,option:dns-server,10.0.72.1

# Upstream resolvers for IoT (adblock layer may override globally)
server=1.1.1.1
server=9.9.9.9
```

> **Tip:** Keep singleton keywords (e.g., `domain=`) only once globally (e.g. in `/etc/dnsmasq.conf`). Repeating them across files causes “illegal repeated keyword”.

Validate & reload:
```bash
sudo dnsmasq --test
sudo systemctl restart dnsmasq
sudo systemctl --no-pager -l status dnsmasq | sed -n '1,25p'
```

Confirm listening:
```bash
sudo ss -lunpt | grep -E 'dnsmasq|:53\b'
```

---

## 3) Quick validation (from an IoT client)

- Obtain IP in **10.0.72.50–199**.
- Default gateway = **10.0.72.1**, DNS = **10.0.72.1**.

Connectivity:
```bash
ping -c 3 10.0.72.1
ping -c 3 1.1.1.1
ping -c 3 8.8.8.8
curl -I https://example.com
```

If adblock is enabled, ad domains (e.g. `doubleclick.net`) should resolve to `0.0.0.0` or NXDOMAIN while normal domains resolve normally.

---

## 4) nftables & sysctl (context)

Forward & NAT must already be in place. Minimal expected rules (conceptual):

```bash
# inet filter forward:
#  - default policy drop
#  - est/rel accept
#  - iif wlan0 oif eth0 accept (new,est,rel)
#  - iif eth0  oif wlan0 accept (est,rel)

# ip nat postrouting:
#  - oif eth0 ip saddr 10.0.72.0/24 masquerade
```

Sysctl (persisted):
```bash
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.eth0.rp_filter=0
net.ipv4.conf.wlan0.rp_filter=0
```

---

## 5) Troubleshooting

- **Phone got 10.0.72.x but gateway/DNS = 10.0.69.1:** You’re hitting option bleed. Ensure `interface:wlan0` scoping in `iot.conf` and remove global `dhcp-option` lines elsewhere.
- **dnsmasq won’t start, “illegal repeated keyword”:** A singleton (like `domain=`) is defined in more than one file. Keep it only once.
- **Counters increment but no internet:** Check the `ip -4 route get … iif wlan0` decision and policy rules; confirm WAN default via `eth0` exists in `main`.
- **Android shows “No internet” while web works:** Cosmetic captive‑portal check blocked by adblock; either ignore or whitelist those specific domains in the adblock layer.

---

**Outcome:** IoT devices get DHCP from the Pi on `wlan0`, policy routing pins flows to `main` so they NAT out `eth0`. The setup is resilient to reboots and coexists with Tailscale and adblock.
