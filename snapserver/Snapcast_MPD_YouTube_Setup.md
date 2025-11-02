# Snapcast + MPV + yt-dlp — Host Pipeline (Raspberry Pi 5)

This document covers the **host side** for piping YouTube audio to Snapserver via `mpv`/`yt-dlp`, controlled by `yt2snapctl`. It includes the hardened sanitizer and a cosmetic systemd tweak so stops don’t look like failures.

> Host: Raspberry Pi 5 • FIFO: `/tmp/snapfifo_youtube` • Service: `yt2snap.service`

---

## 1) Files & Roles

- `/usr/local/bin/yt2snap` — wrapper (optional).
- `/usr/local/bin/yt2snap_run` — executes `mpv` with `yt-dlp` to decode YouTube → raw PCM to FIFO.
- `/usr/local/bin/yt2snapctl` — controller that writes `/etc/yt2snap/env` and restarts the service.
- `/etc/yt2snap/env` — simple key file:
  - `YT_URL` — video or playlist URL
  - `YT_LOOP` — `0|1`
  - `YT_PLAYLIST` — `single|full|shuffle`
- `/etc/systemd/system/yt2snap.service` — systemd unit.

---

## 2) `yt2snapctl` (with URL sanitizer)

Ensure **both** `set` and `set-b64` call `normalize_url()` before writing env. Example excerpt:

```bash
# /usr/local/bin/yt2snapctl (excerpt)
normalize_url() {
  local s="$1"
  # Trim leading/trailing whitespace (do NOT touch backslashes)
  s="$(printf '%s' "$s" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
  # Unescape ampersand encodings that break playlists
  s="${s//\u0026/&}"   # \u0026  -> &
  s="${s//\/u0026/&}"   # /u0026   -> &
  s="${s//u0026/&}"     # u0026    -> &
  s="${s//&amp;/&}"     # &amp;    -> &
  s="${s//%26/&}"       # %26      -> &
  printf '%s' "$s"
}

case "${1:-}" in
  set)
    url_in="$(read_arg_or_stdin "${2:-}")"
    url_fixed="$(normalize_url "$url_in")"
    loop="$(get_loop)"; pl="$(get_pl)"
    [[ "$url_fixed" == *"list="* && "$pl" = "single" ]] && pl="full"
    write_env "$url_fixed" "$loop" "$pl"
    systemctl restart yt2snap
    ;;
  set-b64)
    b64="$(read_arg_or_stdin "${2:-}")"
    url_in="$(printf '%s' "$b64" | base64 -d)"
    url_fixed="$(normalize_url "$url_in")"
    loop="$(get_loop)"; pl="$(get_pl)"
    [[ "$url_fixed" == *"list="* && "$pl" = "single" ]] && pl="full"
    write_env "$url_fixed" "$loop" "$pl"
    systemctl restart yt2snap
    ;;
esac
```

Re‑apply current URL to force a clean write:
```bash
CUR=$(grep -E '^YT_URL=' /etc/yt2snap/env | cut -d'"' -f2)
sudo /usr/local/bin/yt2snapctl set "$CUR"
sed -n '1,3p' /etc/yt2snap/env   # look for a real & before list=
```

---

## 3) `yt2snap_run` (MPV / FIFO)

Typical minimal command (tuned for Snapserver):
```bash
# /usr/local/bin/yt2snap_run (excerpt)
exec mpv --no-video --ao=pcm:pipe=/tmp/snapfifo_youtube   --audio-samplerate=44100 --audio-channels=stereo   --ytdl=yes --ytdl-format='bestaudio/best'   "${YT_URL}"
```
- Output format expected by Snapserver: **RAW PCM**, 44.1 kHz, **s16**, stereo.

Optional debugging:
```
--msg-level=all=v
```

---

## 4) Systemd unit (`yt2snap.service`)

```ini
# /etc/systemd/system/yt2snap.service
[Unit]
Description=Pipe YouTube audio to Snapserver FIFO
After=network-online.target snapserver.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/yt2snap/env
ExecStart=/usr/local/bin/yt2snap_run
Restart=on-failure
# Cosmetic: allow exit status 4 (NOPERMISSION) to be treated as success on stop
SuccessExitStatus=0 4
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
```

Reload & enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now yt2snap
```

---

## 5) Snapserver input

`/etc/snapserver.conf` should expose the FIFO as a stream, e.g.:

```ini
[stream]
stream = pipe:///tmp/snapfifo_youtube?name=YouTube
```

Restart Snapserver:
```bash
sudo systemctl restart snapserver
```

---

## 6) Quick validation

```bash
# Show env
sed -n '1,3p' /etc/yt2snap/env

# Verify playlist via yt-dlp (fast)
URL=$(grep -E '^YT_URL=' /etc/yt2snap/env | cut -d'"' -f2)
yt-dlp --flat-playlist -J "$URL" | jq '.title, .id, (.entries|length)'

# Restart pipeline and tail logs
sudo systemctl restart yt2snap
journalctl -u yt2snap -n 100 --no-pager
```

**If playlists don’t advance:**
- Confirm env has a **real** `&list=` (the sanitizer + base64 should guarantee this).
- Check cookies if you rely on authenticated videos or age‑gated content.
- Transient network errors (e.g., `tls: IO error: Connection reset by peer`) are auto‑retried by mpv/ffmpeg.
