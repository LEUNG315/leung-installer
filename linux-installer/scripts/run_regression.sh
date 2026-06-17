#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_PY="$ROOT_DIR/internal/linux/bin/config_helper.py"
REGRESSION_BASE_DIR="${LEUNG_REGRESSION_BASE_DIR:-$HOME/.tmp-leung-tests}"
mkdir -p "$REGRESSION_BASE_DIR"
WORK_DIR="$(mktemp -d "$REGRESSION_BASE_DIR/linux-installer-regression.XXXXXX")"

cleanup() {
	rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() {
	printf '[REGRESSION] %s\n' "$*" >&2
}

run_case() {
	local name="$1"
	shift
	log "RUN  $name"
	"$@"
	log "PASS $name"
}

test_syntax() {
	bash -n \
		"$ROOT_DIR/install.sh" \
		"$ROOT_DIR/bootstrap.sh" \
		"$ROOT_DIR/internal/linux/install.sh" \
		"$ROOT_DIR"/internal/linux/lib/*.sh \
		"$ROOT_DIR"/scripts/*.sh
	python3 -m py_compile "$HELPER_PY"
}

test_registry_manifest() {
	python3 - <<'PY'
import json
from pathlib import Path
reg = json.loads(Path('internal/linux/manifests/cli-registry.json').read_text(encoding='utf-8'))
ids = [item['id'] for item in reg['clis']]
assert ids == ['claude', 'codex', 'gemini'], ids
for item in reg['clis']:
    assert item['provider_key'].endswith('_base_url')
PY
}

test_noninteractive_default_urls() {
	local cli="" base=""
	for cli in claude codex gemini; do
		base="$WORK_DIR/$cli-default"
		mkdir -p "$base/home"
		HOME="$base/home" LEUNG_HOME="$base/home/.leung" LEUNG_SKIP_DEPS=1 \
			bash "$ROOT_DIR/install.sh" --noninteractive --dry-run --cli "$cli" --api-key sk-test >"$base/out.log" 2>&1
		case "$cli" in
		claude) grep -F 'URL=https://api.leung315.site' "$base/out.log" >/dev/null ;;
		codex) grep -F 'URL=https://api.leung315.site/v1' "$base/out.log" >/dev/null ;;
		gemini) grep -F 'URL=https://api.leung315.site/v1' "$base/out.log" >/dev/null ;;
		esac
	done
}

test_render_templates() {
	HELPER_PY="$HELPER_PY" TMPDIR="$WORK_DIR" python3 - <<'PY'
import json, os, subprocess, tempfile
from pathlib import Path
helper = Path(os.environ['HELPER_PY'])
base = Path(tempfile.mkdtemp(prefix='leung-lite-render-'))

claude_cfg = base / 'claude.json'
subprocess.run(['python3', str(helper), 'render-claude', str(claude_cfg), 'sk-claude', 'https://api.anthropic.com', 'claude-sonnet-4-5'], check=True)
claude = json.loads(claude_cfg.read_text(encoding='utf-8'))
assert claude['env']['ANTHROPIC_BASE_URL'] == 'https://api.anthropic.com'

codex_cfg = base / 'codex.toml'
subprocess.run(['python3', str(helper), 'render-codex', str(codex_cfg), 'sk-codex', 'https://api.openai.com/v1', 'gpt-5.4'], check=True)
text = codex_cfg.read_text(encoding='utf-8')
assert 'model_provider = "leung"' in text
assert '[model_providers.leung]' in text
assert 'name = "LEUNG API"' in text
assert 'base_url = "https://api.openai.com/v1"' in text
assert 'model = "gpt-5.4"' in text

gemini_settings = base / 'gemini-settings.json'
gemini_env = base / 'gemini.env'
subprocess.run(['python3', str(helper), 'render-gemini-settings', str(gemini_settings), 'gemini-3.1-pro-preview'], check=True)
subprocess.run(['python3', str(helper), 'render-gemini-env', str(gemini_env), 'sk-gemini', 'https://generativelanguage.googleapis.com', 'gemini-3.1-pro-preview'], check=True)
assert 'GOOGLE_GEMINI_BASE_URL=https://generativelanguage.googleapis.com' in gemini_env.read_text(encoding='utf-8')
PY
}

test_help_output() {
	output="$(bash "$ROOT_DIR/install.sh" --help 2>&1)"
	grep -F -- '--cli <claude|codex|gemini>' <<<"$output" >/dev/null
	if grep -q 'opencode\|claim\|bundle' <<<"$output"; then
		printf 'help output still contains removed product-surface terms\n' >&2
		return 1
	fi
}

test_quality_and_smoke_scripts() {
	[[ -f "$ROOT_DIR/scripts/run_quality.sh" ]]
	[[ -f "$ROOT_DIR/scripts/run_smoke.sh" ]]
	[[ -f "$ROOT_DIR/scripts/run_release_readiness.sh" ]]
	[[ -f "$ROOT_DIR/scripts/run_live_smoke_matrix.sh" ]]
	[[ -f "$ROOT_DIR/scripts/run_cli_usable_validation.sh" ]]
	grep -F 'shellcheck' "$ROOT_DIR/scripts/run_quality.sh" >/dev/null
	grep -F 'bash scripts/run_smoke.sh' "$ROOT_DIR/README.md" >/dev/null
	grep -F 'bash scripts/run_release_readiness.sh' "$ROOT_DIR/README.md" >/dev/null
	grep -F 'run_cli_usable_validation.sh' "$ROOT_DIR/README.md" >/dev/null
}


test_flow_module_wiring() {
	[[ -f "$ROOT_DIR/internal/linux/lib/flows.sh" ]]
	[[ -f "$ROOT_DIR/internal/linux/lib/flows_install.sh" ]]
	[[ -f "$ROOT_DIR/internal/linux/lib/flows_config.sh" ]]
	[[ -f "$ROOT_DIR/internal/linux/lib/flows_menu.sh" ]]
	[[ -f "$ROOT_DIR/internal/linux/lib/flows_noninteractive.sh" ]]
	grep -F 'source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_install.sh"' "$ROOT_DIR/internal/linux/lib/flows.sh" >/dev/null
	grep -F 'source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_config.sh"' "$ROOT_DIR/internal/linux/lib/flows.sh" >/dev/null
	grep -F 'source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_menu.sh"' "$ROOT_DIR/internal/linux/lib/flows.sh" >/dev/null
	grep -F 'source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/flows_noninteractive.sh"' "$ROOT_DIR/internal/linux/lib/flows.sh" >/dev/null
}

test_menu_matrix() {
	bash "$ROOT_DIR/scripts/run_menu_matrix.sh"
}

test_docs_faq_and_architecture_present() {
	[[ -f "$ROOT_DIR/docs/faq.md" ]]
	[[ -f "$ROOT_DIR/docs/architecture.md" ]]
	grep -F 'run_cli_usable_validation.sh' "$ROOT_DIR/docs/faq.md" >/dev/null
	grep -F 'Architecture Overview' "$ROOT_DIR/docs/architecture.md" >/dev/null
}

test_release_docs_present() {
	[[ -f "$ROOT_DIR/docs/release-process.md" ]]
	[[ -f "$ROOT_DIR/docs/distribution-strategy.md" ]]
	[[ -f "$ROOT_DIR/docs/versioning-policy.md" ]]
	[[ -f "$ROOT_DIR/docs/security.md" ]]
	[[ -f "$ROOT_DIR/docs/support-matrix.md" ]]
	[[ -f "$ROOT_DIR/docs/operations.md" ]]
	grep -F 'RELEASE_TODOS.md' "$ROOT_DIR/docs/release-process.md" >/dev/null
	grep -F 'docs/security.md' "$ROOT_DIR/USER_MANUAL.md" >/dev/null
	grep -F 'docs/operations.md' "$ROOT_DIR/README.md" >/dev/null
}


test_error_message_hints_present() {
	grep -F '请先安装 python3' "$ROOT_DIR/internal/linux/lib/common_download.sh" >/dev/null
	grep -F '仅支持 claude / codex / gemini' "$ROOT_DIR/internal/linux/lib/flows_noninteractive.sh" >/dev/null
	grep -F '示例：--noninteractive --cli codex --api-key sk-xxx' "$ROOT_DIR/internal/linux/lib/flows_noninteractive.sh" >/dev/null
	grep -F '检查网络、npm registry、代理配置' "$ROOT_DIR/internal/linux/lib/installers.sh" >/dev/null
}

test_cli_usable_validation_scaffold() {
	bash "$ROOT_DIR/scripts/run_cli_usable_validation.sh" --help >/dev/null
	grep -F 'claude --version' "$ROOT_DIR/docs/usable-validation.md" >/dev/null
	grep -F 'run_cli_usable_validation.sh' "$ROOT_DIR/.github/workflows/release-gate.yml" >/dev/null
}

test_release_workflows_present() {
	[[ -f "$ROOT_DIR/.github/workflows/ci.yml" ]]
	[[ -f "$ROOT_DIR/.github/workflows/release-gate.yml" ]]
	grep -F 'scripts/run_release_readiness.sh' "$ROOT_DIR/.github/workflows/ci.yml" >/dev/null
	grep -F 'scripts/run_live_smoke_matrix.sh' "$ROOT_DIR/.github/workflows/release-gate.yml" >/dev/null
}

test_codex_release_fallback_checksum() {
	HOME="$WORK_DIR/fallback-home" LEUNG_HOME="$WORK_DIR/fallback-home/.leung" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		source internal/linux/lib/installers.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		[[ "$(codex_release_checksum x86_64-unknown-linux-musl)" =~ ^[0-9a-f]{64}$ ]]
		[[ "$(codex_release_checksum aarch64-unknown-linux-musl)" =~ ^[0-9a-f]{64}$ ]]
	'
}

test_distribution_residue_removed() {
	[[ ! -f "$ROOT_DIR/dist/index.json" ]]
	grep -F '删除该文件' "$ROOT_DIR/docs/distribution-strategy.md" >/dev/null
}


test_proxy_auto_repair_and_override() {
	local case_dir="$WORK_DIR/proxy-repair"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir"
	cat >"$home_dir/.npmrc" <<'EOF_NPM'
proxy=http://127.0.0.1:9
https-proxy=http://127.0.0.1:9
EOF_NPM
	output="$(HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		source internal/linux/lib/installers.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		LEUNG_NODE_RUNTIME=system
		npm_proxy_auto_repair_if_needed
		printf "override=%s\n" "$(npm_proxy_override_env)"
	' 2>&1)"
	grep -F '自动清理该配置' <<<"$output" >/dev/null
	grep -F 'override=' <<<"$output" >/dev/null
	if [[ -f "$home_dir/.npmrc" ]]; then
		! grep -F '127.0.0.1:9' "$home_dir/.npmrc" >/dev/null
	fi
}


test_verify_cli_setup_soft_connectivity_warning() {
	local case_dir="$WORK_DIR/soft-connectivity-warning"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir"
	HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		source internal/linux/lib/connectivity.sh
		source internal/linux/lib/verify.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		verify_cli_config_only() { return 0; }
		verify_cli_config_values() { return 0; }
		verify_cli_binary() { return 0; }
		get_effective_provider_url() { printf "%s\n" "https://example.test/v1"; }
		get_cli_key() { printf "%s\n" "sk-test"; }
		run_connectivity_probe() { printf "transport_fail|6|curl transport failure\n"; }
		verify_cli_setup codex warn
		[[ "$LEUNG_POST_INSTALL_WARNING" == *"远端连通性验证未通过"* ]]
		if verify_cli_setup codex strict; then
			printf "strict connectivity verification unexpectedly passed\n" >&2
			return 1
		fi
	'
}

test_noninteractive_full_install_soft_warning_summary() {
	local case_dir="$WORK_DIR/noninteractive-soft-warning"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir"
	HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		source internal/linux/lib/connectivity.sh
		source internal/linux/lib/verify.sh
		source internal/linux/lib/flows_noninteractive.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		cluster_guard_enforce() { return 0; }
		ensure_system_dependencies() { return 0; }
		ensure_nvm_and_node() { LEUNG_NODE_RUNTIME=system; return 0; }
		install_cli() { return 0; }
		write_cli_config() { return 0; }
		commit_url_if_needed() { return 0; }
		verify_cli_config_only() { return 0; }
		verify_cli_config_values() { return 0; }
		verify_cli_binary() { return 0; }
		get_effective_provider_url() { printf "%s\n" "https://example.test/v1"; }
		get_cli_key() { printf "%s\n" "sk-test"; }
		run_connectivity_probe() { printf "transport_fail|6|curl transport failure\n"; }
		run_noninteractive_full_install_flow codex "Codex CLI" "https://example.test/v1" "sk-test"
		grep -F "注意:" "$LEUNG_SUMMARY_FILE" >/dev/null
		grep -F "远端连通性验证未通过" "$LEUNG_SUMMARY_FILE" >/dev/null
	'
}


test_broken_nvm_falls_back_to_system_node() {
	local case_dir="$WORK_DIR/broken-nvm-fallback"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir/.nvm"
	printf ':%s' "\n" >"$home_dir/.nvm/nvm.sh"
	HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		source internal/linux/lib/node.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		ensure_nvm_and_node
		[[ "$LEUNG_NODE_RUNTIME" == "system" ]]
		grep -F "检测到现有 Node.js" "$LEUNG_LOG_FILE" >/dev/null
	'
}


test_system_deps_skip_when_minimum_available() {
	local case_dir="$WORK_DIR/system-deps-skip"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir"
	HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		source internal/linux/lib/deps.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		detect_package_manager() { printf "%s\n" pacman; }
		install_packages() { printf "install_packages_should_not_run\n" >&2; return 1; }
		ensure_system_dependencies
		grep -F "基础系统依赖已满足" "$LEUNG_LOG_FILE" >/dev/null
	'
}


test_codex_release_fallback_timeout_override_present() {
	grep -F 'LEUNG_CODEX_RELEASE_MAX_TIME' "$ROOT_DIR/internal/linux/lib/installers.sh" >/dev/null
	grep -F '开始下载 codex release' "$ROOT_DIR/internal/linux/lib/common_download.sh" >/dev/null
	grep -F '下载完成，开始校验 SHA256' "$ROOT_DIR/internal/linux/lib/common_download.sh" >/dev/null
}

test_cache_dir_wiring_present() {
	grep -F 'LEUNG_CACHE_DIR="$LEUNG_HOME/cache"' "$ROOT_DIR/internal/linux/lib/common_context.sh" >/dev/null
	grep -F 'download_cache_dir()' "$ROOT_DIR/internal/linux/lib/common_download.sh" >/dev/null
	grep -F 'npm_cache_dir()' "$ROOT_DIR/internal/linux/lib/common_download.sh" >/dev/null
	grep -F 'npm_config_cache=' "$ROOT_DIR/internal/linux/lib/installers.sh" >/dev/null
}


test_rollback_restores_backup_files() {
	local case_dir="$WORK_DIR/rollback-restore"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir/.leung/state" "$home_dir/.leung/logs"
	local target="$home_dir/sample.txt"
	local backup="$home_dir/.leung/backups/sample.txt.bak"
	echo 'before' >"$target"
	mkdir -p "$(dirname "$backup")"
	cp "$target" "$backup"
	HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" TARGET_PATH="$target" BACKUP_PATH="$backup" bash -lc '
		set -euo pipefail
		cd "$ROOT_DIR"
		source internal/linux/lib/common.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		cat >"$LEUNG_RESTORE_STACK_FILE" <<EOF_STACK
$TARGET_PATH|$BACKUP_PATH
EOF_STACK
		echo after >"$TARGET_PATH"
		restore_backups
	'
	grep -Fx 'before' "$target" >/dev/null
}


test_rollback_removes_created_file_side_effect() {
	local case_dir="$WORK_DIR/rollback-created-file"
	local home_dir="$case_dir/home"
	mkdir -p "$home_dir/.leung/state" "$home_dir/.leung/logs"
	local created="$home_dir/created.txt"
	echo 'temp' >"$created"
	python3 - <<'PY_INNER' "$home_dir/.leung/state/transaction.jsonl" "$created"
import json, sys
path, created = sys.argv[1], sys.argv[2]
with open(path, 'w', encoding='utf-8') as f:
    f.write(json.dumps({'kind':'created_file','fields':[created]}, ensure_ascii=False) + '\n')
PY_INNER
	HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" bash -lc '
		set -euo pipefail
		source internal/linux/lib/common.sh
		init_installer_context "$PWD/internal/linux"
		ensure_leung_directories
		init_logging
		LEUNG_TRANSACTION_FILE="$HOME/.leung/state/transaction.jsonl"
		rollback_transaction_side_effects
	'
	[[ ! -f "$created" ]]
}

main() {
	run_case syntax test_syntax
	run_case registry_manifest test_registry_manifest
	run_case noninteractive_default_urls test_noninteractive_default_urls
	run_case render_templates test_render_templates
	run_case help_output test_help_output
	run_case quality_and_smoke_scripts test_quality_and_smoke_scripts
	run_case flow_module_wiring test_flow_module_wiring
	run_case menu_matrix test_menu_matrix
	run_case docs_faq_and_architecture_present test_docs_faq_and_architecture_present
	run_case release_docs_present test_release_docs_present
	run_case error_message_hints_present test_error_message_hints_present
	run_case cli_usable_validation_scaffold test_cli_usable_validation_scaffold
	run_case release_workflows_present test_release_workflows_present
	run_case codex_release_fallback_checksum test_codex_release_fallback_checksum
	run_case distribution_residue_removed test_distribution_residue_removed
	run_case proxy_auto_repair_and_override test_proxy_auto_repair_and_override
	run_case verify_cli_setup_soft_connectivity_warning test_verify_cli_setup_soft_connectivity_warning
	run_case noninteractive_full_install_soft_warning_summary test_noninteractive_full_install_soft_warning_summary
	run_case broken_nvm_falls_back_to_system_node test_broken_nvm_falls_back_to_system_node
	run_case system_deps_skip_when_minimum_available test_system_deps_skip_when_minimum_available
	run_case codex_release_fallback_timeout_override_present test_codex_release_fallback_timeout_override_present
	run_case cache_dir_wiring_present test_cache_dir_wiring_present
	run_case rollback_restores_backup_files test_rollback_restores_backup_files
	run_case rollback_removes_created_file_side_effect test_rollback_removes_created_file_side_effect
	log 'ALL PASSED'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
