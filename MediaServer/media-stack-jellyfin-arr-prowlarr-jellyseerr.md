# Media Stack (Jellyfin + *arr + Prowlarr + Jellyseerr) — Rebuild Notes

This document recreates the **non-VPN** media stack. Jellyfin and the *arr apps run normally on LAN, while **qBittorrent remains VPN-bound** via the separate `~/media-stack/vpn` stack.

## Goals

- Jellyfin + Sonarr/Radarr/Lidarr/Prowlarr/Jellyseerr run on normal LAN IPs/ports
- Sonarr/Radarr/Lidarr send downloads to **qBittorrent behind NordVPN**
- Jellyseerr provides phone-friendly search/request UI linked to Jellyfin + Sonarr/Radarr

## Folder layout (host)

```bash
cd ~
mkdir -p ~/media-stack/media/{tv,movies,music}
mkdir -p ~/media-stack/config/{jellyfin,prowlarr,sonarr,radarr,lidarr,jellyseerr}
# downloads + vpn folders expected from VPN doc
```

## Compose file: `~/media-stack/docker-compose.yml`

```bash
cd ~/media-stack
nano docker-compose.yml
```

Paste:

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    user: "1000:1000"
    environment:
      - TZ=Europe/Athens
    volumes:
      - ./config/jellyfin:/config
      - ./media:/media:ro
    ports:
      - "8096:8096"
    restart: unless-stopped

  jellyseerr:
    image: ghcr.io/fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    environment:
      - TZ=Europe/Athens
    volumes:
      - ./config/jellyseerr:/app/config
    ports:
      - "5055:5055"
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Athens
    volumes:
      - ./config/prowlarr:/config
    ports:
      - "9696:9696"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Athens
    volumes:
      - ./config/sonarr:/config
      - ./media:/media
      - ./downloads:/downloads
    ports:
      - "8989:8989"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Athens
    volumes:
      - ./config/radarr:/config
      - ./media:/media
      - ./downloads:/downloads
    ports:
      - "7878:7878"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: lidarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Athens
    volumes:
      - ./config/lidarr:/config
      - ./media:/media
      - ./downloads:/downloads
    ports:
      - "8686:8686"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
```

## Start the stack

```bash
cd ~/media-stack
docker compose up -d --quiet-pull
docker compose ps
```

Ports (LAN):
- Jellyfin: `8096`
- Jellyseerr: `5055`
- Sonarr: `8989`
- Radarr: `7878`
- Lidarr: `8686`
- Prowlarr: `9696`

## Configure *arr → qBittorrent (VPN-bound)

In each app (**Settings → Download Clients → + → qBittorrent**):

- **Host:** `host.docker.internal`
- **Port:** `8080`
- **Username/Password:** qBittorrent admin
- **Category:**
  - Sonarr: `tv`
  - Radarr: `movies`
  - Lidarr: `music`

Test → Save.

> Using `host.docker.internal` works because we added `extra_hosts: host-gateway` in compose.

## Configure Prowlarr → Sonarr/Radarr/Lidarr

In Prowlarr (**Settings → Apps**) add:

- Sonarr: `http://sonarr:8989` + Sonarr API key
- Radarr: `http://radarr:7878` + Radarr API key
- Lidarr: `http://lidarr:8686` + Lidarr API key

(Grab API keys from each app: **Settings → General**.)

Run sync:
- Prowlarr → **System → Tasks → Application Indexer Sync**

## Root folders in *arr

- Sonarr: **Settings → Media Management → Root Folders** → add `/media/tv`
- Radarr: **Settings → Media Management → Root Folders** → add `/media/movies`
- Lidarr: **Settings → Media Management → Root Folders** → add `/media/music` (optional, when using it)

## Jellyseerr setup (phone-friendly requests)

Open: `http://rpi-media-server:5055` (or `http://<PI_LAN_IP>:5055`)

Typical flow:
1) Sign in via Jellyfin (Jellyseerr will link to your Jellyfin user)
2) Add Jellyfin server: `http://rpi-media-server:8096`
   - URL Base: leave blank (unless you use a reverse-proxy sub-path like `/jellyfin`)
3) Add services:
   - Sonarr: `http://sonarr:8989` + API key
   - Radarr: `http://radarr:7878` + API key
   - Select the root folders (`/media/tv`, `/media/movies`)

From Android: open the URL in the browser and optionally **Add to Home screen** for an “app-like” icon.

## Jellyfin library setup

In Jellyfin Web UI (Dashboard → Libraries):
- Movies library folder: `/media/movies`
- TV library folder: `/media/tv`
- Music library folder: `/media/music`

Notes:
- Sometimes new files don’t show immediately. Using **Scan All Libraries** fixes it.
- Enable “real-time monitoring” on the library if you want faster updates.
- Scheduled scans can be configured under **Dashboard → Scheduled Tasks**.

## End-to-end test

1) Request a movie/show in Jellyseerr
2) Verify it appears in Radarr/Sonarr
3) Verify qBittorrent receives it (category `movies` or `tv`)
4) Verify Radarr/Sonarr imports it into `/media/...`
5) In Jellyfin, if it doesn’t appear right away:
   - Dashboard → Libraries → **Scan All Libraries**

## Troubleshooting

### Jellyfin sees files in the container but doesn’t show them
- Confirm the library folder path is correct (`/media/movies`, not a host path)
- Run **Scan All Libraries**
- Check logs:
  ```bash
  docker exec jellyfin sh -lc 'tail -n 200 /config/log/jellyfin*.log | tail -n 50'
  ```

### Verify Jellyfin can read media as its configured UID
```bash
docker exec -u 1000:1000 jellyfin sh -lc 'ls -la /media/movies | head'
```

### Compose “hangs” but containers are running
In another terminal:
```bash
cd ~/media-stack
docker compose ps
pgrep -a -f "docker compose" || echo "no docker compose process running"
```
