# Home Pi Docs — Index

- **HomePi**  
  `HomePi-main/README.md`
- **Raspberry Pi 5 — DNS AdBlocking (dnsmasq) — Summary**  
  `HomePi-main/adblock/adblock.md`
- **Raspberry Pi Checkpoint Backup — Summary**  
  `HomePi-main/backups/backups.md`
- **Raspberry Pi — DHCP & Connectivity**  
  `HomePi-main/dhcp/dhcp_lan.md`
- **Raspberry Pi 5 Remote Desktop (PIXEL + WayVNC) Setup**  
  `HomePi-main/vnc/vnc.md`

## Section previews

- **Raspberry Pi 5 — DNS AdBlocking (dnsmasq) — Summary** — Packages added / Scripts written / System file changes / dnsmasq configuration & data / systemd (automatic updates) / nftables (DNS enforcement) / Notes
- **Raspberry Pi Checkpoint Backup — Summary** — What’s backed up (paths & elements) / Where checkpoints live & naming / Script filenames (final state) / System file changes (to support backups & PC pull) / Packages added (for this workflow) / Commands you use (backup & restore) / Create a checkpoint (local) / One-off manual capture (equivalent to what the script does)
- **Raspberry Pi — DHCP & Connectivity** — Overview / Files & Configuration / 1) dnsmasq / 2) NetworkManager (LAN profile) / 3) (Optional) Fallback self-heal / Packages / Operational Commands / Outcome
- **Raspberry Pi 5 Remote Desktop (PIXEL + WayVNC) Setup** — 📦 Packages Installed / 📝 System Files Created / Modified / 1. Systemd Target — `/etc/systemd/system/remote-desktop.target` / 2. Drop-in for LightDM — `/etc/systemd/system/lightdm.service.d/remote.conf` / 3. Drop-in for WayVNC — `/etc/systemd/system/wayvnc.service.d/remote.conf` / 4. WayVNC Config — `/home/george/.config/wayvnc/config` / 5. Kernel HDMI Settings — `/boot/firmware/config.txt` / 🔑 Password Setup
