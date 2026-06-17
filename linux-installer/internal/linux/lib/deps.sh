#!/usr/bin/env bash

pkg_list_for_manager() {
	local manager="$1"
	case "$manager" in
	apt-get)
		printf '%s\n' curl git ca-certificates python3 tar xz-utils build-essential
		;;
	dnf5 | dnf | microdnf | tdnf | yum)
		printf '%s\n' curl git ca-certificates python3 tar xz gcc gcc-c++ make
		;;
	apk)
		printf '%s\n' curl git ca-certificates python3 tar xz build-base
		;;
	pacman)
		printf '%s\n' curl git ca-certificates python tar xz base-devel
		;;
	zypper)
		printf '%s\n' curl git-core ca-certificates python3 tar xz gcc gcc-c++ make
		;;
	*)
		return 1
		;;
	esac
}

install_packages() {
	local manager="$1"
	shift
	local packages=("$@")
	[[ ${#packages[@]} -gt 0 ]] || return 0

	log_info "使用 $manager 安装依赖: ${packages[*]}"
	case "$manager" in
	apt-get)
		retry_logged "apt-get update" run_as_root apt-get update
		retry_logged "apt-get install" run_as_root apt-get install -y "${packages[@]}"
		;;
	dnf5)
		retry_logged "dnf5 install" run_as_root dnf5 install -y "${packages[@]}"
		;;
	dnf)
		retry_logged "dnf install" run_as_root dnf install -y "${packages[@]}"
		;;
	microdnf)
		retry_logged "microdnf install" run_as_root microdnf install -y "${packages[@]}"
		;;
	tdnf)
		retry_logged "tdnf install" run_as_root tdnf install -y "${packages[@]}"
		;;
	yum)
		retry_logged "yum install" run_as_root yum install -y "${packages[@]}"
		;;
	apk)
		retry_logged "apk add" run_as_root apk add --no-cache "${packages[@]}"
		;;
	pacman)
		retry_logged "pacman install" run_as_root pacman -Sy --noconfirm --needed "${packages[@]}"
		;;
	zypper)
		retry_logged "zypper install" run_as_root zypper --non-interactive install --no-confirm "${packages[@]}"
		;;
	*)
		log_error "不支持的包管理器: $manager"
		return 1
		;;
	esac
}

bootstrap_ui_dependencies() {
	# shellcheck disable=SC2034
	LEUNG_UI_MODE="tty"
	return 0
}

have_minimum_system_dependencies() {
	local required=(curl git tar xz python3)
	local cmd
	for cmd in "${required[@]}"; do
		command -v "$cmd" >/dev/null 2>&1 || return 1
	done
	return 0
}

ensure_system_dependencies() {
	[[ "$LEUNG_SKIP_DEPS" == "1" ]] && {
		log_info '按要求跳过系统依赖安装。'
		return 0
	}
	if have_minimum_system_dependencies; then
		log_info '检测到基础系统依赖已满足，跳过包管理器安装。'
		return 0
	fi
	local manager
	local packages=()
	manager="$(detect_package_manager)" || {
		log_error '未识别到支持的包管理器。'
		return 1
	}
	while IFS= read -r pkg; do
		[[ -n "$pkg" ]] && packages+=("$pkg")
	done < <(pkg_list_for_manager "$manager")
	install_packages "$manager" "${packages[@]}"
}
