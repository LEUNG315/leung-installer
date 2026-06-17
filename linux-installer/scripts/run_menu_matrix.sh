#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_PY="$ROOT_DIR/internal/linux/bin/config_helper.py"
MENU_BASE_DIR="${LEUNG_MENU_BASE_DIR:-$HOME/.tmp-leung-menu-tests}"
mkdir -p "$MENU_BASE_DIR"
WORK_DIR="$(mktemp -d "$MENU_BASE_DIR/leung-menu-matrix.XXXXXX")"
SERVER_PID=""
SERVER_PORT=""

cleanup() {
	if [[ -n "$SERVER_PID" ]]; then
		kill "$SERVER_PID" >/dev/null 2>&1 || true
	fi
	if [[ "${LEUNG_KEEP_MENU_WORKDIR:-0}" != "1" ]]; then
		rm -rf "$WORK_DIR"
	else
		log "KEEP WORKDIR $WORK_DIR"
	fi
}
trap cleanup EXIT

log() {
	printf '[MENU] %s\n' "$*" >&2
}

assert_contains() {
	local file="$1" needle="$2"
	grep -F "$needle" "$file" >/dev/null
}

default_model_for_cli() {
	case "$1" in
	claude) printf '%s\n' 'claude-sonnet-4-5' ;;
	codex) printf '%s\n' 'gpt-5.4' ;;
	gemini) printf '%s\n' 'gemini-3.1-pro-preview' ;;
	*) return 1 ;;
	esac
}

prepare_cli_state() {
	local home_dir="$1" cli="$2" key="$3" url="$4" model="${5:-}"
	local leung_home="$home_dir/.leung"
	[[ -n "$model" ]] || model="$(default_model_for_cli "$cli")"
	python3 "$HELPER_PY" ensure-auth "$leung_home/auth.json"
	python3 "$HELPER_PY" ensure-config "$leung_home/config.toml"
	python3 "$HELPER_PY" set-auth-key "$leung_home/auth.json" "$cli" "$key"
	python3 "$HELPER_PY" set-provider-url "$leung_home/config.toml" "$cli" "$url"
	python3 "$HELPER_PY" set-model "$leung_home/config.toml" "$cli" "$model"
	python3 "$HELPER_PY" write-native-config "$cli" "$home_dir" "$key" "$url" "$model"
}

run_installer_case() {
	local name="$1" input="$2"
	local case_dir="$WORK_DIR/$name"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	shift 2
	mkdir -p "$home_dir"
	if ! printf '%b' "$input" | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 "$@" \
		bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1; then
		printf '[MENU-CASE] %s FAILED\n' "$name" >&2
		printf '[MENU-CASE] log=%s\n' "$out_log" >&2
		tail -n 200 "$out_log" >&2 || true
		return 1
	fi
	printf '%s\n' "$case_dir"
}

start_refresh_stub_server() {
	local serve_dir="$WORK_DIR/refresh-serve"
	local repo_root="$serve_dir/owner/repo/archive"
	local archive_root="$WORK_DIR/refresh-archive/repo-ref"
	local port_file="$WORK_DIR/refresh-port.txt"
	local archive_path="$repo_root/ref.tar.gz"
	mkdir -p "$repo_root" "$archive_root"
	cat >"$archive_root/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo 'REFRESH-STUB OK'
EOF
	chmod 755 "$archive_root/install.sh"
	tar -czf "$archive_path" -C "$WORK_DIR/refresh-archive" repo-ref
	LEUNG_REFRESH_TEST_SHA="$(python3 - "$archive_path" <<'PY'
import hashlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
PY
)"
	python3 - "$serve_dir" "$port_file" <<'PY' &
import functools
import http.server
import socketserver
import sys

root = sys.argv[1]
port_file = sys.argv[2]
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)

class QuietTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

with QuietTCPServer(("127.0.0.1", 0), handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as f:
        f.write(str(httpd.server_address[1]))
    httpd.serve_forever()
PY
	SERVER_PID=$!
	for _ in $(seq 1 50); do
		if [[ -f "$port_file" ]]; then
			SERVER_PORT="$(cat "$port_file")"
			break
		fi
		sleep 0.1
	done
	[[ -n "$SERVER_PORT" ]]
}

run_case() {
	local name="$1"
	shift
	log "RUN  $name"
	if ! "$@"; then
		log "FAIL $name"
		return 1
	fi
	log "PASS $name"
}

test_main_install_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case main_install $'1\n1\nsk-main-install\n1\ny\n5\n' LEUNG_DRY_RUN=1 LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" 'Claude Code 安装完成'
}

test_main_details_flow() {
	local case_dir="$WORK_DIR/main_details"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-detail https://api.anthropic.com claude-sonnet-4-5
	printf '2\n1\n1\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" 'CLI 配置详情'
}

test_main_verify_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case main_verify $'3\n1\n5\n' LEUNG_DRY_RUN=1 LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '验证完成'
}

test_advanced_api_key_flow() {
	local case_dir out_log home_dir value
	case_dir="$(run_installer_case advanced_api_key $'4\n1\n1\n1\nsk-advanced-api\n4\n6\n5\n' LEUNG_SKIP_DEPS=1)"
	home_dir="$case_dir/home"
	out_log="$case_dir/out.log"
	value="$(python3 "$HELPER_PY" get-auth-key "$home_dir/.leung/auth.json" claude)"
	[[ "$value" == 'sk-advanced-api' ]]
	assert_contains "$out_log" '配置已更新'
}

test_advanced_api_connectivity_flow() {
	local case_dir="$WORK_DIR/advanced_api_connectivity"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-api-connect https://api.anthropic.com claude-sonnet-4-5
	printf '4\n1\n2\n1\n1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 LEUNG_CONNECTIVITY_MOCK_RESULT='pass|200|reachable and accepted' \
		bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" '连通性检查通过'
}

test_advanced_api_status_flow() {
	local case_dir="$WORK_DIR/advanced_api_status"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-api-status https://api.anthropic.com claude-sonnet-4-5
	printf '4\n1\n3\n1\n1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" 'API 配置状态'
}

test_advanced_url_modify_flow() {
	local case_dir="$WORK_DIR/advanced_url_modify"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	local value=""
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-url https://api.anthropic.com claude-sonnet-4-5
	printf '4\n2\n1\n1\nhttps://example.test/v1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	value="$(python3 "$HELPER_PY" get-provider-url "$home_dir/.leung/config.toml" claude)"
	[[ "$value" == 'https://example.test/v1' ]]
	assert_contains "$out_log" 'URL 已更新'
}

test_advanced_url_connectivity_flow() {
	local case_dir="$WORK_DIR/advanced_url_connectivity"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-url-connect https://api.anthropic.com claude-sonnet-4-5
	printf '4\n2\n2\n1\n1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 LEUNG_CONNECTIVITY_MOCK_RESULT='pass|200|reachable and accepted' \
		bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" '连通性检查通过'
}

test_advanced_url_status_flow() {
	local case_dir="$WORK_DIR/advanced_url_status"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-url-status https://api.anthropic.com claude-sonnet-4-5
	printf '4\n2\n3\n1\n1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" 'URL 配置状态'
}

test_advanced_config_regenerate_flow() {
	local case_dir="$WORK_DIR/advanced_config_regenerate"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-regen https://api.anthropic.com claude-sonnet-4-5
	printf '4\n3\n1\n1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" '配置已重写'
}

test_advanced_config_verify_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case advanced_config_verify $'4\n3\n2\n1\n4\n6\n5\n' LEUNG_DRY_RUN=1 LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '验证完成'
}

test_advanced_config_details_flow() {
	local case_dir="$WORK_DIR/advanced_config_details"
	local home_dir="$case_dir/home"
	local out_log="$case_dir/out.log"
	mkdir -p "$home_dir"
	prepare_cli_state "$home_dir" claude sk-config-detail https://api.anthropic.com claude-sonnet-4-5
	printf '4\n3\n3\n1\n1\n4\n6\n5\n' | env HOME="$home_dir" LEUNG_HOME="$home_dir/.leung" LEUNG_UI_STDIN_ONLY=1 \
		LEUNG_SKIP_DEPS=1 bash "$ROOT_DIR/install.sh" >"$out_log" 2>&1
	assert_contains "$out_log" 'CLI 配置详情'
}

test_advanced_maintenance_install_only_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case advanced_install_only $'4\n4\n1\n1\n6\n6\n5\n' LEUNG_DRY_RUN=1 LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '仅安装 CLI 完成'
}

test_advanced_maintenance_test_install_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case advanced_test_install $'4\n4\n2\n1\n1\ny\n6\n6\n5\n' LEUNG_DRY_RUN=1 LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '测试安装已完成'
}

test_advanced_maintenance_clear_cache_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case advanced_clear_cache $'4\n4\n3\n1\n6\n6\n5\n' LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '缓存已清除'
}

test_advanced_maintenance_manual_rollback_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case advanced_manual_rollback $'4\n4\n4\n1\n6\n6\n5\n' LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '当前会话没有可回滚的事务记录'
}

test_advanced_maintenance_refresh_installer_flow() {
	start_refresh_stub_server
	local case_dir out_log
	case_dir="$(run_installer_case advanced_refresh_installer $'4\n4\n5\n' \
		LEUNG_SKIP_DEPS=1 \
		LEUNG_GITHUB_ARCHIVE_BASE="http://127.0.0.1:$SERVER_PORT" \
		LEUNG_BOOTSTRAP_GITHUB_OWNER=owner \
		LEUNG_BOOTSTRAP_GITHUB_REPO=repo \
		LEUNG_BOOTSTRAP_GITHUB_REF=ref \
		LEUNG_BOOTSTRAP_GITHUB_REF_KIND=commit \
		LEUNG_BOOTSTRAP_ARCHIVE_SHA256="$LEUNG_REFRESH_TEST_SHA")"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" 'REFRESH-STUB OK'
}

test_advanced_logs_flow() {
	local case_dir out_log
	case_dir="$(run_installer_case advanced_logs $'4\n5\n1\n6\n5\n' LEUNG_SKIP_DEPS=1)"
	out_log="$case_dir/out.log"
	assert_contains "$out_log" '最近结果 / 日志'
}

main() {
	run_case main_install_flow test_main_install_flow
	run_case main_details_flow test_main_details_flow
	run_case main_verify_flow test_main_verify_flow
	run_case advanced_api_key_flow test_advanced_api_key_flow
	run_case advanced_api_connectivity_flow test_advanced_api_connectivity_flow
	run_case advanced_api_status_flow test_advanced_api_status_flow
	run_case advanced_url_modify_flow test_advanced_url_modify_flow
	run_case advanced_url_connectivity_flow test_advanced_url_connectivity_flow
	run_case advanced_url_status_flow test_advanced_url_status_flow
	run_case advanced_config_regenerate_flow test_advanced_config_regenerate_flow
	run_case advanced_config_verify_flow test_advanced_config_verify_flow
	run_case advanced_config_details_flow test_advanced_config_details_flow
	run_case advanced_maintenance_install_only_flow test_advanced_maintenance_install_only_flow
	run_case advanced_maintenance_test_install_flow test_advanced_maintenance_test_install_flow
	run_case advanced_maintenance_clear_cache_flow test_advanced_maintenance_clear_cache_flow
	run_case advanced_maintenance_manual_rollback_flow test_advanced_maintenance_manual_rollback_flow
	run_case advanced_maintenance_refresh_installer_flow test_advanced_maintenance_refresh_installer_flow
	run_case advanced_logs_flow test_advanced_logs_flow
	log 'ALL PASSED'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
