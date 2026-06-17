#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://static.example.com/installers}"
ARCHIVE_URL="${ARCHIVE_URL:-$BASE_URL/mac-installer.tar.gz}"
WORK_DIR="$(mktemp -d)"
ARCHIVE_PATH="$WORK_DIR/mac-installer.tar.gz"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

have_cmd() { command -v "$1" >/dev/null 2>&1; }

download() {
  local url="$1" out="$2"
  if have_cmd curl; then
    curl -fsSL "$url" -o "$out"
  elif have_cmd wget; then
    wget -qO "$out" "$url"
  else
    echo "[install-mac] missing curl/wget" >&2
    exit 1
  fi
}

echo "[install-mac] downloading $ARCHIVE_URL"
download "$ARCHIVE_URL" "$ARCHIVE_PATH"

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"
ENTRY="$(find "$WORK_DIR" -maxdepth 2 -type f -name install.sh | grep -v '/internal/' | head -n1)"
[ -n "$ENTRY" ] || { echo "[install-mac] install.sh not found" >&2; exit 1; }
chmod +x "$ENTRY"
exec bash "$ENTRY" "$@"
