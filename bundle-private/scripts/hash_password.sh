#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HASH_TOOL="$ROOT_DIR/tools/admin_bundle/password_codec.py"
PASSWORD="${1:-}"

[[ -f "$HASH_TOOL" ]] || {
  printf '[ERROR] hash tool not found: %s\n' "$HASH_TOOL" >&2
  exit 1
}

if [[ -z "$PASSWORD" ]]; then
  printf '请输入密码: ' >&2
  IFS= read -r PASSWORD
fi

python3 - "$HASH_TOOL" "$PASSWORD" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
password = sys.argv[2]
spec = importlib.util.spec_from_file_location("password_codec", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.encode_password(password))
PY
