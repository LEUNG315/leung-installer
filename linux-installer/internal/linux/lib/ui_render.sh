#!/usr/bin/env bash

# shellcheck disable=SC2034
DIALOG_TITLE='linux-installer'

resolved_logo_file() {
	if [[ -n "${LEUNG_LOGO_FILE:-}" ]]; then
		printf '%s\n' "$LEUNG_LOGO_FILE"
	else
		printf '%s\n' "$LEUNG_SCRIPT_DIR/assets/cat-colorblocks-50.txt"
	fi
}

supports_color() {
	[[ -t 2 ]] || return 1
	[[ "${TERM:-}" != "dumb" ]]
}

supports_ansi_logo() {
	supports_color || return 1
	case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
	*UTF-8* | *utf8* | *utf-8*) ;;
	*) return 1 ;;
	esac
}

supports_utf8_text() {
	case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
	*UTF-8* | *utf8* | *utf-8*) return 0 ;;
	*) return 1 ;;
	esac
}

UI_FRAME_WIDTH="${UI_FRAME_WIDTH:-62}"

ui_colorize() {
	local style="$1" text="$2"
	if supports_color; then
		printf '\033[%sm%s\033[0m' "$style" "$text"
	else
		printf '%s' "$text"
	fi
}

ui_rule_char() {
	if supports_utf8_text; then
		printf '─'
	else
		printf '-'
	fi
}

ui_repeat_char() {
	local char="$1" count="$2" i
	for ((i = 0; i < count; i++)); do
		printf '%s' "$char"
	done
}

ui_tone_color() {
	case "${1:-primary}" in
	success | install | ok) printf '%s' '38;5;120' ;;
	error | failure | danger | exit) printf '%s' '38;5;203' ;;
	warn | advanced) printf '%s' '38;5;214' ;;
	confirm | select | purple) printf '%s' '38;5;141' ;;
	accent) printf '%s' '38;5;117' ;;
	muted | quiet) printf '%s' '38;5;245' ;;
	progress) printf '%s' '38;5;51' ;;
	body) printf '%s' '38;5;252' ;;
	*) printf '%s' '38;5;81' ;;
	esac
}

ui_tone_icon() {
	local tone="${1:-primary}"
	if supports_utf8_text; then
		case "$tone" in
		success | install | ok) printf '•' ;;
		error | failure) printf '•' ;;
		danger | exit) printf '•' ;;
		warn | advanced) printf '•' ;;
		confirm | select | purple) printf '•' ;;
		accent) printf '•' ;;
		progress) printf '›' ;;
		muted | quiet) printf '•' ;;
		*) printf '•' ;;
		esac
	else
		case "$tone" in
		success | install | ok) printf '*' ;;
		error | failure | danger | exit) printf '*' ;;
		warn | advanced) printf '*' ;;
		confirm | select | purple) printf '*' ;;
		accent) printf '*' ;;
		progress) printf '>' ;;
		muted | quiet) printf '.' ;;
		*) printf '>' ;;
		esac
	fi
}

ui_frame_prefix() {
	if supports_utf8_text; then
		printf '│'
	else
		printf '|'
	fi
}

ui_frame_rule() {
	local kind="${1:-mid}" line_char="" edge_char="" width="${2:-$UI_FRAME_WIDTH}"
	if supports_utf8_text; then
		case "$kind" in
		top)
			edge_char='╭'
			line_char='─'
			;;
		bottom)
			edge_char='╰'
			line_char='─'
			;;
		*)
			edge_char='├'
			line_char='─'
			;;
		esac
	else
		edge_char='+'
		line_char='-'
	fi
	printf '%s' "$edge_char"
	ui_repeat_char "$line_char" "$width"
}

ui_frame_chars() {
	local kind="${1:-mid}"
	if supports_utf8_text; then
		case "$kind" in
		top) printf '╭ ╮ ─' ;;
		mid) printf '├ ┤ ─' ;;
		bottom) printf '╰ ╯ ─' ;;
		side) printf '│ │' ;;
		esac
	else
		case "$kind" in
		top | mid | bottom) printf '+ + -' ;;
		side) printf '| |' ;;
		esac
	fi
}

ui_display_width() {
	local text="${1:-}"
	if command -v python3 >/dev/null 2>&1; then
		python3 - "$text" <<'PY'
import sys
import unicodedata

text = sys.argv[1]
width = 0
for ch in text:
    if unicodedata.combining(ch):
        continue
    width += 2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1
print(width)
PY
	else
		printf '%s\n' "${#text}"
	fi
}

ui_trim_to_width() {
	local text="${1:-}" max="${2:-$UI_FRAME_WIDTH}"
	if command -v python3 >/dev/null 2>&1; then
		python3 - "$text" "$max" <<'PY'
import sys
import unicodedata

text = sys.argv[1]
limit = int(sys.argv[2])
width = 0
out = []
for ch in text:
    ch_width = 0 if unicodedata.combining(ch) else (2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1)
    if width + ch_width > limit:
        break
    out.append(ch)
    width += ch_width
print("".join(out))
PY
	else
		printf '%s\n' "${text:0:max}"
	fi
}

ui_truncate_text() {
	local text="${1:-}" max="${2:-$UI_FRAME_WIDTH}"
	local width=""
	width="$(ui_display_width "$text")"
	if ((width > max)); then
		if supports_utf8_text && ((max > 1)); then
			printf '%s…' "$(ui_trim_to_width "$text" $((max - 1)))"
		else
			printf '%s' "$(ui_trim_to_width "$text" "$max")"
		fi
	else
		printf '%s' "$text"
	fi
}

ui_pad_text() {
	local text="${1:-}" width="${2:-$UI_FRAME_WIDTH}"
	local display_width="" padding=""
	text="$(ui_truncate_text "$text" "$width")"
	display_width="$(ui_display_width "$text")"
	padding=$((width - display_width))
	((padding < 0)) && padding=0
	printf '%s' "$text"
	ui_repeat_char ' ' "$padding"
}

ui_render_frame_border() {
	local kind="${1:-top}" tone="${2:-primary}" title="${3:-}"
	local left right rule tone_style banner remaining left_fill right_fill banner_width
	tone_style="$(ui_tone_color "$tone")"
	read -r left right rule <<<"$(ui_frame_chars "$kind")"
	if [[ -n "$title" ]]; then
		banner=" $(ui_truncate_text "$title" $((UI_FRAME_WIDTH - 2))) "
		banner_width="$(ui_display_width "$banner")"
		remaining=$((UI_FRAME_WIDTH - banner_width))
		((remaining < 0)) && remaining=0
		left_fill="$(ui_repeat_char "$rule" $((remaining / 2)))"
		right_fill="$(ui_repeat_char "$rule" $((remaining - remaining / 2)))"
		printf '%b%b%b%b%b\n' \
			"$(ui_colorize "$tone_style" "$left")" \
			"$(ui_colorize "$tone_style" "$left_fill")" \
			"$(ui_colorize '1;37' "$banner")" \
			"$(ui_colorize "$tone_style" "$right_fill")" \
			"$(ui_colorize "$tone_style" "$right")" >&2
		return 0
	fi
	printf '%b%b%b\n' \
		"$(ui_colorize "$tone_style" "$left")" \
		"$(ui_colorize "$tone_style" "$(ui_repeat_char "$rule" "$UI_FRAME_WIDTH")")" \
		"$(ui_colorize "$tone_style" "$right")" >&2
}

ui_render_frame_line() {
	local text="${1:-}" tone="${2:-primary}" text_style="${3:-$(ui_tone_color body)}"
	local left right padded tone_style
	tone_style="$(ui_tone_color "$tone")"
	read -r left right <<<"$(ui_frame_chars side)"
	padded="$(ui_pad_text "$text" "$UI_FRAME_WIDTH")"
	printf '%b%b%b\n' \
		"$(ui_colorize "$tone_style" "$left")" \
		"$(ui_colorize "$text_style" "$padded")" \
		"$(ui_colorize "$tone_style" "$right")" >&2
}

ui_frame_blank() {
	local tone="${1:-primary}"
	ui_render_frame_line "" "$tone" "$(ui_tone_color body)"
}

ui_menu_begin() {
	local title="$1" subtitle="${2:-}" tone="${3:-primary}"
	ui_render_frame_border top "$tone" "$title"
	if [[ -n "$subtitle" ]]; then
		ui_render_frame_line " $subtitle" "$tone" "$(ui_tone_color muted)"
	fi
	ui_render_frame_border mid "$tone"
}

ui_menu_item() {
	local key="$1" title="$2" desc="$3" tone="${4:-primary}"
	ui_render_frame_line " [${key}] ${title}" "$tone" '1;37'
	ui_render_frame_line "     ${desc}" "$tone" "$(ui_tone_color muted)"
}

ui_menu_note() {
	local message="$1" tone="${2:-warn}"
	ui_render_frame_line " ${message}" "$tone" "$(ui_tone_color warn)"
}

ui_menu_end() {
	local tone="${1:-primary}"
	ui_render_frame_border bottom "$tone"
}

ui_box_line_style() {
	local tone="${1:-primary}" line="${2:-}"
	if [[ -z "$line" ]]; then
		printf '%s' "$(ui_tone_color muted)"
	elif [[ "$line" == *不一致* || "$line" == *失败* || "$line" == *拒绝* || "$line" == *无效* ]]; then
		printf '%s' "$(ui_tone_color error)"
	elif [[ "$line" == *通过* || "$line" == *完成* || "$line" == *成功* || "$line" == *已更新* || "$line" == *已重写* ]]; then
		printf '%s' "$(ui_tone_color success)"
	elif [[ "$line" == *提示* || "$line" == *注意* || "$line" == *当前动作：* || "$line" == *当前\ URL：* || "$line" == *目标\ CLI：* || "$line" == *模式：* ]]; then
		printf '%s' "$(ui_tone_color warn)"
	elif [[ "$line" == 日志：* || "$line" == 安装器* || "$line" == CLI\ 主配置文件:* || "$line" == CLI\ 附加配置文件:* ]]; then
		printf '%s' "$(ui_tone_color muted)"
	elif [[ "$line" == CLI:* || "$line" == CLI\ ID:* || "$line" == npm\ 包:* || "$line" == 可执行名:* || "$line" == URL:* || "$line" == API\ Key:* || "$line" == 当前\ 使用值* || "$line" == 安装器\ 记录值* || "$line" == CLI\ 实际值* || "$line" == 凭据名称:* || "$line" == 月份:* ]]; then
		printf '%s' '1;37'
	else
		printf '%s' "$(ui_tone_color body)"
	fi
}

ui_render_panel() {
	local tone="$1" title="$2" body="${3:-}"
	local formatted="" line="" line_style=""
	formatted="$(printf '%b' "$body")"

	ui_render_frame_border top "$tone" "$title"
	ui_render_frame_border mid "$tone"

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ -z "$line" ]]; then
			ui_frame_blank "$tone"
			continue
		fi
		line_style="$(ui_box_line_style "$tone" "$line")"
		ui_render_frame_line " $line" "$tone" "$line_style"
	done <<<"$formatted"

	ui_render_frame_border bottom "$tone"
}

ui_success_box() {
	local title="$1" body="${2:-}"
	ui_render_panel "success" "$title" "$body"
}

ui_failure_box() {
	local title="$1" body="${2:-}"
	ui_render_panel "error" "$title" "$body"
}

ui_error_box() {
	local body="${1:-}"
	ui_render_panel "error" "ERROR" "$body"
}

ui_info_box() {
	local body="${1:-}"
	ui_render_panel "primary" "INFO" "$body"
}

ui_show_summary() {
	local title="$1" body="${2:-}"
	ui_render_panel "accent" "$title" "$body"
}

ui_progress_note() {
	local body="${1:-}"
	ui_inline_signal "$body" "progress"
}

ui_inline_signal() {
	local message="$1" tone="${2:-progress}"
	printf '\n%b %b\n' \
		"$(ui_colorize "$(ui_tone_color "$tone")" "$(ui_tone_icon "$tone")")" \
		"$(ui_colorize '1;37' "$message")" >&2
}

ui_hud_rule() {
	local label="$1" tone="${2:-primary}"
	local tone_style="" left_fill="" right_fill="" tick=""
	tone_style="$(ui_tone_color "$tone")"
	if supports_utf8_text; then
		tick='┈'
	else
		tick='-'
	fi
	left_fill="$(ui_repeat_char "$tick" 16)"
	right_fill="$(ui_repeat_char "$tick" 16)"
	printf '%b %b %b %b %b\n' \
		"$(ui_colorize "$tone_style" "$left_fill")" \
		"$(ui_colorize "$tone_style" "$(ui_tone_icon "$tone")")" \
		"$(ui_colorize '1;37' "$label")" \
		"$(ui_colorize "$tone_style" "$(ui_tone_icon "$tone")")" \
		"$(ui_colorize "$tone_style" "$right_fill")" >&2
}

print_logo_only() {
	local logo_file=""
	logo_file="$(resolved_logo_file)"
	if supports_ansi_logo && [[ -f "$logo_file" ]]; then
		cat "$logo_file" >&2
		return 0
	fi
	cat >&2 <<'EOF'
                    -`
                   .x+`
                  `xxz/
                 `+xxzz:
                `+xxzzli:
                -+xxzzli+:
              `/:-:++xxzli+:
             `/++++/+++++++:
            `/++++xxxxxxxxxx:
           `/+++xxzzlliixxxx/`
          ./xxzzllii++iillzzx+`
         .xxzzllii-````/iillzz+`
        -xzzlliii.      :iillzzx.
       :xzlliiii/        iillz+++.
      /xzlliiiiii/        +iillxx/-
    `/xzzlli+/:-        -:/+iillzx+-
   `+xlz+:-`                 `.-/+ixz:
  `++:.                           `-/+/
  .`                                 `/
EOF
}

panel_value() {
	local value="${1:-}"
	if [[ -n "$value" ]]; then
		printf '%s' "$value"
	else
		printf '%s' '未设置'
	fi
}

panel_key_status() {
	local cli="$1"
	local key=""
	key="$(get_cli_key "$cli" 2>/dev/null || true)"
	if [[ -n "$key" ]]; then
		printf '%s' 'key就绪'
	else
		printf '%s' 'key缺失'
	fi
}

panel_signal_chip() {
	local value="${1:-}"
	local label tone
	case "$value" in
	成功)
		label='SUCCESS'
		tone='success'
		;;
	失败)
		label='FAILURE'
		tone='error'
		;;
	*)
		label='IDLE'
		tone='muted'
		;;
	esac
	if supports_color; then
		printf '%b' "$(ui_colorize "$(ui_tone_color "$tone")" "$label")"
	else
		printf '%s' "$label"
	fi
}

panel_last_status_raw() {
	if [[ -f "$LEUNG_SUMMARY_FILE" ]]; then
		awk -F': ' '/^状态:/ {print $2; exit}' "$LEUNG_SUMMARY_FILE" 2>/dev/null
	fi
}

panel_status_label() {
	local value="${1:-}"
	if [[ -z "$value" ]]; then
		printf '%s' '无记录'
	else
		printf '%s' "$value"
	fi
}

panel_status_colored() {
	local value="${1:-}"
	local reset='\033[0m'
	local green='\033[38;5;114m'
	local red='\033[38;5;203m'
	local gray='\033[38;5;245m'
	case "$value" in
	成功) printf '%b' "${green}${value}${reset}" ;;
	失败) printf '%b' "${red}${value}${reset}" ;;
	*) printf '%b' "${gray}${value:-无记录}${reset}" ;;
	esac
}

panel_truncate() {
	local text="${1:-}"
	local max="${2:-28}"
	if ((${#text} > max)); then
		printf '%s…' "${text:0:max-1}"
	else
		printf '%s' "$text"
	fi
}

panel_url_status() {
	local cli="$1"
	local value=""
	value="$(get_effective_provider_url "$cli" 2>/dev/null || true)"
	if [[ -z "$value" ]]; then
		printf '%s' 'url缺失'
	else
		printf '%s' 'url就绪'
	fi
}

panel_cli_health() {
	local cli="$1"
	local key="" url=""
	key="$(get_cli_key "$cli" 2>/dev/null || true)"
	url="$(get_effective_provider_url "$cli" 2>/dev/null || true)"
	if [[ -n "$key" && -n "$url" ]]; then
		printf '%s' 'ready'
	elif [[ -n "$key" || -n "$url" ]]; then
		printf '%s' 'partial'
	else
		printf '%s' 'missing'
	fi
}

panel_cli_matrix_line() {
	local cli="$1" health="" status_text="" status_color='38;5;203' name_text=""
	health="$(panel_cli_health "$cli")"
	case "$cli" in
	claude) name_text='Claude' ;;
	codex) name_text='Codex' ;;
	gemini) name_text='Gemini' ;;
	*) name_text="$cli" ;;
	esac
	case "$health" in
	ready)
		status_text='[OK]'
		status_color='38;5;120'
		;;
	*)
		status_text='[--]'
		status_color='38;5;203'
		;;
	esac
	if supports_color; then
		printf '%b' "$(ui_colorize '38;5;245' "$name_text")"
		printf '    '
		printf '%b' "$(ui_colorize "$status_color" "$status_text")"
	else
		printf '%s    %s' "$name_text" "$status_text"
	fi
}

panel_last_signal_line() {
	local status_raw="$1"
	if supports_color; then
		printf '%b   %b' "$(ui_colorize '38;5;45' 'Last Signal')" "$(panel_signal_chip "$status_raw")"
	else
		printf 'Last Signal   %s' "$(panel_signal_chip "$status_raw")"
	fi
}

panel_signal_ready_line() {
	if supports_color; then
		printf '%b  %b' "$(ui_colorize '38;5;183' 'Signal Ready')" "$(ui_colorize '38;5;120' 'Awaiting Input')"
	else
		printf '%s  %s' 'Signal Ready' 'Awaiting Input'
	fi
}

print_arch_panel() {
	local status_raw status_label
	local left_lines right_lines line_count i left_line right_line
	local logo_mode="ascii"
	local logo_file=""
	local matrix_prefix='├ '
	local primary_panel_color='38;5;81'
	local secondary_panel_color='1;37'
	local deck_label_color='38;5;81'
	local deck_item_label_color='1;37'

	status_raw="$(panel_last_status_raw)"
	status_label="$(panel_status_label "$status_raw")"
	logo_file="$(resolved_logo_file)"

	if supports_ansi_logo && [[ -f "$logo_file" ]]; then
		mapfile -t left_lines <"$logo_file"
		logo_mode="ansi-file"
	else
		left_lines=(
			'                    -`'
			$'                   .x+`'
			$'                  `xxz/'
			$'                 `+xxzz:'
			$'                `+xxzzli:'
			$'                -+xxzzli+:'
			$'              `/:-:++xxzli+:'
			$'             `/++++/+++++++:'
			$'            `/++++xxxxxxxxxx:'
			$'           `/+++xxzzlliixxxx/`'
			$'          ./xxzzllii++iillzzx+`'
			$'         .xxzzllii-````/iillzz+`'
			$'        -xzzlliii.      :iillzzx.'
			$'       :xzlliiii/        iillz+++.'
			$'      /xzlliiiiii/        +iillxx/-'
			$'    `/xzzlli+/:-        -:/+iillzx+-'
			$'   `+xlz+:-`                 `.-/+ixz:'
			$'  `++:.                           `-/+/'
			$'  .`                                 `/'
		)
	fi

	if supports_color; then
		right_lines=(
			"$(ui_colorize "$primary_panel_color" 'linux-installer // LINUX')"
			"$(ui_colorize "$secondary_panel_color" '├ Surface       Linux')"
			"$(ui_colorize "$secondary_panel_color" '├ Status Bus    ONLINE')"
			"$(ui_colorize "$secondary_panel_color" '├ Operator      LEUNG315 XZLI')"
			"$(ui_colorize "$secondary_panel_color" '├ Log Stream    ~/.leung/logs')"
			''
			"$(ui_colorize "$primary_panel_color" 'SYSTEM MATRIX // LIVE')"
			"${matrix_prefix}$(ui_colorize "$secondary_panel_color" '├ Claude   ')    $(ui_colorize '38;5;120' '[OK]')"
			"${matrix_prefix}$(ui_colorize "$secondary_panel_color" '├ Codex    ')    $(ui_colorize '38;5;120' '[OK]')"
			"${matrix_prefix}$(ui_colorize "$secondary_panel_color" '├ Gemini   ')    $(ui_colorize '38;5;203' '[--]')"
			''
			"$(ui_colorize "$deck_label_color" 'COMMAND DECK')"
			"$(ui_colorize "$deck_item_label_color" '├ Last Signal    ') $(panel_signal_chip "$status_raw")"
			"$(ui_colorize "$deck_item_label_color" '├ Signal Ready   ') $(ui_colorize '38;5;120' 'Awaiting Input')"
			''
			"$(ui_colorize '38;5;213' "Updated  ${LEUNG_INSTALLER_UPDATED_AT:-unknown} (pin ${LEUNG_INSTALLER_PIN_REF:-unknown})")"
			''
			"$(ui_colorize '38;5;214' '提示：中转令牌不可直接用于官方 API 接口')"
		)
	else
		right_lines=(
			'linux-installer // LINUX'
			'├ Surface       Linux'
			'├ Status Bus    ONLINE'
			'├ Operator      LEUNG315 XZLI'
			'├ Log Stream    ~/.leung/logs'
			''
			'SYSTEM MATRIX // LIVE'
			'├ Claude       [OK]'
			'├ Codex        [OK]'
			'├ Gemini       [--]'
			''
			'COMMAND DECK'
			"├ Last Signal    ${status_label}"
			'├ Signal Ready   Awaiting Input'
			''
			"Updated  ${LEUNG_INSTALLER_UPDATED_AT:-unknown} (pin ${LEUNG_INSTALLER_PIN_REF:-unknown})"
			''
			'提示：中转令牌不可直接用于官方 API 接口'
		)
	fi

	line_count=${#left_lines[@]}
	for ((i = 0; i < line_count; i++)); do
		left_line="${left_lines[$i]}"
		right_line="${right_lines[$i]:-}"
		if [[ "$logo_mode" == "ansi-file" ]]; then
			printf '%s      %b
' "$left_line" "$right_line" >&2
		elif supports_color; then
			printf '[38;5;39m%-36s[0m      %b
' "$left_line" "$right_line" >&2
		else
			printf '%-36s      %s
' "$left_line" "$right_line" >&2
		fi
	done
}

print_main_menu_list() {
	ui_menu_begin "COMMAND DECK" "请选择功能：" "primary"
	ui_menu_item 1 "安装并配置 CLI" "安装 Claude / Codex / Gemini，写入配置并完成基础验证" "primary"
	ui_frame_blank "primary"
	ui_menu_item 2 "查看 CLI 配置详情" "检查路径、URL、API Key 与 model 的当前状态" "primary"
	ui_frame_blank "primary"
	ui_menu_item 3 "验证已安装 CLI" "对目标 CLI 执行基础验证与配置核对" "primary"
	ui_frame_blank "primary"
	ui_menu_item 4 "高级选项" "修改 API Key / URL、重建配置或查看日志" "primary"
	ui_frame_blank "primary"
	ui_menu_item 5 "退出" "结束当前安装会话" "primary"
	ui_frame_blank "primary"
	ui_menu_end "primary"
}
