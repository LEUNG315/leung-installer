#!/usr/bin/env bash
# sync-to-ventoy.sh — copy all three installer trees from ~/Desktop to Ventoy.
# Run this after plugging the USB drive in.
set -euo pipefail

VENTOY="/run/media/leung/Ventoy"
if [[ ! -d "$VENTOY" ]]; then
    echo "ERROR: Ventoy not mounted at $VENTOY" >&2
    exit 1
fi

echo "=== Syncing win-installer ==="
rsync -av --delete --exclude='.git' ~/Desktop/win-installer/ "$VENTOY/win-installer/"

echo ""
echo "=== Syncing mac-installer ==="
rsync -av --delete --exclude='.git' ~/Desktop/mac-installer/ "$VENTOY/mac-installer/"

echo ""
echo "=== Syncing linux-installer ==="
rsync -av --delete --exclude='.git' --exclude='.omx' ~/Desktop/linux-installer/ "$VENTOY/linux-installer/"

sync
echo ""
echo "Done. All three installers synced to Ventoy."
