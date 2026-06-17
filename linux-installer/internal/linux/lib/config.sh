#!/usr/bin/env bash

ensure_installer_config() {
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" ensure-auth "$LEUNG_AUTH_FILE" >>"$LEUNG_LOG_FILE" 2>&1
	python3 "$LEUNG_BIN_DIR/config_helper.py" ensure-config "$LEUNG_CONFIG_FILE" >>"$LEUNG_LOG_FILE" 2>&1
}

get_provider_url() {
	local cli="${1:-codex}"
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" get-provider-url "$LEUNG_CONFIG_FILE" "$cli"
}

get_effective_provider_url() {
	local cli="$1"
	local stored=""
	require_python || return 1
	stored="$(get_provider_url "$cli" 2>/dev/null || true)"
	if [[ -n "$stored" ]]; then
		printf '%s\n' "$stored"
		return 0
	fi
	local source=""
	source="$(cli_value_source_path "$cli" url 2>/dev/null || true)"
	[[ -f "$source" ]] || return 0
	python3 "$LEUNG_BIN_DIR/config_helper.py" "extract-${cli}-url" "$source"
}

set_provider_url() {
	local cli="$1" url="$2"
	require_python || return 1
	prepare_target_file_write "$LEUNG_CONFIG_FILE"
	python3 "$LEUNG_BIN_DIR/config_helper.py" set-provider-url "$LEUNG_CONFIG_FILE" "$cli" "$url" >>"$LEUNG_LOG_FILE" 2>&1
}

sync_installer_state_from_actual() {
	local cli="$1"
	local actual_url="" actual_key=""
	actual_url="$(extract_cli_config_value url "$cli" 2>/dev/null || true)"
	actual_key="$(extract_cli_config_value key "$cli" 2>/dev/null || true)"
	[[ -n "$actual_url" ]] && set_provider_url "$cli" "$actual_url"
	[[ -n "$actual_key" ]] && set_cli_key "$cli" "$actual_key"
}

ensure_provider_url_synced() {
	local cli="$1"
	local effective_url=""
	local stored_url=""
	require_python || return 1
	effective_url="$(get_effective_provider_url "$cli" 2>/dev/null || true)"
	stored_url="$(get_provider_url "$cli" 2>/dev/null || true)"
	if [[ -n "$effective_url" && "$effective_url" != "$stored_url" ]]; then
		set_provider_url "$cli" "$effective_url"
	fi
}

get_model_name() {
	local cli="$1"
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" get-model "$LEUNG_CONFIG_FILE" "$cli"
}

set_model_name() {
	local cli="$1" model="$2"
	require_python || return 1
	prepare_target_file_write "$LEUNG_CONFIG_FILE"
	python3 "$LEUNG_BIN_DIR/config_helper.py" set-model "$LEUNG_CONFIG_FILE" "$cli" "$model" >>"$LEUNG_LOG_FILE" 2>&1
}

set_actual_cli_key() {
	local cli="$1" key="$2"
	local target=""
	require_python || return 1
	target="$(cli_value_source_path "$cli" key 2>/dev/null || true)"
	[[ -n "$target" ]] || return 1
	prepare_target_file_write "$target"
	python3 "$LEUNG_BIN_DIR/config_helper.py" update-actual-key "$cli" "$target" "$key" >>"$LEUNG_LOG_FILE" 2>&1
}

set_actual_cli_url() {
	local cli="$1" url="$2"
	local target=""
	require_python || return 1
	target="$(cli_value_source_path "$cli" url 2>/dev/null || true)"
	[[ -n "$target" ]] || return 1
	prepare_target_file_write "$target"
	python3 "$LEUNG_BIN_DIR/config_helper.py" update-actual-url "$cli" "$target" "$url" >>"$LEUNG_LOG_FILE" 2>&1
}

write_cli_config() {
	local cli="$1" key="$2" url model primary secondary
	ensure_provider_url_synced "$cli"
	url="$(get_effective_provider_url "$cli")"
	model="$(get_model_name "$cli")"
	if [[ "$LEUNG_DRY_RUN" == "1" ]]; then
		log_info "[DRY-RUN] 将为 $cli 写入配置，URL=$url，KEY=$(display_secret_label "$key")"
		return 0
	fi
	set_cli_key "$cli" "$key"
	primary="$(primary_cli_config_path "$cli" 2>/dev/null || true)"
	secondary="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	[[ -n "$primary" ]] || {
		log_error "未知 CLI: $cli"
		return 1
	}
	prepare_target_file_write "$primary"
	[[ -n "$secondary" ]] && prepare_target_file_write "$secondary"
	python3 "$LEUNG_BIN_DIR/config_helper.py" write-native-config "$cli" "$HOME" "$key" "$url" "$model" >>"$LEUNG_LOG_FILE" 2>&1
}
