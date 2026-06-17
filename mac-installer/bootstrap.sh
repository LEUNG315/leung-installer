#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bootstrap_die() {
    printf '[bootstrap] %s\n' "$*" >&2
    exit 1
}

INSTALLER="$SCRIPT_DIR/install.sh"
[[ -f "$INSTALLER" ]] || bootstrap_die "缺少 install.sh"

exec bash "$INSTALLER" "$@"
