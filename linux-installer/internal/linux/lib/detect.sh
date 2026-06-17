#!/usr/bin/env bash

detect_package_manager() {
	local candidates=(apt-get dnf5 dnf microdnf tdnf yum apk pacman zypper)
	local candidate
	for candidate in "${candidates[@]}"; do
		if command_exists "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

detect_distribution() {
	if [[ -f /etc/os-release ]]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		printf '%s\n' "${PRETTY_NAME:-${NAME:-Linux}}"
	else
		printf 'Linux\n'
	fi
}

cluster_guard_enforce() {
	require_python || return 1
	local output
	output="$(python3 "$LEUNG_BIN_DIR/config_helper.py" cluster-check "$LEUNG_CONFIG_FILE" 2>>"$LEUNG_LOG_FILE")" || {
		log_error "内网环境检测失败。"
		return 1
	}
	if [[ "$output" == BLOCK:* ]]; then
		log_error "检测到内网环境: ${output#BLOCK:}"
		return 1
	fi
	log_info "内网环境检测通过。"
	return 0
}
