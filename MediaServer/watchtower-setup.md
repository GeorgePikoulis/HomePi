# Watchtower setup (Docker Compose)

This document explains how to add **Watchtower** to automatically update containers in a Docker Compose stack.

## 1) Add the service to `docker-compose.yml`

Append (or merge) this service under `services:`:

```yaml
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=Europe/Athens
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 03 * * *
    restart: unless-stopped
```

What it does:

- Watches containers and pulls newer images when available.
- Updates containers automatically on a schedule (**daily at 03:00**).
- `WATCHTOWER_CLEANUP=true` removes old images after successful updates.

**Security note:** Mounting `/var/run/docker.sock` gives Watchtower broad control over Docker. Only run it if you trust the image and your environment.

## 2) Start Watchtower

From the directory that contains your `docker-compose.yml`:

```bash
docker compose up -d watchtower
```

## 3) Verify it’s running

```bash
docker compose ps
docker compose logs -f watchtower
```

You should see Watchtower start up and (at 03:00) perform its update check.

## 4) Optional: Run a one-off update now

Trigger an immediate update run (without waiting for the schedule):

```bash
docker exec watchtower --run-once
```

## 5) Recommended safety approach (label-based opt-in)

If you later add databases or other stateful services, it can be safer to update only explicitly labeled containers.

### 5.1) Change Watchtower to label-only mode

Replace the environment section with:

```yaml
    environment:
      - TZ=Europe/Athens
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 03 * * *
      - WATCHTOWER_LABEL_ENABLE=true
```

### 5.2) Add this label to containers you want auto-updated

Example (add to any service you want Watchtower to manage):

```yaml
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
```

Now Watchtower updates **only** containers that have that label.

## 6) Manual update alternative (no automation)

If you prefer manual, predictable updates:

```bash
docker compose pull
docker compose up -d
```

## 7) Troubleshooting

- **No updates happen:** the image tag might be pinned (e.g. `:1.2.3`) or the image hasn’t published a new tag.
- **Unexpected restarts:** that’s normal during updates; consider label-only mode to control what updates automatically.
