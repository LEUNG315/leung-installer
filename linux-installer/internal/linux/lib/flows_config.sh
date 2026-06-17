#!/usr/bin/env bash

# Interactive configuration and status flows.

modify_key_flow() {
	local cli key primary_path secondary_path success_message
	enforce_cluster_guard_for_sensitive_action "配置API" || return 1
	cli="$(select_cli_for_sensitive_action '配置API')" || return 0
	[[ -n "$cli" ]] || return 0
	local display_name
	display_name="$(cli_display_name "$cli")"
	save_last_selected_cli "$cli"

	if [[ "$LEUNG_TEST_MODE" == "1" ]]; then
		key="$LEUNG_TEST_API_KEY"
	else
		ui_prompt_api_key "$display_name" || return 0
		key="$UI_INPUT_RESULT"
		[[ "$key" != "$UI_BACK_TOKEN" ]] || return 0
	fi
	[[ -n "$key" ]] || {
		ui_error_box "API Key 不能为空。"
		return 1
	}

	ensure_configured_url_for_cli "$cli" || return 0

	run_step "写入 ${display_name} 实际配置" set_actual_cli_key "$cli" "$key"
	run_step "同步 ${display_name} 实际 URL" set_actual_cli_url "$cli" "$(get_effective_provider_url "$cli")"
	run_step "同步安装器状态" sync_installer_state_from_actual "$cli"
	run_step "校验 ${display_name} 配置" verify_cli_config_sync "$cli"
	primary_path="$(primary_cli_config_path "$cli")"
	secondary_path="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	success_message="$display_name 的 API Key 已写入。\n安装器状态文件：$LEUNG_AUTH_FILE\nCLI 主配置文件：$primary_path"
	if [[ -n "$secondary_path" ]]; then
		success_message="${success_message}\nCLI 附加配置文件：$secondary_path"
	fi
	ui_success_box "配置已更新" "$success_message"
}

modify_url_flow() {
	local cli="$1"
	local current new_url current_key stored_url primary_path secondary_path sync_note
	enforce_cluster_guard_for_sensitive_action "配置URL" || return 1

	if [[ -z "$cli" ]]; then
		cli="$(select_cli_for_sensitive_action '配置URL')" || return 0
	fi
	[[ -n "$cli" ]] || return 0
	local display_name
	display_name="$(cli_display_name "$cli")"
	save_last_selected_cli "$cli"

	current="$(get_effective_provider_url "$cli")"
	current_key="$(get_cli_key "$cli" 2>/dev/null || true)"
	ui_prompt_url "$display_name" "$current" || return 1
	new_url="$UI_INPUT_RESULT"
	[[ "$new_url" != "$UI_BACK_TOKEN" ]] || return 0
	if [[ -z "$new_url" ]]; then
		ui_error_box "URL 不能为空。"
		return 1
	fi
	if ! validate_url "$new_url"; then
		ui_error_box "URL 格式不正确，请输入 https:// 开头的地址（localhost 例外）。"
		return 1
	fi

	run_step "写入 ${display_name} 实际 URL" set_actual_cli_url "$cli" "$new_url"
	if [[ -n "$current_key" ]]; then
		run_step "同步 ${display_name} 实际 API Key" set_actual_cli_key "$cli" "$current_key"
	fi
	run_step "同步安装器状态" sync_installer_state_from_actual "$cli"
	stored_url="$(extract_cli_config_value url "$cli" 2>/dev/null || true)"
	if [[ "$stored_url" != "$new_url" ]]; then
		ui_failure_box "URL 写入失败" "$display_name 的 CLI 实际值更新失败。\n目标 URL：$new_url\nCLI 实际值：${stored_url:-<空>}\n\n日志：$LEUNG_LOG_FILE"
		return 1
	fi
	current_key="$(extract_cli_config_value key "$cli" 2>/dev/null || true)"
	primary_path="$(primary_cli_config_path "$cli")"
	secondary_path="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	if [[ -n "$current_key" ]]; then
		run_step "校验 ${display_name} 配置" verify_cli_config_sync "$cli"
		sync_note="已直接修改 CLI 原生配置文件，并同步更新安装器状态文件。"
	else
		sync_note="已直接修改 CLI 原生配置文件中的 URL，并同步更新安装器状态文件。"
	fi
	ui_success_box "URL 已更新" "$display_name 的 URL 已保存。\n安装器状态文件：$LEUNG_CONFIG_FILE\nCLI 主配置文件：$primary_path${secondary_path:+\nCLI 附加配置文件：$secondary_path}\n同步结果：$sync_note"
}

run_connectivity_check_flow() {
	local cli
	cli="$(select_cli_for_sensitive_action '检查URL连通性')" || return 0
	[[ -n "$cli" ]] || return 0
	ensure_configured_url_for_cli "$cli" || return 0
	run_step "检查 URL 连通性" run_connectivity_check_for_cli "$cli"
}

configure_url_flow() {
	while true; do
		ui_url_menu
		case "$UI_MENU_RESULT" in
		modify)
			modify_url_flow ""
			;;
		connectivity)
			run_connectivity_check_flow
			ui_wait_for_back || return 0
			;;
		status)
			show_url_status_flow
			ui_wait_for_back || return 0
			;;
		back | *)
			return 0
			;;
		esac
	done
}

configure_api_flow() {
	while true; do
		ui_api_menu
		case "$UI_MENU_RESULT" in
		key)
			modify_key_flow
			;;
		connectivity)
			run_connectivity_check_flow
			ui_wait_for_back || return 0
			;;
		status)
			show_api_status_flow
			ui_wait_for_back || return 0
			;;
		back | *)
			return 0
			;;
		esac
	done
}

show_api_status_flow() {
	local cli key masked display_name native_key primary_path secondary_path
	local consistency=""
	cli="$(select_cli_for_sensitive_action '查看 API 配置状态')" || return 0
	[[ -n "$cli" ]] || return 0
	display_name="$(cli_display_name "$cli")"
	key="$(get_cli_key "$cli" 2>/dev/null || true)"
	native_key="$(extract_cli_config_value key "$cli" 2>/dev/null || true)"
	masked="$(display_secret_label "$key")"
	primary_path="$(primary_cli_config_path "$cli")"
	secondary_path="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	consistency="$(build_cli_consistency_report "$cli" "$key" "$native_key" "" "" "" "" "")"
	ui_show_summary "API 配置状态" "CLI: $display_name\n安装器状态文件: $LEUNG_AUTH_FILE\nCLI 主配置文件: $primary_path${secondary_path:+\nCLI 附加配置文件: $secondary_path}\n安装器记录值（API Key）: ${masked:-未配置}\nCLI 实际值（API Key）: $(display_secret_label "$native_key")\n\n$consistency"
}

show_url_status_flow() {
	local cli url stored display_name native_url primary_path secondary_path
	local consistency=""
	cli="$(select_cli_for_sensitive_action '查看 URL 配置状态')" || return 0
	[[ -n "$cli" ]] || return 0
	display_name="$(cli_display_name "$cli")"
	url="$(get_effective_provider_url "$cli" 2>/dev/null || true)"
	stored="$(get_provider_url "$cli" 2>/dev/null || true)"
	native_url="$(extract_cli_config_value url "$cli" 2>/dev/null || true)"
	primary_path="$(primary_cli_config_path "$cli")"
	secondary_path="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	consistency="$(build_cli_consistency_report "$cli" "" "" "$stored" "$native_url" "$url" "" "")"
	ui_show_summary "URL 配置状态" "CLI: $display_name\n安装器状态文件: $LEUNG_CONFIG_FILE\nCLI 主配置文件: $primary_path${secondary_path:+\nCLI 附加配置文件: $secondary_path}\n安装器记录值（URL）: ${stored:-未配置}\nCLI 实际值（URL）: ${native_url:-未配置}\n当前使用值（URL）: ${url:-未配置}\n\n$consistency"
}

show_cli_config_details_flow() {
	local cli display_name primary_path secondary_path stored_url effective_url native_url
	local stored_key native_key model native_model package_name binary_name
	local consistency=""
	cli="$(select_cli_for_sensitive_action '查看完整 CLI 配置详情')" || return 0
	[[ -n "$cli" ]] || return 0
	display_name="$(cli_display_name "$cli")"
	primary_path="$(primary_cli_config_path "$cli" 2>/dev/null || true)"
	secondary_path="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	stored_url="$(get_provider_url "$cli" 2>/dev/null || true)"
	effective_url="$(get_effective_provider_url "$cli" 2>/dev/null || true)"
	native_url="$(extract_cli_config_value url "$cli" 2>/dev/null || true)"
	stored_key="$(get_cli_key "$cli" 2>/dev/null || true)"
	native_key="$(extract_cli_config_value key "$cli" 2>/dev/null || true)"
	model="$(get_model_name "$cli" 2>/dev/null || true)"
	native_model="$(extract_cli_config_value model "$cli" 2>/dev/null || true)"
	package_name="$(npm_package_for_cli "$cli" 2>/dev/null || true)"
	binary_name="$(binary_name_for_cli "$cli" 2>/dev/null || true)"
	consistency="$(build_cli_consistency_report "$cli" "$stored_key" "$native_key" "$stored_url" "$native_url" "$effective_url" "$model" "$native_model")"
	ui_show_summary "CLI 配置详情" "CLI: $display_name\nCLI ID: $cli\nnpm 包: ${package_name:-未定义}\n可执行名: ${binary_name:-未定义}\n安装器 API Key 文件: $LEUNG_AUTH_FILE\n安装器 URL / model 文件: $LEUNG_CONFIG_FILE\nCLI 主配置文件: ${primary_path:-未定义}${secondary_path:+\nCLI 附加配置文件: $secondary_path}\n安装器记录值（API Key）: $(display_secret_label "$stored_key")\nCLI 实际值（API Key）: $(display_secret_label "$native_key")\n安装器记录值（URL）: ${stored_url:-未配置}\nCLI 实际值（URL）: ${native_url:-未配置}\n当前使用值（URL）: ${effective_url:-未配置}\n安装器记录值（model）: ${model:-未配置}\nCLI 实际值（model）: ${native_model:-未配置}\n\n$consistency"
	ui_wait_for_back || return 0
}

verify_installed_cli_flow() {
	local cli
	cli="$(select_cli_for_sensitive_action '验证已安装 CLI')" || return 0
	[[ -n "$cli" ]] || return 0
	ensure_configured_url_for_cli "$cli" || return 0
	run_step "验证已安装 CLI" verify_cli_setup "$cli"
	ui_success_box "验证完成" "$(cli_display_name "$cli") 的配置、二进制与连通性检查已通过。"
}

rewrite_config_flow() {
	local cli key
	enforce_cluster_guard_for_sensitive_action "重新生成并写入配置" || return 1
	cli="$(select_cli_for_sensitive_action '重新生成并写入配置')" || return 0
	[[ -n "$cli" ]] || return 0
	local display_name
	display_name="$(cli_display_name "$cli")"
	save_last_selected_cli "$cli"

	key="$(get_cli_key "$cli")"
	if [[ -z "$key" ]]; then
		ui_error_box "未找到 $display_name 的现有 Key，请先执行\"修改客户 API Key\"。"
		return 1
	fi
	ensure_configured_url_for_cli "$cli" || return 0

	write_cli_config "$cli" "$key"
	verify_cli_config_sync "$cli"
	ui_success_box "配置已重写" "$display_name 的配置已重新生成并写入。"
}
