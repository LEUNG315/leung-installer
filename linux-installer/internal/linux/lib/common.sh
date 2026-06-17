#!/usr/bin/env bash

# shellcheck source=lib/common_context.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_context.sh"
# shellcheck source=lib/common_logging.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_logging.sh"
# shellcheck source=lib/common_download.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_download.sh"
# shellcheck source=lib/common_teststate.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_teststate.sh"
# shellcheck source=lib/common_cli.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_cli.sh"
# shellcheck source=lib/common_step.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_step.sh"
# shellcheck source=lib/common_rollback.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common_rollback.sh"

LEUNG_SCRIPT_DIR=""
LEUNG_BIN_DIR=""
LEUNG_HOME="${LEUNG_HOME:-$HOME/.leung}"
LEUNG_AUTH_FILE=""
LEUNG_CONFIG_FILE=""
LEUNG_LOG_DIR=""
LEUNG_BACKUP_DIR=""
LEUNG_CACHE_DIR=""
LEUNG_STATE_DIR=""
LEUNG_LOG_FILE=""
LEUNG_LAST_CLI_FILE=""
LEUNG_SUMMARY_FILE=""
LEUNG_CURRENT_STEP=""
LEUNG_CURRENT_STEP_FILE=""
LEUNG_LAST_ERROR=""
LEUNG_POST_INSTALL_WARNING=""
LEUNG_RESTORE_STACK_FILE=""
LEUNG_TRANSACTION_FILE=""
LEUNG_NPM_GLOBAL_PREFIX=""
LEUNG_NVM_DIR=""
LEUNG_ROLLBACK_STATUS="${LEUNG_ROLLBACK_STATUS:-未执行}"
LEUNG_ROLLBACK_DETAILS="${LEUNG_ROLLBACK_DETAILS:-}"

CLAUDE_HOME="$HOME/.claude"
# shellcheck disable=SC2034
CLAUDE_SETTINGS_FILE="$CLAUDE_HOME/settings.json"
CODEX_HOME="$HOME/.codex"
# shellcheck disable=SC2034
CODEX_CONFIG_FILE="$CODEX_HOME/config.toml"
# shellcheck disable=SC2034
CODEX_AUTH_FILE="$CODEX_HOME/auth.json"
GEMINI_HOME="$HOME/.gemini"
# shellcheck disable=SC2034
GEMINI_SETTINGS_FILE="$GEMINI_HOME/settings.json"
# shellcheck disable=SC2034
GEMINI_ENV_FILE="$GEMINI_HOME/.env"
LEUNG_NODE_VERSION="${LEUNG_NODE_VERSION:-24}"
LEUNG_NVM_VERSION="${LEUNG_NVM_VERSION:-v0.40.4}"
LEUNG_DRY_RUN="${LEUNG_DRY_RUN:-0}"
LEUNG_NONINTERACTIVE="${LEUNG_NONINTERACTIVE:-0}"
LEUNG_SKIP_DEPS="${LEUNG_SKIP_DEPS:-0}"
LEUNG_UI_MODE="${LEUNG_UI_MODE:-auto}"
LEUNG_NODE_RUNTIME="${LEUNG_NODE_RUNTIME:-unknown}"
LEUNG_TEST_MODE="${LEUNG_TEST_MODE:-0}"
LEUNG_KEEP_TEST_CONFIG="${LEUNG_KEEP_TEST_CONFIG:-0}"
LEUNG_TEST_API_KEY="${LEUNG_TEST_API_KEY:-sk-linux-installer-test-only-do-not-use}"
LEUNG_TEST_DEFAULT_URL="${LEUNG_TEST_DEFAULT_URL:-https://example.test/v1}"
LEUNG_DEFAULT_CLAUDE_URL="${LEUNG_DEFAULT_CLAUDE_URL:-https://api.leung315.site}"
LEUNG_DEFAULT_CODEX_URL="${LEUNG_DEFAULT_CODEX_URL:-https://api.leung315.site/v1}"
LEUNG_DEFAULT_GEMINI_URL="${LEUNG_DEFAULT_GEMINI_URL:-https://api.leung315.site}"
LEUNG_TEST_SNAPSHOT_DIR=""
LEUNG_TEST_MANIFEST_FILE=""
LEUNG_TEST_RUNTIME_DIR=""
LEUNG_MANIFEST_DIR=""
LEUNG_CLI_REGISTRY_FILE=""
LEUNG_REFRESH_INSTALLER_ON_EXIT="${LEUNG_REFRESH_INSTALLER_ON_EXIT:-0}"
LEUNG_REFRESH_BOOTSTRAP_URL="${LEUNG_REFRESH_BOOTSTRAP_URL:-}"
LEUNG_REFRESH_BOOTSTRAP_MIRROR_URL="${LEUNG_REFRESH_BOOTSTRAP_MIRROR_URL:-}"
LEUNG_INSTALLER_VERSION="${LEUNG_INSTALLER_VERSION:-}"
LEUNG_INSTALLER_PIN_REF="${LEUNG_INSTALLER_PIN_REF:-}"
LEUNG_INSTALLER_UPDATED_AT="${LEUNG_INSTALLER_UPDATED_AT:-}"
