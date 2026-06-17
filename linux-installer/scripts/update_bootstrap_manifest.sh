#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_FILE="$ROOT_DIR/internal/linux/manifests/downloads.sh"
BOOTSTRAP_FILE="$ROOT_DIR/bootstrap.sh"
OWNER="${LEUNG_BOOTSTRAP_GITHUB_OWNER:-LEUNG315}"
REPO="${LEUNG_BOOTSTRAP_GITHUB_REPO:-linux-installer}"
BASE_URL="${LEUNG_GITHUB_ARCHIVE_BASE:-https://github.com}"
COMMIT_SHA="${1:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
ARCHIVE_URL="${BASE_URL%/}/${OWNER}/${REPO}/archive/${COMMIT_SHA}.tar.gz"

TMP_ARCHIVE="$(mktemp)"
cleanup() {
	rm -f "$TMP_ARCHIVE"
}
trap cleanup EXIT

curl -fsSL "$ARCHIVE_URL" -o "$TMP_ARCHIVE"

ARCHIVE_SHA="$(
	python3 - "$TMP_ARCHIVE" <<'PY'
import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
PY
)"

python3 - "$MANIFEST_FILE" "$BOOTSTRAP_FILE" "$COMMIT_SHA" "$ARCHIVE_SHA" <<'PY'
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
bootstrap_path = Path(sys.argv[2])
commit_sha = sys.argv[3]
archive_sha = sys.argv[4]

manifest_text = manifest_path.read_text(encoding="utf-8")
manifest_text = re.sub(
    r'^(LEUNG_MANIFEST_BOOTSTRAP_REF="\$\{LEUNG_MANIFEST_BOOTSTRAP_REF:-)([A-Fa-f0-9]{40})(}"\s*)$',
    rf'\g<1>{commit_sha}\g<3>',
    manifest_text,
    flags=re.M,
)
manifest_text = re.sub(
    r'^(LEUNG_MANIFEST_BOOTSTRAP_ARCHIVE_SHA256="\$\{LEUNG_MANIFEST_BOOTSTRAP_ARCHIVE_SHA256:-)([A-Fa-f0-9]{64})(}"\s*)$',
    rf'\g<1>{archive_sha}\g<3>',
    manifest_text,
    flags=re.M,
)
manifest_path.write_text(manifest_text, encoding="utf-8")

bootstrap_text = bootstrap_path.read_text(encoding="utf-8")
bootstrap_text = re.sub(
    r'^(BOOTSTRAP_FALLBACK_REF=")([A-Fa-f0-9]{40})("\s*)$',
    rf'\g<1>{commit_sha}\g<3>',
    bootstrap_text,
    flags=re.M,
)
bootstrap_text = re.sub(
    r'^(BOOTSTRAP_FALLBACK_ARCHIVE_SHA256=")([A-Fa-f0-9]{64})("\s*)$',
    rf'\g<1>{archive_sha}\g<3>',
    bootstrap_text,
    flags=re.M,
)
bootstrap_path.write_text(bootstrap_text, encoding="utf-8")
PY

printf '[MANIFEST] Updated %s\n' "$MANIFEST_FILE"
printf '[MANIFEST] Updated %s\n' "$BOOTSTRAP_FILE"
printf '[MANIFEST] Commit: %s\n' "$COMMIT_SHA"
printf '[MANIFEST] SHA256: %s\n' "$ARCHIVE_SHA"
