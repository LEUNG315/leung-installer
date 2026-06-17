#!/usr/bin/env bash

# Noninteractive installer flows and argument-driven execution helpers.

handle_noninteractive_maintenance_actions() {
	if [[ "$NONINTERACTIVE_CLEAR_CACHE" == "1" && "$NONINTERACTIVE_REFRESH_INSTALLER" == "1" ]]; then
		log_error '不能同时使用 --clear-cache 和 --refresh-installer'
		return 1
	fi

	if [[ "$NONINTERACTIVE_CLEAR_CACHE" == "1" ]]; then
		clear_installer_cache
		init_logging
		write_success_summary "" "非交互缓存清理完成。"
		return 0
	fi

	if [[ "$NONINTERACTIVE_REFRESH_INSTALLER" == "1" ]]; then
		refresh_installer_bootstrap
		return 0
	fi

	return 2
}

resolve_noninteractive_cli_context() {
	local cli="$1"

	[[ -n "$cli" ]] || {
		log_error '非交互模式需要 --cli'
		return 1
	}

	case "$cli" in
	claude | codex | gemini)
		printf '%s\n' "$(cli_display_name "$cli")"
		;;
	*)
		log_error "不支持的 CLI: $cli（仅支持 claude / codex / gemini）"
		return 1
		;;
	esac
}

resolve_noninteractive_url() {
	local cli="$1"
	local url="$2"

	if [[ -n "$url" ]]; then
		validate_url "$url" || {
			log_error '提供的 --url 不合法。'
			return 1
		}
	fi

	url="${url:-$(get_effective_provider_url "$cli")}"
	url="${url:-$(default_provider_url "$cli" 2>/dev/null || true)}"
	[[ -n "$url" ]] || {
		log_error '未配置该 CLI 的 URL，且当前也没有可用默认 URL。请通过 --url 或高级选项显式设置。'
		return 1
	}
	printf '%s\n' "$url"
}

run_noninteractive_connectivity_flow() {
	local cli="$1" url="$2" key="$3"
	if [[ -n "$url" ]]; then
		commit_url_if_needed "$cli" "$url"
	fi
	run_step "检查 URL 连通性" verify_connectivity_result_for_cli "$cli" "$url" "$key" "$NONINTERACTIVE_CONNECTIVITY_SEND_AUTH"
	write_success_summary "$cli" "非交互连通性检查成功。"
}

run_noninteractive_install_only_flow() {
	local cli="$1" display_name="$2"
	LEUNG_POST_INSTALL_WARNING=""
	cluster_guard_enforce
	run_step "准备系统依赖" ensure_system_dependencies
	run_step "准备 Node.js 与 npm" ensure_nvm_and_node
	run_step "安装 $display_name" install_cli "$cli"
	if [[ "$LEUNG_DRY_RUN" != "1" ]]; then
		run_step "验证 $display_name 二进制" verify_cli_binary "$cli"
	fi
	write_success_summary "$cli" "非交互仅安装 CLI 完成；未写入 URL/API 配置。"
}

run_noninteractive_full_install_flow() {
	local cli="$1" display_name="$2" url="$3" key="$4"
	local success_detail="非交互流程执行成功。"
	[[ -n "$key" ]] || {
		log_error '非交互模式需要 --api-key，或改用 --test-mode。示例：--noninteractive --cli codex --api-key sk-xxx'
		return 1
	}
	LEUNG_POST_INSTALL_WARNING=""
	cluster_guard_enforce
	run_step "准备系统依赖" ensure_system_dependencies
	maybe_inject_failure "after_system_deps"
	run_step "准备 Node.js 与 npm" ensure_nvm_and_node
	maybe_inject_failure "after_node_ready"
	commit_url_if_needed "$cli" "$url"
	run_step "安装 $display_name" install_cli "$cli"
	maybe_inject_failure "after_cli_install"
	run_step "写入 $display_name 配置" write_cli_config "$cli" "$key"
	run_step "验证 $display_name 安装结果" verify_cli_setup "$cli" warn
	if [[ -n "$LEUNG_POST_INSTALL_WARNING" ]]; then
		success_detail="${success_detail}\n注意: $LEUNG_POST_INSTALL_WARNING"
	fi
	if [[ "$LEUNG_TEST_MODE" == "1" && "$LEUNG_KEEP_TEST_CONFIG" != "1" ]]; then
		restore_test_state
		cleanup_test_state
	fi
	write_success_summary "$cli" "$success_detail"
}

run_noninteractive_flow() {
	local cli="$NONINTERACTIVE_CLI"
	local key="$NONINTERACTIVE_API_KEY"
	local url="$NONINTERACTIVE_URL"
	local display_name=""

	if handle_noninteractive_maintenance_actions; then
		return 0
	else
		case "$?" in
		2) ;;
		1) return 1 ;;
		*) return 1 ;;
		esac
	fi

	display_name="$(resolve_noninteractive_cli_context "$cli")" || return 1

	if [[ "$LEUNG_TEST_MODE" == "1" ]]; then
		key="$LEUNG_TEST_API_KEY"
		[[ -n "$url" ]] || url="$LEUNG_TEST_DEFAULT_URL"
	fi

	if [[ "$LEUNG_INSTALL_ONLY" != "1" ]]; then
		url="$(resolve_noninteractive_url "$cli" "$url")" || return 1
	fi

	if [[ "$NONINTERACTIVE_ACTION" == "connectivity" ]]; then
		run_noninteractive_connectivity_flow "$cli" "$url" "$key"
		return
	fi

	save_last_selected_cli "$cli"
	capture_test_state_for_cli "$cli"

	if [[ "$LEUNG_INSTALL_ONLY" == "1" ]]; then
		run_noninteractive_install_only_flow "$cli" "$display_name"
		return
	fi

	run_noninteractive_full_install_flow "$cli" "$display_name" "$url" "$key"
}
