#!/usr/bin/env bash

LEUNG_CONNECTIVITY_PROBE_PATH="${LEUNG_CONNECTIVITY_PROBE_PATH:-/models}"
LEUNG_CONNECTIVITY_TIMEOUT="${LEUNG_CONNECTIVITY_TIMEOUT:-8}"
LEUNG_CONNECTIVITY_SEND_AUTH="${LEUNG_CONNECTIVITY_SEND_AUTH:-0}"

connectivity_result() {
	local status="$1" code="${2:-}" detail="${3:-}"
	printf '%s|%s|%s\n' "$status" "$code" "$detail"
}

transport_probe_url() {
	local base_url="$1"
	local trimmed="${base_url%/}"
	local path="${LEUNG_CONNECTIVITY_PROBE_PATH:-/models}"
	[[ "$path" == /* ]] || path="/$path"
	printf '%s%s\n' "$trimmed" "$path"
}

connectivity_curl_probe() {
	local url="$1" key="${2:-}"
	local tmp http_code curl_exit curl_config=""
	tmp="$(mktemp)"
	if [[ -n "${LEUNG_CONNECTIVITY_MOCK_RESULT:-}" ]]; then
		printf '%s\n' "$LEUNG_CONNECTIVITY_MOCK_RESULT"
		rm -f "$tmp"
		return 0
	fi
	if [[ -n "$key" ]]; then
		curl_config="$(mktemp)"
		chmod 600 "$curl_config" 2>/dev/null || true
		printf 'header = \"Authorization: Bearer %s\"\n' "$key" >"$curl_config"
		set +e
		http_code="$(curl -sS -K "$curl_config" -o "$tmp" -w '%{http_code}' --connect-timeout "$LEUNG_CONNECTIVITY_TIMEOUT" --max-time "$LEUNG_CONNECTIVITY_TIMEOUT" "$url" 2>>"$LEUNG_LOG_FILE")"
		curl_exit=$?
		set -e
	else
		set +e
		http_code="$(curl -sS -o "$tmp" -w '%{http_code}' --connect-timeout "$LEUNG_CONNECTIVITY_TIMEOUT" --max-time "$LEUNG_CONNECTIVITY_TIMEOUT" "$url" 2>>"$LEUNG_LOG_FILE")"
		curl_exit=$?
		set -e
	fi
	[[ -n "$curl_config" ]] && rm -f "$curl_config"
	if [[ "$curl_exit" -ne 0 ]]; then
		rm -f "$tmp"
		connectivity_result transport_fail "$curl_exit" "curl transport failure"
		return 0
	fi
	rm -f "$tmp"
	case "$http_code" in
	200 | 204)
		connectivity_result pass "$http_code" "reachable and accepted"
		;;
	401 | 403)
		connectivity_result auth_reject "$http_code" "reachable but auth rejected"
		;;
	000)
		connectivity_result transport_fail "$http_code" "empty http code"
		;;
	*)
		connectivity_result http_other "$http_code" "reachable with unexpected HTTP status"
		;;
	esac
}

run_connectivity_probe() {
	local cli="${1:-}" base_url="${2:-}" key="${3:-}" send_auth="${4:-0}"
	local probe_url result status code detail
	[[ -n "$base_url" ]] || {
		log_error "URL 未配置，无法做连通性检查。请先设置默认 URL 或通过 --url 显式传入。"
		return 1
	}
	probe_url="$(transport_probe_url "$base_url")"
	if ! command_exists curl && [[ -z "${LEUNG_CONNECTIVITY_MOCK_RESULT:-}" ]]; then
		log_error "缺少 curl，无法执行连通性检查。"
		return 1
	fi
	if [[ "$send_auth" != "1" ]]; then
		key=""
	fi
	result="$(connectivity_curl_probe "$probe_url" "$key")" || return 1
	IFS='|' read -r status code detail <<<"$result"
	log_info "连通性检查[$cli] status=$status http=$code detail=$detail url=$probe_url auth=$send_auth"
	printf '%s\n' "$result"
}

run_connectivity_check_for_cli() {
	local cli="$1"
	local base_url key result status code detail
	base_url="$(get_effective_provider_url "$cli")"
	key="$(get_cli_key "$cli" 2>/dev/null || true)"
	result="$(run_connectivity_probe "$cli" "$base_url" "$key" "$LEUNG_CONNECTIVITY_SEND_AUTH")" || return 1
	IFS='|' read -r status code detail <<<"$result"
	case "$status" in
	pass)
		ui_success_box "连通性检查通过" "$(cli_display_name "$cli") 的 URL 可访问，状态：$code"
		;;
	auth_reject)
		ui_info_box "$(cli_display_name "$cli") 的 URL 可访问，但认证被拒绝（$code）。这通常表示网络通，Key 或权限需确认。"
		;;
	transport_fail)
		ui_failure_box "连通性检查失败" "$(cli_display_name "$cli") 的 URL 不可达，请检查 DNS/TLS/代理。"
		;;
	*)
		ui_info_box "$(cli_display_name "$cli") 的 URL 已连通，但返回了非预期状态：$code"
		;;
	esac
}

verify_connectivity_result_for_cli() {
	local cli="$1" base_url="$2" key="$3" send_auth="${4:-0}"
	local result status code detail
	result="$(run_connectivity_probe "$cli" "$base_url" "$key" "$send_auth")" || return 1
	IFS='|' read -r status code detail <<<"$result"
	case "$status" in
	pass | auth_reject | http_other)
		return 0
		;;
	*)
		log_error "$cli 连通性检查失败: status=$status http=$code detail=$detail"
		return 1
		;;
	esac
}
