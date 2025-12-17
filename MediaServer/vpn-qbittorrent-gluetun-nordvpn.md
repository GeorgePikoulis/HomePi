# VPN + qBittorrent (NordVPN via Gluetun) — Rebuild Notes

This document recreates the **VPN-bound qBittorrent** setup (only torrents go through NordVPN; everything else stays normal).

## Goals

- qBittorrent traffic exits via **NordVPN**
- If VPN drops, qBittorrent has **no internet** (kill-switch)
- Keep configuration and downloads in stable host folders under `~/media-stack/`

## Prerequisites

- Raspberry Pi has Docker + Docker Compose installed:
  ```bash
  docker --version
  docker compose version
  ```
- NordVPN **Service credentials** (for manual OpenVPN). Do **not** use your normal Nord login email/password.
- `/dev/net/tun` exists on the host (normally true on Debian/Raspberry Pi OS).

## Folder layout (host)

```bash
mkdir -p ~/media-stack/{vpn,downloads/{incomplete,complete},config}
```

We will use:

- `~/media-stack/vpn/` → compose + `.env`
- `~/media-stack/config/qbittorrent/` → qBittorrent config
- `~/media-stack/downloads/` → torrent data

## Compose files

### 1) Create `.env` with NordVPN service credentials

```bash
cd ~/media-stack/vpn
nano .env
```

Example:

```bash
NORDVPN_USER=your_service_username
NORDVPN_PASS=your_service_password
```

> If your password contains `#`, some parsers treat it as a comment in `.env`. If anything looks odd, change the password or escape `#` as `\#`.

### 2) Create `docker-compose.yml`

```bash
cd ~/media-stack/vpn
nano docker-compose.yml
```

Paste:

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - VPN_SERVICE_PROVIDER=nordvpn
      - VPN_TYPE=openvpn
      - OPENVPN_USER=${NORDVPN_USER}
      - OPENVPN_PASSWORD=${NORDVPN_PASS}

      # Pick ONE country (or remove to let it auto-pick)
      - SERVER_COUNTRIES=Netherlands
      # - SERVER_COUNTRIES=Sweden
      # - SERVER_COUNTRIES=Switzerland

      # Allow inbound access to qBittorrent Web UI + torrent port
      - FIREWALL_VPN_INPUT_PORTS=8080,6881
    ports:
      - "8080:8080"     # qBittorrent Web UI
      - "6881:6881/tcp" # incoming torrents TCP
      - "6881:6881/udp" # incoming torrents UDP
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"   # IMPORTANT: qBittorrent uses gluetun’s network stack
    depends_on:
      - gluetun
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Athens
      - WEBUI_PORT=8080
    volumes:
      - ../config/qbittorrent:/config
      - ../downloads:/downloads
    restart: unless-stopped
```

## Start / stop

```bash
cd ~/media-stack/vpn
docker compose up -d --quiet-pull
docker compose ps
```

Expected: `gluetun` becomes **healthy** after a short time.

To stop:

```bash
docker compose down
```

## Verify VPN egress IP

Run a curl container *inside* the gluetun network namespace:

```bash
docker run --rm --network container:gluetun curlimages/curl:latest -s https://ifconfig.me ; echo
```

It should print a **VPN IP**, not your ISP IP.

## Kill-switch / leak test (recommended once)

```bash
# Should succeed while VPN is up
docker exec qbittorrent sh -lc "wget -qO- https://ifconfig.me && echo"

# Stop VPN container
docker stop gluetun

# Should fail (blocked) while VPN is down
docker exec qbittorrent sh -lc "timeout 5 wget -qO- https://ifconfig.me && echo || echo 'BLOCKED (good)'"

# Start VPN again
docker start gluetun
```

## qBittorrent initial configuration (Web UI)

Open from your LAN:

- `http://<PI_LAN_IP>:8080`
- login as `admin`
- first run prints a temporary password in logs:
  ```bash
  docker logs qbittorrent | grep -i "temporary password" | tail -n 1
  ```

Recommended settings:

### Downloads paths

**Tools → Options → Downloads**
- Default Save Path: `/downloads/complete`
- Keep incomplete torrents in: ✅ `/downloads/incomplete`
- (Optional) Append “.!qB” to incomplete files: ✅

### Categories for *arr

Left sidebar → **Categories** → Add:

- `tv` → `/downloads/complete/tv`
- `movies` → `/downloads/complete/movies`
- `music` → `/downloads/complete/music`

### BitTorrent toggles (typical)

**Tools → Options → BitTorrent**
- Enable DHT: ✅
- Enable PeX: ✅
- Enable Local Peer Discovery: ✅

## Troubleshooting

### Gluetun shows `AUTH_FAILED` / unhealthy
- You are likely using the wrong Nord credentials.
- Use Nord’s **Service credentials** for manual/OpenVPN.

### “docker compose up -d” sometimes doesn’t return control
The containers can still be up. Check in another terminal:

```bash
cd ~/media-stack/vpn
docker compose ps
pgrep -a -f "docker compose" || echo "no docker compose process running"
```

If no compose process is running and containers are up, it’s safe to close the stuck terminal.

### Validate mounts
```bash
docker inspect qbittorrent --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```
