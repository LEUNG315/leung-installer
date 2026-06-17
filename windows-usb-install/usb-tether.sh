#!/usr/bin/env bash
set -euo pipefail

WIFI_DEV="${WIFI_DEV:-wlan0}"
ADB_BIN="${ADB_BIN:-adb}"
WAIT_SECS="${WAIT_SECS:-18}"

log() {
  printf '[usb-tether] %s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

get_usb_if() {
  ip -o link show \
    | awk -F': ' '{print $2}' \
    | grep -E '^(enp.*u[0-9].*|usb[0-9]+|rndis[0-9]*|enx[0-9a-f]{12})$' \
    | head -n1 || true
}

get_wifi_gw() {
  ip route show default dev "$WIFI_DEV" 2>/dev/null | awk '{print $3}' | head -n1
}

show_public_ip() {
  curl -4fsS --max-time 5 ifconfig.me 2>/dev/null || echo 'unknown'
}

adb_ready() {
  have_cmd "$ADB_BIN" || return 1
  "$ADB_BIN" get-state >/dev/null 2>&1
}

adb_try() {
  "$ADB_BIN" shell "$@" >/dev/null 2>&1
}

adb_try_usb_rndis() {
  adb_ready || return 1

  log '尝试通过 ADB 切换 USB 功能为 RNDIS…'
  adb_try cmd usb setFunctions rndis,adb && return 0
  adb_try cmd usb setFunctions rndis && return 0
  adb_try svc usb setFunctions rndis,adb && return 0
  adb_try svc usb setFunctions rndis && return 0
  return 1
}

adb_open_tether_settings() {
  adb_ready || return 1
  log '自动打开手机“网络共享/热点”设置页…'
  adb_try am start -a android.settings.TETHER_SETTINGS && return 0
  adb_try am start -a android.settings.WIRELESS_SETTINGS && return 0
  return 1
}

wait_for_usb_if() {
  local i usb_if
  for ((i=0; i<WAIT_SECS; i++)); do
    usb_if="$(get_usb_if)"
    if [[ -n "$usb_if" ]]; then
      echo "$usb_if"
      return 0
    fi
    sleep 1
  done
  return 1
}

switch_to_phone() {
  local usb_if wifi_gw
  usb_if="$1"
  wifi_gw="$(get_wifi_gw || true)"

  if [[ -n "$wifi_gw" ]]; then
    sudo ip route del default via "$wifi_gw" dev "$WIFI_DEV" 2>/dev/null || true
    log "已删除 $WIFI_DEV 默认路由 ($wifi_gw)"
  fi

  log "流量已切到手机 ($usb_if)"
  log "出口 IP: $(show_public_ip)"
}

restore_wifi() {
  local wifi_gw wifi_conn
  wifi_gw="$(nmcli -g IP4.GATEWAY dev show "$WIFI_DEV" 2>/dev/null | head -n1 || true)"
  wifi_conn="$(nmcli -g GENERAL.CONNECTION dev show "$WIFI_DEV" 2>/dev/null | head -n1 || true)"

  if [[ -n "$wifi_conn" && "$wifi_conn" != '--' ]]; then
    nmcli connection up "$wifi_conn" >/dev/null 2>&1 || true
  fi

  if [[ -z "$wifi_gw" ]]; then
    wifi_gw="$(get_wifi_gw || true)"
  fi

  if [[ -n "$wifi_gw" ]]; then
    sudo ip route replace default via "$wifi_gw" dev "$WIFI_DEV"
    log "已恢复 $WIFI_DEV 默认路由 ($wifi_gw)"
  else
    log "未能自动识别 $WIFI_DEV 网关；请确认 Wi‑Fi 已连接"
    return 1
  fi

  log "出口 IP: $(show_public_ip)"
}

auto_on() {
  local usb_if
  usb_if="$(get_usb_if)"

  if [[ -z "$usb_if" ]]; then
    adb_try_usb_rndis || log 'ADB 自动切换 USB 功能失败，继续尝试打开设置页'
    usb_if="$(wait_for_usb_if || true)"
  fi

  if [[ -z "$usb_if" ]]; then
    adb_open_tether_settings || true
    log '请在手机上确认开启“USB 网络共享”，脚本继续等待网卡出现…'
    usb_if="$(wait_for_usb_if || true)"
  fi

  if [[ -z "$usb_if" ]]; then
    log '仍未检测到 USB 网络接口。'
    log '如果这是第一次连接，请先在手机上：1) 允许 USB 调试 2) 开启 USB 网络共享。'
    exit 1
  fi

  switch_to_phone "$usb_if"
}

usage() {
  cat <<USAGE
用法: usb-tether.sh on|off|auto|status
  auto/on  - 自动尝试 ADB 切到 USB 共享，并把默认路由切到手机
  off      - 恢复 Wi‑Fi 默认路由
  status   - 查看当前检测到的 USB 网卡和默认路由

可选环境变量:
  WIFI_DEV=wlan0    Wi‑Fi 网卡名
  WAIT_SECS=18      等待 USB 网卡出现的秒数
  ADB_BIN=adb       adb 可执行文件路径
USAGE
}

status() {
  log "USB_IF: $(get_usb_if || true)"
  log '默认路由:'
  ip route show default || true
}

case "${1:-}" in
  on|auto)
    auto_on
    ;;
  off)
    restore_wifi
    ;;
  status)
    status
    ;;
  *)
    usage
    exit 1
    ;;
esac
