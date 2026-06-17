#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SINGLE_TEST_SCRIPT="$ROOT_DIR/scripts/test_bundle_to_installer_flow.sh"

usage() {
  cat <<'EOF'
Batch smoke-test all available bundle-private -> installer flows for one month.

Usage:
  bash scripts/test_all_bundle_flows.sh [YYYY-MM] [--cli codex --cli gemini] [--keep-artifacts] [--stop-on-fail]

Behavior:
  1. Auto-detect CLIs from secrets/<month>/*_apikey.md when --cli is omitted
  2. Run scripts/test_bundle_to_installer_flow.sh once per CLI
  3. Print pass/fail summary and exit non-zero if any CLI fails
EOF
}

MONTH="${1:-$(date +%Y-%m)}"
if [[ $# -gt 0 && "$1" != --* ]]; then
  shift
fi

INPUT_ROOT="${INPUT_ROOT:-$ROOT_DIR/secrets/$MONTH}"
KEEP_ARTIFACTS=0
STOP_ON_FAIL=0
SELECTED_CLIS=()
PASSED=()
FAILED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cli)
      [[ -n "${2:-}" ]] || {
        printf '[ERROR] missing value for --cli\n' >&2
        exit 1
      }
      SELECTED_CLIS+=("$2")
      shift 2
      ;;
    --keep-artifacts)
      KEEP_ARTIFACTS=1
      shift
      ;;
    --stop-on-fail)
      STOP_ON_FAIL=1
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

[[ -d "$INPUT_ROOT" ]] || {
  printf '[ERROR] input root not found: %s\n' "$INPUT_ROOT" >&2
  exit 1
}
[[ -f "$INPUT_ROOT/users.json" ]] || {
  printf '[ERROR] users.json not found: %s\n' "$INPUT_ROOT/users.json" >&2
  exit 1
}
[[ -x "$SINGLE_TEST_SCRIPT" ]] || {
  printf '[ERROR] single flow test script not found: %s\n' "$SINGLE_TEST_SCRIPT" >&2
  exit 1
}

if [[ ${#SELECTED_CLIS[@]} -eq 0 ]]; then
  while IFS= read -r file; do
    cli="$(basename "$file")"
    cli="${cli%_apikey.md}"
    [[ -n "$cli" ]] && SELECTED_CLIS+=("$cli")
  done < <(find "$INPUT_ROOT" -maxdepth 1 -type f -name '*_apikey.md' | sort)
fi

[[ ${#SELECTED_CLIS[@]} -gt 0 ]] || {
  printf '[ERROR] no *_apikey.md files found under %s\n' "$INPUT_ROOT" >&2
  exit 1
}

printf '[INFO] month: %s\n' "$MONTH"
printf '[INFO] input: %s\n' "$INPUT_ROOT"
printf '[INFO] clis: %s\n' "${SELECTED_CLIS[*]}"

for cli in "${SELECTED_CLIS[@]}"; do
  printf '\n[RUN] cli=%s\n' "$cli"
  args=("$MONTH" --cli "$cli")
  if [[ "$KEEP_ARTIFACTS" -eq 1 ]]; then
    args+=(--keep-artifacts)
  fi

  if bash "$SINGLE_TEST_SCRIPT" "${args[@]}"; then
    PASSED+=("$cli")
    printf '[OK] cli=%s\n' "$cli"
  else
    FAILED+=("$cli")
    printf '[FAIL] cli=%s\n' "$cli" >&2
    if [[ "$STOP_ON_FAIL" -eq 1 ]]; then
      break
    fi
  fi
done

printf '\n=== Batch Summary ===\n'
printf 'month: %s\n' "$MONTH"
printf 'passed(%d): %s\n' "${#PASSED[@]}" "${PASSED[*]:-}"
printf 'failed(%d): %s\n' "${#FAILED[@]}" "${FAILED[*]:-}"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi
