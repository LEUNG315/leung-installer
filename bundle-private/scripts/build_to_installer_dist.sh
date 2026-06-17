#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER_ROOT="${INSTALLER_ROOT:-$ROOT_DIR/../installer}"
MONTH="${1:-$(date +%Y-%m)}"
if [[ $# -gt 0 ]]; then
  shift
fi
INPUT_ROOT="${INPUT_ROOT:-$ROOT_DIR/secrets/$MONTH}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$INSTALLER_ROOT/dist}"
OUTPUT_DIR="$OUTPUT_ROOT/$MONTH"
BUILDER="$ROOT_DIR/tools/admin_bundle/build_monthly_bundles.py"

[[ -d "$INSTALLER_ROOT" ]] || {
  printf '[ERROR] installer repo not found: %s\n' "$INSTALLER_ROOT" >&2
  exit 1
}
[[ -f "$BUILDER" ]] || {
  printf '[ERROR] builder not found: %s\n' "$BUILDER" >&2
  exit 1
}
[[ -d "$INPUT_ROOT" ]] || {
  printf '[ERROR] input root not found: %s\n' "$INPUT_ROOT" >&2
  exit 1
}
[[ -f "$INPUT_ROOT/users.json" ]] || {
  printf '[ERROR] users.json not found: %s\n' "$INPUT_ROOT/users.json" >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"
python3 "$BUILDER" \
  --input-root "$INPUT_ROOT" \
  --output-dir "$OUTPUT_DIR" \
  --month "$MONTH" \
  --verify \
  "$@"

printf '\n[DONE] bundle output: %s\n' "$OUTPUT_DIR"
