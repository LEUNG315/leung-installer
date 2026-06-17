#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
	printf '[LIVE-SMOKE-MATRIX] %s\n' "$*" >&2
}

require_var() {
	local name="$1"
	[[ -n "${!name:-}" ]] || {
		log "missing required env: $name"
		return 1
	}
}

run_cli() {
	local cli="$1"
	local upper="${cli^^}"
	local url_var="LEUNG_LIVE_SMOKE_URL_${upper}"
	local key_var="LEUNG_LIVE_SMOKE_API_KEY_${upper}"
	local url="${!url_var:-${LEUNG_LIVE_SMOKE_URL:-}}"
	local key="${!key_var:-${LEUNG_LIVE_SMOKE_API_KEY:-}}"

	[[ -n "$url" ]] || {
		log "skip $cli: no URL provided via $url_var or LEUNG_LIVE_SMOKE_URL"
		return 0
	}

	log "RUN  $cli"
	LEUNG_LIVE_SMOKE=1 \
	LEUNG_LIVE_SMOKE_CLI="$cli" \
	LEUNG_LIVE_SMOKE_URL="$url" \
	LEUNG_LIVE_SMOKE_API_KEY="$key" \
	bash "$ROOT_DIR/scripts/run_smoke.sh"
	log "PASS $cli"
}

main() {
	local clis=("$@")
	if [[ ${#clis[@]} -eq 0 ]]; then
		clis=(claude codex gemini)
	fi
	for cli in "${clis[@]}"; do
		run_cli "$cli"
	done
	log 'ALL PASSED'
}

main "$@"
