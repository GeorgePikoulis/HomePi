# Raspberry Pi Checkpoint Backup — Summary

Here’s a clean, self-contained recap of everything we set up for **checkpoint backups**.

## What’s backed up (paths & elements)
- **Root filesystem**: `/dev/sda2` (ext4) — *used blocks only*, captured online via `e2image -rap` → `rootfs.img.gz`
- **Boot partition**: `/dev/sda1` (FAT32) — raw dump via `dd` → `boot.img.gz`
- **Metadata & integrity** in each checkpoint folder:
  - `METADATA.txt` (timestamp, kernel, note, devices)
  - `SHA256SUMS` (checksums for the `*.img.gz` files)

## Where checkpoints live & naming
- Base directory: `/home/[REDACTED USER]/checkpoints/`
- Each run creates: `ckpt-YYYY-MM-DD_HH-MM-SS-<note>/`
  - Contains: `rootfs.img.gz`, `boot.img.gz`, `METADATA.txt`, `SHA256SUMS`
- Local rotation: keep last **3** checkpoints by default (change with `KEEP=`)

## Script filenames (final state)
- **Created (kept):**
  - `/usr/local/sbin/make-checkpoint.sh`  ← *local-only checkpoint maker (no cloud upload)*
- **Created earlier and removed:**
  - `/usr/local/sbin/upload-existing-checkpoints.sh` (root/system version) — **removed**
  - `/home/[REDACTED USER]/bin/upload-existing-checkpoints.sh` (user version) — **removed**
  - System/user timers for auto-upload — **removed**

## System file changes (to support backups & PC pull)
- **Samba share** added to `/etc/samba/smb.conf`:
  ```ini
  [checkpoints]
     path = /home/[REDACTED USER]/checkpoints
     browseable = yes
     read only = yes
     guest ok = no
     valid users = [REDACTED USER]
     force user = [REDACTED USER]
  ```
  Then:
  ```bash
  sudo smbpasswd -a [REDACTED USER]
  sudo systemctl restart smbd
  sudo systemctl enable smbd
  ```
  This exposes the checkpoints (read-only) to Windows as `\\rpi.local\checkpoints` (or `\\xxx.yyy.zzz.1\checkpoints`) so Google Drive for Windows can sync them.
- **Removed** any rclone/systemd upload units & configs (so no cloud OAuth on the Pi anymore).

## Packages added (for this workflow)
- `e2fsprogs` (provides `e2image`), `gzip`
- `samba` (server to share checkpoints)
> (We also used `coreutils`/`dd` which are already present. Any prior `rclone`, timers and helpers were uninstalled.)

## Commands you use (backup & restore)

### Create a checkpoint (local)
```bash
# With optional note tag, e.g. “pre-firewall”
sudo make-checkpoint.sh pre-firewall
# Keep more locally (e.g., last 5) for this run:
sudo KEEP=5 make-checkpoint.sh pre-change
```

### One-off manual capture (equivalent to what the script does)
```bash
# Rootfs (used blocks only, safe while mounted)
sudo e2image -rap /dev/sda2 - | gzip -1 > /home/[REDACTED USER]/checkpoints/rootfs.img.gz
# Boot (raw)
sudo dd if=/dev/sda1 bs=1M status=progress | gzip -1 > /home/[REDACTED USER]/checkpoints/boot.img.gz
```

### Restore a checkpoint (from a chosen folder)
> Do this from a rescue environment or with the target SSD attached; **double-check device names**.

```bash
# 1) Restore BOOT
gunzip -c /home/[REDACTED USER]/checkpoints/ckpt-<timestamp>/boot.img.gz   | sudo dd of=/dev/sda1 bs=4M status=progress

# 2) Restore ROOTFS (raw image produced by e2image -r is dd-restorable)
gunzip -c /home/[REDACTED USER]/checkpoints/ckpt-<timestamp>/rootfs.img.gz   | sudo dd of=/dev/sda2 bs=4M status=progress

# 3) Optional: filesystem check & (if needed) expand afterwards
sudo e2fsck -f /dev/sda2 || true
# If you resized the partition, grow the FS:
# sudo resize2fs /dev/sda2
```

### Windows side (to fetch/sync)
- Map the share as a drive (e.g., `Z:`) to `\\rpi.local\checkpoints` using the local user.
- If Google Drive won’t accept network paths directly, create a junction:
  ```powershell
  mklink /J C:\SyncCheckpoints Z:\
  ```
  Then point Google Drive for Windows to **C:\SyncCheckpoints**.
