#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="/home/leung/Desktop/tempo-installer/windows-installer/"
DST_DIR="/home/leung/VMs/shared/windows-installer/"

mkdir -p "$DST_DIR"
rsync -a --delete \
  --exclude 'vm-share' \
  --exclude 'sync-to-vm-share.sh' \
  "$SRC_DIR" "$DST_DIR"

echo "Synced to: $DST_DIR"
find "$DST_DIR" -maxdepth 2 -type f | sort
