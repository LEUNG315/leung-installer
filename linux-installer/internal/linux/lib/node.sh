#!/usr/bin/env bash

LEUNG_GITHUB_PROXY_BASE="${LEUNG_GITHUB_PROXY_BASE:-https://ghproxy.net/}"
LEUNG_GITHUB_RAW_BASE="${LEUNG_GITHUB_RAW_BASE:-https://raw.githubusercontent.com}"
LEUNG_GITHUB_RAW_MIRROR_BASE="${LEUNG_GITHUB_RAW_MIRROR_BASE:-}"
LEUNG_NVM_INSTALL_URL="${LEUNG_NVM_INSTALL_URL:-}"
LEUNG_NVM_INSTALL_MIRROR_URL="${LEUNG_NVM_INSTALL_MIRROR_URL:-}"
LEUNG_NODE_MIRROR="${LEUNG_NODE_MIRROR:-${NVM_NODEJS_ORG_MIRROR:-}}"
LEUNG_NODE_MIRROR_FALLBACK="${LEUNG_NODE_MIRROR_FALLBACK:-https://npmmirror.com/mirrors/node}"
LEUNG_NVM_VERSION="${LEUNG_NVM_VERSION:-${LEUNG_MANIFEST_NVM_VERSION:-v0.40.4}}"
LEUNG_NVM_INSTALL_SHA256="${LEUNG_NVM_INSTALL_SHA256:-${LEUNG_MANIFEST_NVM_INSTALL_SHA256:-4b7412c49960c7d31e8df72da90c1fb5b8cccb419ac99537b737028d497aba4f}}"

nvm_dir() {
	printf '%s\n' "$LEUNG_NVM_DIR"
}

nvm_install_looks_usable() {
	local dir="${1:-}"
	[[ -n "$dir" && -s "$dir/nvm.sh" ]] || return 1
	bash -c '. "$1/nvm.sh" >/dev/null 2>&1 && command -v nvm >/dev/null 2>&1' _ "$dir"
}

system_node_matches() {
	command -v node >/dev/null 2>&1 || return 1
	command -v npm >/dev/null 2>&1 || return 1
	local major
	major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
	[[ "$major" == "$LEUNG_NODE_VERSION" ]]
}

ensure_system_prefix_layout() {
	mkdir -p "$LEUNG_NPM_GLOBAL_PREFIX/bin" "$LEUNG_NPM_GLOBAL_PREFIX/lib"
}

fish_config_dir() {
	if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
		printf '%s\n' "$XDG_CONFIG_HOME/fish/conf.d"
	else
		printf '%s\n' "$HOME/.config/fish/conf.d"
	fi
}

ensure_system_path_profile_block() {
	[[ "$LEUNG_TEST_MODE" == "1" ]] && return 0
	local profiles=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
	local profile
	local block_start='# >>> LEUNG installer npm path >>>'
	local block_end='# <<< LEUNG installer npm path <<<'
	for profile in "${profiles[@]}"; do
		if [[ ! -f "$profile" ]]; then
			touch "$profile"
			record_transaction created_file "$profile"
		fi
		if ! grep -Fq "$block_start" "$profile"; then
			cat >>"$profile" <<EOF2

$block_start
export PATH="\$HOME/.local/share/leung-node-global/bin:\$PATH"
$block_end
EOF2
			record_transaction profile_block "$profile" "$block_start" "$block_end"
		fi
	done

	local fish_dir fish_file fish_start='# >>> LEUNG installer npm path >>>' fish_end='# <<< LEUNG installer npm path <<<'
	fish_dir="$(fish_config_dir)"
	fish_file="$fish_dir/leung_node_path.fish"
	mkdir -p "$fish_dir"
	if [[ ! -f "$fish_file" ]]; then
		: >"$fish_file"
		record_transaction created_file "$fish_file"
	fi
	if ! grep -Fq "$fish_start" "$fish_file"; then
		cat >>"$fish_file" <<EOF2
$fish_start
if not contains -- "\$HOME/.local/share/leung-node-global/bin" \$fish_user_paths
    set -Ua fish_user_paths "\$HOME/.local/share/leung-node-global/bin"
end
$fish_end
EOF2
		record_transaction profile_block "$fish_file" "$fish_start" "$fish_end"
	fi
}

activate_system_prefix_path() {
	case ":$PATH:" in
	*":$LEUNG_NPM_GLOBAL_PREFIX/bin:"*) ;;
	*) export PATH="$LEUNG_NPM_GLOBAL_PREFIX/bin:$PATH" ;;
	esac
}

source_nvm() {
	local dir
	dir="$(nvm_dir)"
	export NVM_DIR="$dir"
	if nvm_install_looks_usable "$dir"; then
		# shellcheck disable=SC1090
		# shellcheck disable=SC1091
		. "$dir/nvm.sh"
	else
		return 1
	fi
}

nvm_exec() {
	local mirror="${1:-}"
	shift || true
	local script_file=""
	script_file="$(mktemp "${TMPDIR:-/tmp}/leung-nvm-exec.XXXXXX")"
	cat >"$script_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export NVM_DIR="$1"
mirror="$2"
shift 2
if [[ -n "$mirror" ]]; then
	export NVM_NODEJS_ORG_MIRROR="$mirror"
fi
. "$NVM_DIR/nvm.sh"
"$@"
EOF
	chmod 700 "$script_file"
	if [[ -n "${LEUNG_LOG_FILE:-}" ]]; then
		"$script_file" "$LEUNG_NVM_DIR" "$mirror" "$@" >>"$LEUNG_LOG_FILE" 2>&1
	else
		"$script_file" "$LEUNG_NVM_DIR" "$mirror" "$@" >&2
	fi
	local status=$?
	rm -f "$script_file"
	return $status
}

ensure_nvm_profile_block() {
	[[ "$LEUNG_TEST_MODE" == "1" ]] && return 0
	local profiles=("$HOME/.bashrc" "$HOME/.zshrc")
	local profile block_start='# >>> LEUNG installer nvm >>>' block_end='# <<< LEUNG installer nvm <<<'
	for profile in "${profiles[@]}"; do
		if [[ ! -f "$profile" ]]; then
			touch "$profile"
			record_transaction created_file "$profile"
		fi
		if ! grep -Fq "$block_start" "$profile"; then
			cat >>"$profile" <<EOF2

$block_start
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
$block_end
EOF2
			record_transaction profile_block "$profile"
		fi
	done

	local fish_dir fish_file fish_start='# >>> LEUNG installer nvm notice >>>' fish_end='# <<< LEUNG installer nvm notice <<<'
	fish_dir="$(fish_config_dir)"
	fish_file="$fish_dir/leung_nvm_notice.fish"
	mkdir -p "$fish_dir"
	if [[ ! -f "$fish_file" ]]; then
		: >"$fish_file"
		record_transaction created_file "$fish_file"
	fi
	if ! grep -Fq "$fish_start" "$fish_file"; then
		cat >>"$fish_file" <<EOF2
$fish_start
# LEUNG installer 使用 bash/zsh 的 nvm 初始化脚本。
# 如需在 fish 中使用 nvm 安装的 Node，请考虑安装 fish 兼容的 nvm 封装，或重新登录 bash/zsh 后再运行 CLI。
$fish_end
EOF2
		record_transaction profile_block "$fish_file" "$fish_start" "$fish_end"
	fi
}

install_nvm() {
	local install_url="" mirror_install_url="" script_path=""
	local dir
	dir="$(nvm_dir)"
	if nvm_install_looks_usable "$dir"; then
		log_info "检测到已有 nvm，跳过 nvm 安装脚本。"
		return 0
	fi
	if [[ -e "$dir/nvm.sh" ]]; then
		log_warn "检测到现有 nvm 安装不完整或不可用：$dir/nvm.sh；将尝试重新安装 nvm。"
	fi
	validate_nvm_version "$LEUNG_NVM_VERSION" || {
		log_error "LEUNG_NVM_VERSION 非法: $LEUNG_NVM_VERSION"
		return 1
	}
	validate_sha256 "$LEUNG_NVM_INSTALL_SHA256" || {
		log_error "LEUNG_NVM_INSTALL_SHA256 非法。"
		return 1
	}
	log_info "安装 nvm $LEUNG_NVM_VERSION"
	ensure_nvm_profile_block
	if [[ -n "$LEUNG_NVM_INSTALL_URL" ]]; then
		install_url="$LEUNG_NVM_INSTALL_URL"
	else
		install_url="${LEUNG_GITHUB_RAW_BASE%/}/nvm-sh/nvm/${LEUNG_NVM_VERSION}/install.sh"
	fi
	if [[ -n "$LEUNG_NVM_INSTALL_MIRROR_URL" ]]; then
		mirror_install_url="$LEUNG_NVM_INSTALL_MIRROR_URL"
	elif [[ -n "$LEUNG_GITHUB_RAW_MIRROR_BASE" ]]; then
		mirror_install_url="${LEUNG_GITHUB_RAW_MIRROR_BASE%/}/nvm-sh/nvm/${LEUNG_NVM_VERSION}/install.sh"
	else
		mirror_install_url="$(github_proxy_wrap_url "$LEUNG_GITHUB_PROXY_BASE" "$install_url" 2>/dev/null || true)"
	fi
	if [[ "$LEUNG_DRY_RUN" == "1" ]]; then
		run_logged echo "download nvm install script -> verify sha256 -> bash $install_url"
	else
		script_path="$(mktemp "${TMPDIR:-/tmp}/nvm-install.sh.XXXXXX")"
		record_transaction created_file "$script_path"
		# Check bundle first (nvm-install.sh)
		if copy_bundled_download_if_valid "nvm install script" "nvm-install.sh" "$script_path" "$LEUNG_NVM_INSTALL_SHA256"; then
			log_info "nvm install script loaded from bundle."
		else
			download_and_verify_file "nvm install script" "$install_url" "$mirror_install_url" "$script_path" "$LEUNG_NVM_INSTALL_SHA256" || return 1
		fi
		chmod 700 "$script_path"
		run_logged env NVM_DIR="$LEUNG_NVM_DIR" bash "$script_path"
		rm -f "$script_path"
	fi
}

ensure_nvm_and_node() {
	validate_node_version "$LEUNG_NODE_VERSION" || {
		log_error "LEUNG_NODE_VERSION 非法: $LEUNG_NODE_VERSION"
		return 1
	}
	if [[ "$LEUNG_DRY_RUN" == "1" ]]; then
		log_info "[DRY-RUN] 跳过真实 nvm/node 安装，模拟使用 Node.js $LEUNG_NODE_VERSION"
		ensure_nvm_profile_block
		LEUNG_NODE_RUNTIME="dry-run"
		return 0
	fi
	# Check if system already has matching Node.js
	if system_node_matches; then
		log_info "检测到现有 Node.js $LEUNG_NODE_VERSION / npm，可直接复用，跳过 nvm 安装。"
		ensure_system_prefix_layout
		ensure_system_path_profile_block
		activate_system_prefix_path
		LEUNG_NODE_RUNTIME="system"
		return 0
	fi
	# Try bundle-based Node.js install (works offline)
	if install_node_from_bundle 2>/dev/null; then
		if system_node_matches; then
			log_info "Node.js installed from bundle, using system mode."
			ensure_system_prefix_layout
			ensure_system_path_profile_block
			activate_system_prefix_path
			LEUNG_NODE_RUNTIME="system"
			return 0
		fi
	fi
	# Fall through to nvm-based install (requires network)
	if source_nvm; then
		LEUNG_NODE_RUNTIME="nvm"
	else
		install_nvm
		source_nvm
		# shellcheck disable=SC2034
		LEUNG_NODE_RUNTIME="nvm"
	fi
	if nvm_exec "" nvm version "$LEUNG_NODE_VERSION"; then
		run_logged env LEUNG_NVM_DIR="$LEUNG_NVM_DIR" bash -c '. "$LEUNG_NVM_DIR/nvm.sh"; nvm alias default "$1"; nvm use "$1"' _ "$LEUNG_NODE_VERSION"
		return 0
	fi
	if ! nvm_exec "$LEUNG_NODE_MIRROR" bash -c 'nvm install "$1"; nvm alias default "$1"; nvm use "$1"' _ "$LEUNG_NODE_VERSION"; then
		if [[ -n "$LEUNG_NODE_MIRROR_FALLBACK" && "$LEUNG_NODE_MIRROR_FALLBACK" != "$LEUNG_NODE_MIRROR" ]]; then
			log_warn "Node 官方源失败，切换镜像重试：$LEUNG_NODE_MIRROR_FALLBACK"
			retry_logged "nvm install node (mirror)" nvm_exec "$LEUNG_NODE_MIRROR_FALLBACK" bash -c 'nvm install "$1"; nvm alias default "$1"; nvm use "$1"' _ "$LEUNG_NODE_VERSION"
		else
			log_error "Node 安装失败，且未配置镜像回退。"
			return 1
		fi
	fi
}
