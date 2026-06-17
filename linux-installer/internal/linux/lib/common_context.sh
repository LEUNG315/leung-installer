#!/usr/bin/env bash

configure_runtime_paths() {
	LEUNG_NPM_GLOBAL_PREFIX="$HOME/.local/share/leung-node-global"
	LEUNG_NVM_DIR="$HOME/.nvm"
	if [[ "$LEUNG_TEST_MODE" == "1" ]]; then
		LEUNG_TEST_RUNTIME_DIR="$LEUNG_STATE_DIR/test-runtime"
		# shellcheck disable=SC2034
		LEUNG_NPM_GLOBAL_PREFIX="$LEUNG_TEST_RUNTIME_DIR/node-global"
		LEUNG_NVM_DIR="$LEUNG_TEST_RUNTIME_DIR/.nvm"
	else
		LEUNG_TEST_RUNTIME_DIR="$LEUNG_STATE_DIR/test-runtime"
	fi
}

init_installer_context() {
	LEUNG_SCRIPT_DIR="$1"
	LEUNG_BIN_DIR="$LEUNG_SCRIPT_DIR/bin"
	LEUNG_MANIFEST_DIR="$LEUNG_SCRIPT_DIR/manifests"
	LEUNG_CLI_REGISTRY_FILE="$LEUNG_MANIFEST_DIR/cli-registry.json"
	LEUNG_AUTH_FILE="$LEUNG_HOME/auth.json"
	LEUNG_CONFIG_FILE="$LEUNG_HOME/config.toml"
	LEUNG_LOG_DIR="$LEUNG_HOME/logs"
	LEUNG_BACKUP_DIR="$LEUNG_HOME/backups"
	LEUNG_CACHE_DIR="$LEUNG_HOME/cache"
	LEUNG_STATE_DIR="$LEUNG_HOME/state"
	LEUNG_LAST_CLI_FILE="$LEUNG_STATE_DIR/last_cli"
	LEUNG_SUMMARY_FILE="$LEUNG_STATE_DIR/last-summary.txt"
	LEUNG_CURRENT_STEP_FILE="$LEUNG_STATE_DIR/current_step"
	LEUNG_RESTORE_STACK_FILE="$LEUNG_STATE_DIR/restore-stack"
	LEUNG_TRANSACTION_FILE="$LEUNG_STATE_DIR/transaction-$(timestamp).jsonl"
	LEUNG_TEST_SNAPSHOT_DIR="$LEUNG_STATE_DIR/test-snapshot-$(timestamp)"
	LEUNG_TEST_MANIFEST_FILE="$LEUNG_TEST_SNAPSHOT_DIR/manifest.tsv"
	LEUNG_TEST_RUNTIME_DIR="$LEUNG_STATE_DIR/test-runtime"
	LEUNG_BUNDLES_DIR="${LEUNG_BUNDLES_DIR:-$LEUNG_SCRIPT_DIR/../../bundles}"
	LEUNG_BUNDLES_DOWNLOADS_DIR="$LEUNG_BUNDLES_DIR/downloads"
	LEUNG_BUNDLES_NPM_CACHE_DIR="$LEUNG_BUNDLES_DIR/npm-cache"
	configure_runtime_paths
	LEUNG_INSTALLER_VERSION="$(detect_installer_version 2>/dev/null || true)"
	LEUNG_INSTALLER_PIN_REF="$(detect_installer_pin_ref 2>/dev/null || true)"
	LEUNG_INSTALLER_UPDATED_AT="$(detect_installer_updated_at 2>/dev/null || true)"
}

short_ref() {
	local value="${1:-}"
	[[ -n "$value" ]] || return 1
	if [[ ${#value} -gt 7 ]]; then
		printf '%s\n' "${value:0:7}"
	else
		printf '%s\n' "$value"
	fi
}

detect_installer_version() {
	local git_dir="" git_ref=""
	git_dir="$(cd -- "$LEUNG_SCRIPT_DIR/../.." 2>/dev/null && git rev-parse --git-dir 2>/dev/null || true)"
	if [[ -n "$git_dir" ]]; then
		git_ref="$(cd -- "$LEUNG_SCRIPT_DIR/../.." 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || true)"
		[[ -n "$git_ref" ]] && {
			printf '%s\n' "$git_ref"
			return 0
		}
	fi
	if [[ -n "${LEUNG_MANIFEST_BOOTSTRAP_REF:-}" ]]; then
		short_ref "$LEUNG_MANIFEST_BOOTSTRAP_REF"
		return 0
	fi
	printf '%s\n' 'unknown'
}

detect_installer_pin_ref() {
	if [[ -n "${LEUNG_MANIFEST_BOOTSTRAP_REF:-}" ]]; then
		short_ref "$LEUNG_MANIFEST_BOOTSTRAP_REF"
		return 0
	fi
	return 1
}

detect_installer_updated_at() {
	local git_dir="" updated_at=""
	git_dir="$(cd -- "$LEUNG_SCRIPT_DIR/../.." 2>/dev/null && git rev-parse --git-dir 2>/dev/null || true)"
	if [[ -n "$git_dir" ]]; then
		updated_at="$(cd -- "$LEUNG_SCRIPT_DIR/../.." 2>/dev/null && git log -1 --date=format:'%Y-%m-%d %H:%M' --format='%cd' 2>/dev/null || true)"
		[[ -n "$updated_at" ]] && {
			printf '%s\n' "$updated_at"
			return 0
		}
	fi
	if command -v date >/dev/null 2>&1; then
		updated_at="$(date -r "$LEUNG_SCRIPT_DIR/install.sh" '+%Y-%m-%d %H:%M' 2>/dev/null || true)"
		[[ -n "$updated_at" ]] && {
			printf '%s\n' "$updated_at"
			return 0
		}
	fi
	printf '%s\n' 'unknown'
}

load_download_manifest() {
	local manifest_file="$LEUNG_MANIFEST_DIR/downloads.sh"
	[[ -f "$manifest_file" ]] || return 1
	# shellcheck disable=SC1090
	source "$manifest_file"
}

bootstrap_ref_kind() {
	printf '%s\n' "${LEUNG_BOOTSTRAP_GITHUB_REF_KIND:-${LEUNG_MANIFEST_BOOTSTRAP_REF_KIND:-commit}}"
}

bootstrap_ref() {
	printf '%s\n' "${LEUNG_BOOTSTRAP_GITHUB_REF:-${LEUNG_MANIFEST_BOOTSTRAP_REF:-}}"
}

bootstrap_archive_sha256() {
	printf '%s\n' "${LEUNG_BOOTSTRAP_ARCHIVE_SHA256:-${LEUNG_MANIFEST_BOOTSTRAP_ARCHIVE_SHA256:-}}"
}

bootstrap_archive_url() {
	local owner repo ref
	owner="${LEUNG_BOOTSTRAP_GITHUB_OWNER:-LEUNG315}"
	repo="${LEUNG_BOOTSTRAP_GITHUB_REPO:-linux-installer}"
	ref="$(bootstrap_ref)"
	case "$(bootstrap_ref_kind)" in
	commit)
		printf '%s/%s/%s/archive/%s.tar.gz\n' \
			"${LEUNG_GITHUB_ARCHIVE_BASE:-https://github.com}" \
			"$owner" \
			"$repo" \
			"$ref"
		;;
	heads | tags)
		printf '%s/%s/%s/archive/refs/%s/%s.tar.gz\n' \
			"${LEUNG_GITHUB_ARCHIVE_BASE:-https://github.com}" \
			"$owner" \
			"$repo" \
			"$(bootstrap_ref_kind)" \
			"$ref"
		;;
	*)
		return 1
		;;
	esac
}

bootstrap_archive_mirror_url() {
	local upstream_url="${1:-}"
	local owner repo ref
	owner="${LEUNG_BOOTSTRAP_GITHUB_OWNER:-LEUNG315}"
	repo="${LEUNG_BOOTSTRAP_GITHUB_REPO:-linux-installer}"
	ref="$(bootstrap_ref)"
	if [[ -n "${LEUNG_GITHUB_ARCHIVE_MIRROR_BASE:-}" ]]; then
		local owner repo ref
		case "$(bootstrap_ref_kind)" in
		commit)
			printf '%s/%s/%s/archive/%s.tar.gz\n' \
				"${LEUNG_GITHUB_ARCHIVE_MIRROR_BASE%/}" \
				"$owner" \
				"$repo" \
				"$ref"
			return 0
			;;
		heads | tags)
			printf '%s/%s/%s/archive/refs/%s/%s.tar.gz\n' \
				"${LEUNG_GITHUB_ARCHIVE_MIRROR_BASE%/}" \
				"$owner" \
				"$repo" \
				"$(bootstrap_ref_kind)" \
				"$ref"
			return 0
			;;
		esac
	fi
	github_proxy_wrap_url "${LEUNG_GITHUB_PROXY_BASE:-https://ghproxy.net/}" "$upstream_url" 2>/dev/null || true
}

cli_registry_get() {
	local cli="$1" field="$2"
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" registry-get "$LEUNG_CLI_REGISTRY_FILE" "$cli" "$field"
}

cli_registry_list() {
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" registry-list "$LEUNG_CLI_REGISTRY_FILE"
}

ensure_leung_directories() {
	mkdir -p "$LEUNG_HOME" "$LEUNG_LOG_DIR" "$LEUNG_BACKUP_DIR" "$LEUNG_CACHE_DIR" "$LEUNG_STATE_DIR"
	chmod 700 "$LEUNG_HOME" "$LEUNG_STATE_DIR" "$LEUNG_CACHE_DIR" || true
}

init_logging() {
	local stamp
	stamp="$(date +%Y%m%d-%H%M%S)"
	LEUNG_LOG_FILE="$LEUNG_LOG_DIR/install-$stamp.log"
	: >"$LEUNG_LOG_FILE"
	chmod 600 "$LEUNG_LOG_FILE" || true
	[[ -f "$LEUNG_SUMMARY_FILE" ]] || : >"$LEUNG_SUMMARY_FILE"
	[[ -n "$LEUNG_CURRENT_STEP_FILE" ]] && : >"$LEUNG_CURRENT_STEP_FILE"
	: >"$LEUNG_RESTORE_STACK_FILE"
	: >"$LEUNG_TRANSACTION_FILE"
	chmod 600 "$LEUNG_SUMMARY_FILE" "$LEUNG_CURRENT_STEP_FILE" "$LEUNG_RESTORE_STACK_FILE" "$LEUNG_TRANSACTION_FILE" || true
	LEUNG_ROLLBACK_STATUS="未执行"
	LEUNG_ROLLBACK_DETAILS=""
}
