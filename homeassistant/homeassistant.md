# Home Assistant Setup (2025-09-15)

## Installation
- Created Python venv at `/srv/homeassistant`
- Installed HomeAssistant Core via pip
- Default config generated at `/home/george/.homeassistant/`

## Fixes
- Crash on startup due to `josepy>=2.0.0` → pinned `josepy<2.0.0`
- Installed `ffmpeg` and updated PATH in systemd unit

## Systemd Service
File: `/etc/systemd/system/home-assistant.service`

```ini
[Unit]
Description=Home Assistant
Wants=network-online.target tailscaled.service
After=network-online.target tailscaled.service

[Service]
Type=simple
User=george
Group=george
WorkingDirectory=/srv/homeassistant
Environment="PATH=/srv/homeassistant/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=/srv/homeassistant/bin/hass -c /home/george/.homeassistant
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Commands:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now home-assistant
sudo systemctl status home-assistant
```

## Access
- LAN: `http://rpi.local:8123`
- Tailscale: `http://<Pi Tailscale IP>:8123`
- Android Companion app configured with internal/external URLs

## Notes
- Works cleanly under systemd
- Remaining warning: Python 3.11 deprecated → upgrade to Python 3.12 later
