#!/usr/bin/env bash

ui_wait_for_back() {
	ui_menu_begin "RETURN" "当前操作已完成" "primary"
	ui_menu_item 1 "返回上一级" "回到上一层 COMMAND DECK 菜单" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1]：' 1 || return 1
}

ui_show_startup() {
	return 0
}

ui_main_menu() {
	clear >/dev/null 2>&1 || true
	printf '\n' >&2
	print_arch_panel
	print_main_menu_list
	ui_prompt_choice '输入编号 [1-5]：' 1 2 3 4 5 || {
		UI_MENU_RESULT="exit"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="install" ;;
	2) UI_MENU_RESULT="details" ;;
	3) UI_MENU_RESULT="verify" ;;
	4) UI_MENU_RESULT="advanced" ;;
	*) UI_MENU_RESULT="exit" ;;
	esac
}

ui_advanced_menu() {
	ui_menu_begin "ADVANCED OPTIONS" "高级选项：" "primary"
	ui_menu_item 1 "API 设置" "修改 API Key、检查连通性、查看 API 状态" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "URL 设置" "修改 URL、检查 URL 连通性、查看 URL 状态" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "配置与验证" "重建配置、验证安装结果、查看完整配置详情" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "安装与维护" "仅安装、测试安装、清缓存、回滚、刷新安装器" "primary"
	ui_frame_blank "primary"
	ui_menu_item 5 "最近结果 / 日志" "快速回看最近一次安装结果与日志路径" "primary"
	ui_frame_blank "primary"
	ui_menu_item 6 "返回上一级" "回到 COMMAND DECK" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-6]：' 1 2 3 4 5 6 || {
		UI_MENU_RESULT="back"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="api" ;;
	2) UI_MENU_RESULT="url" ;;
	3) UI_MENU_RESULT="config" ;;
	4) UI_MENU_RESULT="maintenance" ;;
	5) UI_MENU_RESULT="logs" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_api_menu() {
	ui_menu_begin "API CONTROL" "配置API：" "primary"
	ui_menu_item 1 "修改 API Key" "更新当前 CLI 的 API Key" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "检查 API / URL 连通性" "验证凭据与地址是否可达" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "查看 API 配置状态" "对比安装器记录值与 CLI 实际值" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "返回上一级" "回到高级选项" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-4]：' 1 2 3 4 || {
		UI_MENU_RESULT="back"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="key" ;;
	2) UI_MENU_RESULT="connectivity" ;;
	3) UI_MENU_RESULT="status" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_url_menu() {
	ui_menu_begin "URL CONTROL" "配置URL：" "primary"
	ui_menu_item 1 "修改URL" "更新当前 CLI 使用的网关地址" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "检查URL连通性" "验证当前地址是否可达" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "查看 URL 配置状态" "检查记录值、实际值与当前值" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "返回上一级" "回到高级选项" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-4]：' 1 2 3 4 || {
		UI_MENU_RESULT="back"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="modify" ;;
	2) UI_MENU_RESULT="connectivity" ;;
	3) UI_MENU_RESULT="status" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_config_menu() {
	ui_menu_begin "CONFIG CONTROL" "配置与验证：" "primary"
	ui_menu_item 1 "重新生成并写入配置" "按当前记录值重建 CLI 配置文件" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "验证已安装 CLI" "执行基础验证与配置核对" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "查看完整 CLI 配置详情" "查看路径、URL、API Key 与 model 的状态" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "返回上一级" "回到高级选项" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-4]：' 1 2 3 4 || {
		UI_MENU_RESULT="back"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="regenerate" ;;
	2) UI_MENU_RESULT="verify" ;;
	3) UI_MENU_RESULT="details" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_maintenance_menu() {
	ui_menu_begin "MAINTENANCE" "安装与维护：" "primary"
	ui_menu_item 1 "仅安装 CLI（不写配置）" "只安装程序本体；不写 URL / API Key / model" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "测试安装（内置测试 Key）" "写入测试配置并演练完整流程，随后自动回滚" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "清除安装器缓存" "清理 ~/.leung 下的日志、临时态与测试缓存" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "手动回滚本次事务" "尝试恢复当前会话已记录的配置与副作用" "primary"
	ui_frame_blank "primary"
	ui_menu_item 5 "刷新安装器" "重新拉取最新 bootstrap 并启动新版安装器" "primary"
	ui_frame_blank "primary"
	ui_menu_item 6 "返回上一级" "回到高级选项" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-6]：' 1 2 3 4 5 6 || {
		UI_MENU_RESULT="back"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="install_only" ;;
	2) UI_MENU_RESULT="test_install" ;;
	3) UI_MENU_RESULT="clear_cache" ;;
	4) UI_MENU_RESULT="manual_rollback" ;;
	5) UI_MENU_RESULT="refresh_installer" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_select_cli_from_list() {
	local prompt_label="${1:-请选择目标 CLI：}"
	shift || true
	local options=("$@")
	local count="${#options[@]}"
	local idx=1 cli="" display_name=""
	if ((count == 0)); then
		UI_MENU_RESULT="back"
		return 0
	fi
	ui_menu_begin "CLI SELECTOR" "$prompt_label" "primary"
	for cli in "${options[@]}"; do
		display_name="$cli"
		if command -v cli_display_name >/dev/null 2>&1; then
			display_name="$(cli_display_name "$cli" 2>/dev/null || printf '%s' "$cli")"
		fi
		ui_menu_item "$idx" "$display_name" "安装并配置 $display_name" "primary"
		ui_frame_blank "primary"
		idx=$((idx + 1))
	done
	ui_menu_item "$idx" "返回上一级" "取消当前选择并回退" "primary"
	ui_menu_end "primary"
	local choices=()
	for ((idx = 1; idx <= count + 1; idx++)); do
		choices+=("$idx")
	done
	ui_prompt_choice "输入编号 [1-$((count + 1))]：" "${choices[@]}" || return 1
	if [[ "$UI_MENU_RESULT" == "$((count + 1))" ]]; then
		UI_MENU_RESULT="back"
		return 0
	fi
	if [[ "$UI_MENU_RESULT" =~ ^[0-9]+$ ]] && ((UI_MENU_RESULT >= 1 && UI_MENU_RESULT <= count)); then
		UI_MENU_RESULT="${options[$((UI_MENU_RESULT - 1))]}"
		return 0
	fi
	UI_MENU_RESULT="back"
}

ui_select_cli_single() {
	ui_menu_begin "CLI SELECTOR" "请选择要安装和配置的 CLI：" "primary"
	ui_menu_item 1 "Claude Code" "安装并配置 Claude Code" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "Codex CLI" "安装并配置 Codex CLI" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "Gemini CLI" "安装并配置 Gemini CLI" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "返回上一级" "取消当前选择并回退" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-4]：' 1 2 3 4 || return 1
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="claude" ;;
	2) UI_MENU_RESULT="codex" ;;
	3) UI_MENU_RESULT="gemini" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_confirm_target_cli() {
	local action_label="$1" cli="$2"
	local cli_label="$cli"
	if command -v cli_display_name >/dev/null 2>&1; then
		cli_label="$(cli_display_name "$cli" 2>/dev/null || printf '%s' "$cli")"
	fi
	ui_menu_begin "TARGET CONFIRM" "检测到历史 CLI，确认本次目标" "primary"
	ui_menu_note "检测到上次操作的 CLI 是：${cli_label}" "primary"
	ui_menu_note "当前动作：${action_label}" "warn"
	ui_frame_blank "primary"
	ui_menu_item 1 "继续使用 ${cli_label}" "沿用历史目标 CLI 继续执行" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "重新选择 CLI" "回到 CLI 列表重新指定目标" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "取消" "退出当前敏感操作" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-3]：' 1 2 3 || {
		UI_MENU_RESULT="cancel"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="keep" ;;
	2) UI_MENU_RESULT="reselection" ;;
	*) UI_MENU_RESULT="cancel" ;;
	esac
}

ui_prompt_api_key() {
	local cli_label="$1"
	ui_prompt_text_with_back "请输入 ${cli_label} 的 API Key"
}

ui_prompt_url() {
	local cli="$1" current="$2"
	ui_inline_signal "当前 ${cli} URL: ${current:-<空>}" "primary"
	ui_prompt_text_with_back "请输入 ${cli} 的 URL"
}

ui_confirm_keep_existing_key() {
	local cli="$1" masked="$2"
	tty_prompt "检测到 ${cli} 已存在 Key：${masked}，保留当前 Key？[y/N]：" || return 1
	case "$UI_INPUT_RESULT" in
	y | Y | yes | YES) return 0 ;;
	*) return 1 ;;
	esac
}

ui_url_confirm_menu() {
	local cli="$1" url="$2"
	local cli_label="$cli"
	if command -v cli_display_name >/dev/null 2>&1; then
		cli_label="$(cli_display_name "$cli" 2>/dev/null || printf '%s' "$cli")"
	fi
	ui_menu_begin "URL CONFIRM" "确认安装前即将写入的地址" "primary"
	ui_menu_note "目标 CLI：${cli_label}" "primary"
	ui_menu_note "当前 URL：$url" "primary"
	ui_frame_blank "primary"
	ui_menu_item 1 "继续安装" "接受当前 URL 并进入下一步" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "修改 URL" "返回并重新输入地址" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "返回上一步" "取消本次 URL 确认" "primary"
	ui_menu_end "primary"
	ui_prompt_choice '输入编号 [1-3]：' 1 2 3 || {
		UI_MENU_RESULT="back"
		return 0
	}
	case "$UI_MENU_RESULT" in
	1) UI_MENU_RESULT="continue" ;;
	2) UI_MENU_RESULT="modify" ;;
	*) UI_MENU_RESULT="back" ;;
	esac
}

ui_confirm_install_summary() {
	local cli="$1" url="$2" masked="$3"
	local extra=""
	if [[ "$LEUNG_TEST_MODE" == "1" ]]; then
		extra='\n模式：测试安装（将写入内置测试 Key）'
	fi
	ui_render_panel "confirm" "INSTALL LOADOUT" "目标 CLI：$cli\nURL：$url\nAPI Key：$masked${extra}"
	tty_prompt '确认开始安装？[y/N]：' || return 1
	case "$UI_INPUT_RESULT" in
	y | Y | yes | YES) return 0 ;;
	*) return 1 ;;
	esac
}
