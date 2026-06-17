#!/usr/bin/env bash
# LEUNG CLI Installer - Interactive UI (macOS)
# Follows linux-installer tty-safe input pattern to prevent
# auto-exit when stdin is not a terminal (e.g. curl | bash).

UI_BACK_TOKEN="__back__"
UI_MENU_RESULT=""
UI_INPUT_RESULT=""
REPLY_API_KEY=""

# ─── TTY-safe input layer ───────────────────────────────────────────────────

tty_read_line() {
    local var=""
    if [[ -t 0 ]]; then
        IFS= read -r var || return 1
    elif [[ -r /dev/tty ]]; then
        IFS= read -r var </dev/tty || return 1
    else
        IFS= read -r var || return 1
    fi
    UI_INPUT_RESULT="$var"
}

tty_prompt() {
    local prompt="$1"
    printf '%s' "$prompt" >&2
    tty_read_line
}

ui_prompt_choice() {
    local prompt="$1"
    shift
    local allowed=""
    while true; do
        if ! tty_prompt "$prompt"; then
            return 1
        fi
        # Ignore empty input (prevents auto-enter issue)
        if [[ -z "$UI_INPUT_RESULT" ]]; then
            continue
        fi
        for allowed in "$@"; do
            if [[ "$UI_INPUT_RESULT" == "$allowed" ]]; then
                UI_MENU_RESULT="$UI_INPUT_RESULT"
                return 0
            fi
        done
        printf '\033[31m  无效输入：%s\033[0m\n' "$UI_INPUT_RESULT" >&2
    done
}

ui_prompt_text() {
    local prompt="$1"
    while true; do
        if ! tty_prompt "$prompt"; then
            return 1
        fi
        if [[ -n "$UI_INPUT_RESULT" ]]; then
            return 0
        fi
    done
}

# ─── Banner & display ───────────────────────────────────────────────────────

show_banner() {
    printf '\n' >&2
    printf '\033[36m  ╔══════════════════════════════════════════════╗\033[0m\n' >&2
    printf '\033[36m  ║       LEUNG CLI Installer for macOS          ║\033[0m\n' >&2
    printf '\033[36m  ║                                              ║\033[0m\n' >&2
    printf '\033[36m  ║   Codex CLI / Claude Code / Gemini CLI       ║\033[0m\n' >&2
    printf '\033[36m  ║   + Codex Desktop + LEUNG API Relay          ║\033[0m\n' >&2
    printf '\033[36m  ╚══════════════════════════════════════════════╝\033[0m\n' >&2
    printf '\n' >&2
}

# ─── Main menu ──────────────────────────────────────────────────────────────

show_main_menu() {
    printf '\n' >&2
    printf '  Choose an action:\n' >&2
    printf '    \033[32m[1] Install CLIs + Configure\033[0m\n' >&2
    printf '    \033[33m[2] Configure only\033[0m\n' >&2
    printf '    \033[36m[3] View current configuration\033[0m\n' >&2
    printf '    \033[90m[4] Exit\033[0m\n' >&2
    printf '\n' >&2
    ui_prompt_choice '  Selection (1-4): ' 1 2 3 4 || {
        MENU_CHOICE="4"
        return 0
    }
    MENU_CHOICE="$UI_MENU_RESULT"
}

# ─── CLI selection ──────────────────────────────────────────────────────────

show_cli_selection() {
    printf '\n' >&2
    printf '  Select CLIs to install:\n' >&2
    printf '    \033[32m[1] All (Codex CLI + Claude + Gemini + Codex Desktop)\033[0m\n' >&2
    printf '    \033[33m[2] Codex CLI only\033[0m\n' >&2
    printf '    \033[33m[3] Claude Code only\033[0m\n' >&2
    printf '    \033[33m[4] Gemini CLI only\033[0m\n' >&2
    printf '    \033[33m[5] Codex Desktop only\033[0m\n' >&2
    printf '    \033[36m[6] Custom selection\033[0m\n' >&2
    printf '\n' >&2
    ui_prompt_choice '  Selection (1-6): ' 1 2 3 4 5 6 || {
        CLI_SELECTION="1"
        return 0
    }
    CLI_SELECTION="$UI_MENU_RESULT"
}

show_custom_selection() {
    INSTALL_CODEX=0; INSTALL_DESKTOP=0; INSTALL_CLAUDE=0; INSTALL_GEMINI=0

    tty_prompt '    Install Codex CLI? (Y/n): ' || true
    [[ -z "$UI_INPUT_RESULT" || "$UI_INPUT_RESULT" =~ ^[Yy] ]] && INSTALL_CODEX=1

    tty_prompt '    Install Codex Desktop? (Y/n): ' || true
    [[ -z "$UI_INPUT_RESULT" || "$UI_INPUT_RESULT" =~ ^[Yy] ]] && INSTALL_DESKTOP=1

    tty_prompt '    Install Claude Code? (Y/n): ' || true
    [[ -z "$UI_INPUT_RESULT" || "$UI_INPUT_RESULT" =~ ^[Yy] ]] && INSTALL_CLAUDE=1

    tty_prompt '    Install Gemini CLI? (Y/n): ' || true
    [[ -z "$UI_INPUT_RESULT" || "$UI_INPUT_RESULT" =~ ^[Yy] ]] && INSTALL_GEMINI=1
}

# ─── API Key input ──────────────────────────────────────────────────────────

# Legacy single-key input (kept for backward compatibility)
read_api_key() {
    local default="${1:-}"
    if [[ -n "$default" ]]; then
        local masked="${default:0:8}..."
        printf '  Current API Key: %s\n' "$masked" >&2
    fi
    while true; do
        tty_prompt '  Enter your API Key (shared across all CLIs): ' || return 1
        REPLY_API_KEY="$UI_INPUT_RESULT"
        if [[ -z "$REPLY_API_KEY" && -n "$default" ]]; then
            REPLY_API_KEY="$default"
            return 0
        fi
        if [[ -n "$REPLY_API_KEY" ]]; then
            return 0
        fi
        printf '\033[31m  API Key cannot be empty.\033[0m\n' >&2
    done
}

# Per-CLI key input. Accepts space-separated list of CLIs to configure.
# Sets REPLY_KEY_CODEX, REPLY_KEY_CLAUDE, REPLY_KEY_GEMINI variables.
REPLY_KEY_CODEX=""
REPLY_KEY_CLAUDE=""
REPLY_KEY_GEMINI=""

read_api_keys() {
    local clis="$1"  # e.g. "codex claude gemini"
    REPLY_KEY_CODEX=""
    REPLY_KEY_CLAUDE=""
    REPLY_KEY_GEMINI=""

    # Collect existing keys as defaults
    local default_codex="" default_claude="" default_gemini=""
    for cli in $clis; do
        case "$cli" in
            codex)  default_codex="$(get_current_config codex)" ;;
            claude) default_claude="$(get_current_config claude)" ;;
            gemini) default_gemini="$(get_current_config gemini)" ;;
        esac
    done

    # Count how many CLIs are selected
    local cli_count=0
    for _ in $clis; do cli_count=$((cli_count + 1)); done

    # If only one CLI, just ask for that key directly
    if [[ "$cli_count" -eq 1 ]]; then
        local the_cli="$clis"
        local the_default=""
        case "$the_cli" in
            codex)  the_default="$default_codex" ;;
            claude) the_default="$default_claude" ;;
            gemini) the_default="$default_gemini" ;;
        esac
        _read_single_key "$the_cli" "$the_default"
        return 0
    fi

    # Multiple CLIs — ask shared or separate
    printf '\n' >&2
    printf '  API Key 配置方式:\n' >&2
    printf '    \033[32m[1] 所有 CLI 使用同一个 Key\033[0m\n' >&2
    printf '    \033[33m[2] 每个 CLI 使用不同的 Key\033[0m\n' >&2
    printf '\n' >&2
    ui_prompt_choice '  Selection (1-2): ' 1 2 || {
        UI_MENU_RESULT="1"
    }

    if [[ "$UI_MENU_RESULT" == "1" ]]; then
        # Shared key — find any existing key as default
        local shared_default="${default_codex:-${default_claude:-${default_gemini:-}}}"
        if [[ -n "$shared_default" ]]; then
            printf '  Current shared Key: %s...\n' "${shared_default:0:8}" >&2
        fi
        local shared_key=""
        while true; do
            tty_prompt '  Enter API Key (shared): ' || return 1
            shared_key="$UI_INPUT_RESULT"
            if [[ -z "$shared_key" && -n "$shared_default" ]]; then
                shared_key="$shared_default"
                break
            fi
            if [[ -n "$shared_key" ]]; then
                break
            fi
            printf '\033[31m  API Key cannot be empty.\033[0m\n' >&2
        done
        for cli in $clis; do
            case "$cli" in
                codex)  REPLY_KEY_CODEX="$shared_key" ;;
                claude) REPLY_KEY_CLAUDE="$shared_key" ;;
                gemini) REPLY_KEY_GEMINI="$shared_key" ;;
            esac
        done
    else
        # Separate keys
        for cli in $clis; do
            _read_single_key "$cli" ""
        done
    fi
}

_read_single_key() {
    local cli="$1" default="$2"
    local display=""
    case "$cli" in
        codex)  display="Codex";  [[ -z "$default" ]] && default="$(get_current_config codex)" ;;
        claude) display="Claude"; [[ -z "$default" ]] && default="$(get_current_config claude)" ;;
        gemini) display="Gemini"; [[ -z "$default" ]] && default="$(get_current_config gemini)" ;;
    esac

    if [[ -n "$default" ]]; then
        printf '  [%s] Current Key: %s...\n' "$display" "${default:0:8}" >&2
    fi

    local key=""
    while true; do
        tty_prompt "  Enter API Key for $display: " || return 1
        key="$UI_INPUT_RESULT"
        if [[ -z "$key" && -n "$default" ]]; then
            key="$default"
            break
        fi
        if [[ -n "$key" ]]; then
            break
        fi
        printf '\033[31m  API Key cannot be empty.\033[0m\n' >&2
    done

    case "$cli" in
        codex)  REPLY_KEY_CODEX="$key" ;;
        claude) REPLY_KEY_CLAUDE="$key" ;;
        gemini) REPLY_KEY_GEMINI="$key" ;;
    esac
}

# ─── Confirmation ───────────────────────────────────────────────────────────

confirm_action() {
    local msg="$1"
    tty_prompt "  $msg (Y/n): " || return 1
    [[ -z "$UI_INPUT_RESULT" || "$UI_INPUT_RESULT" =~ ^[Yy] ]]
}
