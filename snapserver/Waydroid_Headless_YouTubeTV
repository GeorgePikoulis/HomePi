# RPi 5: Headless Waydroid YouTube TV (boot-safe) + Watchdog (with fuse)

This is the “clean + repeatable” setup we ended up with to make **Waydroid + YouTube TV** start and stay alive **without needing VNC/GUI first**.

It uses:
- a **headless Wayland compositor** (Weston) running as a **systemd --user** service
- a **persistent Waydroid session** running as a **systemd --user** service
- an **app launcher** oneshot unit for YouTube TV
- a **watchdog timer** that checks the Android process + foreground activity and relaunches (with cooldown + escalation fuse)
- minimal **sudoers** rules so the watchdog can run unattended after reboot

---

## 0) Assumptions / prerequisites

- Waydroid is installed and the system service is enabled:
  - `waydroid-container.service` should exist and be enabled.
- Weston is installed:
  - `weston --version` works (we used `weston 14.0.2`).
- User is `george` (UID 1000).
- YouTube TV package name:
  - `com.google.android.youtube.tv`

---

## 1) Cleanup old scripts/units (recommended)

If you previously tried other launchers/spoofs, remove them so you know what’s running.

### 1.1 Remove the old user unit + script (example)
```bash
systemctl --user stop waydroid-youtube-apponly.service 2>/dev/null || true
systemctl --user disable waydroid-youtube-apponly.service 2>/dev/null || true
systemctl --user reset-failed waydroid-youtube-apponly.service 2>/dev/null || true

rm -f ~/.config/systemd/user/default.target.wants/waydroid-youtube-apponly.service
rm -f ~/.config/systemd/user/waydroid-youtube-apponly.service
rm -f ~/.local/bin/waydroid-youtube-apponly.sh

systemctl --user daemon-reload
```

### 1.2 Remove any custom “tv spoof” system unit (example)
```bash
sudo systemctl disable --now waydroid-tv-spoof.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/waydroid-tv-spoof.service
sudo systemctl daemon-reload
sudo systemctl reset-failed waydroid-tv-spoof.service 2>/dev/null || true
```

---

## 2) Enable user lingering (critical for boot-without-login)

This is what allows `systemd --user` services to start at boot even if you never open a local GUI session.

```bash
sudo loginctl enable-linger george
loginctl show-user george -p Linger
```

Expected: `Linger=yes`

---

## 3) Headless Wayland compositor (Weston) as a user service

Weston is started **headless** and creates a Wayland socket in a **private runtime dir** with correct permissions (0700).

### 3.1 Create `~/.config/systemd/user/weston-waydroid.service`
```ini
[Unit]
Description=Weston headless Wayland compositor for Waydroid
After=basic.target

[Service]
Type=simple
RuntimeDirectory=waydroid-runtime
RuntimeDirectoryMode=0700
Environment=XDG_RUNTIME_DIR=%t/waydroid-runtime
ExecStart=/usr/bin/weston --backend=headless-backend.so --socket=wayland-waydroid --idle-time=0 --log=%h/.local/state/weston-waydroid.log
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

### 3.2 Enable and start it
```bash
systemctl --user daemon-reload
systemctl --user enable --now weston-waydroid.service
systemctl --user status weston-waydroid.service --no-pager -l
```

### 3.3 Verify the socket exists
```bash
ls -la /run/user/1000/waydroid-runtime | grep -E 'wayland|lock'
```

Expected (example):
- `/run/user/1000/waydroid-runtime/wayland-waydroid`
- `/run/user/1000/waydroid-runtime/wayland-waydroid.lock`

---

## 4) Persistent Waydroid session (headless) as a user service

We run `waydroid session start` as a long-lived user service.

### 4.1 Create `~/.config/systemd/user/waydroid-session-headless.service`
```ini
[Unit]
Description=Waydroid session (headless, via weston-waydroid)
Requires=weston-waydroid.service
After=weston-waydroid.service

[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-waydroid
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Make Weston's socket visible in the "normal" runtime dir
ExecStartPre=/bin/sh -c 'ln -sf /run/user/1000/waydroid-runtime/wayland-waydroid /run/user/1000/wayland-waydroid; ln -sf /run/user/1000/waydroid-runtime/wayland-waydroid.lock /run/user/1000/wayland-waydroid.lock'

ExecStart=/usr/bin/waydroid session start
Restart=on-failure
RestartSec=2
TimeoutStartSec=0

[Install]
WantedBy=default.target
```

### 4.2 Enable and start it
```bash
systemctl --user daemon-reload
systemctl --user enable --now waydroid-session-headless.service
systemctl --user status waydroid-session-headless.service --no-pager -l
```

### 4.3 Verify
```bash
waydroid status
```

Expected:
- `Session: RUNNING`
- `Container: RUNNING`
- `Wayland display: wayland-waydroid`

---

## 5) Disable Waydroid autosuspend (prevents “Container: FROZEN”)

```bash
waydroid prop set persist.waydroid.suspend false
waydroid prop get persist.waydroid.suspend
```

Expected: `false`

If you need to unfreeze manually:
```bash
sudo waydroid container unfreeze || true
```

---

## 6) YouTube TV launcher oneshot (run at boot)

This unit waits for Waydroid session/container and then launches YouTube TV.

### 6.1 Create `~/.config/systemd/user/waydroid-youtube-launch.service`
```ini
[Unit]
Description=Launch YouTube TV in Waydroid (headless)
After=waydroid-session-headless.service
Requires=waydroid-session-headless.service

[Service]
Type=oneshot
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-waydroid
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

ExecStart=/bin/sh -c '\
  for i in $(seq 1 120); do \
    s="$(waydroid status 2>/dev/null || true)"; \
    echo "$s" | grep -q "Session:[[:space:]]*RUNNING" && echo "$s" | grep -q "Container:[[:space:]]*RUNNING" && break; \
    sleep 1; \
  done; \
  timeout 60s waydroid app launch com.google.android.youtube.tv \
'
TimeoutStartSec=180
RemainAfterExit=no

[Install]
WantedBy=default.target
```

### 6.2 Enable and start it
```bash
systemctl --user daemon-reload
systemctl --user enable --now waydroid-youtube-launch.service
systemctl --user status waydroid-youtube-launch.service --no-pager -l
```

---

## 7) Watchdog: “Is YouTube alive?” + cooldown + fuse + journald logging

### Why sudo?
`waydroid shell` requires root, and we use it to check:
- `pidof com.google.android.youtube.tv`
- `dumpsys activity … topResumedActivity`

### 7.1 Sudoers rule (passwordless for only what we need)
Create:
`/etc/sudoers.d/waydroid-watchdog`

```sudoers
# Allow george's watchdog to probe Waydroid + recover without a password prompt
george ALL=(root) NOPASSWD: /usr/bin/waydroid shell *
george ALL=(root) NOPASSWD: /usr/bin/waydroid container unfreeze
george ALL=(root) NOPASSWD: /usr/bin/systemctl restart waydroid-container.service
```

Install + validate:
```bash
sudo tee /etc/sudoers.d/waydroid-watchdog >/dev/null <<'EOF'
# Allow george's watchdog to probe Waydroid + recover without a password prompt
george ALL=(root) NOPASSWD: /usr/bin/waydroid shell *
george ALL=(root) NOPASSWD: /usr/bin/waydroid container unfreeze
george ALL=(root) NOPASSWD: /usr/bin/systemctl restart waydroid-container.service
EOF

sudo chmod 0440 /etc/sudoers.d/waydroid-watchdog
sudo visudo -cf /etc/sudoers.d/waydroid-watchdog
```

Expected: `parsed OK`

### 7.2 Watchdog script (final version with fuse)
Create `~/.local/bin/waydroid-youtube-watchdog.sh`:

```bash
#!/bin/bash
set -euo pipefail

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-waydroid
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

STATE_DIR="$HOME/.local/state"
mkdir -p "$STATE_DIR"

COOLDOWN_SEC=120
COOLDOWN_FILE="$STATE_DIR/waydroid-youtube-watchdog.last_relaunch"

# Fuse settings
FUSE_WINDOW_SEC=600   # 10 min
FUSE_LIMIT=5
FUSE_FILE="$STATE_DIR/waydroid-youtube-watchdog.relaunch_times"

echo "=== $(date) watchdog tick ==="

st="$(waydroid status 2>/dev/null || true)"
echo "$st"

# Unfreeze if needed
if echo "$st" | grep -q "Container:[[:space:]]*FROZEN"; then
  echo "Container is FROZEN -> unfreezing..."
  sudo -n waydroid container unfreeze || true
  sleep 2
  st="$(waydroid status 2>/dev/null || true)"
  echo "$st"
fi

# Ensure base is up
if ! echo "$st" | grep -q "Session:[[:space:]]*RUNNING"; then
  echo "Session not RUNNING -> restarting waydroid-session-headless.service"
  systemctl --user restart waydroid-session-headless.service || true
  exit 0
fi
if ! echo "$st" | grep -q "Container:[[:space:]]*RUNNING"; then
  echo "Container not RUNNING -> restarting waydroid-session-headless.service"
  systemctl --user restart waydroid-session-headless.service || true
  exit 0
fi

need_relaunch=0

# Process present?
if ! sudo -n waydroid shell -- sh -c 'pidof com.google.android.youtube.tv >/dev/null 2>&1'; then
  echo "YouTube TV missing"
  need_relaunch=1
else
  top="$(sudo -n waydroid shell -- sh -c 'dumpsys activity activities 2>/dev/null | grep -E "mResumedActivity|topResumedActivity" | tail -n 1' || true)"
  echo "TOP=$top"
  echo "$top" | grep -q "com.google.android.youtube.tv" || need_relaunch=1
  [ "$need_relaunch" -eq 1 ] && echo "YouTube TV not foreground"
fi

[ "$need_relaunch" -eq 0 ] && { echo "OK"; exit 0; }

# Cooldown
now="$(date +%s)"
last=0
[ -f "$COOLDOWN_FILE" ] && last="$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)"
delta=$(( now - last ))
if [ "$delta" -lt "$COOLDOWN_SEC" ]; then
  echo "Relaunch suppressed (cooldown ${delta}s < ${COOLDOWN_SEC}s)"
  exit 0
fi

echo "$now" > "$COOLDOWN_FILE"

# Fuse accounting: keep only timestamps within window
touch "$FUSE_FILE"
tmp="$(mktemp)"
awk -v now="$now" -v win="$FUSE_WINDOW_SEC" '($1 >= now-win){print $1}' "$FUSE_FILE" > "$tmp" || true
mv "$tmp" "$FUSE_FILE"
echo "$now" >> "$FUSE_FILE"
count="$(wc -l < "$FUSE_FILE" | tr -d ' ')"
echo "Relaunch count in last ${FUSE_WINDOW_SEC}s: $count (limit $FUSE_LIMIT)"

if [ "$count" -ge "$FUSE_LIMIT" ]; then
  echo "FUSE TRIPPED -> restarting Waydroid session + container"
  systemctl --user restart waydroid-session-headless.service || true
  sleep 5
  st2="$(waydroid status 2>/dev/null || true)"
  echo "$st2"
  echo "$st2" | grep -q "Container:[[:space:]]*RUNNING" || sudo -n systemctl restart waydroid-container.service || true
  : > "$FUSE_FILE"
  exit 0
fi

echo "Triggering relaunch via waydroid-youtube-launch.service"
systemctl --user restart waydroid-youtube-launch.service || true
```

Install it:
```bash
chmod +x ~/.local/bin/waydroid-youtube-watchdog.sh
```

### 7.3 systemd watchdog service + timer (journald logging)
Create `~/.config/systemd/user/waydroid-youtube-watchdog.service`:

```ini
[Unit]
Description=Watchdog for Waydroid YouTube TV

[Service]
Type=oneshot
SyslogIdentifier=waydroid-youtube-watchdog
StandardOutput=journal
StandardError=journal
ExecStart=%h/.local/bin/waydroid-youtube-watchdog.sh
```

Create `~/.config/systemd/user/waydroid-youtube-watchdog.timer`:

```ini
[Unit]
Description=Run Waydroid YouTube TV watchdog periodically

[Timer]
OnBootSec=60
OnUnitActiveSec=30
AccuracySec=5
Unit=waydroid-youtube-watchdog.service

[Install]
WantedBy=timers.target
```

Enable:
```bash
systemctl --user daemon-reload
systemctl --user enable --now waydroid-youtube-watchdog.timer
systemctl --user status waydroid-youtube-watchdog.timer --no-pager -l
```

View watchdog logs:
```bash
journalctl --no-pager -n 200 _SYSTEMD_USER_UNIT=waydroid-youtube-watchdog.service
```

---

## 8) Final “what should be enabled”

User services:
```bash
systemctl --user list-unit-files --state=enabled | grep -E 'weston-waydroid|waydroid-session-headless|waydroid-youtube-launch|waydroid-youtube-watchdog'
```

Expected enabled:
- `weston-waydroid.service`
- `waydroid-session-headless.service`
- `waydroid-youtube-launch.service`
- `waydroid-youtube-watchdog.timer`

System service:
```bash
sudo systemctl is-enabled waydroid-container.service
sudo systemctl status waydroid-container.service --no-pager -l
```

---

## 9) Useful troubleshooting commands

### Waydroid status
```bash
waydroid status
```

### Session logs
```bash
journalctl --user -u waydroid-session-headless.service -b --no-pager -n 250 -l
```

### Weston logs
```bash
tail -n 200 ~/.local/state/weston-waydroid.log
systemctl --user status weston-waydroid.service --no-pager -l
```

### Container logs
```bash
sudo journalctl -u waydroid-container.service -b --no-pager -n 250 -l
```

### Force restart stack
```bash
systemctl --user restart weston-waydroid.service
systemctl --user restart waydroid-session-headless.service
systemctl --user start waydroid-youtube-launch.service
```

---

## 10) Files created/modified

### User units
- `~/.config/systemd/user/weston-waydroid.service`
- `~/.config/systemd/user/waydroid-session-headless.service`
- `~/.config/systemd/user/waydroid-youtube-launch.service`
- `~/.config/systemd/user/waydroid-youtube-watchdog.service`
- `~/.config/systemd/user/waydroid-youtube-watchdog.timer`

### User scripts/state
- `~/.local/bin/waydroid-youtube-watchdog.sh`
- `~/.local/state/waydroid-youtube-watchdog.last_relaunch`
- `~/.local/state/waydroid-youtube-watchdog.relaunch_times`
- `~/.local/state/weston-waydroid.log`

### System sudoers
- `/etc/sudoers.d/waydroid-watchdog`

---

## 11) Why this worked (the key bits)

- **Linger** means user services start at boot without GUI login.
- Weston runs headless and creates a Wayland socket with correct perms (0700) using `RuntimeDirectory`.
- We **bind the socket back** into `/run/user/1000` so Waydroid “sees it like a normal desktop”.
- Persistent `waydroid session start` makes the session stable (no brittle oneshot waiting loops).
- `persist.waydroid.suspend=false` prevents “Container: FROZEN”.
- Watchdog checks **both process + foreground activity** and escalates if there’s a crash loop.
