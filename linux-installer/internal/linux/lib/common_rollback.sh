#!/usr/bin/env bash

restore_backups() {
	[[ "$LEUNG_DRY_RUN" == "1" ]] && return 0
	[[ -f "$LEUNG_RESTORE_STACK_FILE" ]] || return 0
	tac "$LEUNG_RESTORE_STACK_FILE" 2>/dev/null | while IFS='|' read -r target backup; do
		[[ -n "$target" && -n "$backup" && -f "$backup" ]] || continue
		mkdir -p "$(dirname "$target")"
		cp -a "$backup" "$target"
		log_warn "已回滚: $target <- $backup"
	done
}

remove_block_from_file() {
	local file="$1" start_marker="$2" end_marker="$3"
	[[ -f "$file" ]] || return 0
	python3 - "$file" "$start_marker" "$end_marker" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
start = sys.argv[2]
end = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()
out = []
skip = False
for line in lines:
    if line == start:
        skip = True
        continue
    if skip and line == end:
        skip = False
        continue
    if not skip:
        out.append(line)
path.write_text("\n".join(out).rstrip() + ("\n" if out else ""), encoding="utf-8")
PY
}

rollback_transaction_side_effects() {
	[[ "$LEUNG_DRY_RUN" == "1" ]] && return 0
	[[ -f "$LEUNG_TRANSACTION_FILE" ]] || return 0
	if command -v tac >/dev/null 2>&1; then
		tac "$LEUNG_TRANSACTION_FILE"
	else
		python3 -c 'import sys; lines=sys.stdin.read().splitlines(); print("\\n".join(reversed(lines)))' <"$LEUNG_TRANSACTION_FILE"
	fi | while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		local kind f1 f2
		kind="$(python3 -c 'import json,sys; x=json.loads(sys.stdin.read()); print(x["kind"])' <<<"$line")"
		f1="$(python3 -c 'import json,sys; x=json.loads(sys.stdin.read()); print(x["fields"][0] if x["fields"] else "")' <<<"$line")"
		f2="$(python3 -c 'import json,sys; x=json.loads(sys.stdin.read()); print(x["fields"][1] if len(x["fields"]) > 1 else "")' <<<"$line")"
		case "$kind" in
		created_file)
			[[ -n "$f1" && -f "$f1" ]] && rm -f "$f1" && log_warn "已删除新建文件: $f1"
			;;
		created_dir)
			if [[ -n "$f1" && -d "$f1" ]]; then
				rmdir "$f1" 2>/dev/null || true
			fi
			;;
		profile_block)
			if [[ -n "$f1" ]]; then
				if [[ -n "$f2" ]]; then
					local start_marker end_marker
					start_marker="$f2"
					end_marker="$(python3 -c 'import json,sys; x=json.loads(sys.stdin.read()); print(x["fields"][2] if len(x["fields"]) > 2 else "")' <<<"$line")"
					[[ -n "$end_marker" ]] && remove_block_from_file "$f1" "$start_marker" "$end_marker"
				else
					remove_block_from_file "$f1" '# >>> LEUNG installer nvm >>>' '# <<< LEUNG installer nvm <<<'
				fi
			fi
			;;
		npm_global_install)
			if [[ -n "$f1" ]]; then
				log_warn "尝试卸载本次安装的 npm 包: $f1"
				bash -lc "export NVM_DIR=\"$LEUNG_NVM_DIR\"; [ -s \"$LEUNG_NVM_DIR/nvm.sh\" ] && . \"$LEUNG_NVM_DIR/nvm.sh\"; command -v nvm >/dev/null 2>&1 && nvm use $LEUNG_NODE_VERSION >/dev/null 2>&1 || true; npm uninstall -g \"$f1\"" >>"$LEUNG_LOG_FILE" 2>&1 || true
			fi
			;;
		codex_release_install)
			[[ -n "$f1" && -f "$f1" ]] && rm -f "$f1" && log_warn "已删除 Codex release 安装产物: $f1"
			;;
		esac
	done
}

rollback_current_transaction() {
	local rollback_ok=0
	LEUNG_ROLLBACK_STATUS="进行中"
	LEUNG_ROLLBACK_DETAILS="已尝试恢复备份与事务副作用。"
	if ! restore_backups; then
		rollback_ok=1
	fi
	if ! rollback_transaction_side_effects; then
		rollback_ok=1
	fi
	if ! restore_test_state; then
		rollback_ok=1
	fi
	if ! cleanup_test_transaction_side_effects; then
		rollback_ok=1
	fi
	if ! cleanup_test_state; then
		rollback_ok=1
	fi
	if [[ "$rollback_ok" -eq 0 ]]; then
		LEUNG_ROLLBACK_STATUS="成功"
		LEUNG_ROLLBACK_DETAILS="已恢复本次事务备份并清理已记录副作用。"
		log_warn "失败后回滚完成。"
		return 0
	fi
	LEUNG_ROLLBACK_STATUS="部分失败"
	LEUNG_ROLLBACK_DETAILS="回滚已尝试，但存在未完全恢复的残留，请检查日志。"
	log_warn "失败后回滚存在残留，请检查日志。"
	return 1
}

on_error_trap() {
	local exit_code="$1"
	if [[ "$exit_code" -ne 0 ]]; then
		trap - ERR
		set +e
		log_error "安装流程失败，步骤=${LEUNG_CURRENT_STEP:-unknown}，退出码=$exit_code"
		rollback_current_transaction || true
		write_summary "失败" "" "错误: ${LEUNG_LAST_ERROR:-未知错误}
回滚: ${LEUNG_ROLLBACK_STATUS}
回滚说明: ${LEUNG_ROLLBACK_DETAILS}"
		exit "$exit_code"
	fi
}
