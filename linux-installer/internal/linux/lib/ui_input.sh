#!/usr/bin/env bash

use_dialog_ui() { return 1; }
UI_BACK_TOKEN="__back__"
UI_MENU_RESULT=""
UI_INPUT_RESULT=""
LEUNG_UI_STDIN_ONLY="${LEUNG_UI_STDIN_ONLY:-0}"

ui_input_retry_available() {
	[[ "$LEUNG_UI_STDIN_ONLY" == "1" ]] && return 1
	[[ -t 0 ]] && return 0
	python3 - <<'PY' >/dev/null 2>&1
import os
try:
    fd = os.open('/dev/tty', os.O_RDONLY)
except OSError:
    raise SystemExit(1)
else:
    os.close(fd)
    raise SystemExit(0)
PY
}

tty_read_line() {
	local var=""
	local tty_path=""
	if [[ -t 0 ]]; then
		IFS= read -r var || return 1
	elif [[ "$LEUNG_UI_STDIN_ONLY" == "1" ]]; then
		IFS= read -r var || return 1
	elif tty_path="$(
		python3 - <<'PY' 2>/dev/null
import os
try:
    fd = os.open('/dev/tty', os.O_RDONLY)
except OSError:
    raise SystemExit(1)
else:
    os.close(fd)
    print('/dev/tty')
PY
	)" && [[ -n "$tty_path" ]]; then
		IFS= read -r var <"$tty_path" || return 1
	else
		IFS= read -r var || return 1
	fi
	UI_INPUT_RESULT="$var"
}

tty_prompt() {
	local prompt="$1"
	printf '%b %s ' \
		"$(ui_colorize "$(ui_tone_color progress)" "$(ui_tone_icon progress)")" \
		"$prompt" >&2
	tty_read_line
}

ui_prompt_choice() {
	local prompt="$1"
	shift
	local allowed=""
	while true; do
		if ! tty_prompt "$prompt"; then
			if ui_input_retry_available; then
				ui_error_box "输入读取失败，请重新输入。"
				continue
			fi
			return 1
		fi
		if [[ -z "$UI_INPUT_RESULT" ]]; then
			continue
		fi
		for allowed in "$@"; do
			if [[ "$UI_INPUT_RESULT" == "$allowed" ]]; then
				UI_MENU_RESULT="$UI_INPUT_RESULT"
				return 0
			fi
		done
		ui_error_box "输入无效：$UI_INPUT_RESULT"
	done
}

ui_is_back_input() {
	local value="${1:-}"
	[[ "$value" == "0" || "$value" == "b" || "$value" == "B" || "$value" == "back" || "$value" == "BACK" ]]
}

ui_prompt_text_with_back() {
	local prompt="$1"
	while true; do
		tty_prompt "$prompt（输入 0 返回上一级）："
		if [[ $? -ne 0 ]]; then
			if ui_input_retry_available; then
				ui_error_box "输入读取失败，请重新输入。"
				continue
			fi
			return 1
		fi
		if ui_is_back_input "$UI_INPUT_RESULT"; then
			UI_INPUT_RESULT="$UI_BACK_TOKEN"
			return 0
		fi
		return 0
	done
}

