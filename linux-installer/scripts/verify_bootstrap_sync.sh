#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_FILE="$ROOT_DIR/internal/linux/manifests/downloads.sh"
BOOTSTRAP_FILE="$ROOT_DIR/bootstrap.sh"

manifest_ref="$(python3 - "$MANIFEST_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^LEUNG_MANIFEST_BOOTSTRAP_REF="\$\{LEUNG_MANIFEST_BOOTSTRAP_REF:-([A-Fa-f0-9]{40})\}"$', text, re.M)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)"

manifest_sha="$(python3 - "$MANIFEST_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^LEUNG_MANIFEST_BOOTSTRAP_ARCHIVE_SHA256="\$\{LEUNG_MANIFEST_BOOTSTRAP_ARCHIVE_SHA256:-([A-Fa-f0-9]{64})\}"$', text, re.M)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)"

bootstrap_ref="$(python3 - "$BOOTSTRAP_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^BOOTSTRAP_FALLBACK_REF="([A-Fa-f0-9]{40})"$', text, re.M)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)"

bootstrap_sha="$(python3 - "$BOOTSTRAP_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^BOOTSTRAP_FALLBACK_ARCHIVE_SHA256="([A-Fa-f0-9]{64})"$', text, re.M)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)"

if [[ "$manifest_ref" != "$bootstrap_ref" ]]; then
	printf '[BOOTSTRAP-SYNC] ref mismatch: manifest=%s bootstrap=%s\n' "$manifest_ref" "$bootstrap_ref" >&2
	exit 1
fi

if [[ "$manifest_sha" != "$bootstrap_sha" ]]; then
	printf '[BOOTSTRAP-SYNC] sha mismatch: manifest=%s bootstrap=%s\n' "$manifest_sha" "$bootstrap_sha" >&2
	exit 1
fi

printf '[BOOTSTRAP-SYNC] OK ref=%s sha=%s\n' "$manifest_ref" "$manifest_sha" >&2
