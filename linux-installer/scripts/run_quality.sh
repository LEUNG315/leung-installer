#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

run_shellcheck() {
	if ! command -v shellcheck >/dev/null 2>&1; then
		printf '[QUALITY] shellcheck not installed; skipping\n' >&2
		return 0
	fi
	shellcheck -x -P SCRIPTDIR \
		"$ROOT_DIR/install.sh" \
		"$ROOT_DIR/bootstrap.sh" \
		"$ROOT_DIR"/internal/linux/install.sh \
		"$ROOT_DIR"/internal/linux/lib/*.sh
}

run_shfmt_check() {
	if ! command -v shfmt >/dev/null 2>&1; then
		printf '[QUALITY] shfmt not installed; skipping\n' >&2
		return 0
	fi
	shfmt -d \
		"$ROOT_DIR/install.sh" \
		"$ROOT_DIR/bootstrap.sh" \
		"$ROOT_DIR"/internal/linux/install.sh \
		"$ROOT_DIR"/internal/linux/lib/*.sh \
		"$ROOT_DIR"/scripts/*.sh
}

run_bootstrap_sync_check() {
	bash "$ROOT_DIR/scripts/verify_bootstrap_sync.sh"
}


run_shellcheck
run_shfmt_check
run_bootstrap_sync_check
printf '[QUALITY] ALL PASSED\n' >&2
