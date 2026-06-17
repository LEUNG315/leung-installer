#!/usr/bin/env bash

capture_test_state_path() {
	local path="$1"
	local backup=""
	[[ "$LEUNG_TEST_MODE" == "1" ]] || return 0
	[[ "$LEUNG_KEEP_TEST_CONFIG" == "1" ]] && return 0
	mkdir -p "$LEUNG_TEST_SNAPSHOT_DIR"
	[[ -f "$LEUNG_TEST_MANIFEST_FILE" ]] || : >"$LEUNG_TEST_MANIFEST_FILE"
	if python3 - "$LEUNG_TEST_MANIFEST_FILE" "$path" <<'PY'; then
import sys
from pathlib import Path
manifest = Path(sys.argv[1])
target = sys.argv[2]
if not manifest.exists():
    raise SystemExit(1)
for line in manifest.read_text(encoding="utf-8").splitlines():
    cols = line.split("\t")
    if cols and cols[0] == target:
        raise SystemExit(0)
raise SystemExit(1)
PY
		return 0
	fi
	if [[ -f "$path" ]]; then
		backup="$LEUNG_TEST_SNAPSHOT_DIR/files$path"
		mkdir -p "$(dirname "$backup")"
		cp -a "$path" "$backup"
		printf '%s\t%s\t%s\n' "$path" "exists" "$backup" >>"$LEUNG_TEST_MANIFEST_FILE"
	else
		printf '%s\t%s\t%s\n' "$path" "missing" "" >>"$LEUNG_TEST_MANIFEST_FILE"
	fi
}

capture_test_state_for_cli() {
	local cli="$1"
	local path
	[[ "$LEUNG_TEST_MODE" == "1" ]] || return 0
	[[ "$LEUNG_KEEP_TEST_CONFIG" == "1" ]] && return 0
	capture_test_state_path "$LEUNG_AUTH_FILE"
	capture_test_state_path "$LEUNG_CONFIG_FILE"
	capture_test_state_path "$LEUNG_LAST_CLI_FILE"
	capture_test_state_path "$HOME/.profile"
	capture_test_state_path "$HOME/.bashrc"
	capture_test_state_path "$HOME/.zshrc"
	while IFS= read -r path; do
		[[ -n "$path" ]] && capture_test_state_path "$path"
	done < <(cli_config_paths "$cli")
}

cleanup_test_transaction_side_effects() {
	local previous_mode="$LEUNG_DRY_RUN"
	[[ "$LEUNG_TEST_MODE" == "1" ]] || return 0
	[[ "$LEUNG_KEEP_TEST_CONFIG" == "1" ]] && return 0
	LEUNG_DRY_RUN=0
	rollback_transaction_side_effects
	LEUNG_DRY_RUN="$previous_mode"
}

restore_test_state() {
	local path state backup
	[[ "$LEUNG_TEST_MODE" == "1" ]] || return 0
	[[ "$LEUNG_KEEP_TEST_CONFIG" == "1" ]] && return 0
	[[ -f "$LEUNG_TEST_MANIFEST_FILE" ]] || return 0
	while IFS=$'\t' read -r path state backup; do
		[[ -n "$path" ]] || continue
		case "$state" in
		exists)
			[[ -f "$backup" ]] || continue
			mkdir -p "$(dirname "$path")"
			cp -a "$backup" "$path"
			;;
		missing)
			rm -f "$path"
			;;
		esac
	done <"$LEUNG_TEST_MANIFEST_FILE"
}

cleanup_test_state() {
	if [[ -n "$LEUNG_TEST_RUNTIME_DIR" && -d "$LEUNG_TEST_RUNTIME_DIR" ]]; then
		rm -rf "$LEUNG_TEST_RUNTIME_DIR"
	fi
	[[ -n "$LEUNG_TEST_SNAPSHOT_DIR" && -d "$LEUNG_TEST_SNAPSHOT_DIR" ]] || return 0
	rm -rf "$LEUNG_TEST_SNAPSHOT_DIR"
}

clear_installer_cache() {
	[[ -n "$LEUNG_LOG_DIR" && -d "$LEUNG_LOG_DIR" ]] && rm -rf "$LEUNG_LOG_DIR"
	[[ -n "$LEUNG_BACKUP_DIR" && -d "$LEUNG_BACKUP_DIR" ]] && rm -rf "$LEUNG_BACKUP_DIR"
	[[ -n "$LEUNG_STATE_DIR" && -d "$LEUNG_STATE_DIR" ]] && rm -rf "$LEUNG_STATE_DIR"
	[[ -n "$LEUNG_LOG_DIR" ]] && mkdir -p "$LEUNG_LOG_DIR"
	[[ -n "$LEUNG_BACKUP_DIR" ]] && mkdir -p "$LEUNG_BACKUP_DIR"
	[[ -n "$LEUNG_STATE_DIR" ]] && mkdir -p "$LEUNG_STATE_DIR"
	[[ -n "$LEUNG_HOME" ]] && chmod 700 "$LEUNG_HOME" "$LEUNG_STATE_DIR" 2>/dev/null || true
	[[ -n "$LEUNG_SUMMARY_FILE" ]] && : >"$LEUNG_SUMMARY_FILE"
	[[ -n "$LEUNG_LOG_FILE" ]] && : >"$LEUNG_LOG_FILE"
	[[ -n "$LEUNG_RESTORE_STACK_FILE" ]] && : >"$LEUNG_RESTORE_STACK_FILE"
	[[ -n "$LEUNG_TRANSACTION_FILE" ]] && : >"$LEUNG_TRANSACTION_FILE"
	chmod 600 "$LEUNG_SUMMARY_FILE" "$LEUNG_LOG_FILE" "$LEUNG_RESTORE_STACK_FILE" "$LEUNG_TRANSACTION_FILE" 2>/dev/null || true
}
