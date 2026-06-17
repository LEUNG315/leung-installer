#!/usr/bin/env bash

# Shared flow helpers and module wiring for installer flow orchestration.

# shellcheck source=lib/flows_install.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_install.sh"
# shellcheck source=lib/flows_config.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_config.sh"
# shellcheck source=lib/flows_menu.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_menu.sh"
# shellcheck source=lib/flows_noninteractive.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_noninteractive.sh"

value_consistency_label() {
	local recorded="${1:-}" actual="${2:-}"
	if [[ "$recorded" == "$actual" ]]; then
		printf '%s\n' '一致'
	elif [[ -z "$recorded" && -z "$actual" ]]; then
		printf '%s\n' '一致（均未配置）'
	elif [[ -z "$recorded" ]]; then
		printf '%s\n' '不一致（缺少安装器记录值）'
	elif [[ -z "$actual" ]]; then
		printf '%s\n' '不一致（缺少 CLI 实际值）'
	else
		printf '%s\n' '不一致'
	fi
}

append_mismatch_line() {
	local label="$1" recorded="$2" actual="$3" current="${4:-}"
	if [[ "$recorded" == "$actual" && (-z "$current" || "$actual" == "$current") ]]; then
		return 0
	fi
	printf '%s\n' "- $label：安装器记录值=[${recorded:-未配置}]，CLI 实际值=[${actual:-未配置}]${current:+，当前使用值=[${current:-未配置}]}"
}

build_cli_consistency_report() {
	local cli="$1"
	local recorded_key="$2" actual_key="$3" recorded_url="$4" actual_url="$5" current_url="$6" recorded_model="$7" actual_model="$8"
	local report=""
	local mismatch=""
	local mismatch_header_added=0
	report+="API Key 一致性: $(value_consistency_label "$recorded_key" "$actual_key")"$'\n'
	report+="URL 一致性: $(value_consistency_label "$recorded_url" "$actual_url")"$'\n'
	if [[ -n "$recorded_model" || -n "$actual_model" ]]; then
		report+="model 一致性: $(value_consistency_label "$recorded_model" "$actual_model")"$'\n'
	fi
	mismatch="$(append_mismatch_line "API Key" "$(display_secret_label "$recorded_key")" "$(display_secret_label "$actual_key")")"
	if [[ -n "$mismatch" ]]; then
		report+="不一致详情："$'\n'
		report+="$mismatch"$'\n'
		mismatch_header_added=1
	fi
	mismatch="$(append_mismatch_line "URL" "$recorded_url" "$actual_url" "$current_url")"
	if [[ -n "$mismatch" ]]; then
		[[ "$mismatch_header_added" -eq 1 ]] || report+="不一致详情："$'\n'
		report+="$mismatch"$'\n'
		mismatch_header_added=1
	fi
	mismatch="$(append_mismatch_line "model" "$recorded_model" "$actual_model")"
	if [[ -n "$mismatch" ]]; then
		[[ "$mismatch_header_added" -eq 1 ]] || report+="不一致详情："$'\n'
		report+="$mismatch"$'\n'
	fi
	printf '%s' "${report%$'\n'}"
}

prompt_valid_url() {
	local cli_label="$1" current="${2:-}" new_url=""
	while true; do
		ui_prompt_url "$cli_label" "$current" || return 1
		new_url="$UI_INPUT_RESULT"
		[[ "$new_url" != "$UI_BACK_TOKEN" ]] || return 1
		if [[ -z "$new_url" ]]; then
			ui_error_box "URL 不能为空。"
			continue
		fi
		if ! validate_url "$new_url"; then
			ui_error_box "URL 格式不正确，请输入 https:// 开头的地址（localhost 例外）。"
			current="$new_url"
			continue
		fi
		printf '%s\n' "$new_url"
		return 0
	done
}

resolve_install_url() {
	local cli="$1" display_name="$2"
	local url=""
	url="$(get_effective_provider_url "$cli")"
	if [[ -z "$url" ]]; then
		if [[ "$LEUNG_TEST_MODE" == "1" ]]; then
			url="$LEUNG_TEST_DEFAULT_URL"
		else
			url="$(default_provider_url "$cli" 2>/dev/null || true)"
		fi
		if [[ -n "$url" ]]; then
			ui_info_box "将使用 $display_name 默认 URL：$url
如需自定义，可在下一步选择修改。"
		fi
	fi
	while [[ -z "$url" ]]; do
		ui_info_box "当前 $display_name 的 URL 为空，先进行设置。"
		url="$(prompt_valid_url "$display_name" "$url")" || return 1
	done
	while true; do
		ui_url_confirm_menu "$cli" "$url"
		case "$UI_MENU_RESULT" in
		continue)
			printf '%s\n' "$url"
			return 0
			;;
		modify)
			url="$(prompt_valid_url "$display_name" "$url")" || return 1
			;;
		back | *)
			return 1
			;;
		esac
	done
}

commit_url_if_needed() {
	local cli="$1" url="$2"
	local current_stored="" display_name=""
	display_name="$(cli_display_name "$cli")"
	current_stored="$(get_provider_url "$cli" 2>/dev/null || true)"
	if [[ "$url" != "$current_stored" ]]; then
		run_step "写入 ${display_name} URL" set_provider_url "$cli" "$url"
		maybe_inject_failure "after_provider_url_write"
		maybe_inject_failure "after_shared_url_write"
	fi
}
