#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
	printf '[CLI-USABLE] %s\n' "$*" >&2
}

usage() {
	cat <<'USAGE'
Usage:
  bash scripts/run_cli_usable_validation.sh --cli <claude|codex|gemini> [--cmd '...']

Environment fallbacks:
  LEUNG_USABLE_CLI
  LEUNG_USABLE_CMD

Notes:
- This script is for real environments after installation/configuration is complete.
- It does not install CLIs; it validates that the installed CLI can execute a minimal command.
- Default commands are best-effort probes and may need adjustment as upstream CLIs evolve.
USAGE
}

resolve_default_cmd() {
	case "$1" in
	claude) printf '%s\n' 'claude --version' ;;
	codex) printf '%s\n' 'codex --version' ;;
	gemini) printf '%s\n' 'gemini --version' ;;
	*) return 1 ;;
	esac
}

main() {
	local cli="${LEUNG_USABLE_CLI:-}"
	local cmd="${LEUNG_USABLE_CMD:-}"
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--cli)
			cli="${2:-}"
			shift 2
			;;
		--cmd)
			cmd="${2:-}"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf 'Unknown option: %s\n' "$1" >&2
			usage >&2
			exit 1
			;;
		esac
	done

	[[ -n "$cli" ]] || {
		log 'missing CLI; use --cli <claude|codex|gemini>'
		exit 1
	}
	case "$cli" in
	claude|codex|gemini) ;;
	*) log "unsupported cli: $cli"; exit 1 ;;
	esac

	[[ -n "$cmd" ]] || cmd="$(resolve_default_cmd "$cli")"
	log "RUN  cli=$cli cmd=$cmd"
	bash -lc "$cmd"
	log "PASS cli=$cli"
}

main "$@"
