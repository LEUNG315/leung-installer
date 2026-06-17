#!/usr/bin/env bash

# Interactive menu orchestration and error-wrapper flows.

select_cli_for_sensitive_action() {
	local action_label="$1"
	local cli=""
	cli="$(load_last_selected_cli || true)"
	if [[ -n "$cli" ]]; then
		ui_confirm_target_cli "$action_label" "$cli" || return 1
		case "$UI_MENU_RESULT" in
		keep)
			printf '%s\n' "$cli"
			return 0
			;;
		reselection) ;;
		cancel | *)
			return 1
			;;
		esac
	fi
	ui_select_cli_single || return 1
	cli="$UI_MENU_RESULT"
	[[ "$cli" != "back" ]] || return 1
	printf '%s\n' "$cli"
}

ensure_configured_url_for_cli() {
	local cli="$1"
	local url display_name
	display_name="$(cli_display_name "$cli")"
	url="$(get_effective_provider_url "$cli")"
	while [[ -z "$url" ]]; do
		url="$(default_provider_url "$cli" 2>/dev/null || true)"
		if [[ -n "$url" ]]; then
			run_step "写入 ${display_name} 默认 URL" set_provider_url "$cli" "$url"
			continue
		fi
		ui_info_box "当前 $display_name 的 URL 为空，先进行设置。"
		if ! modify_url_flow "$cli"; then
			return 1
		fi
		url="$(get_effective_provider_url "$cli")"
	done
}

enforce_cluster_guard_for_sensitive_action() {
	local action_label="$1"
	if ! cluster_guard_enforce; then
		ui_failure_box "操作已拒绝" "当前环境不允许执行：$action_label\n\n日志：$LEUNG_LOG_FILE"
		return 1
	fi
}

configure_advanced_flow() {
	while true; do
		ui_advanced_menu
		case "$UI_MENU_RESULT" in
		api)
			configure_api_flow
			;;
		url)
			configure_url_flow
			;;
		config)
			while true; do
				ui_config_menu
				case "$UI_MENU_RESULT" in
				regenerate)
					rewrite_config_flow
					;;
				verify)
					verify_installed_cli_flow
					;;
				details)
					show_cli_config_details_flow
					;;
				back | *)
					break
					;;
				esac
			done
			;;
		maintenance)
			while true; do
				ui_maintenance_menu
				case "$UI_MENU_RESULT" in
				install_only)
					run_install_only_flow
					;;
				test_install)
					run_test_install_flow
					;;
				clear_cache)
					clear_cache_flow
					ui_wait_for_back || return 0
					;;
				manual_rollback)
					manual_rollback_flow
					ui_wait_for_back || return 0
					;;
				refresh_installer)
					refresh_installer_flow
					;;
				back | *)
					break
					;;
				esac
			done
			;;
		logs)
			show_last_results_flow
			ui_wait_for_back || return 0
			;;
		back | *)
			return 0
			;;
		esac
	done
}

handle_interactive_action_failure() {
	local exit_code="${1:-1}" action_label="${2:-当前操作}"
	local failed_step=""
	failed_step="$(load_current_step 2>/dev/null || true)"
	[[ -n "$failed_step" ]] || failed_step="${LEUNG_CURRENT_STEP:-unknown}"
	log_error "${action_label}失败，步骤=${failed_step:-unknown}，退出码=$exit_code"
	rollback_current_transaction || true
	write_summary "失败" "" "错误: ${LEUNG_LAST_ERROR:-未知错误}
回滚: ${LEUNG_ROLLBACK_STATUS}
回滚说明: ${LEUNG_ROLLBACK_DETAILS}"
	ui_failure_box "${action_label}失败" "操作未完成，已返回主菜单。\n步骤：${failed_step:-unknown}\n日志：$LEUNG_LOG_FILE"
}

run_interactive_menu_action() {
	local action_label="$1"
	shift
	local rc=0
	set +e
	(
		set -Eeuo pipefail
		"$@"
	)
	rc=$?
	set -e
	if [[ "$rc" -ne 0 ]]; then
		handle_interactive_action_failure "$rc" "$action_label"
	fi
	return 0
}
