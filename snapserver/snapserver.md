# Snapserver on HomePi — Radio via MPD + Home Assistant Control
**Updated:** 2025-10-08  
**Host:** `rpi` (`rpi.local`) • **User:** `george` • **Snapserver:** `0.26.0` • **Home Assistant:** Core (in `~/.homeassistant`)

This document replaces the previous `snapserver.md`. It captures the working setup we implemented during the session, so it can be reproduced or restored quickly.

---

## Overview

```
Home Assistant (Radio Browser, UI, Automations)
        │
        │ media_player.play_media  (target = MPD)
        ▼
MPD (player)  ── PCM 44.1k/16/2 ──>  /tmp/snapfifo  ──>  Snapserver (FLAC)  ──>  Snapclients
                                                   ▲
                      Master + per-client volume via HA Snapcast integration
```

**Why this design?**  
- Radio discovery and selection is done in **Home Assistant** with the **Radio Browser** integration.  
- **MPD** performs the actual playback and writes raw PCM audio into a **FIFO** that **Snapserver** reads and distributes to all **Snapclients** synchronously.  
- Volume is handled by **Snapcast** inside Home Assistant: one **group (master)** slider + **per‑client** sliders.

---

## 1) Snapserver: create the FIFO stream

### 1.1 Create the FIFO
```bash
sudo rm -f /tmp/snapfifo
sudo mkfifo /tmp/snapfifo
sudo chmod 666 /tmp/snapfifo    # simple cross-user access; tighten later if desired
```

### 1.2 Configure Snapserver
`/etc/snapserver.conf`:
```ini
[stream]
# MPD will write raw PCM to this FIFO
source = pipe:///tmp/snapfifo?name=MPD&codec=flac&sampleformat=44100:16:2

[snapserver]
bind_to_address = 0.0.0.0
http_enabled = true
http_port = 1780
tcp_enabled = true
tcp_port = 1704
```

Restart & verify:
```bash
sudo systemctl restart snapserver
sudo systemctl status --no-pager snapserver
ss -lntup | grep -E '1704|1705|1780' || true
# Expect LISTEN on 1704/1705/1780. "end of file" is OK until a writer connects.
```

---

## 2) MPD: output to the FIFO

### 2.1 Install and start
```bash
sudo apt update
sudo apt install -y mpd mpc
sudo systemctl enable --now mpd
```

### 2.2 Configure `/etc/mpd.conf`
Key blocks (merge with existing):
```conf
# Network (HA will talk to MPD here)
bind_to_address                 "10.0.69.1"    # or your LAN IP for HA reachability
port                            "6600"

# Files & DB
music_directory                 "/var/lib/mpd/music"
playlist_directory              "/var/lib/mpd/playlists"
db_file                         "/var/lib/mpd/tag_cache"
state_file                      "/var/lib/mpd/state"
sticker_file                    "/var/lib/mpd/sticker.sql"

# Audio to Snapserver FIFO
audio_output {
        type            "fifo"
        name            "snapfifo"
        path            "/tmp/snapfifo"
        format          "44100:16:2"
}
```

Create directories and restart:
```bash
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists
sudo chown -R mpd:mpd /var/lib/mpd
sudo systemctl restart mpd
ss -lntp | grep 6600 || true
```

### 2.3 Quick playback test (known-good stations)
Some radio URLs trip MPD (e.g., HLS AAC). Use these to verify pipeline:
```bash
# SomaFM Groove Salad (MP3)
mpc -h 10.0.69.1 clear
mpc -h 10.0.69.1 add https://ice4.somafm.com/groovesalad-128-mp3
mpc -h 10.0.69.1 play
mpc -h 10.0.69.1 status

# (Optional) Radio Paradise FLAC
# mpc -h 10.0.69.1 clear
# mpc -h 10.0.69.1 add http://stream.radioparadise.com/flac
# mpc -h 10.0.69.1 play
```

Check Snapserver is ingesting (no more continuous “end of file” while playing):
```bash
sudo journalctl -u snapserver -n 50 --no-pager
```

---

## 3) Home Assistant: integrate Snapcast (volume) and MPD (source)

### 3.1 Snapcast integration (master & per‑client volume)
- In HA: **Settings → Devices & Services → Add Integration → “Snapcast”**  
- Host: `10.0.69.1`, Port: `1780`
- You’ll get:
  - **Group media_player** (master volume)
  - One **media_player per client** (per‑room volume)

### 3.2 MPD integration (playback target for Radio Browser)
Home Assistant Core (no add-ons), config at `~/.homeassistant`.

Edit `configuration.yaml`:
```yaml
media_player:
  - platform: mpd
    host: 10.0.69.1
    port: 6600
    # password: !secret mpd_password   # only if configured in mpd.conf
```

Restart HA Core. After restart you should see `media_player.mpd`.

### 3.3 Play from HA (manual test)
**Developer Tools → Services**:
```yaml
service: media_player.play_media
target:
  entity_id: media_player.mpd
data:
  media_content_id: "https://ice4.somafm.com/groovesalad-128-mp3"
  media_content_type: "music"
```

### 3.4 Use **Radio Browser** for station selection
- In HA **Media → Radio Browser**, pick a station and select **MPD** as the target (not “Web browser”).  
- MPD will switch streams; Snapserver distributes audio; Snapcast entities handle master/per-client volume.

---

## 4) Optional: Preset script + Lovelace “combo” card

### 4.1 Script
`~/.homeassistant/scripts.yaml` (include file in `configuration.yaml` with `script: !include scripts.yaml`):
```yaml
play_radio_on_mpd:
  alias: Play radio on MPD
  mode: restart
  fields:
    url:
      description: Stream URL
      example: https://ice4.somafm.com/groovesalad-128-mp3
  sequence:
    - service: media_player.play_media
      target:
        entity_id: media_player.mpd
      data:
        media_content_id: "{{ url }}"
        media_content_type: "music"
```

Reload scripts in HA (**Developer Tools → YAML → Reload Scripts**).

### 4.2 Lovelace card (MPD controls + quick buttons)
Add a **Manual** card with:
```yaml
type: vertical-stack
cards:
  - type: media-control
    entity: media_player.mpd   # adjust if your MPD entity id differs
  - type: grid
    columns: 2
    square: false
    cards:
      - type: button
        name: Groove Salad
        icon: mdi:radio
        tap_action:
          action: call-service
          service: media_player.play_media
          target:
            entity_id: media_player.mpd
          data:
            media_content_id: "https://ice4.somafm.com/groovesalad-128-mp3"
            media_content_type: "music"
      - type: button
        name: Radio Browser
        icon: mdi:playlist-music
        tap_action:
          action: navigate
          navigation_path: /media-browser
```

This gives you:
- **MPD transport controls** (play/stop/seek)  
- One‑tap **Groove Salad**  
- Quick jump to **Radio Browser** to pick any station and target MPD

---

## 5) Notes & Troubleshooting

- **“end of file” in Snapserver logs**: normal when FIFO has no writer; disappears when MPD plays.
- **“Connection refused” from `mpc`**: MPD not listening where you connect. Match the IP in `bind_to_address` and `mpc -h <IP>`.
- **BBC / HLS URLs failing**: Some HLS/AAC streams don’t work with distro MPD builds. Prefer MP3/FLAC URLs, or feed via `ffmpeg` into the FIFO as a process source (advanced).
- **HA doesn’t show MPD**: Ensure `media_player:` block is in `configuration.yaml`, HA restarted, and network/firewall allows HA → `10.0.69.1:6600`.
- **Volume model**: Keep Snapclients at 100% and use the **group** (master) slider in HA for overall volume; tweak **per‑client** sliders for room balance.

---

## 6) Future Enhancements (optional)

- **Announcements ducking**: Add a second process stream for TTS/alerts with higher priority via Snapserver’s `meta` stream.
- **Spotify**: Add `librespot` as another stream and switch sources from HA automations.
- **Server UI**: Serve a small web UI that talks to `/jsonrpc` for advanced controls; or rely entirely on HA (recommended).

---

## 7) Quick restore checklist

1. Create `/tmp/snapfifo`, set perms.  
2. Ensure `/etc/snapserver.conf` has the `pipe:///tmp/snapfifo?...name=MPD` stream.  
3. Install/configure MPD with `fifo` output → `/tmp/snapfifo`.  
4. Test with `mpc` (e.g., SomaFM).  
5. In HA: add **Snapcast** (1780) and **MPD** (6600).  
6. Use Radio Browser → target **MPD**.  
7. (Optional) Add script + Lovelace card.

---

**Maintainer notes:**  
- Hostname: `rpi` (`rpi.local`)  
- Main user: `george`  
- Snapserver JSON-RPC: `http://10.0.69.1:1780/jsonrpc`  
- FIFO path: `/tmp/snapfifo`  
- Stream name: `MPD`
