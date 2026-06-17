#!/usr/bin/env bash

save_last_selected_cli() {
	printf '%s\n' "$1" >"$LEUNG_LAST_CLI_FILE"
	chmod 600 "$LEUNG_LAST_CLI_FILE" || true
	record_transaction state_file "$LEUNG_LAST_CLI_FILE"
}

load_last_selected_cli() {
	[[ -f "$LEUNG_LAST_CLI_FILE" ]] || return 1
	tr -d '[:space:]' <"$LEUNG_LAST_CLI_FILE"
}

validate_url() {
	local url="$1"
	[[ "$url" =~ ^https://.+$ || "$url" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]+)?(/.*)?$ ]]
}

supported_clis() {
	cli_registry_list
}

is_supported_cli() {
	local cli="${1:-}" item
	while IFS= read -r item; do
		[[ "$item" == "$cli" ]] && return 0
	done < <(supported_clis)
	return 1
}

cli_display_name() {
	cli_registry_get "$1" display_name
}

cli_native_path_rel() {
	local cli="$1" kind="$2"
	cli_registry_get "$cli" "native_paths.$kind"
}

cli_native_value_source_kind() {
	local cli="$1" kind="$2"
	cli_registry_get "$cli" "native_value_sources.$kind"
}

primary_cli_config_path() {
	local rel=""
	rel="$(cli_native_path_rel "$1" primary 2>/dev/null || true)"
	[[ -n "$rel" ]] || return 1
	printf '%s\n' "$HOME/$rel"
}

secondary_cli_config_path() {
	local rel=""
	rel="$(cli_native_path_rel "$1" secondary 2>/dev/null || true)"
	[[ -n "$rel" ]] || return 1
	printf '%s\n' "$HOME/$rel"
}

cli_value_source_path() {
	local cli="$1" kind="$2" source_kind="" rel=""
	source_kind="$(cli_native_value_source_kind "$cli" "$kind" 2>/dev/null || true)"
	[[ -n "$source_kind" ]] || return 1
	rel="$(cli_native_path_rel "$cli" "$source_kind" 2>/dev/null || true)"
	[[ -n "$rel" ]] || return 1
	printf '%s\n' "$HOME/$rel"
}

get_cli_key() {
	local cli="${1:-codex}"
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" get-auth-key "$LEUNG_AUTH_FILE" "$cli"
}

set_cli_key() {
	local cli="$1" key="$2"
	require_python || return 1
	prepare_target_file_write "$LEUNG_AUTH_FILE"
	python3 "$LEUNG_BIN_DIR/config_helper.py" set-auth-key "$LEUNG_AUTH_FILE" "$cli" "$key" >>"$LEUNG_LOG_FILE" 2>&1
}

default_provider_url() {
	case "$1" in
	claude) printf '%s\n' "$LEUNG_DEFAULT_CLAUDE_URL" ;;
	codex) printf '%s\n' "$LEUNG_DEFAULT_CODEX_URL" ;;
	gemini) printf '%s\n' "$LEUNG_DEFAULT_GEMINI_URL" ;;
	*) return 1 ;;
	esac
}

cli_config_paths() {
	local primary="" secondary=""
	primary="$(primary_cli_config_path "$1" 2>/dev/null || true)"
	secondary="$(secondary_cli_config_path "$1" 2>/dev/null || true)"
	[[ -n "$primary" ]] && printf '%s\n' "$primary"
	[[ -n "$secondary" ]] && printf '%s\n' "$secondary"
	return 0
}
