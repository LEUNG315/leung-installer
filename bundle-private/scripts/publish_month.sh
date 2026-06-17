#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ALL_SCRIPT="$ROOT_DIR/scripts/test_all_bundle_flows.sh"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_to_installer_dist.sh"
INSTALLER_ROOT="${INSTALLER_ROOT:-$ROOT_DIR/../installer}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$INSTALLER_ROOT/dist}"

usage() {
  cat <<'EOF'
One-shot monthly publish helper for bundle-private.

Usage:
  bash scripts/publish_month.sh [YYYY-MM] [--cli codex --cli gemini] [--skip-tests] [--keep-artifacts] [--stop-on-fail] [--git-add] [--git-commit]

Default behavior:
  1. Run batch smoke tests for the month
  2. If all tests pass, build release bundles into installer/dist/<month>

Options:
  --cli <name>         Only test/build selected CLI(s); may be repeated
  --skip-tests         Build directly without running smoke tests first
  --keep-artifacts     Preserve temp artifacts from test phase
  --stop-on-fail       Stop batch tests on first failing CLI
  --git-add            Stage generated dist files in installer repo
  --git-commit         Stage and commit generated dist files in installer repo
  --git-message <msg>  Custom commit message for --git-commit
EOF
}

default_commit_message() {
  local month="$1"
  local scope="${2:-all}"
  cat <<EOF
发布 ${month} 安装包产物以便静态分发

自动化测试通过后更新 installer/dist 下的月度 bundle 与索引。

Constraint: 发布产物需兼容 installer 现有 bundle 消费协议
Rejected: 手工逐文件发布 | 易漏 manifest/index 且不可复现
Confidence: high
Scope-risk: narrow
Directive: 若调整 bundle 产物结构需同步 bundle-private 构建脚本与 installer 消费逻辑
Tested: bash scripts/publish_month.sh ${month}${scope:+ --cli ${scope}}
Not-tested: 远程 git push
EOF
}

stage_dist_files() {
  local month="$1"
  local repo_root="$2"
  local dist_root="$OUTPUT_ROOT"
  local month_dir="$dist_root/$month"
  local index_file="$dist_root/index.json"
  [[ -d "$month_dir" ]] || {
    printf '[ERROR] month output not found for git add: %s\n' "$month_dir" >&2
    return 1
  }
  git -C "$repo_root" add -- "$month_dir" "$index_file"
}

commit_dist_files() {
  local month="$1"
  local repo_root="$2"
  local message="$3"
  stage_dist_files "$month" "$repo_root"
  if git -C "$repo_root" diff --cached --quiet -- "$OUTPUT_ROOT/$month" "$OUTPUT_ROOT/index.json"; then
    printf '[INFO] no staged dist changes to commit\n'
    return 0
  fi
  printf '%s\n' "$message" | git -C "$repo_root" commit --file -
}

MONTH="${1:-$(date +%Y-%m)}"
if [[ $# -gt 0 && "$1" != --* ]]; then
  shift
fi

SELECTED_CLIS=()
KEEP_ARTIFACTS=0
STOP_ON_FAIL=0
SKIP_TESTS=0
DO_GIT_ADD=0
DO_GIT_COMMIT=0
GIT_MESSAGE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cli)
      [[ -n "${2:-}" ]] || {
        printf '[ERROR] missing value for --cli\n' >&2
        exit 1
      }
      SELECTED_CLIS+=("$2")
      shift 2
      ;;
    --keep-artifacts)
      KEEP_ARTIFACTS=1
      shift
      ;;
    --stop-on-fail)
      STOP_ON_FAIL=1
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --git-add)
      DO_GIT_ADD=1
      shift
      ;;
    --git-commit)
      DO_GIT_COMMIT=1
      DO_GIT_ADD=1
      shift
      ;;
    --git-message)
      GIT_MESSAGE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ -x "$TEST_ALL_SCRIPT" ]] || {
  printf '[ERROR] batch test script not found: %s\n' "$TEST_ALL_SCRIPT" >&2
  exit 1
}
[[ -x "$BUILD_SCRIPT" ]] || {
  printf '[ERROR] build script not found: %s\n' "$BUILD_SCRIPT" >&2
  exit 1
}

cli_args=()
for cli in "${SELECTED_CLIS[@]}"; do
  cli_args+=(--cli "$cli")
done

printf '[INFO] publish month: %s\n' "$MONTH"
if [[ ${#SELECTED_CLIS[@]} -gt 0 ]]; then
  printf '[INFO] selected clis: %s\n' "${SELECTED_CLIS[*]}"
else
  printf '[INFO] selected clis: auto-detect from secrets/%s/*_apikey.md\n' "$MONTH"
fi

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  printf '\n[STEP 1/3] batch smoke tests\n'
  test_args=("$MONTH" "${cli_args[@]}")
  if [[ "$KEEP_ARTIFACTS" -eq 1 ]]; then
    test_args+=(--keep-artifacts)
  fi
  if [[ "$STOP_ON_FAIL" -eq 1 ]]; then
    test_args+=(--stop-on-fail)
  fi
  bash "$TEST_ALL_SCRIPT" "${test_args[@]}"
else
  printf '\n[STEP 1/3] batch smoke tests skipped (--skip-tests)\n'
fi

printf '\n[STEP 2/3] build release bundles\n'
build_args=("$MONTH" "${cli_args[@]}" "${EXTRA_ARGS[@]}")
bash "$BUILD_SCRIPT" "${build_args[@]}"

if [[ "$DO_GIT_ADD" -eq 1 ]]; then
  printf '\n[STEP 3/3] stage dist files\n'
  repo_root="$(git -C "$INSTALLER_ROOT" rev-parse --show-toplevel)"
  stage_dist_files "$MONTH" "$repo_root"
  printf '[GIT] staged %s/%s and index.json\n' "$OUTPUT_ROOT" "$MONTH"
  if [[ "$DO_GIT_COMMIT" -eq 1 ]]; then
    scope=""
    if [[ ${#SELECTED_CLIS[@]} -eq 1 ]]; then
      scope="${SELECTED_CLIS[0]}"
    fi
    message="${GIT_MESSAGE:-$(default_commit_message "$MONTH" "$scope")}"
    commit_dist_files "$MONTH" "$repo_root" "$message"
    printf '[GIT] committed dist changes\n'
  fi
else
  printf '\n[STEP 3/3] git stage/commit skipped\n'
fi

printf '\n[PUBLISH READY] month=%s\n' "$MONTH"
printf '[PUBLISH READY] output=%s\n' "$OUTPUT_ROOT/$MONTH"
