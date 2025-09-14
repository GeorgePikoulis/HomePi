# DHCP on LAN (eth1) — Raspberry Pi 5 Router

_Last updated: 2025-09-14 13:23._

This document defines the **authoritative, minimal and stable** setup for serving **DHCP/DNS on LAN (10.0.69.0/24)** from the Raspberry Pi (host: `rpi`, IP: **10.0.69.1**), using **dnsmasq** and **NetworkManager**. It replaces older notes and fixes the pitfall where DHCP options from another scope could “bleed” across interfaces.

---

## Target

- **Interface:** `eth1` (to TP-LINK TL‑SG105 switch / wired clients)  
- **Subnet:** `10.0.69.0/24`  
- **Router (Pi):** `10.0.69.1`  
- **DNS handed to clients:** `10.0.69.1` (Pi running dnsmasq)  
- **Upstream DNS:** Cloudflare + Quad9 (temporary — adblock can override upstreams globally)

> **Note:** WAN remains on `eth0`. Only `eth0` should install a default route. LAN must _not_ install a default route.

---

## 1) NetworkManager profile (`LAN-10.0.69`)

```bash
sudo nmcli c modify "LAN-10.0.69"   ipv4.method manual   ipv4.addresses "10.0.69.1/24"   ipv4.never-default yes   ipv4.route-metric 500   ipv6.method disabled   connection.autoconnect yes
```

- `ipv4.never-default yes`: prevents LAN from adding a default route (WAN keeps control).
- `route-metric` may be adjusted to taste; lower = more preferred for on-link routes (doesn’t affect default because there isn’t one).

Verify:
```bash
ip a show eth1
ip route show table main | grep 10.0.69.0
```

Expected connected route:
```
10.0.69.0/24 dev eth1 proto kernel scope link src 10.0.69.1
```

---

## 2) dnsmasq (per-interface scoping)

**Use interface‑scoped directives** to avoid the “wrong gateway/DNS” bug. Place this file at `/etc/dnsmasq.d/lan.conf`:

```conf
#/etc/dnsmasq.d/lan.conf
interface=eth1
bind-interfaces

# Serve only on eth1 (LAN)
dhcp-range=interface:eth1,10.0.69.100,10.0.69.199,255.255.255.0,12h
dhcp-option=interface:eth1,option:router,10.0.69.1
dhcp-option=interface:eth1,option:dns-server,10.0.69.1

# Upstream resolvers for LAN (adblock layer may override globally)
server=1.1.1.1
server=9.9.9.9
```

> **Important:** Do **not** place singleton keywords like `domain=...` in multiple files. Keep any such global keyword _only once_ (usually in `/etc/dnsmasq.conf`), otherwise dnsmasq may fail with “illegal repeated keyword”.

Validate & reload:
```bash
sudo dnsmasq --test
sudo systemctl restart dnsmasq
sudo systemctl --no-pager -l status dnsmasq | sed -n '1,25p'
```

Confirm it’s listening on port 53:
```bash
sudo ss -lunpt | grep -E 'dnsmasq|:53\b'
```

---

## 3) Boot ordering (dnsmasq after NetworkManager)

Ensure dnsmasq waits for NetworkManager to be online (already present in repo as `override.conf`):

`/etc/systemd/system/dnsmasq.service.d/override.conf`
```ini
[Unit]
After=NetworkManager-wait-online.service network-online.target
Wants=NetworkManager-wait-online.service network-online.target
```

Apply:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dnsmasq
```

---

## 4) Quick validation (from a LAN client)

- Obtain DHCP lease on **10.0.69.100–199**.
- Default gateway = **10.0.69.1**, DNS = **10.0.69.1**.

Connectivity checks:
```bash
ping 10.0.69.1
dig +short @10.0.69.1 example.com
ping -c 3 1.1.1.1
ping -c 3 8.8.8.8
curl -I https://example.com
```

If adblock is enabled, ad/tracker domains should resolve to `0.0.0.0` (or NXDOMAIN), while normal domains resolve normally.

---

## 5) Troubleshooting

- **Wrong gateway/DNS handed out:** Make sure `dhcp-option=interface:eth1,...` is used and remove/disable any global `dhcp-option` lines that could override.  
  ```bash
  grep -RIl '^[[:space:]]*dhcp-\(option\|range\)' /etc/dnsmasq.conf /etc/dnsmasq.d
  ```
- **dnsmasq fails with “illegal repeated keyword”:** You likely set a singleton keyword (e.g., `domain=`) in more than one file. Keep it only **once** globally.
- **No DHCP after reboot:** Confirm boot ordering override and that `eth1` is up before dnsmasq starts.
- **Clients resolve but no internet:** Check nftables NAT and forward rules, WAN default route on `eth0`, and `net.ipv4.ip_forward=1`.

---

## 6) Reference: sysctl & nftables (for completeness)

Sysctl persistence (already applied in router build):
```bash
sudo tee /etc/sysctl.d/99-router.conf >/dev/null <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.eth0.rp_filter=0
net.ipv4.conf.wlan0.rp_filter=0
EOF
sudo sysctl --system
```

nftables service enabled:
```bash
sudo systemctl enable --now nftables
sudo nft list ruleset | sed -n '1,60p'
```

---

**Outcome:** LAN clients get correct DHCP options from the Pi on `eth1`, DNS is served locally by dnsmasq, and internet flows via WAN `eth0` with NAT, surviving reboots.
