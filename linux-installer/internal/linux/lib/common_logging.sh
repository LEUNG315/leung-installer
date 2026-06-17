#!/usr/bin/env bash

log_info() {
	if [[ -n "${LEUNG_LOG_FILE:-}" ]]; then
		printf '[INFO] %s\n' "$*" | tee -a "$LEUNG_LOG_FILE" >&2
	else
		printf '[INFO] %s\n' "$*" >&2
	fi
}

log_warn() {
	if [[ -n "${LEUNG_LOG_FILE:-}" ]]; then
		printf '[WARN] %s\n' "$*" | tee -a "$LEUNG_LOG_FILE" >&2
	else
		printf '[WARN] %s\n' "$*" >&2
	fi
}

log_error() {
	LEUNG_LAST_ERROR="$*"
	if [[ -n "${LEUNG_LOG_FILE:-}" ]]; then
		printf '[ERROR] %s\n' "$*" | tee -a "$LEUNG_LOG_FILE" >&2
	else
		printf '[ERROR] %s\n' "$*" >&2
	fi
}

record_transaction() {
	local kind="$1"
	shift
	[[ -n "$LEUNG_TRANSACTION_FILE" ]] || return 0
	python3 - "$LEUNG_TRANSACTION_FILE" "$kind" "$@" <<'PY'
import json, sys
path = sys.argv[1]
kind = sys.argv[2]
fields = sys.argv[3:]
payload = {"kind": kind, "fields": fields}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(payload, ensure_ascii=False) + "\n")
PY
}

maybe_inject_failure() {
	local token="$1"
	[[ -n "${LEUNG_FAIL_AT:-}" && "${LEUNG_FAIL_AT:-}" == "$token" ]] || return 0
	log_error "注入失败点触发: $token"
	return 1
}

write_summary() {
	local status="$1"
	local cli="${2:-}"
	local extra="${3:-}"
	cat >"$LEUNG_SUMMARY_FILE" <<EOF
状态: $status
CLI: ${cli:-N/A}
最后步骤: ${LEUNG_CURRENT_STEP:-N/A}
日志: $LEUNG_LOG_FILE
${extra}
EOF
	chmod 600 "$LEUNG_SUMMARY_FILE" || true
}

write_success_summary() {
	local cli="${1:-}"
	local detail="${2:-已完成安装、配置与基础验证。}"
	write_summary "成功" "$cli" "说明: $detail"
}

mask_secret() {
	local value="${1:-}"
	local len=${#value}
	if ((len == 0)); then
		printf ''
	elif ((len <= 8)); then
		printf '****'
	else
		printf '%s****%s' "${value:0:4}" "${value: -4}"
	fi
}

is_test_key() {
	[[ -n "${1:-}" && "$1" == "$LEUNG_TEST_API_KEY" ]]
}

display_secret_label() {
	local value="${1:-}"
	if is_test_key "$value"; then
		printf '%s' '内置测试 Key'
		return 0
	fi
	mask_secret "$value"
}

