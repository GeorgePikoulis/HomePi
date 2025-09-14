#!/usr/bin/env bash
set -euo pipefail

# ========= Settings =========
OWNER_USER="[REDACTED USER]"
BASE_DIR="/home/${OWNER_USER}/checkpoints"
KEEP="${KEEP:-3}"                           # how many checkpoints to keep
BOOT_PART="${BOOT_PART:-/dev/sda1}"         # boot (FAT)
ROOT_PART="${ROOT_PART:-/dev/sda2}"         # root (ext4)

# ========= Naming =========
TS="$(date +%F_%H-%M-%S)"
NOTE="${1:-}"                               # optional note, e.g. pre-change
TAG="$TS${NOTE:+-$NOTE}"
OUTDIR="${BASE_DIR}/ckpt-${TAG}"

# ========= Setup =========
install -d -m 700 -o "${OWNER_USER}" -g "${OWNER_USER}" "$OUTDIR"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&2; }

log "[*] Creating checkpoint → ${OUTDIR}"

# ========= Rootfs =========
log "[*] Imaging root (${ROOT_PART})"
sudo e2image -f -rap "${ROOT_PART}" - | gzip -1 > "${OUTDIR}/rootfs.img.gz"

# ========= Boot =========
log "[*] Imaging boot (${BOOT_PART})"
sudo dd if="${BOOT_PART}" bs=1M status=progress | gzip -1 > "${OUTDIR}/boot.img.gz"

# ========= Metadata & Checksums =========
{
  echo "timestamp=${TS}"
  echo "note=${NOTE}"
  echo "hostname=$(hostname)"
  echo "kernel=$(uname -r)"
  echo "boot_part=${BOOT_PART}"
  echo "root_part=${ROOT_PART}"
} > "${OUTDIR}/METADATA.txt"

( cd "${OUTDIR}" && sha256sum *.img.gz > SHA256SUMS )

# ========= Prune local old checkpoints =========
mapfile -t DIRS < <(find "${BASE_DIR}" -maxdepth 1 -type d -name 'ckpt-*' | LC_ALL=C sort)
COUNT=${#DIRS[@]}
if (( COUNT > KEEP )); then
  TO_DELETE=$((COUNT-KEEP))
  log "[*] Pruning $TO_DELETE old local checkpoint(s)…"
  for ((i=0; i<TO_DELETE; i++)); do
    OLD="${DIRS[$i]}"
    log "    - deleting $OLD"
    rm -rf "$OLD"
  done
fi

log "[*] Done. Checkpoint: ckpt-${TAG}"
