#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC2034
LEUNG_MANIFEST_DIR="$SCRIPT_DIR/manifests"
load_download_manifest || true
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck source=lib/deps.sh
source "$SCRIPT_DIR/lib/deps.sh"
# shellcheck source=lib/node.sh
source "$SCRIPT_DIR/lib/node.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/connectivity.sh
source "$SCRIPT_DIR/lib/connectivity.sh"
# shellcheck source=lib/installers.sh
source "$SCRIPT_DIR/lib/installers.sh"
# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/flows.sh
source "$SCRIPT_DIR/lib/flows.sh"

NONINTERACTIVE_CLI="${NONINTERACTIVE_CLI:-}"
NONINTERACTIVE_API_KEY="${NONINTERACTIVE_API_KEY:-}"
NONINTERACTIVE_URL="${NONINTERACTIVE_URL:-}"
NONINTERACTIVE_ACTION="${NONINTERACTIVE_ACTION:-install}"
NONINTERACTIVE_CLEAR_CACHE="${NONINTERACTIVE_CLEAR_CACHE:-0}"
NONINTERACTIVE_REFRESH_INSTALLER="${NONINTERACTIVE_REFRESH_INSTALLER:-0}"
NONINTERACTIVE_CONNECTIVITY_SEND_AUTH="${NONINTERACTIVE_CONNECTIVITY_SEND_AUTH:-0}"
LEUNG_INSTALL_ONLY="${LEUNG_INSTALL_ONLY:-0}"

usage() {
	cat <<'EOF'
Usage:
  bash install.sh
  bash install.sh --noninteractive --cli codex --api-key sk-xxx
  bash install.sh --noninteractive --cli gemini --api-key sk-xxx --url https://custom.example/v1

Options:
  --dry-run
  --noninteractive
  --cli <claude|codex|gemini>
  --api-key <value>
  --url <value>    目标 CLI 的 URL；未提供时使用该 CLI 的默认 URL
  --check-connectivity
  --check-connectivity-with-auth
  --skip-deps
  --install-only            只安装 CLI 程序本体，不写 URL / API Key / model
  --test-mode               写入内置测试配置跑完整流程，随后自动回滚
  --keep-test-config
  --clear-cache
  --refresh-installer
EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dry-run)
			LEUNG_DRY_RUN=1
			;;
		--noninteractive)
			LEUNG_NONINTERACTIVE=1
			;;
		--skip-deps)
			LEUNG_SKIP_DEPS=1
			;;
		--install-only)
			LEUNG_INSTALL_ONLY=1
			;;
		--test-mode)
			LEUNG_TEST_MODE=1
			;;
		--keep-test-config)
			LEUNG_KEEP_TEST_CONFIG=1
			;;
		--cli)
			NONINTERACTIVE_CLI="${2:-}"
			shift
			;;
		--api-key)
			NONINTERACTIVE_API_KEY="${2:-}"
			shift
			;;
		--url)
			NONINTERACTIVE_URL="${2:-}"
			shift
			;;
		--clear-cache)
			NONINTERACTIVE_CLEAR_CACHE=1
			;;
		--refresh-installer)
			NONINTERACTIVE_REFRESH_INSTALLER=1
			;;
		--check-connectivity)
			NONINTERACTIVE_ACTION="connectivity"
			;;
		--check-connectivity-with-auth)
			NONINTERACTIVE_ACTION="connectivity"
			NONINTERACTIVE_CONNECTIVITY_SEND_AUTH=1
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			printf 'Unknown option: %s\n' "$1" >&2
			usage >&2
			exit 1
			;;
		esac
		shift
	done
}

main_menu_loop() {
	while true; do
		ui_main_menu
		case "$UI_MENU_RESULT" in
		install)
			run_interactive_menu_action "安装流程" run_install_entry_flow
			;;
		details)
			run_interactive_menu_action "查看 CLI 配置详情" show_cli_config_details_flow
			;;
		verify)
			run_interactive_menu_action "验证已安装 CLI" verify_installed_cli_flow
			;;
		advanced)
			run_interactive_menu_action "高级选项" configure_advanced_flow
			;;
		exit | *)
			break
			;;
		esac
	done
}

main() {
	parse_args "$@"
	init_installer_context "$SCRIPT_DIR"
	ensure_leung_directories
	if [[ "$LEUNG_NONINTERACTIVE" == "1" ]]; then
		trap 'on_error_trap $?' ERR
	fi
	init_logging
	maybe_inject_failure "after_init_logging"
	bootstrap_ui_dependencies
	if ! command -v python3 >/dev/null 2>&1; then
		if [[ "$LEUNG_SKIP_DEPS" == "1" ]]; then
			printf '[ERROR] 缺少 python3，且当前启用了 --skip-deps，无法自动补齐依赖。请先安装 python3，或去掉 --skip-deps 后重试。\n' >&2
			return 1
		fi
		printf '[INFO] 检测到缺少 python3，先尝试自动安装基础依赖...\n' >&2
		ensure_system_dependencies
	fi
	ensure_installer_config
	if [[ "$LEUNG_NONINTERACTIVE" == "1" ]]; then
		run_noninteractive_flow
		return
	fi
	ui_show_startup
	main_menu_loop
}

main "$@"
