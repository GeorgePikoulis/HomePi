# Snapserver Setup (2025-09-15)

## Installation
```bash
sudo apt update
sudo apt install -y snapserver
```

## Configuration
File: `/etc/snapserver.conf`

```ini
[stream]
source = pipe:///tmp/snapfifo?name=HomePi&sampleformat=44100:16:2

[snapserver]
bind_to_address = 0.0.0.0
http_enabled = true
http_port = 1780
tcp_enabled = true
tcp_port = 1704
```

## Systemd
Snapserver package provides its own service.

```bash
sudo systemctl enable --now snapserver
systemctl status snapserver
```

## Verification
- Web status page: `http://<rpi-ip>:1780`
- TCP stream: port `1704`

## Notes
- Snapserver is persistent at boot
- Next step: feed audio into Snapserver and connect Pi Zero 2 W as Snapclient
