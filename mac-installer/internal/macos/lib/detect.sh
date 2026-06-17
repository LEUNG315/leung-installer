#!/usr/bin/env bash
# LEUNG CLI Installer - System detection

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) printf 'x86_64' ;;
        arm64|aarch64) printf 'aarch64' ;;
        *) printf '%s' "$arch" ;;
    esac
}

detect_macos_version() {
    sw_vers -productVersion 2>/dev/null || echo "unknown"
}

test_brew_available() {
    have_cmd brew
}

test_npm_available() {
    have_cmd npm
}

test_node_available() {
    have_cmd node
}

test_cli_installed() {
    local cli="$1"
    case "$cli" in
        codex)  have_cmd codex ;;
        claude) have_cmd claude ;;
        gemini) have_cmd gemini ;;
        *) return 1 ;;
    esac
}

get_cli_version() {
    local cli="$1" binary=""
    case "$cli" in
        codex)  binary="codex" ;;
        claude) binary="claude" ;;
        gemini) binary="gemini" ;;
        *) return 1 ;;
    esac
    "$binary" --version 2>/dev/null || echo ""
}

test_codex_desktop_installed() {
    [[ -d "/Applications/Codex.app" ]] || \
    [[ -d "$HOME/Applications/Codex.app" ]]
}

test_config_exists() {
    local cli="$1"
    case "$cli" in
        codex)  [[ -f "$CODEX_CONFIG_FILE" ]] ;;
        claude) [[ -f "$CLAUDE_CONFIG_FILE" ]] ;;
        gemini) [[ -f "$GEMINI_CONFIG_FILE" ]] ;;
        *) return 1 ;;
    esac
}

# Verify a Mach-O binary matches the current machine's architecture.
# Returns 0 if compatible, 1 otherwise.
verify_binary_arch() {
    local binary_path="$1"
    local current_arch
    current_arch="$(uname -m)"

    if ! have_cmd file; then
        log_warn "file command not available, skipping arch verification."
        return 0
    fi

    local file_info
    file_info="$(file "$binary_path" 2>/dev/null)"

    # Universal binary — always OK
    if [[ "$file_info" == *"universal binary"* ]]; then
        return 0
    fi

    case "$current_arch" in
        arm64|aarch64)
            if [[ "$file_info" == *"arm64"* ]]; then
                return 0
            fi
            # x86_64 binary on arm64 — check Rosetta
            if [[ "$file_info" == *"x86_64"* ]]; then
                if test_rosetta_available; then
                    log_warn "Binary is x86_64, will run via Rosetta 2."
                    return 0
                else
                    log_error "Binary is x86_64 but Rosetta 2 is not installed."
                    log_error "Install Rosetta: softwareupdate --install-rosetta"
                    return 1
                fi
            fi
            ;;
        x86_64|amd64)
            if [[ "$file_info" == *"x86_64"* ]]; then
                return 0
            fi
            if [[ "$file_info" == *"arm64"* ]]; then
                log_error "Binary is arm64 but this machine is x86_64."
                return 1
            fi
            ;;
    esac

    # Could not determine — let it pass, runtime will catch it
    log_warn "Could not verify binary architecture: $file_info"
    return 0
}

# Check if Rosetta 2 is available on Apple Silicon
test_rosetta_available() {
    # /Library/Apple/usr/share/rosetta exists when Rosetta is installed
    [[ -d "/Library/Apple/usr/share/rosetta" ]] || \
    arch -x86_64 /usr/bin/true 2>/dev/null
}

print_system_status() {
    local macos_ver arch brew_ok node_ok npm_ok
    macos_ver="$(detect_macos_version)"
    arch="$(detect_arch)"
    brew_ok=$(test_brew_available && echo "Available" || echo "Not found")
    node_ok=$(test_node_available && echo "Available" || echo "Not found")
    npm_ok=$(test_npm_available && echo "Available" || echo "Not found")

    printf '\n\033[36m  System Status:\033[0m\n'
    printf '    macOS:         %s (%s)\n' "$macos_ver" "$arch"
    printf '    Homebrew:      %s\n' "$brew_ok"
    printf '    Node.js:       %s\n' "$node_ok"
    printf '    npm:           %s\n' "$npm_ok"
    printf '\n'

    for cli in codex claude gemini; do
        local display="" installed=""
        case "$cli" in
            codex)  display="Codex CLI" ;;
            claude) display="Claude Code" ;;
            gemini) display="Gemini CLI" ;;
        esac
        if test_cli_installed "$cli"; then
            local ver
            ver="$(get_cli_version "$cli")"
            printf '    %-14s \033[32mInstalled%s\033[0m\n' "$display:" "${ver:+ ($ver)}"
        else
            printf '    %-14s \033[90mNot installed\033[0m\n' "$display:"
        fi
    done

    if test_codex_desktop_installed; then
        printf '    %-14s \033[32mInstalled\033[0m\n' "Codex Desktop:"
    else
        printf '    %-14s \033[90mNot installed\033[0m\n' "Codex Desktop:"
    fi
    printf '\n'
}
