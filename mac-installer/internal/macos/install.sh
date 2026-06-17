#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/node-config.sh"
source "$SCRIPT_DIR/lib/download.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/installers.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/ui.sh"

# CLI arguments
NONINTERACTIVE=0
ARG_API_KEY=""
ARG_CODEX_KEY=""
ARG_CLAUDE_KEY=""
ARG_GEMINI_KEY=""
ARG_URL=""
ARG_MODEL=""
ARG_CLIS=""
SKIP_DESKTOP=0
CONFIG_ONLY=0

usage() {
    cat <<'EOF'
LEUNG CLI Installer for macOS
================================

Usage:
  bash install.sh                                    Interactive mode
  bash install.sh --noninteractive --api-key sk-xxx  Install all CLIs
  bash install.sh --noninteractive --api-key sk-xxx --cli codex,claude
  bash install.sh --config-only --api-key sk-xxx     Config only

Options:
  --noninteractive   Run without prompts
  --api-key <key>    Default API Key (used when per-CLI key not set)
  --codex-key <key>  API Key for Codex CLI
  --claude-key <key> API Key for Claude Code
  --gemini-key <key> API Key for Gemini CLI
  --url <url>        Override base URL for all CLIs
  --model <model>    Override model name
  --cli <list>       Which CLIs: codex, claude, gemini (comma-separated)
                     Default: all three
  --skip-desktop     Skip Codex Desktop installation
  --config-only      Only write config files
  --help             Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --noninteractive) NONINTERACTIVE=1 ;;
            --api-key)    ARG_API_KEY="${2:-}"; shift ;;
            --codex-key)  ARG_CODEX_KEY="${2:-}"; shift ;;
            --claude-key) ARG_CLAUDE_KEY="${2:-}"; shift ;;
            --gemini-key) ARG_GEMINI_KEY="${2:-}"; shift ;;
            --url)        ARG_URL="${2:-}"; shift ;;
            --model)      ARG_MODEL="${2:-}"; shift ;;
            --cli)        ARG_CLIS="${2:-}"; shift ;;
            --skip-desktop) SKIP_DESKTOP=1 ;;
            --config-only)  CONFIG_ONLY=1 ;;
            --help|-h)  usage; exit 0 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
        esac
        shift
    done
}

# Resolve the effective key for a given CLI (per-CLI key takes priority)
resolve_api_key() {
    local cli="$1"
    case "$cli" in
        codex)  printf '%s' "${ARG_CODEX_KEY:-$ARG_API_KEY}" ;;
        claude) printf '%s' "${ARG_CLAUDE_KEY:-$ARG_API_KEY}" ;;
        gemini) printf '%s' "${ARG_GEMINI_KEY:-$ARG_API_KEY}" ;;
    esac
}

run_noninteractive() {
    if [[ -z "$ARG_API_KEY" && -z "$ARG_CODEX_KEY" && -z "$ARG_CLAUDE_KEY" && -z "$ARG_GEMINI_KEY" ]]; then
        print_fail "API Key is required. Use --api-key or per-CLI keys (--codex-key, --claude-key, --gemini-key)."
        exit 1
    fi

    local IFS=','
    local clis=()
    if [[ -n "$ARG_CLIS" ]]; then
        read -ra clis <<< "$ARG_CLIS"
    else
        clis=(codex claude gemini)
    fi

    ensure_directories

    if [[ "$CONFIG_ONLY" != "1" ]]; then
        for cli in "${clis[@]}"; do
            if ! test_cli_installed "$cli"; then
                install_cli "$cli" || log_warn "$cli installation failed."
            else
                print_ok "$cli already installed."
            fi
        done

        if [[ "$SKIP_DESKTOP" != "1" ]]; then
            local has_codex=0
            for c in "${clis[@]}"; do [[ "$c" == "codex" ]] && has_codex=1; done
            if [[ "$has_codex" == "1" ]] && ! test_codex_desktop_installed; then
                install_codex_desktop || true
            fi
        fi
    fi

    for cli in "${clis[@]}"; do
        local key
        key="$(resolve_api_key "$cli")"
        if [[ -z "$key" ]]; then
            log_warn "No API key for $cli, skipping config."
            continue
        fi
        write_cli_config "$cli" "$key" "$ARG_URL" "$ARG_MODEL"
        print_ok "$cli configured."
    done

    print_ok "Installation complete."
    show_all_config_summary
}

run_interactive() {
    show_banner
    ensure_directories

    if ! command -v python3 >/dev/null 2>&1; then
        printf '\033[33m  [WARN] python3 未找到，部分配置读取功能将受限。\033[0m\n' >&2
        printf '  请安装 Xcode Command Line Tools: xcode-select --install\n' >&2
        printf '\n' >&2
    fi

    print_system_status

    while true; do
        show_main_menu
        case "$MENU_CHOICE" in
            1) run_interactive_install ;;
            2) run_interactive_config ;;
            3) show_all_config_summary ;;
            4) printf '\n  Bye!\n\n'; return ;;
            *) printf '\033[31m  Invalid selection.\033[0m\n' ;;
        esac
    done
}

run_interactive_install() {
    INSTALL_CODEX=0; INSTALL_DESKTOP=0; INSTALL_CLAUDE=0; INSTALL_GEMINI=0

    show_cli_selection
    case "$CLI_SELECTION" in
        1) INSTALL_CODEX=1; INSTALL_CLAUDE=1; INSTALL_GEMINI=1; INSTALL_DESKTOP=1 ;;
        2) INSTALL_CODEX=1 ;;
        3) INSTALL_CLAUDE=1 ;;
        4) INSTALL_GEMINI=1 ;;
        5) INSTALL_DESKTOP=1 ;;
        6) show_custom_selection ;;
        *) INSTALL_CODEX=1; INSTALL_CLAUDE=1; INSTALL_GEMINI=1; INSTALL_DESKTOP=1 ;;
    esac

    # Build space-separated CLI list for read_api_keys
    # Codex Desktop shares config with Codex CLI (~/.codex/), so include codex
    # in config when Desktop is selected.
    local cli_list=""
    if [[ "$INSTALL_CODEX" == "1" || "$INSTALL_DESKTOP" == "1" ]]; then
        cli_list="${cli_list}codex "
    fi
    [[ "$INSTALL_CLAUDE" == "1" ]] && cli_list="${cli_list}claude "
    [[ "$INSTALL_GEMINI" == "1" ]] && cli_list="${cli_list}gemini "
    cli_list="${cli_list% }"  # trim trailing space

    if [[ -n "$cli_list" ]]; then
        read_api_keys "$cli_list"
    fi

    printf '\n'
    if ! confirm_action "Proceed with installation?"; then
        printf '  Cancelled.\n'
        return
    fi

    # CLIs to install (binaries)
    local install_clis=()
    [[ "$INSTALL_CODEX" == "1" ]] && install_clis+=(codex)
    [[ "$INSTALL_CLAUDE" == "1" ]] && install_clis+=(claude)
    [[ "$INSTALL_GEMINI" == "1" ]] && install_clis+=(gemini)

    # CLIs to configure (Desktop shares codex config)
    local config_clis=()
    if [[ "$INSTALL_CODEX" == "1" || "$INSTALL_DESKTOP" == "1" ]]; then
        config_clis+=(codex)
    fi
    [[ "$INSTALL_CLAUDE" == "1" ]] && config_clis+=(claude)
    [[ "$INSTALL_GEMINI" == "1" ]] && config_clis+=(gemini)

    if [[ ${#install_clis[@]} -gt 0 ]]; then
        for cli in "${install_clis[@]}"; do
            if ! test_cli_installed "$cli"; then
                install_cli "$cli" || true
            else
                print_ok "$cli already installed."
            fi
        done
    fi

    if [[ "$INSTALL_DESKTOP" == "1" ]]; then
        if ! test_codex_desktop_installed; then
            install_codex_desktop || true
        else
            print_ok "Codex Desktop already installed."
        fi
    fi

    if [[ ${#config_clis[@]} -gt 0 ]]; then
        print_step "Writing configuration..."
        for cli in "${config_clis[@]}"; do
            local key=""
            case "$cli" in
                codex)  key="$REPLY_KEY_CODEX" ;;
                claude) key="$REPLY_KEY_CLAUDE" ;;
                gemini) key="$REPLY_KEY_GEMINI" ;;
            esac
            if [[ -n "$key" ]]; then
                write_cli_config "$cli" "$key" "" ""
                print_ok "$cli configured."
            fi
        done
    fi

    printf '\n'
    print_ok "All done!"
    show_all_config_summary
}

run_interactive_config() {
    printf '\n  Configure which CLIs? (enter numbers, e.g. 123):\n' >&2
    printf '    [1] Codex   [2] Claude   [3] Gemini   [A] All\n' >&2
    tty_prompt '  Selection: ' || return
    local sel="$UI_INPUT_RESULT"
    [[ -z "$sel" || "$sel" =~ [Aa] ]] && sel="123"

    local clis=() cli_list=""
    if [[ "$sel" == *1* ]]; then clis+=(codex); cli_list="${cli_list}codex "; fi
    if [[ "$sel" == *2* ]]; then clis+=(claude); cli_list="${cli_list}claude "; fi
    if [[ "$sel" == *3* ]]; then clis+=(gemini); cli_list="${cli_list}gemini "; fi
    cli_list="${cli_list% }"

    if [[ ${#clis[@]} -eq 0 ]]; then
        printf '\033[31m  No CLI selected.\033[0m\n' >&2
        return
    fi

    read_api_keys "$cli_list"

    for cli in "${clis[@]}"; do
        local key=""
        case "$cli" in
            codex)  key="$REPLY_KEY_CODEX" ;;
            claude) key="$REPLY_KEY_CLAUDE" ;;
            gemini) key="$REPLY_KEY_GEMINI" ;;
        esac
        if [[ -n "$key" ]]; then
            write_cli_config "$cli" "$key" "" ""
        fi
    done

    print_ok "Configuration updated."
    show_all_config_summary
}

# Main
parse_args "$@"

if [[ "$NONINTERACTIVE" == "1" ]]; then
    run_noninteractive
else
    run_interactive
fi
