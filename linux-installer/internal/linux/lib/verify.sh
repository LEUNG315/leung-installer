#!/usr/bin/env bash

verify_cli_expected_url() {
	local cli="$1"
	local url=""
	url="$(get_effective_provider_url "$cli")"
	[[ -n "$url" ]] || {
		log_error "$cli 未找到有效 URL"
		return 1
	}
	validate_url "$url" || {
		log_error "$cli 的 URL 格式不合法: $url"
		return 1
	}
	printf '%s\n' "$url"
}

verify_cli_expected_key() {
	local cli="$1"
	local key=""
	key="$(get_cli_key "$cli")"
	[[ -n "$key" ]] || {
		log_error "$cli 未找到有效 API Key"
		return 1
	}
	printf '%s\n' "$key"
}

verify_cli_expected_model() {
	local cli="$1"
	local model=""
	model="$(get_model_name "$cli")"
	[[ -n "$model" ]] || {
		log_error "$cli 未找到有效 model"
		return 1
	}
	printf '%s\n' "$model"
}

cli_native_config_model_optional() {
	[[ "$(cli_registry_get "$1" native_model_optional 2>/dev/null || true)" == "1" ]]
}

extract_cli_config_value() {
	local kind="$1" cli="$2"
	local source=""
	source="$(cli_value_source_path "$cli" "$kind" 2>/dev/null || true)"
	[[ -n "$source" ]] || {
		log_error "未知 CLI 或未知字段: $cli/$kind"
		return 1
	}
	require_python || return 1
	python3 "$LEUNG_BIN_DIR/config_helper.py" "extract-${cli}-${kind}" "$source"
}

assert_equal_or_fail() {
	local label="$1" expected="$2" actual="$3"
	if [[ "$expected" != "$actual" ]]; then
		log_error "$label 不匹配。expected=[$expected] actual=[$actual]"
		return 1
	fi
}

verify_cli_config_values() {
	local cli="$1"
	local expected_url expected_key expected_model actual_url actual_key actual_model
	expected_url="$(verify_cli_expected_url "$cli")" || return 1
	expected_key="$(verify_cli_expected_key "$cli")" || return 1
	expected_model="$(verify_cli_expected_model "$cli")" || return 1

	actual_url="$(extract_cli_config_value url "$cli")" || return 1
	actual_key="$(extract_cli_config_value key "$cli")" || return 1
	actual_model="$(extract_cli_config_value model "$cli")" || return 1

	[[ -n "$actual_url" ]] || {
		log_error "$cli 配置文件中缺少 URL"
		return 1
	}
	[[ -n "$actual_key" ]] || {
		log_error "$cli 配置文件中缺少 API Key"
		return 1
	}

	validate_url "$actual_url" || {
		log_error "$cli 配置文件中的 URL 格式不合法: $actual_url"
		return 1
	}
	assert_equal_or_fail "$cli URL" "$expected_url" "$actual_url" || return 1
	assert_equal_or_fail "$cli API Key" "$expected_key" "$actual_key" || return 1
	if [[ -n "$actual_model" ]]; then
		assert_equal_or_fail "$cli model" "$expected_model" "$actual_model" || return 1
	elif ! cli_native_config_model_optional "$cli"; then
		log_error "$cli 配置文件中缺少 model"
		return 1
	fi
}

verify_cli_binary() {
	local cli="$1"
	local binary
	local resolved_binary=""
	binary="$(binary_name_for_cli "$cli")"
	if [[ "$cli" == "codex" && "${LEUNG_CODEX_FALLBACK_BINARY:-0}" == "1" ]]; then
		if command -v codex_install_target_path >/dev/null 2>&1; then
			resolved_binary="$(codex_install_target_path 2>/dev/null || true)"
		fi
		if [[ -n "$resolved_binary" && -x "$resolved_binary" ]]; then
			run_logged "$resolved_binary" --version
			return 0
		fi
		log_error "Codex fallback 已安装，但当前未找到可执行文件路径。"
		return 1
	elif [[ "$LEUNG_NODE_RUNTIME" == "system" && -x "$LEUNG_NPM_GLOBAL_PREFIX/bin/$binary" ]]; then
		run_logged "$LEUNG_NPM_GLOBAL_PREFIX/bin/$binary" --version
	elif ! command_exists "$binary" && [[ "$LEUNG_NODE_RUNTIME" != "system" ]]; then
		nvm_run_logged "" "$binary" --version
	else
		run_logged "$binary" --version
	fi
}

verify_cli_config_only() {
	local cli="$1"
	local primary="" secondary=""
	primary="$(primary_cli_config_path "$cli" 2>/dev/null || true)"
	secondary="$(secondary_cli_config_path "$cli" 2>/dev/null || true)"
	[[ -f "$primary" ]] || {
		log_error "缺少 $(cli_display_name "$cli") 配置文件"
		return 1
	}
	if [[ -n "$secondary" && ! -f "$secondary" ]]; then
		log_error "缺少 $(cli_display_name "$cli") 附加配置文件"
		return 1
	fi
}

verify_cli_config_sync() {
	local cli="$1"
	verify_cli_config_only "$cli" || return 1
	verify_cli_config_values "$cli" || return 1
}

build_cli_connectivity_warning() {
	local cli="$1" code="$2" detail="$3"
	printf '%s 已完成本地安装与配置，但远端连通性验证未通过：status=transport_fail http=%s detail=%s。请检查 URL、DNS、TLS 或代理后，再执行“验证已安装 CLI”。\n' \
		"$cli" "$code" "$detail"
}

verify_cli_setup() {
	local cli="$1" connectivity_mode="${2:-strict}"
	if [[ "$LEUNG_DRY_RUN" == "1" ]]; then
		log_info "[DRY-RUN] 跳过 $cli 的真实版本校验，仅检查流程连通性。"
		return 0
	fi
	LEUNG_POST_INSTALL_WARNING=""
	verify_cli_config_only "$cli" || return 1
	verify_cli_config_values "$cli" || return 1
	verify_cli_binary "$cli" || return 1
	verify_cli_connectivity "$cli" "$connectivity_mode" || return 1
}

verify_cli_connectivity() {
	local cli="$1" mode="${2:-strict}"
	local result status code detail
	result="$(run_connectivity_probe "$cli" "$(get_effective_provider_url "$cli")" "$(get_cli_key "$cli" 2>/dev/null || true)" "1")" || return 1
	IFS='|' read -r status code detail <<<"$result"
	case "$status" in
	pass | auth_reject | http_other)
		return 0
		;;
	*)
		if [[ "$mode" == "warn" ]]; then
			LEUNG_POST_INSTALL_WARNING="$(build_cli_connectivity_warning "$cli" "$code" "$detail")"
			log_warn "$LEUNG_POST_INSTALL_WARNING"
			return 0
		fi
		log_error "$cli 连通性验证失败: status=$status http=$code detail=$detail"
		return 1
		;;
	esac
}
