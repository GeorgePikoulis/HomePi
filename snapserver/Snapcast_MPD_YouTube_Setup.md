
# HomePi: Snapcast Music Sources (MPD + YouTube) — Setup & Home Assistant Control
_Last updated: 2025-10-08 17:58 UTC_

This document captures the working setup from our session for playing **internet radio (via MPD)** and **YouTube (videos / playlists / lives via yt-dlp + mpv)** into **Snapcast**, fully controllable from **Home Assistant (Core, Python venv)**.

Hostname: `rpi` (`rpi.local`) · Main user: `george` · Snapserver v0.26.0

---

## 1) Overview
**Goal**
- Play radio streams and YouTube (including **playlists** and **lives**) through Snapcast, controlled by Home Assistant.
- Use Snapserver streams:
  - `MPD` → radios and any URL MPD can play.
  - `YouTube` → audio from YouTube via FIFO pipeline.

**Architecture**
```
YouTube URL --(yt-dlp/mpv)--> /tmp/snapfifo_youtube --\
                                                         \ 
Radio/MPD  --(MPD FIFO)----> /tmp/snapfifo ---------------> Snapserver ---> Snapclients
```

---

## 2) Snapserver streams (FIFO)
**Config file:** `/etc/snapserver.conf`

```ini
[stream]
# MPD source (existing)
source = pipe:///tmp/snapfifo?name=MPD&codec=flac&sampleformat=44100:16:2

# YouTube source
source = pipe:///tmp/snapfifo_youtube?name=YouTube&codec=flac&sampleformat=44100:16:2

[snapserver]
bind_to_address = 0.0.0.0
http_enabled = true
http_port = 1780
tcp_enabled = true
tcp_port = 1704
```

**Create FIFOs & perms**
```bash
sudo rm -f /tmp/snapfifo /tmp/snapfifo_youtube
sudo mkfifo /tmp/snapfifo /tmp/snapfifo_youtube
sudo chmod 666 /tmp/snapfifo /tmp/snapfifo_youtube
sudo systemctl restart snapserver
```

**Verify**
```bash
ss -lntup | grep -E '1704|1705|1780'
sudo journalctl -u snapserver -n 50 --no-pager
```

---

## 3) MPD → FIFO (radios)
**Install & enable**
```bash
sudo apt update
sudo apt install -y mpd mpc
sudo systemctl enable --now mpd
```

**`/etc/mpd.conf` essentials**
```conf
bind_to_address         "10.0.69.1"   # or "127.0.0.1" if HA runs on same host only
port                    "6600"

music_directory         "/var/lib/mpd/music"
playlist_directory      "/var/lib/mpd/playlists"
db_file                 "/var/lib/mpd/tag_cache"
state_file              "/var/lib/mpd/state"
sticker_file            "/var/lib/mpd/sticker.sql"

audio_output {
    type    "fifo"
    name    "snapfifo"
    path    "/tmp/snapfifo"
    format  "44100:16:2"
}
```

**Dirs & ownership**
```bash
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists
sudo chown -R mpd:mpd /var/lib/mpd
sudo systemctl restart mpd
```

**Quick test**
```bash
mpc -h 10.0.69.1 clear
mpc -h 10.0.69.1 add https://ice4.somafm.com/groovesalad-128-mp3
mpc -h 10.0.69.1 play
```

---

## 4) YouTube pipeline (yt-dlp + mpv) → FIFO
We use a small service and helpers to stream any YouTube link to `/tmp/snapfifo_youtube` using **mpv**. Playlists and lives are supported.

### 4.1 Files & service
**Environment file** `/etc/yt2snap/env`:
```bash
sudo tee /etc/yt2snap/env >/dev/null <<'EOF'
YT_URL=""
YT_LOOP=0            # 0=one-shot, 1=loop (service restarts between items when used with wrapper)
YT_PLAYLIST=full     # full | single | auto
EOF
```

**Runner** `/usr/local/bin/yt2snap` (always uses mpv; playlists via an expanded list file):
```bash
sudo tee /usr/local/bin/yt2snap >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

FIFO="/tmp/snapfifo_youtube"
URL="${1:-}"

source /etc/yt2snap/env 2>/dev/null || true
PLAYLIST="${YT_PLAYLIST:-full}"

if [[ -z "${URL}" ]]; then
  echo "Usage: yt2snap <youtube_url|playlist|mix|live>" >&2
  exit 2
fi

# Ensure FIFO exists
if [[ ! -p "$FIFO" ]]; then
  rm -f "$FIFO"
  mkfifo "$FIFO"
  chmod 666 "$FIFO"
fi

is_playlist_url() { [[ "$URL" =~ ([?&]list=|/playlist) ]]; }

mpv_single() {
  exec mpv "$URL" --no-video --keep-open=no --idle=no       --ytdl=yes --ytdl-format=bestaudio/best       --ytdl-raw-options=no-playlist=       --cache=no       --audio-samplerate=44100 --audio-format=s16 --audio-channels=stereo       --ao=pcm --ao-pcm-file="$FIFO" --ao-pcm-waveheader=no
}

mpv_playlist_file() {
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  yt-dlp -i --yes-playlist --flat-playlist          -O "https://www.youtube.com/watch?v=%(id)s" "$URL" > "$tmp" || true

  if [ "$(wc -l < "$tmp")" -lt 2 ]; then
    yt-dlp -i --yes-playlist --flat-playlist            --extractor-args "youtube:player_client=android"            -O "https://www.youtube.com/watch?v=%(id)s" "$URL" > "$tmp" || true
  fi

  if [ "$(wc -l < "$tmp")" -lt 2 ]; then
    rm -f "$tmp"; mpv_single; return
  fi

  mpv --no-video --keep-open=no --idle=no       --ytdl=yes --ytdl-format=bestaudio/best       --cache=no       --audio-samplerate=44100 --audio-format=s16 --audio-channels=stereo       --ao=pcm --ao-pcm-file="$FIFO" --ao-pcm-waveheader=no       --playlist="$tmp"
}

case "${PLAYLIST,,}" in
  single|no|0|one) mpv_single ;;
  auto|"") if is_playlist_url; then mpv_playlist_file; else mpv_single; fi ;;
  full|yes|1|all|*) if is_playlist_url; then mpv_playlist_file; else mpv_single; fi ;;
esac
EOF
sudo chmod +x /usr/local/bin/yt2snap
```

**Wrapper** `/usr/local/bin/yt2snap_run`:
```bash
sudo tee /usr/local/bin/yt2snap_run >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/yt2snap/env 2>/dev/null || true
URL="${YT_URL:-}"
LOOP="${YT_LOOP:-0}"

if [[ -z "$URL" ]]; then
  echo "yt2snap_run: YT_URL empty; nothing to play."
  exit 0
fi

run_once() { /usr/local/bin/yt2snap "$URL"; }

if [[ "$LOOP" = "1" ]]; then
  while true; do run_once || true; sleep 1; done
else
  run_once
fi
EOF
sudo chmod +x /usr/local/bin/yt2snap_run
```

**Service** `/etc/systemd/system/yt2snap.service`:
```ini
[Unit]
Description=Pipe YouTube audio to Snapserver FIFO
Wants=snapserver.service
After=network-online.target snapserver.service

[Service]
Type=simple
EnvironmentFile=-/etc/yt2snap/env
ExecStart=/usr/local/bin/yt2snap_run
Restart=on-failure
RestartSec=3
Nice=5
User=_snapserver
Group=_snapserver

[Install]
WantedBy=multi-user.target
```

Enable & test:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now yt2snap.service
sudo systemctl status --no-pager yt2snap
```

**Helper** `/usr/local/bin/yt2snapctl` (safe setter):
```bash
sudo tee /usr/local/bin/yt2snapctl >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
URL="${1:-}"
if [[ -z "${URL}" ]]; then
  echo "Usage: yt2snapctl <youtube_url>" >&2
  exit 2
fi

ENV="/etc/yt2snap/env"; TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
URL="$(printf "%s" "$URL" | tr -d '\r\n\t')"

if [[ ! -f "$ENV" ]]; then
  printf 'YT_URL=""\nYT_LOOP=0\nYT_PLAYLIST=full\n' | sudo tee "$ENV" >/dev/null
fi

awk -v new="YT_URL=\"${URL}\"" '
BEGIN{set=0}
$0 ~ /^YT_URL=/ {print new; set=1; next}
{print}
END{if(!set) print new}
' "$ENV" > "$TMP"

sudo install -m 0644 "$TMP" "$ENV"
sudo systemctl daemon-reload
sudo systemctl restart yt2snap.service
EOF
sudo chmod +x /usr/local/bin/yt2snapctl
```

**Optional sudoers**:
```bash
echo 'george ALL=(ALL) NOPASSWD: /usr/local/bin/yt2snapctl, /bin/systemctl restart yt2snap.service, /bin/systemctl stop yt2snap.service' | sudo tee /etc/sudoers.d/yt2snap-ha >/dev/null
```

---

## 5) Home Assistant (Core, venv) integration

### 5.1 `configuration.yaml`
```yaml
media_player:
  - platform: mpd
    host: 10.0.69.1
    port: 6600

# YouTube controls
input_text:
  youtube_url:
    name: YouTube URL
    min: 0
    max: 500

shell_command:
  yt2snap_set: 'sudo /usr/local/bin/yt2snapctl "{{ url }}"'
  yt2snap_stop: 'sudo systemctl stop yt2snap.service'
  yt2snap_restart: 'sudo systemctl restart yt2snap.service'
  yt2snap_loop_on: 'sudo sed -i "s/^YT_LOOP=.*/YT_LOOP=1/" /etc/yt2snap/env && sudo systemctl restart yt2snap.service'
  yt2snap_loop_off: 'sudo sed -i "s/^YT_LOOP=.*/YT_LOOP=0/" /etc/yt2snap/env && sudo systemctl restart yt2snap.service'
```

### 5.2 `scripts.yaml`
```yaml
play_youtube_on_snapcast:
  alias: Play YouTube on Snapcast
  mode: restart
  sequence:
    - variables:
        url: "{{ states('input_text.youtube_url') }}"
    - condition: template
      value_template: "{{ url | length > 0 }}"
    - service: shell_command.yt2snap_set
      data:
        url: "{{ url }}"
    - delay: "00:00:01"
    - service: media_player.select_source
      target:
        entity_id: media_player.rpi_snapcast_group
      data:
        source: "YouTube"

switch_snapcast_to_mpd:
  alias: Switch Snapcast to MPD
  sequence:
    - service: media_player.select_source
      target:
        entity_id: media_player.rpi_snapcast_group
      data:
        source: "MPD"

stop_youtube_stream:
  alias: Stop YouTube (pipeline)
  sequence:
    - service: shell_command.yt2snap_stop

pause_soft_snapcast:
  alias: "Pause (soft): mute group"
  sequence:
    - service: media_player.volume_mute
      target:
        entity_id: media_player.rpi_snapcast_group
      data:
        is_muted: true

resume_soft_snapcast:
  alias: "Resume (soft): unmute group"
  sequence:
    - service: media_player.volume_mute
      target:
        entity_id: media_player.rpi_snapcast_group
      data:
        is_muted: false

pause_hard_youtube:
  alias: "Pause (hard): stop YouTube pipeline"
  sequence:
    - service: shell_command.yt2snap_stop

resume_hard_youtube:
  alias: "Resume (hard): restart YouTube pipeline"
  sequence:
    - service: shell_command.yt2snap_restart

repeat_on_youtube:
  alias: "Repeat: ON"
  sequence:
    - service: shell_command.yt2snap_loop_on

repeat_off_youtube:
  alias: "Repeat: OFF"
  sequence:
    - service: shell_command.yt2snap_loop_off
```

### 5.3 Lovelace card
```yaml
type: vertical-stack
cards:
  - type: entities
    title: Snapcast · YouTube Control
    entities:
      - entity: input_text.youtube_url
        name: "YouTube URL (video/playlist/live)"

  - type: horizontal-stack
    cards:
      - type: button
        name: "▶ Play on YouTube Stream"
        icon: mdi:play-circle
        tap_action:
          action: call-service
          service: script.play_youtube_on_snapcast
      - type: button
        name: "■ Stop YouTube"
        icon: mdi:stop-circle
        tap_action:
          action: call-service
          service: script.stop_youtube_stream

  - type: horizontal-stack
    cards:
      - type: button
        name: "Source · MPD"
        icon: mdi:music
        tap_action:
          action: call-service
          service: media_player.select_source
          data:
            source: MPD
          target:
            entity_id: media_player.rpi_snapcast_group
      - type: button
        name: "Source · YouTube"
        icon: mdi:youtube
        tap_action:
          action: call-service
          service: media_player.select_source
          data:
            source: YouTube
          target:
            entity_id: media_player.rpi_snapcast_group

  - type: horizontal-stack
    cards:
      - type: button
        name: "Pause (soft)"
        icon: mdi:volume-mute
        tap_action:
          action: call-service
          service: script.pause_soft_snapcast
      - type: button
        name: "Resume (soft)"
        icon: mdi:volume-high
        tap_action:
          action: call-service
          service: script.resume_soft_snapcast
      - type: button
        name: "Pause (hard)"
        icon: mdi:stop
        tap_action:
          action: call-service
          service: script.pause_hard_youtube
      - type: button
        name: "Resume (hard)"
        icon: mdi:play
        tap_action:
          action: call-service
          service: script.resume_hard_youtube

  - type: horizontal-stack
    cards:
      - type: button
        name: "Repeat: ON"
        icon: mdi:repeat
        tap_action:
          action: call-service
          service: script.repeat_on_youtube
      - type: button
        name: "Repeat: OFF"
        icon: mdi:repeat-off
        tap_action:
          action: call-service
          service: script.repeat_off_youtube
```

---

## 6) Troubleshooting & notes
- Ensure group source in HA is **YouTube** for YT audio, **MPD** for radios.
- `yt-dlp` changes frequently; keep it updated:
  ```bash
  sudo pip3 install --break-system-packages -U yt-dlp
  ```
- For HLS radios that fail in MPD, use alternative MP3/FLAC endpoints.
- Sudoers for HA user (`george`) is required to run shell_command without password.

---

## 7) Quick commands
```bash
/usr/local/bin/yt2snapctl "https://www.youtube.com/watch?v=...&list=..."
sudo systemctl restart yt2snap.service
sudo journalctl -u yt2snap -n 80 --no-pager
sudo journalctl -u snapserver -n 80 --no-pager
```

