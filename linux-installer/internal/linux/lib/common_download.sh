#!/usr/bin/env bash

timestamp() {
	date +%Y%m%d-%H%M%S
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

have_download_tool() {
	command_exists curl || command_exists wget
}

hash_string() {
	local value="${1:-}"
	if command_exists sha256sum; then
		printf '%s' "$value" | sha256sum | awk '{print $1}'
		return 0
	fi
	if command_exists shasum; then
		printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
		return 0
	fi
	require_python || return 1
	python3 - "$value" <<'PY'
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
PY
}

require_python() {
	if ! command_exists python3; then
		log_error '缺少 python3，无法继续。请先安装 python3 后重试。'
		return 1
	fi
}

validate_sha256() {
	[[ "${1:-}" =~ ^[A-Fa-f0-9]{64}$ ]]
}

validate_node_version() {
	[[ "${1:-}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]
}

validate_nvm_version() {
	[[ "${1:-}" =~ ^v[0-9]+(\.[0-9]+){2}$ ]]
}

validate_release_tag() {
	[[ "${1:-}" =~ ^rust-v[0-9]+(\.[0-9]+){2}$ ]]
}

validate_git_commit_sha() {
	[[ "${1:-}" =~ ^[A-Fa-f0-9]{40}$ ]]
}

validate_http_url() {
	[[ "${1:-}" =~ ^https?://[^[:space:]]+$ ]]
}

normalize_proxy_base() {
	local base="${1:-}"
	[[ -n "$base" ]] || return 1
	if [[ "$base" == */ ]]; then
		printf '%s\n' "$base"
	else
		printf '%s/\n' "$base"
	fi
}

github_proxy_wrap_url() {
	local proxy_base="${1:-}" upstream_url="${2:-}"
	local normalized=""
	[[ -n "$proxy_base" && -n "$upstream_url" ]] || return 1
	case "$upstream_url" in
	https://github.com/* | https://raw.githubusercontent.com/* | https://codeload.github.com/* | https://release-assets.githubusercontent.com/*) ;;
	*) return 1 ;;
	esac
	normalized="$(normalize_proxy_base "$proxy_base")" || return 1
	printf '%s%s\n' "$normalized" "$upstream_url"
}

prepare_target_file_write() {
	local path="$1"
	local dir
	[[ "$LEUNG_DRY_RUN" == "1" ]] && return 0
	dir="$(dirname "$path")"
	if [[ ! -d "$dir" ]]; then
		mkdir -p "$dir"
		record_transaction created_dir "$dir"
	fi
	if [[ ! -e "$path" ]]; then
		record_transaction created_file "$path"
	else
		backup_file_if_exists "$path"
	fi
}

download_cache_dir() {
	printf '%s\n' "${LEUNG_CACHE_DIR:-$HOME/.leung/cache}/downloads"
}

npm_cache_dir() {
	printf '%s\n' "${LEUNG_CACHE_DIR:-$HOME/.leung/cache}/npm"
}

bundle_downloads_dir() {
	printf '%s\n' "${LEUNG_BUNDLES_DOWNLOADS_DIR:-}"
}

bundle_npm_cache_dir() {
	printf '%s\n' "${LEUNG_BUNDLES_NPM_CACHE_DIR:-}"
}

copy_bundled_download_if_valid() {
	local label="$1" filename="$2" dest="$3" expected_sha="${4:-}"
	local bundles_dir=""
	bundles_dir="$(bundle_downloads_dir)"
	[[ -n "$bundles_dir" && -d "$bundles_dir" ]] || return 1
	local bundle_file="$bundles_dir/$filename"
	[[ -f "$bundle_file" ]] || return 1
	if [[ -n "$expected_sha" ]]; then
		verify_download_checksum "$label bundle" "$bundle_file" "$expected_sha" >/dev/null 2>&1 || {
			log_warn "$label bundle SHA256 mismatch, skipping bundle."
			return 1
		}
	fi
	cp -f "$bundle_file" "$dest"
	log_info "$label loaded from bundle: $bundle_file"
	return 0
}

npm_install_from_bundle() {
	local pkg="$1" label="${2:-$1}"
	local bundles_npm=""
	bundles_npm="$(bundle_npm_cache_dir)"
	[[ -n "$bundles_npm" && -d "$bundles_npm" ]] || return 1
	local safe_name=""
	safe_name="$(printf '%s' "$pkg" | tr '/' '-' | tr -d '@' | sed 's/^-//')"

	# Check for full offline directory (with all deps)
	local offline_dir="$LEUNG_BUNDLES_DIR/npm-offline/$safe_name"
	if [[ -d "$offline_dir" ]] && ls "$offline_dir"/*.tgz >/dev/null 2>&1; then
		log_info "$label: installing from offline bundle (full deps)..."
		# Install all dependency tarballs first, then the main package
		local main_tgz=""
		for tgz in "$offline_dir"/*.tgz; do
			local basename_tgz
			basename_tgz="$(basename "$tgz")"
			if [[ "$basename_tgz" == "$safe_name"* ]] || [[ "$basename_tgz" == *"$(printf '%s' "$pkg" | tr '/' '-')"* ]]; then
				main_tgz="$tgz"
			fi
		done
		# Install with offline cache
		if [[ -n "$main_tgz" ]]; then
			if npm install -g --offline --cache "$offline_dir" "$main_tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
				log_info "$label installed from offline bundle."
				return 0
			fi
			# Fallback: try installing the main tgz directly
			if npm install -g "$main_tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
				log_info "$label installed from bundle tgz."
				return 0
			fi
		fi
		log_warn "$label offline bundle install failed, falling through."
	fi

	# Legacy: single tgz in npm-cache
	local tgz="$bundles_npm/${safe_name}.tgz"
	[[ -f "$tgz" ]] || return 1
	log_info "$label: installing from bundle tgz ($tgz)..."
	if npm install -g "$tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
		log_info "$label installed from bundle."
		return 0
	fi
	log_warn "$label bundle npm install failed, falling through."
	return 1
}

install_node_from_bundle() {
	local arch="" node_dir="" node_ver=""
	arch="$(uname -m)"
	node_dir="${LEUNG_BUNDLES_DIR:-}/node"
	[[ -d "$node_dir" ]] || return 1
	[[ -f "$node_dir/version.txt" ]] || return 1
	node_ver="$(cat "$node_dir/version.txt")"

	local target=""
	case "$arch" in
		x86_64|amd64)  target="linux-x64" ;;
		aarch64|arm64) target="linux-arm64" ;;
		*) return 1 ;;
	esac

	local tarball="$node_dir/node-v${node_ver}-${target}.tar.xz"
	[[ -f "$tarball" ]] || return 1

	local install_dir="$HOME/.local/share/leung-node"
	log_info "Installing Node.js v${node_ver} from bundle..."
	mkdir -p "$install_dir"
	tar -xJf "$tarball" -C "$install_dir" --strip-components=1 2>>"$LEUNG_LOG_FILE" || return 1

	# Add to PATH
	export PATH="$install_dir/bin:$PATH"

	local shell_rc=""
	if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
		shell_rc="$HOME/.zshrc"
	else
		shell_rc="$HOME/.bashrc"
	fi
	if ! grep -q "leung-node" "$shell_rc" 2>/dev/null; then
		printf '\nexport PATH="%s/bin:$PATH"\n' "$install_dir" >> "$shell_rc"
	fi

	log_info "Node.js v${node_ver} installed from bundle to $install_dir"
	return 0
}

download_cache_key() {
	local primary_url="$1" expected_sha="${2:-}" dest="$3"
	local base=""
	base="$(basename "$dest")"
	if [[ -n "$expected_sha" ]] && validate_sha256 "$expected_sha"; then
		printf '%s-%s\n' "$expected_sha" "$base"
		return 0
	fi
	printf '%s-%s\n' "$(hash_string "$primary_url")" "$base"
}

download_cache_path() {
	local primary_url="$1" expected_sha="${2:-}" dest="$3"
	printf '%s/%s\n' "$(download_cache_dir)" "$(download_cache_key "$primary_url" "$expected_sha" "$dest")"
}

copy_cached_download_if_valid() {
	local label="$1" primary_url="$2" dest="$3" expected_sha="${4:-}" cache_path=""
	cache_path="$(download_cache_path "$primary_url" "$expected_sha" "$dest")"
	[[ -f "$cache_path" ]] || return 1
	if [[ -n "$expected_sha" ]]; then
		verify_download_checksum "$label cache" "$cache_path" "$expected_sha" >/dev/null 2>&1 || {
			rm -f "$cache_path"
			return 1
		}
	fi
	cp -f "$cache_path" "$dest"
	log_info "$label 命中本地缓存：$cache_path"
	return 0
}

store_download_in_cache() {
	local primary_url="$1" source_path="$2" expected_sha="${3:-}" cache_path=""
	cache_path="$(download_cache_path "$primary_url" "$expected_sha" "$source_path")"
	mkdir -p "$(dirname "$cache_path")"
	cp -f "$source_path" "$cache_path"
}

show_download_progress() {
	local label="$1" path="$2" pid="$3"
	local tty_path=""
	if [[ -w /dev/tty ]]; then
		tty_path="/dev/tty"
	elif [[ -t 2 ]]; then
		tty_path="/dev/stderr"
	else
		return 0
	fi
	while kill -0 "$pid" 2>/dev/null; do
		local size_bytes=0 size_mb="0.0"
		if [[ -f "$path" ]]; then
			size_bytes="$(wc -c <"$path" 2>/dev/null || printf '0')"
		fi
		size_mb="$(python3 - "$size_bytes" <<'PY'
import sys
print(f"{int(sys.argv[1]) / 1048576:.1f}")
PY
)"
		printf '\r[INFO] %s 下载中：%s MB' "$label" "$size_mb" >"$tty_path"
		sleep 1
	done
	local status=0
	wait "$pid" || status=$?
	local final_bytes=0 final_mb="0.0"
	if [[ -f "$path" ]]; then
		final_bytes="$(wc -c <"$path" 2>/dev/null || printf '0')"
	fi
	final_mb="$(python3 - "$final_bytes" <<'PY'
import sys
print(f"{int(sys.argv[1]) / 1048576:.1f}")
PY
)"
	printf '\r[INFO] %s 下载结束：%s MB\n' "$label" "$final_mb" >"$tty_path"
	return "$status"
}

download_to_file_once() {
	local url="$1" dest="$2" label="${3:-download}"
	if command_exists curl; then
		local curl_args=(
			-fsSL
			--retry 2
			--connect-timeout "${LEUNG_DOWNLOAD_CONNECT_TIMEOUT:-10}"
			--max-time "${LEUNG_DOWNLOAD_MAX_TIME:-300}"
			-o "$dest"
			"$url"
		)
		if [[ -w /dev/tty || -t 2 ]]; then
			curl "${curl_args[@]}" >>"$LEUNG_LOG_FILE" 2>&1 &
			local pid=$!
			show_download_progress "$label" "$dest" "$pid"
			return $?
		fi
		curl "${curl_args[@]}"
		return
	fi
	if command_exists wget; then
		if [[ -w /dev/tty || -t 2 ]]; then
			wget -qO "$dest" "$url" >>"$LEUNG_LOG_FILE" 2>&1 &
			local pid=$!
			show_download_progress "$label" "$dest" "$pid"
			return $?
		fi
		wget -qO "$dest" "$url"
		return
	fi
	log_error '缺少 curl / wget，无法下载远端文件。'
	return 1
}

download_to_file() {
	local label="$1" primary_url="$2" mirror_url="$3" dest="$4"
	local filename=""
	filename="$(basename "$dest")"
	validate_http_url "$primary_url" || {
		log_error "$label URL 非法: $primary_url"
		return 1
	}
	# 1) Bundle first
	if copy_bundled_download_if_valid "$label" "$filename" "$dest" "${LEUNG_DOWNLOAD_EXPECTED_SHA:-}"; then
		return 0
	fi
	# 2) Local cache
	mkdir -p "$(download_cache_dir)"
	if copy_cached_download_if_valid "$label" "$primary_url" "$dest" "${LEUNG_DOWNLOAD_EXPECTED_SHA:-}"; then
		return 0
	fi
	# 3) Online primary
	if download_to_file_once "$primary_url" "$dest" "$label" >>"$LEUNG_LOG_FILE" 2>&1; then
		store_download_in_cache "$primary_url" "$dest" "${LEUNG_DOWNLOAD_EXPECTED_SHA:-}"
		return 0
	fi
	# 4) Online mirror
	if [[ -n "$mirror_url" ]]; then
		validate_http_url "$mirror_url" || {
			log_error "$label 镜像 URL 非法: $mirror_url"
			return 1
		}
		if [[ "$mirror_url" != "$primary_url" ]]; then
			log_warn "$label 官方源失败，切换镜像重试：$mirror_url"
			if download_to_file_once "$mirror_url" "$dest" "$label" >>"$LEUNG_LOG_FILE" 2>&1; then
				store_download_in_cache "$primary_url" "$dest" "${LEUNG_DOWNLOAD_EXPECTED_SHA:-}"
				return 0
			fi
			return $?
		fi
	fi
	return 1
}

sha256_file() {
	local path="$1"
	if command_exists sha256sum; then
		sha256sum "$path" | awk '{print $1}'
		return 0
	fi
	if command_exists shasum; then
		shasum -a 256 "$path" | awk '{print $1}'
		return 0
	fi
	require_python || return 1
	python3 - "$path" <<'PY'
import hashlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    print(hashlib.sha256(f.read()).hexdigest())
PY
}

verify_download_checksum() {
	local label="$1" path="$2" expected="$3" actual=""
	validate_sha256 "$expected" || {
		log_error "$label 预期 SHA256 非法: $expected"
		return 1
	}
	actual="$(sha256_file "$path")" || {
		log_error "$label 无法计算 SHA256: $path"
		return 1
	}
	if [[ "$actual" != "${expected,,}" && "$actual" != "${expected^^}" ]]; then
		log_error "$label SHA256 校验失败。expected=$expected actual=$actual"
		return 1
	fi
	log_info "$label SHA256 校验通过。"
}

download_and_verify_file() {
	local label="$1" primary_url="$2" mirror_url="$3" dest="$4" expected_sha="$5"
	local old_expected_sha="${LEUNG_DOWNLOAD_EXPECTED_SHA:-}"
	LEUNG_DOWNLOAD_EXPECTED_SHA="$expected_sha"
	log_info "开始下载 $label"
	download_to_file "$label" "$primary_url" "$mirror_url" "$dest" || {
		LEUNG_DOWNLOAD_EXPECTED_SHA="$old_expected_sha"
		log_error "$label 下载失败。"
		return 1
	}
	log_info "$label 下载完成，开始校验 SHA256。"
	verify_download_checksum "$label" "$dest" "$expected_sha"
	local status=$?
	LEUNG_DOWNLOAD_EXPECTED_SHA="$old_expected_sha"
	return $status
}

run_logged() {
	log_info "执行: $*"
	if [[ "$LEUNG_DRY_RUN" == "1" ]]; then
		if [[ -n "${LEUNG_LOG_FILE:-}" ]]; then
			printf '[DRY-RUN] %s\n' "$*" | tee -a "$LEUNG_LOG_FILE" >&2
		else
			printf '[DRY-RUN] %s\n' "$*" >&2
		fi
		return 0
	fi
	if [[ -n "${LEUNG_LOG_FILE:-}" ]]; then
		"$@" >>"$LEUNG_LOG_FILE" 2>&1
	else
		"$@" >&2
	fi
}

retry_logged() {
	local label="$1"
	shift
	local attempt max_attempts=3
	for attempt in $(seq 1 "$max_attempts"); do
		log_info "重试包装[$label] 第 $attempt/$max_attempts 次"
		if [[ "$LEUNG_DRY_RUN" == "1" ]]; then
			run_logged "$@"
			return 0
		fi
		if "$@" >>"$LEUNG_LOG_FILE" 2>&1; then
			return 0
		fi
		log_warn "$label 失败，第 $attempt 次重试未成功。"
		sleep 1
	done
	log_error "$label 连续 $max_attempts 次失败。"
	return 1
}

is_root() {
	[[ "${EUID:-$(id -u)}" -eq 0 ]]
}

run_as_root() {
	if is_root; then
		"$@"
	elif command_exists sudo; then
		sudo "$@"
	else
		log_error '当前操作需要 root 或 sudo。'
		return 1
	fi
}

backup_file_if_exists() {
	local path="$1"
	local stamp dest
	[[ -f "$path" ]] || return 0
	[[ "$LEUNG_DRY_RUN" == "1" ]] && return 0
	stamp="$(timestamp)"
	dest="$LEUNG_BACKUP_DIR/$stamp/${path#/}"
	mkdir -p "$(dirname "$dest")"
	cp -a "$path" "$dest"
	log_info "已备份: $path -> $dest"
	printf '%s|%s\n' "$path" "$dest" >>"$LEUNG_RESTORE_STACK_FILE"
	record_transaction backup "$path" "$dest"
}

secure_write_file() {
	local path="$1"
	local mode="$2"
	[[ "$LEUNG_DRY_RUN" == "1" ]] && return 0
	prepare_target_file_write "$path"
	cat >"$path"
	chmod "$mode" "$path" || true
}
