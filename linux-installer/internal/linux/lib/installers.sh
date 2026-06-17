#!/usr/bin/env bash

LEUNG_NPM_REGISTRY="${LEUNG_NPM_REGISTRY:-}"
LEUNG_NPM_REGISTRY_MIRROR="${LEUNG_NPM_REGISTRY_MIRROR:-https://registry.npmmirror.com}"
LEUNG_GITHUB_PROXY_BASE="${LEUNG_GITHUB_PROXY_BASE:-https://ghproxy.net/}"
LEUNG_GITHUB_RELEASE_BASE="${LEUNG_GITHUB_RELEASE_BASE:-https://github.com}"
LEUNG_GITHUB_RELEASE_MIRROR_BASE="${LEUNG_GITHUB_RELEASE_MIRROR_BASE:-}"
LEUNG_CODEX_FALLBACK_BINARY="${LEUNG_CODEX_FALLBACK_BINARY:-0}"
LEUNG_CODEX_FALLBACK_TAG="${LEUNG_CODEX_FALLBACK_TAG:-${LEUNG_MANIFEST_CODEX_FALLBACK_TAG:-rust-v0.130.0}}"
LEUNG_CODEX_FALLBACK_SHA256_X86_64="${LEUNG_CODEX_FALLBACK_SHA256_X86_64:-${LEUNG_MANIFEST_CODEX_FALLBACK_SHA256_X86_64:-16779e7b7857508a768a36d7d4e084eec336ec23946ed70a9b09489b8f861190}}"
LEUNG_CODEX_FALLBACK_SHA256_AARCH64="${LEUNG_CODEX_FALLBACK_SHA256_AARCH64:-${LEUNG_MANIFEST_CODEX_FALLBACK_SHA256_AARCH64:-1d7e00f2c22c3016b5bcb71c61010947b022a90e2901bc6baafe82256492c767}}"

npm_package_for_cli() {
	cli_registry_get "$1" npm_package
}

binary_name_for_cli() {
	cli_registry_get "$1" binary_name
}

assert_known_cli() {
	npm_package_for_cli "$1" >/dev/null
}

local_proxy_url_unreachable() {
	local url="$1"
	local host="" port=""
	[[ -n "$url" && "$url" != "null" ]] || return 1
	if [[ "$url" =~ ^https?://(127\.0\.0\.1|localhost):([0-9]+) ]]; then
		host="${BASH_REMATCH[1]}"
		port="${BASH_REMATCH[2]}"
		if command -v timeout >/dev/null 2>&1; then
			if timeout 1 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" >/dev/null 2>&1; then
				return 1
			fi
		else
			if bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" >/dev/null 2>&1; then
				return 1
			fi
		fi
		return 0
	fi
	return 1
}

nvm_run_logged() {
	local mirror="${1:-}"
	shift || true
	local script_file=""
	script_file="$(mktemp "${TMPDIR:-/tmp}/leung-nvm-run.XXXXXX")"
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
nvm use "$1" >/dev/null
shift
"$@"
EOF
	chmod 700 "$script_file"
	"$script_file" "$LEUNG_NVM_DIR" "$mirror" "$LEUNG_NODE_VERSION" "$@"
	local status=$?
	rm -f "$script_file"
	return $status
}

npm_env_with_cache() {
	printf '%s\n' "npm_config_cache=$(npm_cache_dir)"
}

npm_config_get_for_runtime() {
	local key="$1"
	if [[ "$LEUNG_NODE_RUNTIME" == "system" ]]; then
		npm config get "$key" 2>/dev/null || true
	else
		nvm_run_logged "" npm config get "$key" 2>/dev/null || true
	fi
}

npm_config_delete_for_runtime() {
	local key="$1"
	if [[ "$LEUNG_NODE_RUNTIME" == "system" ]]; then
		npm config delete "$key" >>"$LEUNG_LOG_FILE" 2>&1 || true
	else
		nvm_run_logged "" npm config delete "$key" >>"$LEUNG_LOG_FILE" 2>&1 || true
	fi
}

npm_proxy_auto_repair_if_needed() {
	local proxy="" https_proxy=""
	proxy="$(npm_config_get_for_runtime proxy)"
	https_proxy="$(npm_config_get_for_runtime https-proxy)"
	if local_proxy_url_unreachable "$proxy"; then
		log_warn "检测到 npm proxy 指向不可用的本地代理：$proxy，正在自动清理该配置。"
		npm_config_delete_for_runtime proxy
	fi
	if local_proxy_url_unreachable "$https_proxy"; then
		log_warn "检测到 npm https-proxy 指向不可用的本地代理：$https_proxy，正在自动清理该配置。"
		npm_config_delete_for_runtime https-proxy
	fi
	return 0
}

npm_proxy_override_env() {
	local proxy="" https_proxy=""
	proxy="$(npm_config_get_for_runtime proxy)"
	https_proxy="$(npm_config_get_for_runtime https-proxy)"
	if local_proxy_url_unreachable "$proxy" || local_proxy_url_unreachable "$https_proxy"; then
		log_warn "检测到 npm 本地代理配置不可用，将在本次安装中临时绕过 npm proxy / https-proxy。"
		printf '%s\n' "npm_config_proxy= npm_config_https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= http_proxy= https_proxy= all_proxy="
	fi
}

codex_release_target() {
	local arch
	arch="$(uname -m)"
	case "$arch" in
	x86_64 | amd64) printf '%s\n' 'x86_64-unknown-linux-musl' ;;
	aarch64 | arm64) printf '%s\n' 'aarch64-unknown-linux-musl' ;;
	*) return 1 ;;
	esac
}

codex_release_checksum() {
	case "$1" in
	x86_64-unknown-linux-musl) printf '%s\n' "$LEUNG_CODEX_FALLBACK_SHA256_X86_64" ;;
	aarch64-unknown-linux-musl) printf '%s\n' "$LEUNG_CODEX_FALLBACK_SHA256_AARCH64" ;;
	*) return 1 ;;
	esac
}

codex_install_target_path() {
	local node_path=""
	if [[ "$LEUNG_NODE_RUNTIME" == "nvm" ]]; then
		if command -v nvm >/dev/null 2>&1; then
			node_path="$(nvm which "$LEUNG_NODE_VERSION" 2>/dev/null || true)"
		fi
		if [[ -z "$node_path" || "$node_path" == "N/A" ]]; then
			node_path="$(bash -lc "export NVM_DIR=\"$LEUNG_NVM_DIR\"; . \"$LEUNG_NVM_DIR/nvm.sh\" 2>/dev/null || exit 1; nvm which \"$LEUNG_NODE_VERSION\" 2>/dev/null || true" 2>/dev/null || true)"
		fi
		if [[ -n "$node_path" && "$node_path" != "N/A" ]]; then
			printf '%s/codex\n' "$(dirname "$node_path")"
			return 0
		fi
	fi
	ensure_system_prefix_layout
	printf '%s\n' "$LEUNG_NPM_GLOBAL_PREFIX/bin/codex"
}

install_codex_release_fallback() {
	local target url mirror_url="" tmp_dir archive_name codex_path target_path archive_path archive_sha
	local old_connect_timeout="" old_max_time=""
	target="$(codex_release_target)" || {
		log_error "当前架构暂不支持 Codex release fallback: $(uname -m)"
		return 1
	}
	validate_release_tag "$LEUNG_CODEX_FALLBACK_TAG" || {
		log_error "LEUNG_CODEX_FALLBACK_TAG 非法: $LEUNG_CODEX_FALLBACK_TAG"
		return 1
	}
	archive_name="codex-${target}.tar.gz"
	url="${LEUNG_GITHUB_RELEASE_BASE%/}/openai/codex/releases/download/${LEUNG_CODEX_FALLBACK_TAG}/${archive_name}"
	if [[ -n "$LEUNG_GITHUB_RELEASE_MIRROR_BASE" ]]; then
		mirror_url="${LEUNG_GITHUB_RELEASE_MIRROR_BASE%/}/openai/codex/releases/download/${LEUNG_CODEX_FALLBACK_TAG}/${archive_name}"
	else
		mirror_url="$(github_proxy_wrap_url "$LEUNG_GITHUB_PROXY_BASE" "$url" 2>/dev/null || true)"
	fi
	tmp_dir="$(mktemp -d)"
	archive_path="$tmp_dir/$archive_name"
	archive_sha="$(codex_release_checksum "$target")" || return 1
	log_warn "npm 安装 Codex 失败，回退官方 release 二进制：$url"
	log_info "Codex release 包较大，下载期间终端可能短时间无额外输出，请等待。"
	record_transaction created_dir "$tmp_dir"
	old_connect_timeout="${LEUNG_DOWNLOAD_CONNECT_TIMEOUT:-}"
	old_max_time="${LEUNG_DOWNLOAD_MAX_TIME:-}"
	LEUNG_DOWNLOAD_CONNECT_TIMEOUT="${LEUNG_CODEX_RELEASE_CONNECT_TIMEOUT:-10}"
	LEUNG_DOWNLOAD_MAX_TIME="${LEUNG_CODEX_RELEASE_MAX_TIME:-180}"
	download_and_verify_file "codex release" "$url" "$mirror_url" "$archive_path" "$archive_sha" || return 1
	LEUNG_DOWNLOAD_CONNECT_TIMEOUT="$old_connect_timeout"
	LEUNG_DOWNLOAD_MAX_TIME="$old_max_time"
	tar -xzf "$archive_path" -C "$tmp_dir" >>"$LEUNG_LOG_FILE" 2>&1
	if [[ -f "$tmp_dir/codex-${target}" ]]; then
		codex_path="$tmp_dir/codex-${target}"
	else
		codex_path="$(
			find "$tmp_dir" -type f \
				\( -name codex -o -name "codex-${target}" -o -name 'codex-*' \) \
				! -name '*.tar.gz' \
				! -name '*.tgz' \
				! -name '*.zip' |
				head -n 1
		)"
	fi
	[[ -n "$codex_path" ]] || {
		log_error "Codex release fallback 解包后未找到 codex 可执行文件。"
		return 1
	}
	target_path="$(codex_install_target_path)" || {
		log_error "无法确定 Codex fallback 的安装目标路径。"
		return 1
	}
	prepare_target_file_write "$target_path"
	install -m 755 "$codex_path" "$target_path"
	LEUNG_CODEX_FALLBACK_BINARY=1
	record_transaction codex_release_install "$target_path"
	rm -rf "$tmp_dir"
}

install_cli() {
	local cli="$1"
	local pkg
	if [[ "${LEUNG_DRY_RUN:-0}" == "1" ]]; then
		log_info "[DRY-RUN] 跳过 $cli 的真实安装，模拟 CLI 已安装。"
		record_transaction dry_run_cli_install "$cli"
		return 0
	fi
	local npm_registry_args=()
	local npm_registry_mirror_args=()
	local npm_proxy_env=()
	local npm_cache_env=()
	pkg="$(npm_package_for_cli "$cli")"
	# Try bundle first
	if npm_install_from_bundle "$pkg" "$cli"; then
		record_transaction npm_global_install "$pkg"
		return 0
	fi
	npm_proxy_auto_repair_if_needed
	mkdir -p "$(npm_cache_dir)"
	[[ -n "$LEUNG_NPM_REGISTRY" ]] && npm_registry_args=(--registry "$LEUNG_NPM_REGISTRY")
	[[ -n "$LEUNG_NPM_REGISTRY_MIRROR" ]] && npm_registry_mirror_args=(--registry "$LEUNG_NPM_REGISTRY_MIRROR")
	npm_cache_env=(npm_config_cache="$(npm_cache_dir)")
	if [[ -n "$(npm_proxy_override_env)" ]]; then
		npm_proxy_env=(npm_config_proxy= npm_config_https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= http_proxy= https_proxy= all_proxy=)
	fi
	if [[ "$cli" == "codex" ]]; then
		ensure_system_prefix_layout
		if [[ "$LEUNG_NODE_RUNTIME" == "system" ]]; then
			if env npm_config_prefix="$LEUNG_NPM_GLOBAL_PREFIX" "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_args[@]}" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
				record_transaction npm_global_install "$pkg"
				return 0
			elif [[ -n "$LEUNG_NPM_REGISTRY_MIRROR" && "$LEUNG_NPM_REGISTRY_MIRROR" != "$LEUNG_NPM_REGISTRY" ]]; then
				log_warn "Codex npm 官方源失败，切换 npm 镜像重试：$LEUNG_NPM_REGISTRY_MIRROR"
				if env npm_config_prefix="$LEUNG_NPM_GLOBAL_PREFIX" "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_mirror_args[@]}" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
					record_transaction npm_global_install "$pkg"
					return 0
				fi
			fi
		else
			if nvm_run_logged "" env "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_args[@]}" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
				record_transaction npm_global_install "$pkg"
				return 0
			elif [[ -n "$LEUNG_NPM_REGISTRY_MIRROR" && "$LEUNG_NPM_REGISTRY_MIRROR" != "$LEUNG_NPM_REGISTRY" ]]; then
				log_warn "Codex npm 官方源失败，切换 npm 镜像重试：$LEUNG_NPM_REGISTRY_MIRROR"
				if nvm_run_logged "" env "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_mirror_args[@]}" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
					record_transaction npm_global_install "$pkg"
					return 0
				fi
			fi
		fi
		install_codex_release_fallback
		return 0
	fi
	if [[ "$LEUNG_NODE_RUNTIME" == "system" ]]; then
		ensure_system_prefix_layout
		if ! env npm_config_prefix="$LEUNG_NPM_GLOBAL_PREFIX" "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_args[@]}" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
			if [[ -n "$LEUNG_NPM_REGISTRY_MIRROR" && "$LEUNG_NPM_REGISTRY_MIRROR" != "$LEUNG_NPM_REGISTRY" ]]; then
				log_warn "$cli npm 官方源失败，切换 npm 镜像重试：$LEUNG_NPM_REGISTRY_MIRROR"
				retry_logged "npm install -g $pkg (mirror)" env npm_config_prefix="$LEUNG_NPM_GLOBAL_PREFIX" "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_mirror_args[@]}" "$pkg"
			else
				log_error "npm install -g $pkg 失败，且未配置 npm 镜像回退。请检查网络、npm registry、代理配置，或显式配置镜像。"
				return 1
			fi
		fi
	else
		if ! nvm_run_logged "" env "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_args[@]}" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
			if [[ -n "$LEUNG_NPM_REGISTRY_MIRROR" && "$LEUNG_NPM_REGISTRY_MIRROR" != "$LEUNG_NPM_REGISTRY" ]]; then
				log_warn "$cli npm 官方源失败，切换 npm 镜像重试：$LEUNG_NPM_REGISTRY_MIRROR"
				retry_logged "npm install -g $pkg (mirror)" nvm_run_logged "" env "${npm_cache_env[@]}" "${npm_proxy_env[@]}" npm install -g "${npm_registry_mirror_args[@]}" "$pkg"
			else
				log_error "npm install -g $pkg 失败，且未配置 npm 镜像回退。请检查网络、npm registry、代理配置，或显式配置镜像。"
				return 1
			fi
		fi
	fi
	record_transaction npm_global_install "$pkg"
}
