#!/usr/bin/env bash
# LEUNG CLI Installer - Common functions and constants

set -euo pipefail

# Ensure essential system paths are present even in non-interactive SSH or
# curl|bash invocations where PATH may be extremely minimal.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH}"

LEUNG_HOME="${HOME}/.leung"
CODEX_HOME="${HOME}/.codex"
CODEX_CONFIG_FILE="${CODEX_HOME}/config.toml"
CODEX_AUTH_FILE="${CODEX_HOME}/auth.json"
CLAUDE_HOME="${HOME}/.claude"
CLAUDE_CONFIG_FILE="${CLAUDE_HOME}/settings.json"
GEMINI_HOME="${HOME}/.gemini"
GEMINI_CONFIG_FILE="${GEMINI_HOME}/settings.json"
GEMINI_ENV_FILE="${GEMINI_HOME}/.env"
LEUNG_LOG_DIR="${LEUNG_HOME}/logs"
LEUNG_LOG_FILE="${LEUNG_LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

LEUNG_DEFAULT_CODEX_URL="https://api.leung315.site/v1"
LEUNG_DEFAULT_CLAUDE_URL="https://api.leung315.site"
LEUNG_DEFAULT_GEMINI_URL="https://api.leung315.site"
LEUNG_DEFAULT_CODEX_MODEL="gpt-5.4"
LEUNG_DEFAULT_CLAUDE_MODEL="claude-sonnet-4-5"
LEUNG_DEFAULT_GEMINI_MODEL="gemini-2.5-pro"

CODEX_FALLBACK_TAG="rust-v0.137.0"
# SHA256 of the release tarballs (codex-<target>.tar.gz). Used to reject
# truncated/corrupted downloads before extraction — a slow/unstable network
# can otherwise yield a partial binary that crashes with a dyld
# "rebase opcodes terminated early" error at runtime.
CODEX_FALLBACK_SHA256_X86_64="32206ff8e4edb3422832b24d25a521246e4478b67bab2ec63bee632fdf94b306"
CODEX_FALLBACK_SHA256_AARCH64="628d2278b1fa2a467452635f2fd5aaeee98de4a94f2af06031e4790da6844046"

# Codex Desktop (Electron app)
CODEX_DESKTOP_VERSION="26.609.41114"
CODEX_DESKTOP_URL_BASE="https://persistent.oaistatic.com/codex-app-prod"
# SHA256 of the zip files — set to "" to skip verification (e.g. if version updates)
CODEX_DESKTOP_SHA256_X86_64=""
CODEX_DESKTOP_SHA256_AARCH64=""
GITHUB_RELEASE_BASE="https://github.com"
# Multiple GitHub download proxies, tried in order. Direct github.com is often
# blocked/throttled in CN; ghfast.top is the most reliable mirror in testing.
# A bash array so it splits correctly regardless of shell IFS/word-splitting.
GITHUB_PROXY_BASES=(
    "https://ghfast.top/"
    "https://ghproxy.net/"
    "https://gh.llkk.cc/"
    "https://mirror.ghproxy.com/"
)
# Backward-compat single value (first entry of the list).
GITHUB_PROXY_BASE="https://ghfast.top/"
NPM_REGISTRY_MIRROR="https://registry.npmmirror.com"

ensure_directories() {
    local dirs=("$LEUNG_HOME" "$LEUNG_LOG_DIR" "$CODEX_HOME" "$CLAUDE_HOME" "$GEMINI_HOME")
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || mkdir -p "$d"
    done
}

log_msg() {
    local level="${1:-INFO}" msg="${2:-}"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" >> "$LEUNG_LOG_FILE" 2>/dev/null || true
    case "$level" in
        ERROR) printf '\033[31m[%s] [%s] %s\033[0m\n' "$ts" "$level" "$msg" ;;
        WARN)  printf '\033[33m[%s] [%s] %s\033[0m\n' "$ts" "$level" "$msg" ;;
        *)     printf '\033[90m[%s] [%s] %s\033[0m\n' "$ts" "$level" "$msg" ;;
    esac
}

log_info()  { log_msg INFO  "$1"; }
log_warn()  { log_msg WARN  "$1"; }
log_error() { log_msg ERROR "$1"; }

print_step() {
    printf '\n\033[36m>> %s\033[0m\n' "$1"
    log_info "$1"
}

print_ok() {
    printf '\033[32m[OK] %s\033[0m\n' "$1"
    log_info "$1"
}

print_fail() {
    printf '\033[31m[FAIL] %s\033[0m\n' "$1"
    log_error "$1"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}
