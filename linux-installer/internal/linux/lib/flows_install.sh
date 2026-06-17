#!/usr/bin/env bash

# Interactive install and maintenance flows.

run_selected_install_flow() {
	local cli="$1"
	local key=""
	local url=""
	local masked=""
	local current_key=""
	local display_name=""
	local success_message=""
	local summary_detail="已完成安装、配置与基础验证。"
	local codex_hint=""

	display_name="$(cli_display_name "$cli")"

	save_last_selected_cli "$cli"
	capture_test_state_for_cli "$cli"

	if [[ "$LEUNG_TEST_MODE" == "1" ]]; then
		key="$LEUNG_TEST_API_KEY"
	else
		current_key="$(get_cli_key "$cli")"
		if [[ -n "$current_key" ]]; then
			if ui_confirm_keep_existing_key "$display_name" "$(display_secret_label "$current_key")"; then
				key="$current_key"
			fi
		fi

		if [[ -z "$key" ]]; then
			ui_prompt_api_key "$display_name" || return 0
			key="$UI_INPUT_RESULT"
			if [[ -z "$key" ]]; then
				ui_error_box "API Key 不能为空。"
				return 1
			fi
		fi
	fi

	url="$(resolve_install_url "$cli" "$display_name")" || return 0

	masked="$(display_secret_label "$key")"
	if ! ui_confirm_install_summary "$display_name" "$url" "$masked"; then
		return 0
	fi

	if ! cluster_guard_enforce; then
		ui_failure_box "安装前检查失败" "检测到内网环境，已拒绝继续。\n\n日志：$LEUNG_LOG_FILE"
		return 1
	fi

	ui_progress_note "正在准备系统依赖…"
	run_step "准备系统依赖" ensure_system_dependencies
	maybe_inject_failure "after_system_deps"

	ui_progress_note "正在准备 Node.js / npm …"
	run_step "准备 Node.js 与 npm" ensure_nvm_and_node
	maybe_inject_failure "after_node_ready"

	commit_url_if_needed "$cli" "$url"

	ui_progress_note "正在安装 $display_name …"
	run_step "安装 $display_name" install_cli "$cli"
	maybe_inject_failure "after_cli_install"

	ui_progress_note "正在写入 $display_name 配置…"
	run_step "写入 $display_name 配置" write_cli_config "$cli" "$key"

	ui_progress_note "正在验证 $display_name 安装结果…"
	LEUNG_POST_INSTALL_WARNING=""
	run_step "验证 $display_name 安装结果" verify_cli_setup "$cli" warn

	success_message="已完成 $display_name 的安装、配置与基础验证。\n\n日志：$LEUNG_LOG_FILE"
	if [[ -n "$LEUNG_POST_INSTALL_WARNING" ]]; then
		success_message="${success_message}\n\n注意：$LEUNG_POST_INSTALL_WARNING"
		summary_detail="${summary_detail}\n注意: $LEUNG_POST_INSTALL_WARNING"
	fi
	if [[ "$cli" == "codex" ]]; then
		if [[ "$LEUNG_NODE_RUNTIME" == "nvm" ]]; then
			codex_hint="Codex 已安装到当前 nvm Node 环境。\n如果当前终端还找不到 codex，请执行：\nsource ~/.zshrc\n或\nsource ~/.bashrc\n或重新打开终端。"
		elif [[ -x "$LEUNG_NPM_GLOBAL_PREFIX/bin/codex" ]]; then
			codex_hint="Codex 已安装到：$LEUNG_NPM_GLOBAL_PREFIX/bin/codex\n如果当前终端还找不到 codex，请执行：\nsource ~/.zshrc\n或\nsource ~/.bashrc\n或重新打开终端。"
		fi
	fi
	if [[ -n "$codex_hint" ]]; then
		success_message="${success_message}\n\n${codex_hint}"
	fi
	if [[ "$LEUNG_TEST_MODE" == "1" && "$LEUNG_KEEP_TEST_CONFIG" != "1" ]]; then
		if ! restore_test_state; then
			ui_failure_box "${display_name} 测试安装回滚失败" "测试安装已完成，但恢复配置现场失败。\n\n日志：$LEUNG_LOG_FILE"
			return 1
		fi
		if ! cleanup_test_transaction_side_effects; then
			ui_failure_box "${display_name} 测试安装回滚失败" "测试安装已完成，但清理安装副作用失败。\n\n日志：$LEUNG_LOG_FILE"
			return 1
		fi
		if ! cleanup_test_state; then
			ui_failure_box "${display_name} 测试安装回滚失败" "测试安装已完成，但删除测试快照失败。\n\n日志：$LEUNG_LOG_FILE"
			return 1
		fi
		success_message="${success_message}\n\n测试安装已完成，且已恢复配置与清理测试副作用。"
		summary_detail="${summary_detail}\n测试安装已完成，并已恢复配置现场及清理测试副作用。"
		write_success_summary "$cli" "$summary_detail"
	else
		write_success_summary "$cli" "$summary_detail"
	fi
	ui_success_box "$display_name 安装完成" "$success_message"
}

show_last_results_flow() {
	local summary="" latest_log="" summary_log=""
	if [[ -f "$LEUNG_SUMMARY_FILE" ]]; then
		summary="$(cat "$LEUNG_SUMMARY_FILE")"
		summary_log="$(awk -F': ' '/^日志:/ {print $2; exit}' "$LEUNG_SUMMARY_FILE" 2>/dev/null || true)"
	else
		summary="暂无最近一次执行摘要。"
	fi
	if [[ -n "$summary_log" && -f "$summary_log" ]]; then
		latest_log="$summary_log"
	else
		latest_log="$(find "$LEUNG_LOG_DIR" -maxdepth 1 -type f -name 'install-*.log' ! -path "$LEUNG_LOG_FILE" -print 2>/dev/null | sort | tail -n 1 || true)"
		if [[ -z "$latest_log" ]]; then
			latest_log="$(find "$LEUNG_LOG_DIR" -maxdepth 1 -type f -name 'install-*.log' -print 2>/dev/null | sort | tail -n 1 || true)"
		fi
	fi
	if [[ -n "$latest_log" ]]; then
		summary="${summary}\n\n最近日志：$latest_log"
		summary="${summary}\n\n最近日志片段：\n$(tail -n 20 "$latest_log" 2>/dev/null)"
	fi
	ui_show_summary "最近结果 / 日志" "$summary"
}

run_test_install_flow() {
	local previous_test_mode="$LEUNG_TEST_MODE"
	local result=0
	LEUNG_TEST_MODE=1
	ui_info_box "测试安装会写入程序内置测试 Key；界面不会显示明文。默认测试 URL：$LEUNG_TEST_DEFAULT_URL"
	local cli
	ui_select_cli_single || {
		LEUNG_TEST_MODE="$previous_test_mode"
		return 0
	}
	cli="$UI_MENU_RESULT"
	[[ -n "$cli" ]] || {
		LEUNG_TEST_MODE="$previous_test_mode"
		return 0
	}
	[[ "$cli" != "back" ]] || {
		LEUNG_TEST_MODE="$previous_test_mode"
		return 0
	}
	run_selected_install_flow "$cli" || result=$?
	LEUNG_TEST_MODE="$previous_test_mode"
	return "$result"
}

run_install_only_flow() {
	local cli display_name=""
	LEUNG_POST_INSTALL_WARNING=""
	ui_info_box "仅安装 CLI 模式只安装程序本体，不写入 URL、API Key、model，也不做连通性校验。"
	ui_select_cli_single || return 0
	cli="$UI_MENU_RESULT"
	[[ -n "$cli" && "$cli" != "back" ]] || return 0
	display_name="$(cli_display_name "$cli")"
	save_last_selected_cli "$cli"
	capture_test_state_for_cli "$cli"
	if ! cluster_guard_enforce; then
		ui_failure_box "仅安装 CLI 失败" "检测到内网环境，已拒绝继续。\n\n日志：$LEUNG_LOG_FILE"
		return 1
	fi
	run_step "准备系统依赖" ensure_system_dependencies
	run_step "准备 Node.js 与 npm" ensure_nvm_and_node
	run_step "安装 $display_name" install_cli "$cli"
	if [[ "$LEUNG_DRY_RUN" != "1" ]]; then
		run_step "验证 $display_name 二进制" verify_cli_binary "$cli"
	fi
	write_success_summary "$cli" "仅安装 CLI 完成；未写入 URL/API 配置。"
	ui_success_box "仅安装 CLI 完成" "$display_name 已安装完成。\n\n本次没有写入 URL、API Key 或 model。"
}

clear_cache_flow() {
	clear_installer_cache
	init_logging
	write_success_summary "" "已清除 ~/.leung 下的日志、备份、状态与测试缓存。"
	ui_success_box "缓存已清除" "已清理 ~/.leung/logs、~/.leung/backups、~/.leung/state。\n不会影响已安装 CLI 的原生配置文件。"
}

manual_rollback_flow() {
	if [[ ! -s "$LEUNG_TRANSACTION_FILE" && ! -s "$LEUNG_RESTORE_STACK_FILE" ]]; then
		ui_info_box "当前会话没有可回滚的事务记录。"
		return 0
	fi
	if rollback_current_transaction; then
		write_success_summary "" "已手动执行当前会话事务回滚。"
		ui_success_box "回滚已完成" "已尝试恢复当前会话记录的配置与副作用。\n日志：$LEUNG_LOG_FILE"
		return 0
	fi
	ui_failure_box "回滚存在残留" "已尝试执行手动回滚，但仍存在未完全恢复的残留。\n\n日志：$LEUNG_LOG_FILE"
	return 1
}

refresh_installer_bootstrap() {
	local archive_url="" archive_mirror_url="" archive_sha="" refresh_args=("$@")
	local tmp_archive="" work_dir=""
	archive_url="$(bootstrap_archive_url)" || {
		log_error '刷新安装器失败：无法解析 bootstrap archive URL'
		return 1
	}
	archive_mirror_url="$(bootstrap_archive_mirror_url "$archive_url")"
	archive_sha="$(bootstrap_archive_sha256)"
	[[ -n "$archive_sha" ]] || {
		log_error '刷新安装器失败：缺少 bootstrap archive SHA256 pin'
		return 1
	}
	tmp_archive="$(mktemp "${TMPDIR:-/tmp}/leung-refresh-archive.XXXXXX.tar.gz")"
	work_dir="$(mktemp -d "${TMPDIR:-/tmp}/leung-refresh-stage.XXXXXX")"
	download_and_verify_file "installer archive" "$archive_url" "$archive_mirror_url" "$tmp_archive" "$archive_sha" || {
		rm -f "$tmp_archive"
		rm -rf "$work_dir"
		log_error "刷新安装器失败：$archive_url"
		return 1
	}
	tar -xzf "$tmp_archive" -C "$work_dir" --strip-components=1 || {
		rm -f "$tmp_archive"
		rm -rf "$work_dir"
		log_error '刷新安装器失败：归档解压失败'
		return 1
	}
	log_info "刷新安装器：执行已校验 installer archive -> $archive_url"
	exec bash "$work_dir/install.sh" "${refresh_args[@]}"
}

refresh_installer_flow() {
	write_success_summary "" "准备重新拉取最新 bootstrap 并切换到新版安装器。"
	ui_info_box "即将重新拉取最新 bootstrap，并启动新版安装器。\n当前会话将切换到新版本。"
	refresh_installer_bootstrap
}

run_install_entry_flow() {
	local cli=""
	ui_select_cli_single || return 0
	cli="$UI_MENU_RESULT"
	[[ -n "$cli" && "$cli" != "back" ]] || return 0
	run_selected_install_flow "$cli"
}
