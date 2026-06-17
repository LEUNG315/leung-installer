#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
	printf '[RELEASE-READINESS] %s\n' "$*" >&2
}

run_step() {
	local name="$1"
	shift
	log "RUN  $name"
	"$@"
	log "PASS $name"
}

main() {
	run_step regression bash "$ROOT_DIR/scripts/run_regression.sh"
	run_step quality bash "$ROOT_DIR/scripts/run_quality.sh"
	run_step smoke bash "$ROOT_DIR/scripts/run_smoke.sh"
	log 'ALL PASSED'
}

main "$@"
