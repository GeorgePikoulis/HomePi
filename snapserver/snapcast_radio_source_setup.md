# Snapcast Radio Source (MPD → FIFO) Controlled by Home Assistant

**Host:** `rpi` (`rpi.local`)  
**Main user:** `george`  
**Goal:** Use Home Assistant to control a radio/music source that plays through Snapcast to all Snapclients.  
**Pipeline:** **MPD → /tmp/snapfifo → Snapserver** (clients subscribe to the Snapserver stream `MPD`).

---

## 1) Snapserver Overview & Ports

Snapserver is installed as a systemd service and listens on:

- **Control UI (HTTP):** `:1780` → Open in browser: `http://rpi.local:1780`
- **TCP control:** `:1704`
- **Streaming:** `:1705`

Verify (example output shown):
```bash
ss -lntup | grep -E '1704|1705|1780|1781' || true
# tcp LISTEN 0 4096 0.0.0.0:1780
# tcp LISTEN 0 4096 0.0.0.0:1705
# tcp LISTEN 0 4096 0.0.0.0:1704
```

Systemd unit:
```ini
# /lib/systemd/system/snapserver.service
[Service]
ExecStart=/usr/bin/snapserver --logging.sink=system --server.datadir="${HOME}" $SNAPSERVER_OPTS
User=_snapserver
Group=_snapserver
```

**Note:** Service runs as `_snapserver`, so our FIFO must be readable by that user.

---

## 2) Configure Snapserver to read a FIFO stream

### 2.1 Create the FIFO
```bash
sudo rm -f /tmp/snapfifo
sudo mkfifo /tmp/snapfifo
sudo chmod 666 /tmp/snapfifo   # easy cross-user access (tighten later if desired)
```

### 2.2 Configure the stream
`/etc/snapserver.conf`:
```ini
[stream]
# Optional example left commented:
#source = pipe:///tmp/snapfifo?name=HomePi&sampleformat=44100:16:2
source = pipe:///tmp/snapfifo?name=MPD&codec=flac&sampleformat=44100:16:2

[snapserver]
bind_to_address = 0.0.0.0
http_enabled = true
http_port = 1780
tcp_enabled = true
tcp_port = 1704
```

Restart & check logs:
```bash
sudo systemctl restart snapserver
sudo journalctl -u snapserver -n 50 --no-pager
```

**What you should see:**
```
Adding source: pipe:///tmp/snapfifo?name=MPD&codec=flac&sampleformat=44100:16:2
PcmStream: MPD, sampleFormat: 44100:16:2
PipeStream mode: create
Stream: {"path":"/tmp/snapfifo", ... "name":"MPD" ...}
Init - compression level: 2
Exception: end of file  # harmless until a writer connects
Service 'Snapcast' successfully established.
```

> **FYI**: Prior to adding a writer, Snapserver may spam **“Connect exception: Bad file descriptor”** or **“end of file”**. This stops once MPD starts writing PCM into the FIFO.

---

## 3) Install & Configure MPD to write into the FIFO

### 3.1 Install MPD + CLI
```bash
sudo apt update
sudo apt install -y mpd mpc
```

If you see errors like **“Failed to open '/var/lib/mpd/tag_cache'”**, just create the directories as below.

### 3.2 MPD configuration

Open:
```bash
sudo nano /etc/mpd.conf
```

Ensure these key settings (edit/add as needed):

```ini
# === Network (bind where Home Assistant can reach you) ===
# For local-only control from the same host, you could use 127.0.0.1.
# In this setup we bound to the Pi's LAN IP:
bind_to_address                 "10.0.69.1"
port                            "6600"

# === Files & DB ===
music_directory                 "/var/lib/mpd/music"
playlist_directory              "/var/lib/mpd/playlists"
db_file                         "/var/lib/mpd/tag_cache"
state_file                      "/var/lib/mpd/state"
sticker_file                    "/var/lib/mpd/sticker.sql"

# === HTTP/stream input support for radios ===
input {
    plugin "curl"
}

# === Audio to Snapserver FIFO ===
audio_output {
    type            "fifo"
    name            "snapfifo"
    path            "/tmp/snapfifo"
    format          "44100:16:2"
}

# Optional convenience (if present it's fine to keep):
# auto_enable_output "yes"

# Keep other example outputs commented out (ALSA/httpd/etc.)
```

Create paths & set ownership:
```bash
sudo mkdir -p /var/lib/mpd/music /var/lib/mpd/playlists
sudo chown -R mpd:mpd /var/lib/mpd
```

Restart & verify:
```bash
sudo systemctl restart mpd
sudo systemctl status --no-pager mpd
ss -lntp | grep 6600 || true   # should show LISTEN on 10.0.69.1:6600
```

### 3.3 Quick radio test

**Important:** Some HLS streams (e.g. BBC) may fail with `avformat_open_input()` on distro MPD builds. Test with known-good streams first.

```bash
# Talk to MPD on its bound IP:
mpc -h 10.0.69.1 clear

# Radio Paradise (FLAC)
mpc -h 10.0.69.1 add http://stream.radioparadise.com/flac
mpc -h 10.0.69.1 play
mpc -h 10.0.69.1 status

# Radio Paradise Mellow (FLAC)
mpc -h 10.0.69.1 clear
mpc -h 10.0.69.1 add http://stream.radioparadise.com/mellow-flac
mpc -h 10.0.69.1 play
mpc -h 10.0.69.1 status

# SomaFM Groove Salad (MP3)
mpc -h 10.0.69.1 clear
mpc -h 10.0.69.1 add https://ice4.somafm.com/groovesalad-128-mp3
mpc -h 10.0.69.1 play
mpc -h 10.0.69.1 status
```

While playing, Snapserver logs should no longer print “end of file”, and all Snapclients should output audio from the `MPD` stream.

---

## 4) Home Assistant Integration (control MPD and Snapcast)

### 4.1 Add MPD integration to Home Assistant

If you prefer YAML:
```yaml
# configuration.yaml
media_player:
  - platform: mpd
    host: 10.0.69.1
    port: 6600
    name: MPD
```

Or use the **UI → Settings → Devices & Services → “+ Add Integration” → MPD** and set `host=10.0.69.1`, `port=6600`.

You’ll get an entity like `media_player.mpd`.

### 4.2 Play a radio from Home Assistant

**Correct service:** `media_player.play_media` (not `media_player.media_play`)

Example **Developer Tools → Services**:
```yaml
service: media_player.play_media
target:
  entity_id: media_player.mpd
data:
  media_content_id: https://ice4.somafm.com/groovesalad-128-mp3
  media_content_type: music
```

**Common error fixed:**  
```
Failed to call service media_player.media_play.
extra keys not allowed @ data['media_content_id']
```
Use `media_player.play_media` instead, as shown above.

### 4.3 Quick scripts for favorite stations

```yaml
script:
  play_groove_salad:
    alias: Play Groove Salad
    sequence:
      - service: media_player.play_media
        target:
          entity_id: media_player.mpd
        data:
          media_content_id: https://ice4.somafm.com/groovesalad-128-mp3
          media_content_type: music

  play_radio_paradise:
    alias: Play Radio Paradise (FLAC)
    sequence:
      - service: media_player.play_media
        target:
          entity_id: media_player.mpd
        data:
          media_content_id: http://stream.radioparadise.com/flac
          media_content_type: music
```

### 4.4 Simple Lovelace dropdown (choose station)

```yaml
type: entities
title: House Radio
entities:
  - entity: input_select.house_radio
  - entity: script.play_house_radio
```

`configuration.yaml`:
```yaml
input_select:
  house_radio:
    name: House Radio
    options:
      - Groove Salad
      - Radio Paradise
    initial: Groove Salad

script:
  play_house_radio:
    alias: Play Selected House Radio
    sequence:
      - choose:
          - conditions: "{{ states('input_select.house_radio') == 'Groove Salad' }}"
            sequence:
              - service: media_player.play_media
                target:
                  entity_id: media_player.mpd
                data:
                  media_content_id: https://ice4.somafm.com/groovesalad-128-mp3
                  media_content_type: music
          - conditions: "{{ states('input_select.house_radio') == 'Radio Paradise' }}"
            sequence:
              - service: media_player.play_media
                target:
                  entity_id: media_player.mpd
                data:
                  media_content_id: http://stream.radioparadise.com/flac
                  media_content_type: music
```

You can then add **automations** to switch station or start/stop based on presence, time, etc.

---

## 5) Troubleshooting Notes

- **“Connect exception: Bad file descriptor” (Snapserver):** harmless until a writer connects to the FIFO. Confirm `/etc/snapserver.conf` stream and re-check after MPD starts playing.
- **“Exception: end of file” (Snapserver):** indicates FIFO is open but has no data yet—expected when idle.
- **`MPD error: Connection refused` when using `mpc`:** MPD not listening where you’re connecting. Use `mpc -h <bind IP>` and verify `bind_to_address` in `/etc/mpd.conf` (e.g., `10.0.69.1`) and that port 6600 is listening.
- **Missing MPD state/db files (`tag_cache`, `state`):** create `/var/lib/mpd/{music,playlists}` and `chown -R mpd:mpd /var/lib/mpd`, then restart MPD.
- **`avformat_open_input() failed` on some stations (e.g., BBC/HLS):** Debian’s MPD build may lack HLS features. Workarounds:
  - Use alternative non-HLS (MP3/AAC/FLAC) URLs for the same station when available.
  - Or insert an **ffmpeg**/`ffplay`/`gst-launch-1.0` process to transcode HLS → PCM into `/tmp/snapfifo` (advanced, optional).

---

## 6) Next Steps (optional)

- **Snapserver source priority / multiple sources** (e.g., Spotify/librespot, TTS announcements).
- **Home Assistant source switching** via scripts and automations (already scaffolded above).
- **Per-room volume & mute** with Snapclient entities.
- **Announcements**: switch to a higher-priority process stream for TTS, then back to MPD.
- **Security:** If you expose MPD on `0.0.0.0`, restrict with `nftables` to HA host only.

---

### Appendix: Quick Commands Reference

```bash
# Snapserver
sudo systemctl restart snapserver
sudo journalctl -u snapserver -n 50 --no-pager

# MPD
sudo systemctl restart mpd
sudo systemctl status --no-pager mpd
ss -lntp | grep 6600 || true

# MPC to MPD on 10.0.69.1
mpc -h 10.0.69.1 clear
mpc -h 10.0.69.1 add https://ice4.somafm.com/groovesalad-128-mp3
mpc -h 10.0.69.1 play
mpc -h 10.0.69.1 status
```
