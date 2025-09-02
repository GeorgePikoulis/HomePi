# Raspberry Pi 5 — DNS AdBlocking (dnsmasq) — Summary

**Host:** `rpi` (Raspberry Pi OS)  
**User:** `[REDACTED]`  
**Purpose:** DNS-level ad blocking for LAN/WLAN, with DNS enforcement via nftables

---

## Packages added
- `dnsmasq` — lightweight DNS/DHCP server
- `curl` — fetch blocklists
- `ca-certificates` — TLS trust for HTTPS list downloads
- `bind9-dnsutils` — tools like `dig` for testing

---

## Scripts written
- **/usr/local/bin/update-adblock.sh**  
  Merges reputable *hosts*-format lists into a single block file and reloads dnsmasq.
  - Sources used: StevenBlack hosts, OISD basic hosts
  - Extracts domains, normalizes & dedupes
  - Applies **whitelist** (`/etc/dnsmasq.d/adblock/whitelist.txt`)
  - Emits both IPv4 and IPv6 blocking lines into: **`/etc/dnsmasq.d/adblock/hosts.block`**
  - Reloads dnsmasq to apply the update

---

## System file changes

### dnsmasq configuration & data
- **Directory:** `/etc/dnsmasq.d/adblock/`
  - **`hosts.block`** — *generated* blocklist (from the updater script)
  - **`whitelist.txt`** — domains to exempt from the generated lists (one per line)
  - **`custom.hosts`** — manual block entries in hosts format (A + AAAA)
- **`/etc/dnsmasq.d/10-adblock.conf`**
  ```ini
  # Use generated blocklist
  addn-hosts=/etc/dnsmasq.d/adblock/hosts.block
  # Manual entries
  addn-hosts=/etc/dnsmasq.d/adblock/custom.hosts

  # QoL
  cache-size=10000
  min-cache-ttl=300
  clear-on-reload
  ```
- **`/etc/dnsmasq.d/11-adblock-local.conf`** — local **wildcard** blocks
  ```ini
  # Example wildcard (blocks domain + all subdomains, both A and AAAA)
  address=/example.com/0.0.0.0
  address=/example.com/::
  ```

### systemd (automatic updates)
- **`/etc/systemd/system/adblock-update.service`**
  - Runs `/usr/local/bin/update-adblock.sh` (oneshot)
- **`/etc/systemd/system/adblock-update.timer`**
  - `OnCalendar=03:30`
  - `RandomizedDelaySec=30m`
  - `Persistent=true`
  - **Enabled** and started to refresh lists daily

### nftables (DNS enforcement)
- **`/etc/nftables.conf`** — additions:
  - In `table ip nat` (new **prerouting** chain):
    ```nft
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname { "eth1", "wlan0", "wlan1" } udp dport 53 counter redirect to :53
        iifname { "eth1", "wlan0", "wlan1" } tcp dport 53 counter redirect to :53
    }
    ```
  - In `table inet filter` → `chain forward` (**IPv6 DNS hardening**; placed near the top before accepts):
    ```nft
    # DNS hardening: block IPv6 DNS from LAN/WLAN (prevents bypass)
    meta nfproto ipv6 iifname { "eth1", "wlan0", "wlan1" } udp dport 53 counter drop
    meta nfproto ipv6 iifname { "eth1", "wlan0", "wlan1" } tcp dport 53 counter drop
    ```

---

## Notes
- dnsmasq on this host listens on the LAN IP (e.g., `10.0.69.1`). DHCP should hand out the Pi as DNS for clients.
- **Reload vs Restart:**
  - `hosts.block` updates → `systemctl reload dnsmasq` is sufficient (and `clear-on-reload` flushes cache).
  - Adding/removing `address=/.../` wildcard entries → **`systemctl restart dnsmasq`** to pick up new files.
- **Whitelist scope:** affects only the *generated* list (`hosts.block`); it does **not** override local wildcard rules in `11-adblock-local.conf`.
