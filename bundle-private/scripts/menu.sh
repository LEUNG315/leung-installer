#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

prompt_month() {
  local default_month
  default_month="$(date +%Y-%m)"
  read -r -p "Month [${default_month}]: " MONTH
  MONTH="${MONTH:-$default_month}"
}

prompt_clis() {
  read -r -p "CLIs (empty=all, e.g. codex gemini): " raw
  CLI_ARGS=()
  for cli in $raw; do
    CLI_ARGS+=(--cli "$cli")
  done
}

while true; do
  echo
  echo 'bundle-private menu'
  echo '1) 一键发布（先测后出包）'
  echo '2) 批量测试所有 CLI'
  echo '3) 只出包'
  echo '4) 单 CLI 端到端测试'
  echo '5) 生成 password_hash'
  echo '6) 退出'
  read -r -p '选择 [1-6]: ' choice
  case "$choice" in
    1)
      prompt_month
      prompt_clis
      read -r -p 'git add? [y/N]: ' do_add
      read -r -p 'git commit? [y/N]: ' do_commit
      args=("$MONTH" "${CLI_ARGS[@]}")
      [[ "$do_add" =~ ^[Yy]$ ]] && args+=(--git-add)
      [[ "$do_commit" =~ ^[Yy]$ ]] && args+=(--git-commit)
      bash "$ROOT_DIR/scripts/publish_month.sh" "${args[@]}"
      ;;
    2)
      prompt_month
      prompt_clis
      bash "$ROOT_DIR/scripts/test_all_bundle_flows.sh" "$MONTH" "${CLI_ARGS[@]}"
      ;;
    3)
      prompt_month
      prompt_clis
      bash "$ROOT_DIR/scripts/build_to_installer_dist.sh" "$MONTH" "${CLI_ARGS[@]}"
      ;;
    4)
      prompt_month
      read -r -p 'CLI: ' cli
      read -r -p 'User (optional): ' user
      args=("$MONTH" --cli "$cli")
      [[ -n "$user" ]] && args+=(--user "$user")
      bash "$ROOT_DIR/scripts/test_bundle_to_installer_flow.sh" "${args[@]}"
      ;;
    5)
      read -r -p 'Password: ' pw
      bash "$ROOT_DIR/scripts/hash_password.sh" "$pw"
      ;;
    6)
      exit 0
      ;;
    *)
      echo '无效选择'
      ;;
  esac
done
