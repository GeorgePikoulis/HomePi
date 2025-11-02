# Home Assistant ⇄ YouTube ▶ Snapcast (Dockerized HA, base64‑safe)

This document describes the **final, working integration** from **Home Assistant (running in Docker)** to the Raspberry Pi host’s Snapcast input, driving YouTube video/playlist audio via `mpv`/`yt-dlp`. It fixes the classic “plays only the first track” issue by ensuring URLs are delivered **base64‑encoded** (no `&` escaping) and by hardening the host controller (`yt2snapctl`).

> Host: `rpi` (`rpi.local`) • User: `george` • Snap FIFO: `/tmp/snapfifo_youtube`  
> HA runs in **Docker** (container commonly named `homeassistant`).

---

## 0) High‑level architecture

```
[Phone/HA Dashboard] -> Home Assistant (Docker)
   |  shell_command.yt2snap_set_* (base64_encode URL)
   v
SSH (key: /config/keys/ha_ed25519) to host 127.0.0.1 as george
   v
/usr/local/bin/yt2snapctl set-b64 -   (sanitizes URL, writes /etc/yt2snap/env)
   v
systemd: yt2snap.service   ->  mpv + yt-dlp  ->  /tmp/snapfifo_youtube  ->  Snapserver
```

**Why base64?** It preserves `&list=` in playlist URLs end‑to‑end, eliminating HA/Jinja/JSON escaping like `\u0026` that break playlist advancement.

---

## 1) Docker specifics (HA)

- Container name assumed: `homeassistant`. Adjust if different.
- HA config is mounted as `/config` inside the container and points at the host path:
  - Host: `/home/george/.homeassistant`
  - Container: `/config`
- The SSH private key used by shell_commands resides **inside the container** as `/config/keys/ha_ed25519` and authenticates to `george@127.0.0.1` (the **host**).

**Useful checks**
```bash
# On the host:
docker ps --format 'table {{.Names}}	{{.Image}}	{{.Status}}'
docker inspect homeassistant | jq -r '.[0].Mounts[] | select(.Destination=="/config") | .Source'

# Shell into the container (if needed):
docker exec -it homeassistant bash
ls -l /config/keys/ha_ed25519
```

---

## 2) Ensure top‑level include for shell commands

In **`/home/george/.homeassistant/configuration.yaml`** make sure this **top‑level** include exists (aligned with `automation/script/scene` — not indented under other keys):

```yaml
# configuration.yaml
default_config:

frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

# shell_command moved to external file (top-level)
shell_command: !include shell_command.yaml

# --- YouTube → Snapcast controls ---
input_text:
  youtube_url:
    name: YouTube URL
    min: 0
    max: 255
```

> Common pitfall: placing `shell_command: !include shell_command.yaml` **inside** `input_text:` breaks parsing.

---

## 3) `shell_command.yaml` (base64‑safe + SSH to host)

**`/home/george/.homeassistant/shell_command.yaml`**

We use Jinja’s **`base64_encode`** (not `tojson`). This avoids `\u0026`/`/u0026` artifacts entirely.

```yaml
# A) Pass a URL directly via service data: {url: "https://...&list=..."}
yt2snap_set_from_url: >-
  bash -lc 'echo -n {{ url | default("", true) | string | base64_encode }} |
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl set-b64 -'

# B) Or read the URL from the helper input_text.youtube_url
yt2snap_set_from_helper: >-
  bash -lc 'echo -n {{ states("input_text.youtube_url") | string | base64_encode }} |
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl set-b64 -'

# Playlist / loop toggles (host-side control via SSH)
yt2snap_playlist_full: >-
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl playlist full

yt2snap_playlist_shuffle: >-
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl playlist shuffle

yt2snap_loop_on: >-
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl loop on

yt2snap_loop_off: >-
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl loop off

# Optional controls
yt2snap_stop: >-
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl stop

yt2snap_restart: >-
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl restart
```

**Legacy compatibility (optional):**
```yaml
yt2snap_set_env_and_restart: >-
  bash -lc 'echo -n {{ url | default("", true) | string | base64_encode }} |
  ssh -i /config/keys/ha_ed25519 -o StrictHostKeyChecking=no george@127.0.0.1
  sudo /usr/local/bin/yt2snapctl set-b64 -'
```

---

## 4) Example HA script / automation snippets

**Script using the helper**
```yaml
# scripts.yaml
play_youtube_on_snapcast:
  alias: Play YouTube on Snapcast
  sequence:
    - service: shell_command.yt2snap_set_from_helper
    - service: shell_command.yt2snap_playlist_full
    - service: shell_command.yt2snap_loop_on
```

**Automation (button press)**
```yaml
# automations.yaml
- alias: Set YT URL from dashboard input and play
  trigger:
    - platform: state
      entity_id: input_text.youtube_url
  action:
    - service: shell_command.yt2snap_set_from_helper
    - service: shell_command.yt2snap_playlist_full
```

---

## 5) Verification & Troubleshooting

**Verify env:**
```bash
sudo sed -n '1,3p' /etc/yt2snap/env
# Expect: YT_URL="https://www.youtube.com/watch?v=...&list=..."
```

**Check playlist is detected:**
```bash
URL=$(grep -E '^YT_URL=' /etc/yt2snap/env | cut -d'"' -f2)
yt-dlp --flat-playlist -J "$URL" | jq '.title, .id, (.entries|length)'
# entries > 1 for playlists
```

**Common pitfalls fixed here:**
- `LoggingUndefined is not JSON serializable`: direct URL service called without `url:` → either use the helper service or pass `data: { url: "..." }`.
- `\u0026` / `/u0026` in env: remove `tojson`, use `base64_encode`; host `yt2snapctl` now sanitizes anyway (see Snapcast doc).
- YAML include under wrong block: ensure `shell_command: !include shell_command.yaml` is **top‑level**.

---

## 6) Operational notes

- **Docker restarts:** shell_commands work after HA container restarts; SSH key must be readable inside container (`/config/keys/ha_ed25519`).
- **Security:** the SSH key should be locked to user `george` on localhost, and sudoers rules on the host should allow `/usr/local/bin/yt2snapctl *` for that user without TTY prompt (if you choose to configure NOPASSWD).
- **Version pinning:** consider pinning `yt-dlp` in a venv to avoid surprise format regressions.
