#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER_ROOT="${INSTALLER_ROOT:-$ROOT_DIR/../installer}"
OPEN_BUNDLE_TOOL="$ROOT_DIR/tools/admin_bundle/open_cli_bundle.py"

usage() {
  cat <<'EOF'
Smoke-test the real bundle-private -> installer bundle flow.

Usage:
  bash scripts/test_bundle_to_installer_flow.sh [YYYY-MM] [--cli codex] [--user alice] [--password xxx] [--keep-artifacts]

Behavior:
  1. Build bundle from bundle-private/secrets/<month>/ via build_to_installer_dist.sh
  2. Read back the bundle with the chosen password
  3. Run installer --bundle-mode in dry-run mode
  4. Verify installer metadata matches the decrypted payload
EOF
}

MONTH="${1:-$(date +%Y-%m)}"
if [[ $# -gt 0 && "$1" != --* ]]; then
  shift
fi

CLI="codex"
USER_NAME=""
PASSWORD="${BUNDLE_PASSWORD:-}"
KEEP_ARTIFACTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cli)
      CLI="${2:-}"
      shift 2
      ;;
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --password)
      PASSWORD="${2:-}"
      shift 2
      ;;
    --keep-artifacts)
      KEEP_ARTIFACTS=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf '[ERROR] unknown arg: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

INPUT_ROOT="${INPUT_ROOT:-$ROOT_DIR/secrets/$MONTH}"
TMP_BASE="${TMP_BASE:-$(mktemp -d /tmp/bundle-private-e2e.XXXXXX)}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$TMP_BASE/out}"
HOME_DIR="${HOME_DIR:-$TMP_BASE/home}"
BUILD_LOG="$TMP_BASE/build.log"
INSTALL_LOG="$TMP_BASE/install.log"

cleanup() {
  local status="$?"
  if [[ "$status" -eq 0 && "$KEEP_ARTIFACTS" -eq 0 ]]; then
    rm -rf "$TMP_BASE"
    return
  fi
  printf '[INFO] artifacts kept: %s\n' "$TMP_BASE" >&2
}
trap cleanup EXIT

[[ -d "$INSTALLER_ROOT" ]] || {
  printf '[ERROR] installer repo not found: %s\n' "$INSTALLER_ROOT" >&2
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
[[ -f "$OPEN_BUNDLE_TOOL" ]] || {
  printf '[ERROR] open bundle tool not found: %s\n' "$OPEN_BUNDLE_TOOL" >&2
  exit 1
}

user_info="$(
  python3 - "$INPUT_ROOT/users.json" "$CLI" "$USER_NAME" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
cli = sys.argv[2]
requested_user = sys.argv[3].strip()
data = json.loads(path.read_text(encoding="utf-8"))
users = data.get("users") or data.get("passwords") or []

def eligible(item: dict) -> bool:
    status = str(item.get("status", "")).strip().lower()
    if status in {"revoked", "disabled"}:
        return False
    allowed = item.get("allowed_clis")
    if isinstance(allowed, list) and allowed:
        return cli in allowed
    return True

selected = None
for item in users:
    if not isinstance(item, dict) or not eligible(item):
        continue
    if requested_user and str(item.get("name", "")).strip() != requested_user:
        continue
    password = str(item.get("password", "")).strip()
    if not password:
        continue
    selected = item
    break

if selected is None:
    raise SystemExit(f"no eligible user with plaintext password found for cli={cli} user={requested_user or '<auto>'}")

print(json.dumps({
    "name": str(selected.get("name", "")).strip(),
    "password": str(selected.get("password", "")).strip(),
}, ensure_ascii=False))
PY
)"

USER_NAME="$(
  USER_INFO="$user_info" python3 - <<'PY'
import json
import os
print(json.loads(os.environ["USER_INFO"])["name"])
PY
)"

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(
    USER_INFO="$user_info" python3 - <<'PY'
import json
import os
print(json.loads(os.environ["USER_INFO"]).get("password", ""))
PY
  )"
fi

[[ -n "$PASSWORD" ]] || {
  printf '[ERROR] bundle password is empty; use --password or put plaintext password in users.json\n' >&2
  exit 1
}

mkdir -p "$HOME_DIR"

LEUNG_BUNDLE_PBKDF2_ITERATIONS="${LEUNG_BUNDLE_PBKDF2_ITERATIONS:-10}" \
INSTALLER_ROOT="$INSTALLER_ROOT" \
OUTPUT_ROOT="$OUTPUT_ROOT" \
bash "$ROOT_DIR/scripts/build_to_installer_dist.sh" "$MONTH" --cli "$CLI" >"$BUILD_LOG" 2>&1

BUNDLE_PATH="$OUTPUT_ROOT/$MONTH/$CLI.bundle.json"
[[ -f "$BUNDLE_PATH" ]] || {
  printf '[ERROR] bundle not found after build: %s\n' "$BUNDLE_PATH" >&2
  exit 1
}

payload="$(
  LEUNG_BUNDLE_PBKDF2_ITERATIONS="${LEUNG_BUNDLE_PBKDF2_ITERATIONS:-10}" \
    python3 "$OPEN_BUNDLE_TOOL" \
      --source "$BUNDLE_PATH" \
      --password "$PASSWORD"
)"

HOME="$HOME_DIR" \
LEUNG_HOME="$HOME_DIR/.leung" \
LEUNG_SKIP_DEPS=1 \
LEUNG_DRY_RUN=1 \
LEUNG_CONNECTIVITY_MOCK_RESULT='pass|200|reachable and accepted' \
LEUNG_BUNDLE_PASSWORD="$PASSWORD" \
LEUNG_BUNDLE_PBKDF2_ITERATIONS="${LEUNG_BUNDLE_PBKDF2_ITERATIONS:-10}" \
bash "$INSTALLER_ROOT/install.sh" \
  --noninteractive \
  --bundle-mode \
  --requested-cli "$CLI" \
  --bundle-source "$BUNDLE_PATH" >"$INSTALL_LOG" 2>&1

AUTH_PATH="$HOME_DIR/.leung/auth.json"
CONFIG_PATH="$HOME_DIR/.leung/config.toml"
PAYLOAD="$payload" AUTH_PATH="$AUTH_PATH" CONFIG_PATH="$CONFIG_PATH" BUNDLE_PATH="$BUNDLE_PATH" python3 - <<'PY'
import json
import os
import tomllib
from pathlib import Path

payload = json.loads(os.environ["PAYLOAD"])
auth = json.loads(Path(os.environ["AUTH_PATH"]).read_text(encoding="utf-8"))
config = tomllib.loads(Path(os.environ["CONFIG_PATH"]).read_text(encoding="utf-8"))
codex = auth["profiles"]["default"][payload["cli"]]
prov = config["provisioning"]
providers = config["providers"]
models = config["models"]

assert codex["managed_by"] == "github-static-bundle"
assert codex["claim_id"] == payload["user_name"]
assert codex["credential_name"] == payload["credential_name"]
assert codex["issued_at"] == payload["bundle_month"]
assert prov["mode"] == "bundle"
assert prov["managed_by"] == "github-static-bundle"
assert prov["last_claim_id"] == payload["user_name"]
assert prov["last_credential_name"] == payload["credential_name"]
assert prov["bundle_month"] == payload["bundle_month"]
assert prov["bundle_source"] == os.environ["BUNDLE_PATH"]
assert providers[f"{payload['cli']}_base_url"] == payload["base_url"]
assert models[payload["cli"]] == payload["model"]
PY

printf 'PASS bundle-private -> installer dry-run ok\n'
printf '  month: %s\n' "$MONTH"
printf '  cli: %s\n' "$CLI"
printf '  user: %s\n' "$USER_NAME"
printf '  bundle: %s\n' "$BUNDLE_PATH"
printf '  build-log: %s\n' "$BUILD_LOG"
printf '  install-log: %s\n' "$INSTALL_LOG"
