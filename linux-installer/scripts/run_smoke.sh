#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_BASE_DIR="${LEUNG_SMOKE_BASE_DIR:-$HOME/.tmp-leung-smoke}"
mkdir -p "$SMOKE_BASE_DIR"
WORK_DIR="$(mktemp -d "$SMOKE_BASE_DIR/leung-smoke.XXXXXX")"

cleanup() {
	rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() {
	printf '[SMOKE] %s\n' "$*" >&2
}

run_noninteractive_connectivity_smoke() {
	local home_dir="$WORK_DIR/connectivity-home"
	mkdir -p "$home_dir"
	HOME="$home_dir" \
		LEUNG_HOME="$home_dir/.leung" \
		LEUNG_CONNECTIVITY_MOCK_RESULT='pass|200|reachable and accepted' \
		bash "$ROOT_DIR/install.sh" --noninteractive --cli codex --url https://example.test/v1 --check-connectivity
}

run_noninteractive_test_install_smoke() {
	local home_dir="$WORK_DIR/install-home"
	mkdir -p "$home_dir"
	HOME="$home_dir" \
		LEUNG_HOME="$home_dir/.leung" \
		LEUNG_SKIP_DEPS=1 \
		LEUNG_DRY_RUN=1 \
		LEUNG_CONNECTIVITY_MOCK_RESULT='pass|200|reachable and accepted' \
		bash "$ROOT_DIR/install.sh" --noninteractive --test-mode --cli codex
}

run_live_smoke_if_configured() {
	[[ "${LEUNG_LIVE_SMOKE:-0}" == "1" ]] || {
		log 'live smoke disabled; set LEUNG_LIVE_SMOKE=1 to enable'
		return 0
	}
	[[ -n "${LEUNG_LIVE_SMOKE_CLI:-}" && -n "${LEUNG_LIVE_SMOKE_URL:-}" ]] || {
		log 'live smoke requested but LEUNG_LIVE_SMOKE_CLI / LEUNG_LIVE_SMOKE_URL missing'
		return 1
	}
	local home_dir="$WORK_DIR/live-home"
	mkdir -p "$home_dir"
	HOME="$home_dir" \
		LEUNG_HOME="$home_dir/.leung" \
		bash "$ROOT_DIR/install.sh" --noninteractive --cli "$LEUNG_LIVE_SMOKE_CLI" ${LEUNG_LIVE_SMOKE_API_KEY:+--api-key "$LEUNG_LIVE_SMOKE_API_KEY"} --url "$LEUNG_LIVE_SMOKE_URL" --check-connectivity
}

run_noninteractive_connectivity_smoke
run_noninteractive_test_install_smoke
run_live_smoke_if_configured
log 'ALL PASSED'
