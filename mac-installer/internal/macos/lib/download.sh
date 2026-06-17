#!/usr/bin/env bash
# LEUNG CLI Installer - Download utilities with bundle-first logic

# Resolve bundles directory (relative to installer root)
_resolve_bundles_dir() {
    local script_dir
    # BASH_SOURCE is bash-only; fall back to $0 for zsh compatibility in tests.
    local this_file="${BASH_SOURCE[0]:-${(%):-%x}}" 2>/dev/null || this_file="$0"
    script_dir="$(cd -- "$(dirname -- "$this_file")/.." && pwd 2>/dev/null)" || return
    local bundles="$script_dir/../../bundles"
    if [[ -d "$bundles" ]]; then
        cd -- "$bundles" && pwd
    else
        echo ""
    fi
}

BUNDLES_DIR="$(_resolve_bundles_dir)"
BUNDLES_DOWNLOADS_DIR="${BUNDLES_DIR:+$BUNDLES_DIR/downloads}"
BUNDLES_NPM_CACHE_DIR="${BUNDLES_DIR:+$BUNDLES_DIR/npm-cache}"
LOCAL_CACHE_DIR="${LEUNG_HOME}/cache"

# Check bundle for a file by name
bundle_has_file() {
    local filename="$1"
    [[ -n "$BUNDLES_DOWNLOADS_DIR" && -f "$BUNDLES_DOWNLOADS_DIR/$filename" ]]
}

# Copy from bundle to dest
bundle_copy_file() {
    local filename="$1" dest="$2"
    if bundle_has_file "$filename"; then
        cp "$BUNDLES_DOWNLOADS_DIR/$filename" "$dest"
        log_info "Loaded from bundle: $filename"
        return 0
    fi
    return 1
}

# Check local cache
cache_has_file() {
    local filename="$1"
    [[ -d "$LOCAL_CACHE_DIR" && -f "$LOCAL_CACHE_DIR/$filename" ]]
}

cache_copy_file() {
    local filename="$1" dest="$2"
    if cache_has_file "$filename"; then
        cp "$LOCAL_CACHE_DIR/$filename" "$dest"
        log_info "Loaded from cache: $filename"
        return 0
    fi
    return 1
}

# Save to local cache after successful download
cache_save_file() {
    local src="$1" filename="$2"
    mkdir -p "$LOCAL_CACHE_DIR"
    cp "$src" "$LOCAL_CACHE_DIR/$filename"
}

download_file() {
    local url="$1" dest="$2" timeout="${3:-120}"
    log_info "Downloading: $url"
    if have_cmd curl; then
        curl -fSL --connect-timeout 15 --max-time "$timeout" \
            --progress-bar -o "$dest" "$url" 2>&1 | while IFS= read -r line; do
            printf '\r  %s' "$line"
        done
        printf '\n'
        [[ -f "$dest" && -s "$dest" ]] && return 0
        return 1
    fi
    if have_cmd wget; then
        wget --timeout="$timeout" --show-progress -qO "$dest" "$url" 2>&1
        [[ -f "$dest" && -s "$dest" ]] && return 0
        return 1
    fi
    log_error "Missing curl/wget, cannot download."
    return 1
}

# Priority: bundle → cache → online (primary) → online (mirror)
download_with_fallback() {
    local filename="$1" primary_url="$2" mirror_url="${3:-}" dest="$4" expected_sha="${5:-}"

    # 1) Bundle
    if bundle_copy_file "$filename" "$dest"; then
        if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
            log_warn "Bundle file SHA256 mismatch, falling through to download."
            rm -f "$dest"
        else
            return 0
        fi
    fi

    # 2) Local cache
    if cache_copy_file "$filename" "$dest"; then
        if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
            log_warn "Cached file SHA256 mismatch, falling through to download."
            rm -f "$dest"
        else
            return 0
        fi
    fi

    # 3) Online primary
    print_step "Downloading $filename..."
    if download_file "$primary_url" "$dest"; then
        if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
            rm -f "$dest"
        else
            cache_save_file "$dest" "$filename"
            print_ok "Downloaded: $filename"
            return 0
        fi
    fi

    # 4) Online mirror
    if [[ -n "$mirror_url" && "$mirror_url" != "$primary_url" ]]; then
        log_warn "Primary failed, trying mirror..."
        if download_file "$mirror_url" "$dest"; then
            if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
                rm -f "$dest"
                return 1
            fi
            cache_save_file "$dest" "$filename"
            print_ok "Downloaded from mirror: $filename"
            return 0
        fi
    fi

    print_fail "Failed to obtain: $filename"
    return 1
}

# Download a GitHub release asset, trying direct URL then every configured
# proxy in GITHUB_PROXY_BASES, with bundle/cache lookup first. Every candidate
# is SHA256-verified (when expected_sha is set) so a truncated/corrupted
# download is rejected and the next mirror is tried instead of installing a
# broken binary. Returns 0 on first verified success.
download_github_release() {
    local github_url="$1" dest="$2" expected_sha="${3:-}" timeout="${4:-600}"
    local filename
    filename="$(basename "$dest")"

    # 1) Bundle
    if bundle_copy_file "$filename" "$dest"; then
        if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
            log_warn "Bundle file SHA256 mismatch, falling through to download."
            rm -f "$dest"
        else
            return 0
        fi
    fi

    # 2) Local cache
    if cache_copy_file "$filename" "$dest"; then
        if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
            log_warn "Cached file SHA256 mismatch, falling through to download."
            rm -f "$dest"
        else
            return 0
        fi
    fi

    # 3) Build ordered candidate list. Proxies first (direct github.com is
    #    frequently blocked/throttled and would waste the full timeout before
    #    falling through); direct GitHub URL last as a final fallback.
    local candidates=()
    local base
    for base in "${GITHUB_PROXY_BASES[@]}"; do
        [[ -z "$base" ]] && continue
        candidates+=("${base%/}/${github_url}")
    done
    candidates+=("$github_url")

    print_step "Downloading $filename..."
    local url idx=0 total="${#candidates[@]}"
    for url in "${candidates[@]}"; do
        idx=$((idx + 1))
        log_info "Attempt $idx/$total: $url"
        if download_file "$url" "$dest" "$timeout"; then
            # gzip tarballs: verify archive integrity even without a known SHA
            if [[ "$filename" == *.tar.gz || "$filename" == *.tgz ]] && have_cmd gzip; then
                if ! gzip -t "$dest" 2>/dev/null; then
                    log_warn "Downloaded archive is corrupt (gzip check failed), trying next source."
                    rm -f "$dest"
                    continue
                fi
            fi
            if [[ -n "$expected_sha" ]] && ! verify_sha256 "$dest" "$expected_sha"; then
                log_warn "SHA256 mismatch, trying next source."
                rm -f "$dest"
                continue
            fi
            cache_save_file "$dest" "$filename"
            print_ok "Downloaded: $filename"
            return 0
        fi
        log_warn "Source $idx/$total failed."
    done

    print_fail "Failed to obtain $filename from all $total sources."
    return 1
}

# Legacy wrapper for compatibility
download_with_mirror() {
    local primary_url="$1" mirror_url="${2:-}" dest="$3" expected_sha="${4:-}"
    local filename
    filename="$(basename "$dest")"
    download_with_fallback "$filename" "$primary_url" "$mirror_url" "$dest" "$expected_sha"
}

sha256_of_file() {
    local path="$1"
    if have_cmd shasum; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif have_cmd sha256sum; then
        sha256sum "$path" | awk '{print $1}'
    else
        python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$path"
    fi
}

verify_sha256() {
    local path="$1" expected="$2"
    [[ -n "$expected" ]] || return 0
    log_info "Verifying SHA256..."
    local actual
    actual="$(sha256_of_file "$path")"
    if [[ "$actual" != "$expected" ]]; then
        log_error "SHA256 mismatch: expected=$expected actual=$actual"
        return 1
    fi
    log_info "SHA256 OK: $actual"
    return 0
}

github_proxy_url() {
    local url="$1"
    local base="${GITHUB_PROXY_BASE%/}"
    printf '%s/%s\n' "$base" "$url"
}

# npm bundle-first install
npm_install_from_bundle() {
    local pkg="$1" safe_name=""
    safe_name="$(echo "$pkg" | tr '/' '-' | tr '@' '' | sed 's/^-//')"

    # Full offline directory (with all deps)
    local offline_dir="${BUNDLES_DIR:+$BUNDLES_DIR/npm-offline/$safe_name}"
    if [[ -n "$offline_dir" && -d "$offline_dir" ]] && ls "$offline_dir"/*.tgz >/dev/null 2>&1; then
        log_info "Installing $pkg from offline bundle (full deps)..."
        local main_tgz=""
        for tgz in "$offline_dir"/*.tgz; do
            local bn
            bn="$(basename "$tgz")"
            if [[ "$bn" == "$safe_name"* ]] || [[ "$bn" == *"$(printf '%s' "$pkg" | tr '/' '-')"* ]]; then
                main_tgz="$tgz"
            fi
        done
        if [[ -n "$main_tgz" ]]; then
            if npm install -g --offline --cache "$offline_dir" "$main_tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
                print_ok "$pkg installed from offline bundle."
                return 0
            fi
            if npm install -g "$main_tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
                print_ok "$pkg installed from bundle tgz."
                return 0
            fi
        fi
        log_warn "$pkg offline bundle install failed, falling through."
    fi

    # Legacy single tgz
    local bundle_tgz="${BUNDLES_NPM_CACHE_DIR:+$BUNDLES_NPM_CACHE_DIR/${safe_name}.tgz}"
    local cache_tgz="${LOCAL_CACHE_DIR}/${safe_name}.tgz"

    if [[ -n "$bundle_tgz" && -f "$bundle_tgz" ]]; then
        log_info "Installing $pkg from bundle tgz..."
        if npm install -g "$bundle_tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
            print_ok "$pkg installed from bundle."
            return 0
        fi
    fi

    if [[ -f "$cache_tgz" ]]; then
        log_info "Installing $pkg from cache tgz..."
        if npm install -g "$cache_tgz" >>"$LEUNG_LOG_FILE" 2>&1; then
            print_ok "$pkg installed from cache."
            return 0
        fi
    fi

    return 1
}

install_node_from_bundle() {
    local arch="" node_dir="" node_ver=""
    local expected_sha=""
    arch="$(uname -m)"
    node_dir="${BUNDLES_DIR:+$BUNDLES_DIR/node}"
    [[ -n "$node_dir" && -d "$node_dir" ]] || return 1
    [[ -f "$node_dir/version.txt" ]] || return 1
    node_ver="$(cat "$node_dir/version.txt")"

    local target=""
    case "$arch" in
        x86_64|amd64)
            target="darwin-x64"
            expected_sha="${NODE_LTS_SHA256_DARWIN_X64:-}"
            ;;
        arm64|aarch64)
            target="darwin-arm64"
            expected_sha="${NODE_LTS_SHA256_DARWIN_ARM64:-}"
            ;;
        *) return 1 ;;
    esac

    local tarball="$node_dir/node-v${node_ver}-${target}.tar.gz"
    [[ -f "$tarball" ]] || return 1

    if [[ -n "$expected_sha" ]] && ! verify_sha256 "$tarball" "$expected_sha"; then
        log_error "Bundled Node.js archive checksum mismatch: $tarball"
        return 1
    fi

    local install_dir="$HOME/.local/share/leung-node"
    log_info "Installing Node.js v${node_ver} from bundle..."
    mkdir -p "$install_dir"
    tar -xzf "$tarball" -C "$install_dir" --strip-components=1 2>>"$LEUNG_LOG_FILE" || return 1

    export PATH="$install_dir/bin:$PATH"

    local shell_rc="$HOME/.zshrc"
    [[ -f "$shell_rc" ]] || shell_rc="$HOME/.bash_profile"
    if ! grep -q "leung-node" "$shell_rc" 2>/dev/null; then
        printf '\nexport PATH="%s/bin:$PATH"\n' "$install_dir" >> "$shell_rc"
    fi

    log_info "Node.js v${node_ver} installed from bundle to $install_dir"
    return 0
}

install_node_from_official() {
    local arch="" target="" node_major="" node_ver=""
    local filename="" url="" expected_sha=""
    local install_dir="$HOME/.local/share/leung-node"
    local tmp_dir="" tarball=""
    local -a release_bases=()
    local base="" idx=0 total=0

    node_major="${NODE_LTS_MAJOR:-24}"
    node_ver="${NODE_LTS_VERSION:-}"

    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            target="darwin-x64"
            expected_sha="${NODE_LTS_SHA256_DARWIN_X64:-}"
            ;;
        arm64|aarch64)
            target="darwin-arm64"
            expected_sha="${NODE_LTS_SHA256_DARWIN_ARM64:-}"
            ;;
        *) log_error "Unsupported architecture for Node.js: $arch"; return 1 ;;
    esac

    if [[ -n "${NODE_RELEASE_BASES:-}" ]]; then
        IFS=',' read -r -a release_bases <<< "${NODE_RELEASE_BASES}"
    else
        release_bases=("${NODE_RELEASE_BASES_DEFAULT[@]}")
    fi

    if [[ -z "$node_ver" ]]; then
        log_error "NODE_LTS_VERSION is empty; cannot download fixed Node.js LTS."
        return 1
    fi
    log_info "Using fixed Node.js LTS v${node_ver} (${target})"

    filename="node-v${node_ver}-${target}.tar.gz"
    tmp_dir="$(mktemp -d)"
    tarball="${tmp_dir}/${filename}"
    idx=0

    total="${#release_bases[@]}"
    for base in "${release_bases[@]}"; do
        idx=$((idx + 1))
        base="${base%/}"
        url="${base}/v${node_ver}/${filename}"
        print_step "Downloading Node.js ${filename} from source ${idx}/${total}"
        if download_with_fallback "$filename" "$url" "" "$tarball" "$expected_sha"; then
            log_info "Downloaded Node.js from ${base}"
            break
        fi
        rm -f "$tarball"
        log_warn "Node.js download failed from ${base}"
    done

    if [[ ! -s "$tarball" ]]; then
        rm -rf "$tmp_dir"
        log_error "Failed to download Node.js ${filename} from all configured sources."
        return 1
    fi

    log_info "Installing Node.js v${node_ver} to $install_dir..."
    mkdir -p "$install_dir"
    if ! tar -xzf "$tarball" -C "$install_dir" --strip-components=1 2>>"$LEUNG_LOG_FILE"; then
        rm -rf "$tmp_dir"
        log_error "Failed to extract Node.js archive."
        return 1
    fi
    rm -rf "$tmp_dir"

    export PATH="$install_dir/bin:$PATH"
    ensure_path_entry "$install_dir/bin"

    if ! test_node_available || ! test_npm_available; then
        log_error "Node.js downloaded, but node/npm is still unavailable."
        return 1
    fi

    log_info "Node.js v${node_ver} installed from official archive."
    return 0
}
