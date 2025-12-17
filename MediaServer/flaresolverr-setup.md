# FlareSolverr setup (Docker Compose)

This document explains how to add and run **FlareSolverr** alongside a media stack (Prowlarr/Sonarr/Radarr/Lidarr, etc.) using **Docker Compose**.

## 1) Add the service to `docker-compose.yml`

Append (or merge) this service under `services:`:

```yaml
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=Europe/Athens
    ports:
      - "8191:8191"
    restart: unless-stopped
```

Notes:

- Port **8191** is FlareSolverr’s default HTTP API port.
- `TZ=Europe/Athens` is optional but keeps logs/time consistent.

## 2) Start FlareSolverr

From the directory that contains your `docker-compose.yml`:

```bash
docker compose up -d flaresolverr
```

## 3) Verify it’s running

List containers:

```bash
docker compose ps
```

Follow logs:

```bash
docker compose logs -f flaresolverr
```

Quick HTTP check from the host (expects a JSON response):

```bash
curl -s http://localhost:8191/ | head
```

## 4) Use it from Prowlarr

This is configured in the **Prowlarr UI** (not in Compose).

Typical setup:

- In Prowlarr, add FlareSolverr (Settings → Indexers / General / or “FlareSolverr” depending on your UI version)
- URL should usually be:
  - **If Prowlarr is in the same compose network:** `http://flaresolverr:8191`
  - **From the host machine:** `http://localhost:8191`

## 5) Update FlareSolverr

Pull and recreate just this service:

```bash
docker compose pull flaresolverr
docker compose up -d flaresolverr
```

## 6) Troubleshooting

- **Port already in use:** change the left side of the port mapping (host port), e.g. `"8192:8191"`.
- **Prowlarr can’t reach FlareSolverr:** use the internal Docker DNS name `flaresolverr` and ensure both services are in the same compose project/network.
