# DHCP & Connectivity — Trusted Wi‑Fi (wlan1, 5 GHz)

**Updated:** 2025-09-14

This document adds DHCP/DNS for the **Trusted 5 GHz SSID** served by NetworkManager on **`wlan1`**.

- **SSID:** `[REDACTED]` (configured in NetworkManager)
- **Interface:** `wlan1`
- **Gateway/DNS (Pi):** `10.0.70.1`
- **Subnet:** `10.0.70.0/24`
- **DHCP pool:** `10.0.70.100–10.0.70.199`

> AP creation (SSID, passphrase, channel, static IP) is handled by NetworkManager (`Trusted-10.0.70`). This page focuses on **dnsmasq** for DHCP/DNS only.

---

## 1) dnsmasq config (Trusted 5 GHz)

Create `/etc/dnsmasq.d/trusted-10.0.70.conf`:

```ini
# Trusted 5 GHz (wlan1)
interface=wlan1
bind-interfaces
except-interface=lo
except-interface=eth0

# Safer DNS defaults
domain-needed
bogus-priv
dhcp-authoritative

# DHCP pool (scoped to wlan1 to prevent option bleed)
dhcp-range=interface:wlan1,10.0.70.100,10.0.70.199,255.255.255.0,12h

# Router (option 3) and DNS (option 6) -> the Pi
dhcp-option=interface:wlan1,option:router,10.0.70.1
dhcp-option=interface:wlan1,option:dns-server,10.0.70.1

# (Optional) Local domain & host hints
#domain=home.lan
#address=/rpi.local/10.0.70.1
```

> **Why interface‑scoped lines?** Using `interface:wlan1` on `dhcp-range`/`dhcp-option` avoids accidental “gateway/DNS bleed” from other `dnsmasq.d/*.conf` files (e.g., LAN or IoT) into this SSID.

---

## 2) Reload & health checks

```bash
# Validate config syntax
sudo dnsmasq --test

# Apply changes
sudo systemctl reload dnsmasq || sudo systemctl restart dnsmasq

# Confirm dnsmasq is listening for DHCP/DNS
systemctl --no-pager -l status dnsmasq | sed -n '1,40p'
sudo ss -lntup | grep -E ':(53|67)\b.*dnsmasq' || true

# Verify the Pi's wlan1 address
ip addr show wlan1 | sed -n '1,30p'
```

---

## 3) Client verification 

- Device should receive **`10.0.70.100–199`**, **gateway `10.0.70.1`**, **DNS `10.0.70.1`**.
- Quick tests:
  ```bash
  ping -c 3 10.0.70.1
  nslookup rpi.local 10.0.70.1 || dig +short rpi.local @10.0.70.1
  dig +short dns.google @10.0.70.1
  ```

> If internet fails but local ping works, check nftables NAT/forward rules for `10.0.70.0/24` → `eth0` and confirm `net.ipv4.ip_forward=1`.

---

## 4) nftables (reference)

If not already present, you need forwarding and masquerade for this subnet. Example sketch (adapt to your table/chain names):

```nft
# in table ip nat:
oifname "eth0" ip saddr 10.0.70.0/24 counter masquerade

# in table ip filter (forward chain):
iifname "wlan1" oifname "eth0" ct state established,related accept
iifname "wlan1" oifname "eth0" accept
oifname "wlan1" iifname "eth0" ct state established,related accept
```

> Your repo’s nftables may already handle this; keep rules **per‑subnet** to maintain segmentation between IoT (`10.0.72.0/24`), LAN (`10.0.69.0/24`), and Trusted (`10.0.70.0/24`).

---

## 5) Troubleshooting

- **Got wrong gateway/DNS?** Ensure only one file provides DHCP options for `wlan1` and use **`interface:wlan1`** scoping as above.
- **No leases issued:** Check that NetworkManager has `wlan1` up with `10.0.70.1/24` and that `dnsmasq --test` is OK.
- **mDNS name:** Access the Pi via `rpi.local` (mDNS). If a client doesn’t resolve `.local`, use the IP `10.0.70.1`.
- **Leases file:** `/var/lib/misc/dnsmasq.leases` shows active leases.

---

## Appendix — NetworkManager AP (reference only)

AP is managed by NM; shown here for completeness in case the profile needs re‑creation:

```bash
SSID="[REDACTED]"
CON="Trusted-10.0.70"
IF="wlan1"

sudo nmcli con add type wifi ifname "$IF" con-name "$CON" autoconnect yes ssid "$SSID"
sudo nmcli con modify "$CON" 802-11-wireless.mode ap 802-11-wireless.band a 802-11-wireless.channel 36
sudo nmcli con modify "$CON" wifi-sec.key-mgmt wpa-psk
sudo nmcli con modify "$CON" wifi-sec.psk "[REDACTED]"
sudo nmcli con modify "$CON" wifi-sec.proto rsn
sudo nmcli con modify "$CON" wifi-sec.group ccmp
sudo nmcli con modify "$CON" wifi-sec.pairwise ccmp
sudo nmcli con modify "$CON" ipv4.method manual ipv4.addresses 10.0.70.1/24 ipv4.never-default yes
sudo nmcli con modify "$CON" ipv6.method ignore
sudo nmcli con up "$CON"
```

---

### Files touched
- `/etc/dnsmasq.d/trusted-10.0.70.conf` (new)

### See also
- `dhcp/dhcp_lan.md` and `dhcp/dhcp_iot.md` for style and cross‑checks.
- Top‑level **README** (Quick Links & topology).

