# Home Pi Docs — Index

_Updated: 2025-09-14 13:29._

Raspberry Pi 5 home router/AP project. Docs, configs and small scripts for a **single‑Pi home gateway**:

- **WAN:** `eth0` → ISP CPE
- **LAN (wired):** `eth1` → TL‑SG105 switch → PCs/TV/IoT hub
- **Wi‑Fi (IoT 2.4 GHz):** `wlan0` → SSID `[REDACTED]` → `10.0.72.0/24`
- **Wi‑Fi (Trusted 5 GHz):** `wlan1` → (planned) → `10.0.70.0/24`
- **VPN:** `tailscale0` for remote access
- **Core services:** NetworkManager, **dnsmasq** (DHCP/DNS + AdBlock), **nftables** (FW/NAT), **CAKE** (QoS), **WayVNC**, Backups

> Hostname: `rpi` (`rpi.local`) • Main user: `[REDACTED]`

---

## Quick Links

- **AdBlock (dnsmasq) — Summary** → [`adblock/adblock.md`](adblock/adblock.md)
- **Checkpoint Backups — Summary** → [`backups/backups.md`](backups/backups.md)
- **DHCP & Connectivity — LAN (eth1)** → [`dhcp/dhcp_lan.md`](dhcp/dhcp_lan.md)
- **DHCP & Connectivity — IoT Wi‑Fi (wlan0, 2.4 GHz)** → [`dhcp/dhcp_iot.md`](dhcp/dhcp_iot.md)
- **Remote Desktop (PIXEL + WayVNC)** → [`vnc/vnc.md`](vnc/vnc.md)

> If any link still points to `HomePi-main/...`, update it to a **relative path** like `adblock/adblock.md` (this README already uses relative paths).

---

## Network Topology (current)

```
        Internet
           │
      ISP CPE (NAT)
           │ 192.168.1.0/24
           │
         eth0 (WAN)  ───────────────────────────────┐
           │                                        │
      ┌────┴────┐                                   │
      │  RPi 5  │                                   │
      │  (rpi)  │ tailscale0 (remote admin)         │
      └────┬────┘                                   │
           │                                        │
      eth1 │ 10.0.69.0/24                           │
           │ → TL‑SG105 switch                      │
           │                                        │
      wlan0│ 10.0.72.0/24 (IoT 2.4 GHz)             │  → NAT via eth0
           │  SSID: [REDACTED]                      │
      wlan1│ 10.0.70.0/24 (Trusted 5 GHz) (planned) │
```

### Routing & Firewall (high level)
- **Policy routing:** IoT (`10.0.72.0/24`) pinned to **table `main` (254)** to avoid Tailscale table conflicts.
- **nftables:** default‑drop on `forward`; explicit `wlan0→eth0` allow + return path; `masquerade` for `10.0.72.0/24` out `eth0`.
- **Sysctl:** `net.ipv4.ip_forward=1`; `rp_filter=0` (all/default/eth0/wlan0).
- **QoS:** CAKE SmartQueue (configured separately).
- **DNS:** dnsmasq on the Pi; **per‑interface DHCP options** to prevent gateway/DNS bleed between LAN/IoT; AdBlock via hosts lists.

---

## Fast Start — IoT 2.4 GHz Wi‑Fi (wlan0)

1. **NetworkManager (profile `IoT-10.0.72`)**
   - Static `10.0.72.1/24`, `ipv4.never-default yes`, WPA2‑PSK.
   - Add NM **routing‑rules**: `priority 60 from 10.0.72.0/24 table 254`, `priority 85 iif wlan0 table 254`.
2. **dnsmasq** — use **interface‑scoped** lines (no global `dhcp-option`):
   - `dhcp-range=interface:wlan0,10.0.72.50,10.0.72.199,255.255.255.0,12h`
   - `dhcp-option=interface:wlan0,option:router,10.0.72.1`
   - `dhcp-option=interface:wlan0,option:dns-server,10.0.72.1`
3. **nftables** — allow `wlan0→eth0` and `masquerade` `10.0.72.0/24` out `eth0`.

Full details in **[`dhcp/dhcp_iot.md`](dhcp/dhcp_iot.md)**.

---

## Repo Layout

- `adblock/` — dnsmasq AdBlock setup & update script(s)
- `backups/` — checkpoint backup/restore docs & scripts
- `dhcp/` — per‑subnet DHCP/DNS docs (`dhcp_lan.md`, `dhcp_iot.md`)
- `nftables/` — nftables configs (FW/NAT/QoS glue)
- `vnc/` — PIXEL desktop + WayVNC units & usage

---

## Roadmap / TODO

- **Trusted 5 GHz (wlan1)** — Multi‑SSID & guest network
- **NordVPN as WAN uplink** (policy‑based)
- **Samba** file server
- **Torrent client** (remote add via magnet)
- **Multi‑room audio** (to home speakers)
- **Firewall hardening** presets & metrics

---

## Contributing / Notes to Self

- Keep **per‑interface** DHCP options in `dnsmasq.d` (avoid option bleed).
- Avoid repeating singleton dnsmasq keywords (`domain=` etc.) across files.
- Prefer **relative links** in docs so the repo browses well on GitHub and in local zips.
- Commit messages: `docs(dhcp): …`, `feat(nft): …`, `fix(adblock): …` for quick history scanning.
