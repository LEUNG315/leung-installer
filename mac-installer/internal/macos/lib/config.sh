#!/usr/bin/env bash
# LEUNG CLI Installer - Configuration writing

TEMPLATE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../templates" && pwd)"

write_codex_config() {
    local api_key="$1" base_url="${2:-$LEUNG_DEFAULT_CODEX_URL}" model="${3:-$LEUNG_DEFAULT_CODEX_MODEL}"

    mkdir -p "$CODEX_HOME"

    cat > "$CODEX_CONFIG_FILE" <<EOF
model_provider = "leung"
model = "${model}"
model_reasoning_effort = "high"
disable_response_storage = true

[model_providers.leung]
name = "LEUNG API"
base_url = "${base_url}"
wire_api = "responses"
requires_openai_auth = true
model_context_window = 250000
model_auto_compact_token_limit = 200000
EOF
    chmod 600 "$CODEX_CONFIG_FILE"

    cat > "$CODEX_AUTH_FILE" <<EOF
{
  "OPENAI_API_KEY": "${api_key}"
}
EOF
    chmod 600 "$CODEX_AUTH_FILE"

    log_info "Written: $CODEX_CONFIG_FILE, $CODEX_AUTH_FILE"
}

write_claude_config() {
    local api_key="$1" base_url="${2:-$LEUNG_DEFAULT_CLAUDE_URL}" model="${3:-$LEUNG_DEFAULT_CLAUDE_MODEL}"

    mkdir -p "$CLAUDE_HOME"

    # Claude Code reads settings.json with an "env" block for API config.
    # Matches the Linux template format.
    cat > "$CLAUDE_CONFIG_FILE" <<EOF
{
  "ENABLE_TOOL_SEARCH": true,
  "skipWebFetchPreflight": true,
  "env": {
    "ANTHROPIC_BASE_URL": "${base_url}",
    "ANTHROPIC_API_KEY": "${api_key}",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"
  }
}
EOF
    chmod 600 "$CLAUDE_CONFIG_FILE"

    log_info "Written: $CLAUDE_CONFIG_FILE"
}

write_gemini_config() {
    local api_key="$1" base_url="${2:-$LEUNG_DEFAULT_GEMINI_URL}" model="${3:-$LEUNG_DEFAULT_GEMINI_MODEL}"

    mkdir -p "$GEMINI_HOME"

    # Gemini CLI expects security.auth to identify which auth method to use, and
    # model.name (not a flat "model" string). Matches the Linux template.
    cat > "$GEMINI_CONFIG_FILE" <<EOF
{
  "security": {
    "auth": {
      "selectedType": "gemini-api-key",
      "enforcedType": "gemini-api-key"
    }
  },
  "model": {
    "name": "${model}"
  }
}
EOF
    chmod 600 "$GEMINI_CONFIG_FILE"

    # .env — Gemini CLI reads GOOGLE_GEMINI_BASE_URL (not GEMINI_API_BASE_URL)
    cat > "$GEMINI_ENV_FILE" <<EOF
GOOGLE_GEMINI_BASE_URL=${base_url}
GEMINI_API_KEY=${api_key}
GEMINI_MODEL=${model}
EOF
    chmod 600 "$GEMINI_ENV_FILE"

    log_info "Written: $GEMINI_CONFIG_FILE, $GEMINI_ENV_FILE"
}

write_cli_config() {
    local cli="$1" api_key="$2" base_url="${3:-}" model="${4:-}"
    case "$cli" in
        codex)  write_codex_config "$api_key" "${base_url:-$LEUNG_DEFAULT_CODEX_URL}" "${model:-$LEUNG_DEFAULT_CODEX_MODEL}" ;;
        claude) write_claude_config "$api_key" "${base_url:-$LEUNG_DEFAULT_CLAUDE_URL}" "${model:-$LEUNG_DEFAULT_CLAUDE_MODEL}" ;;
        gemini) write_gemini_config "$api_key" "${base_url:-$LEUNG_DEFAULT_GEMINI_URL}" "${model:-$LEUNG_DEFAULT_GEMINI_MODEL}" ;;
        *) log_error "Unknown CLI: $cli"; return 1 ;;
    esac
}

get_current_config() {
    local cli="$1"
    case "$cli" in
        codex)
            if [[ -f "$CODEX_AUTH_FILE" ]]; then
                python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('OPENAI_API_KEY',''))" "$CODEX_AUTH_FILE" 2>/dev/null || true
            fi
            ;;
        claude)
            if [[ -f "$CLAUDE_CONFIG_FILE" ]]; then
                python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('env',{}).get('ANTHROPIC_API_KEY','') or d.get('apiKey',''))" "$CLAUDE_CONFIG_FILE" 2>/dev/null || true
            fi
            ;;
        gemini)
            if [[ -f "$GEMINI_ENV_FILE" ]]; then
                awk -F= '/^GEMINI_API_KEY=/ {print $2}' "$GEMINI_ENV_FILE" 2>/dev/null || true
            fi
            ;;
    esac
}

show_all_config_summary() {
    printf '\n\033[36m  Current Configuration:\033[0m\n'
    for cli in codex claude gemini; do
        local display="" config_file="" key=""
        case "$cli" in
            codex)  display="Codex CLI";  config_file="$CODEX_CONFIG_FILE" ;;
            claude) display="Claude Code"; config_file="$CLAUDE_CONFIG_FILE" ;;
            gemini) display="Gemini CLI"; config_file="$GEMINI_CONFIG_FILE" ;;
        esac
        if [[ -f "$config_file" ]]; then
            key="$(get_current_config "$cli")"
            local masked=""
            if [[ -n "$key" ]]; then
                masked="${key:0:8}..."
            fi
            printf '    [%s]\n' "$display"
            printf '      Config: %s\n' "$config_file"
            [[ -n "$masked" ]] && printf '      Key:    %s\n' "$masked"
        fi
    done
    printf '\n'
}
