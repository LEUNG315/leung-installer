#!/usr/bin/env bash
# LEUNG CLI Installer - CLI installation logic

install_cli_via_npm() {
    local cli="$1" pkg=""
    case "$cli" in
        codex)  pkg="@openai/codex" ;;
        claude) pkg="@anthropic-ai/claude-code" ;;
        gemini) pkg="@google/gemini-cli" ;;
        *) log_error "Unknown CLI: $cli"; return 1 ;;
    esac

    if ! ensure_nodejs_available; then
        log_error "npm not available and automatic Node.js installation failed."
        return 1
    fi

    # Try bundle/cache first
    if npm_install_from_bundle "$pkg"; then
        return 0
    fi

    log_info "Installing $cli via npm ($pkg)..."
    if npm install -g "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
        print_ok "$cli installed via npm."
        return 0
    fi

    log_warn "npm official registry failed, trying mirror..."
    if npm install -g --registry "$NPM_REGISTRY_MIRROR" "$pkg" >>"$LEUNG_LOG_FILE" 2>&1; then
        print_ok "$cli installed via npm mirror."
        return 0
    fi

    return 1
}

install_node_via_homebrew() {
    if ! test_brew_available; then
        return 1
    fi

    log_info "Trying Homebrew for Node.js..."
    if brew install node >>"$LEUNG_LOG_FILE" 2>&1; then
        hash -r 2>/dev/null || true
        if test_node_available && test_npm_available; then
            print_ok "Node.js installed via Homebrew."
            return 0
        fi
    fi

    log_warn "brew install node failed."
    return 1
}

ensure_nodejs_available() {
    if test_node_available && test_npm_available; then
        log_info "Node.js and npm already available; skipping Node.js installation."
        return 0
    fi

    print_step "Installing Node.js (required for npm)..."
    log_info "Node.js install strategy: bundle -> Homebrew -> configured release mirrors"

    print_step "Trying bundled Node.js"
    if install_node_from_bundle 2>/dev/null && test_node_available && test_npm_available; then
        print_ok "Node.js installed from local bundle."
        return 0
    fi
    log_warn "Bundled Node.js unavailable or install failed."

    print_step "Trying Homebrew Node.js"
    if install_node_via_homebrew; then
        return 0
    fi

    log_warn "Bundle/Homebrew Node.js install unavailable, trying configured Node.js download mirrors..."
    print_step "Trying online Node.js download mirrors"
    if install_node_from_official 2>/dev/null && test_node_available && test_npm_available; then
        print_ok "Node.js installed from official archive."
        return 0
    fi

    return 1
}

install_codex_cli() {
    print_step "Installing Codex CLI..."

    if test_brew_available; then
        log_info "Trying brew install..."
        if brew install openai-codex >>"$LEUNG_LOG_FILE" 2>&1; then
            print_ok "Codex CLI installed via Homebrew."
            return 0
        fi
        log_warn "brew install failed, trying npm..."
    fi

    if install_cli_via_npm "codex"; then
        return 0
    fi

    log_warn "npm install failed, trying GitHub release binary..."
    install_codex_from_release
}

install_codex_from_release() {
    local arch target tag filename github_url
    local tmp_dir dest_file install_dir target_path

    arch="$(detect_arch)"
    case "$arch" in
        x86_64)  target="x86_64-apple-darwin" ;;
        aarch64) target="aarch64-apple-darwin" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac

    tag="$CODEX_FALLBACK_TAG"
    filename="codex-${target}.tar.gz"
    github_url="${GITHUB_RELEASE_BASE}/openai/codex/releases/download/${tag}/${filename}"

    tmp_dir="$(mktemp -d)"
    dest_file="${tmp_dir}/${filename}"

    local expected_sha=""
    case "$arch" in
        x86_64)  expected_sha="$CODEX_FALLBACK_SHA256_X86_64" ;;
        aarch64) expected_sha="$CODEX_FALLBACK_SHA256_AARCH64" ;;
    esac

    # Tries direct GitHub then every proxy in GITHUB_PROXY_BASES, verifying
    # gzip integrity + SHA256 on each so a truncated download never reaches
    # extraction (the root cause of dyld "rebase opcodes terminated early").
    if ! download_github_release "$github_url" "$dest_file" "$expected_sha"; then
        rm -rf "$tmp_dir"
        print_fail "Failed to download Codex CLI binary."
        return 1
    fi

    if ! tar -xzf "$dest_file" -C "$tmp_dir" 2>>"$LEUNG_LOG_FILE"; then
        rm -rf "$tmp_dir"
        print_fail "Failed to extract Codex archive (corrupted download)."
        return 1
    fi

    local codex_bin=""
    codex_bin="$(find "$tmp_dir" -type f -name 'codex' ! -name '*.tar.gz' | head -n1)"
    if [[ -z "$codex_bin" ]]; then
        codex_bin="$(find "$tmp_dir" -type f -name "codex-${target}" | head -n1)"
    fi

    if [[ -z "$codex_bin" ]]; then
        rm -rf "$tmp_dir"
        print_fail "Codex binary not found in release archive."
        return 1
    fi

    install_dir="/usr/local/bin"
    if [[ ! -w "$install_dir" ]]; then
        install_dir="${HOME}/.local/bin"
        mkdir -p "$install_dir"
    fi
    target_path="${install_dir}/codex"

    chmod +x "$codex_bin"
    cp "$codex_bin" "$target_path"
    rm -rf "$tmp_dir"

    if [[ "$install_dir" == "${HOME}/.local/bin" ]]; then
        ensure_path_entry "$install_dir"
    fi

    # Verify binary architecture matches this machine
    if ! verify_binary_arch "$target_path"; then
        rm -f "$target_path"
        print_fail "Codex binary architecture mismatch. Removed $target_path."
        return 1
    fi

    # Strip the quarantine attribute and apply an ad-hoc signature. The release
    # binary is unsigned; without this, Gatekeeper or a stale signature can
    # block execution on recent macOS.
    xattr -d com.apple.quarantine "$target_path" 2>/dev/null || true
    if have_cmd codesign; then
        codesign --force --sign - "$target_path" >>"$LEUNG_LOG_FILE" 2>&1 || \
            log_warn "codesign (ad-hoc) failed; binary may still run."
    fi

    # Smoke-test the binary to catch dyld / codesign issues early
    if ! "$target_path" --version >/dev/null 2>&1; then
        local err_msg
        err_msg="$("$target_path" --version 2>&1 || true)"
        rm -f "$target_path"
        print_fail "Codex binary failed to run (possible corrupted download)."
        if [[ "$err_msg" == *"rebase opcodes"* || "$err_msg" == *"dyld"* ]]; then
            printf '  Error: %s\n' "$err_msg" >&2
            printf '  This usually means the binary is corrupted or incompatible.\n' >&2
            printf '  Try: 1) Re-run the installer  2) Install via npm: npm i -g @openai/codex\n' >&2
        fi
        return 1
    fi

    print_ok "Codex CLI installed to $target_path"
}

install_claude_cli() {
    print_step "Installing Claude Code..."

    if test_brew_available; then
        log_info "Trying brew install..."
        if brew install claude-code >>"$LEUNG_LOG_FILE" 2>&1; then
            print_ok "Claude Code installed via Homebrew."
            return 0
        fi
        log_warn "brew install failed, trying npm..."
    fi

    if install_cli_via_npm "claude"; then
        return 0
    fi

    print_fail "Claude Code installation failed."
    printf '  You can install manually: npm install -g @anthropic-ai/claude-code\n'
    return 1
}

install_gemini_cli() {
    print_step "Installing Gemini CLI..."

    if install_cli_via_npm "gemini"; then
        return 0
    fi

    print_fail "Gemini CLI installation failed."
    printf '  You can install manually: npm install -g @google/gemini-cli\n'
    return 1
}

install_cli() {
    local cli="$1"
    case "$cli" in
        codex)  install_codex_cli ;;
        claude) install_claude_cli ;;
        gemini) install_gemini_cli ;;
        *) log_error "Unknown CLI: $cli"; return 1 ;;
    esac
}

install_codex_desktop() {
    print_step "Installing Codex Desktop..."

    local arch arch_label filename download_url expected_sha
    arch="$(detect_arch)"
    case "$arch" in
        x86_64)
            arch_label="x64"
            expected_sha="$CODEX_DESKTOP_SHA256_X86_64"
            ;;
        aarch64)
            arch_label="arm64"
            expected_sha="$CODEX_DESKTOP_SHA256_AARCH64"
            ;;
        *) log_error "Unsupported architecture for Codex Desktop: $arch"; return 1 ;;
    esac

    filename="Codex-darwin-${arch_label}-${CODEX_DESKTOP_VERSION}.zip"
    download_url="${CODEX_DESKTOP_URL_BASE}/${filename}"

    local tmp_dir dest_file
    tmp_dir="$(mktemp -d)"
    dest_file="${tmp_dir}/${filename}"

    # Download — try bundle/cache, then direct URL (oaistatic.com CDN, no proxy needed)
    if ! download_with_fallback "$filename" "$download_url" "" "$dest_file" "$expected_sha"; then
        rm -rf "$tmp_dir"
        print_fail "Failed to download Codex Desktop."
        printf '  You can download manually: https://openai.com/codex/\n'
        return 1
    fi

    # Verify zip integrity
    if ! unzip -tq "$dest_file" >>"$LEUNG_LOG_FILE" 2>&1; then
        rm -rf "$tmp_dir"
        print_fail "Codex Desktop zip is corrupt. Please re-run the installer."
        return 1
    fi

    # Extract and install to /Applications (or ~/Applications)
    local app_dir="/Applications"
    if [[ ! -w "$app_dir" ]]; then
        app_dir="${HOME}/Applications"
        mkdir -p "$app_dir"
    fi

    log_info "Extracting Codex Desktop to $app_dir..."
    unzip -oq "$dest_file" -d "$tmp_dir/extracted" >>"$LEUNG_LOG_FILE" 2>&1

    # Find the .app bundle inside extracted contents
    local app_bundle=""
    app_bundle="$(find "$tmp_dir/extracted" -maxdepth 2 -name "Codex.app" -type d | head -1)"
    if [[ -z "$app_bundle" ]]; then
        # Fallback: any .app
        app_bundle="$(find "$tmp_dir/extracted" -maxdepth 2 -name "*.app" -type d | head -1)"
    fi

    if [[ -z "$app_bundle" ]]; then
        rm -rf "$tmp_dir"
        print_fail "Codex.app not found in zip archive."
        return 1
    fi

    # Remove old installation if present
    local target_app="${app_dir}/$(basename "$app_bundle")"
    if [[ -d "$target_app" ]]; then
        log_info "Removing previous installation: $target_app"
        rm -rf "$target_app"
    fi

    # Move into Applications
    mv "$app_bundle" "$app_dir/" >>"$LEUNG_LOG_FILE" 2>&1
    rm -rf "$tmp_dir"

    # Remove quarantine so it can launch without Gatekeeper prompt
    xattr -r -d com.apple.quarantine "$target_app" 2>/dev/null || true

    print_ok "Codex Desktop installed to $target_app"
}

ensure_path_entry() {
    local dir="$1"
    local shell_rc=""

    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
        shell_rc="${HOME}/.zshrc"
    else
        shell_rc="${HOME}/.bash_profile"
    fi

    if [[ -f "$shell_rc" ]] && grep -q "$dir" "$shell_rc" 2>/dev/null; then
        return 0
    fi

    printf '\nexport PATH="%s:$PATH"\n' "$dir" >> "$shell_rc"
    export PATH="${dir}:${PATH}"
    log_info "Added $dir to PATH in $shell_rc"
}
