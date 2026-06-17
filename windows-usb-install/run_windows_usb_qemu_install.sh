#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/project-cache"
QEMU_CACHE_DIR="$CACHE_DIR/qemu"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="$QEMU_CACHE_DIR/$RUN_ID"
DEFAULT_TARGET="/dev/sdb"
DEFAULT_WINDOWS_ISO="$SCRIPT_DIR/ventoy-backup/Win11_25H2_Chinese_Simplified_x64_v2.iso"
DEFAULT_WINPE_ISO="$CACHE_DIR/winpe-auto.iso"
DEFAULT_AUTOUNATTEND_ISO="$CACHE_DIR/autounattend.iso"
OVMF_CODE_SECBOOT="/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
OVMF_CODE_FALLBACK="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS_TEMPLATE="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
OVMF_VARS="$RUN_DIR/OVMF_VARS.4m.fd"
TPM_STATE_DIR="$RUN_DIR/tpm-state"
TPM_SOCKET="$RUN_DIR/swtpm.sock"
TPM_PIDFILE="$TPM_STATE_DIR/swtpm.pid"
QEMU_SERIAL_LOG="$RUN_DIR/qemu-serial.log"
MONITOR_SOCKET="$RUN_DIR/monitor.sock"
QEMU_STDOUT_LOG="$RUN_DIR/qemu-stdout.log"
QEMU_STDERR_LOG="$RUN_DIR/qemu-stderr.log"
MEMORY_MB="${MEMORY_MB:-8192}"
CPUS="${CPUS:-4}"
TARGET_DISK="$DEFAULT_TARGET"
WINDOWS_ISO="$DEFAULT_WINDOWS_ISO"
WINPE_ISO="$DEFAULT_WINPE_ISO"
AUTOUNATTEND_ISO="$DEFAULT_AUTOUNATTEND_ISO"

usage() {
  cat <<'USAGE'
Usage:
  run_windows_usb_qemu_install.sh [--target /dev/sdX] [--windows-iso /path/to/windows.iso] [--winpe-iso /path/to/winpe-auto.iso] [--autounattend-iso /path/to/autounattend.iso]
USAGE
}

die() {
  printf '[windows-usb-qemu] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_DISK="$2"; shift 2 ;;
    --windows-iso) WINDOWS_ISO="$2"; shift 2 ;;
    --winpe-iso) WINPE_ISO="$2"; shift 2 ;;
    --autounattend-iso) AUTOUNATTEND_ISO="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_cmd lsblk
require_cmd pkexec
require_cmd qemu-system-x86_64
require_cmd cp
require_cmd swtpm
require_cmd setfacl
require_cmd udisksctl
require_cmd python3

[[ -f "$WINDOWS_ISO" ]] || die "Windows ISO not found: $WINDOWS_ISO"
[[ -f "$WINPE_ISO" ]] || die "WinPE ISO not found: $WINPE_ISO"
[[ -f "$AUTOUNATTEND_ISO" ]] || die "Autounattend ISO not found: $AUTOUNATTEND_ISO"
[[ -f "$OVMF_VARS_TEMPLATE" ]] || die "OVMF vars template not found: $OVMF_VARS_TEMPLATE"
[[ -b "$TARGET_DISK" ]] || die "target disk is not a block device: $TARGET_DISK"

WINDOWS_SRC="$(findmnt -no SOURCE --target "$WINDOWS_ISO" 2>/dev/null || true)"
if [[ -n "$WINDOWS_SRC" ]] && [[ "$WINDOWS_SRC" == ${TARGET_DISK}* ]]; then
  die "Windows ISO is stored on target disk mount ($WINDOWS_SRC); move it off $TARGET_DISK first"
fi

if [[ -f "$OVMF_CODE_SECBOOT" ]]; then
  OVMF_CODE="$OVMF_CODE_SECBOOT"
elif [[ -f "$OVMF_CODE_FALLBACK" ]]; then
  OVMF_CODE="$OVMF_CODE_FALLBACK"
else
  die "No usable OVMF code file found"
fi

TRANSPORT="$(lsblk -d -n -o TRAN "$TARGET_DISK" 2>/dev/null | awk 'NR==1{print $1}')"
MODEL="$(lsblk -d -n -o MODEL "$TARGET_DISK" 2>/dev/null | sed -n '1p' | sed 's/^ *//;s/ *$//')"
SIZE="$(lsblk -d -n -o SIZE "$TARGET_DISK" 2>/dev/null | sed -n '1p')"
PARTS=( $(lsblk -ln -o NAME "$TARGET_DISK" | tail -n +2 | sed 's#^#/dev/#') )

[[ "$TARGET_DISK" == /dev/sd* ]] || die "refusing non-/dev/sdX target: $TARGET_DISK"
[[ "$TARGET_DISK" != /dev/nvme* ]] || die "refusing NVMe target: $TARGET_DISK"
[[ "$TRANSPORT" == "usb" ]] || die "refusing non-USB target ($TRANSPORT): $TARGET_DISK"

mkdir -p "$RUN_DIR" "$TPM_STATE_DIR"
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
rm -f "$TPM_SOCKET" "$TPM_PIDFILE" "$QEMU_SERIAL_LOG" "$MONITOR_SOCKET" "$QEMU_STDOUT_LOG" "$QEMU_STDERR_LOG"

printf '[windows-usb-qemu] target: %s\n' "$TARGET_DISK"
printf '[windows-usb-qemu] model: %s\n' "$MODEL"
printf '[windows-usb-qemu] size: %s\n' "$SIZE"
printf '[windows-usb-qemu] transport: %s\n' "$TRANSPORT"
printf '[windows-usb-qemu] windows iso: %s\n' "$WINDOWS_ISO"
printf '[windows-usb-qemu] winpe iso: %s\n' "$WINPE_ISO"
printf '[windows-usb-qemu] autounattend iso: %s\n' "$AUTOUNATTEND_ISO"
printf '[windows-usb-qemu] ovmf code: %s\n' "$OVMF_CODE"
printf '[windows-usb-qemu] run dir: %s\n' "$RUN_DIR"
printf '[windows-usb-qemu] WARNING: this will let WinPE wipe %s completely if boot succeeds.\n' "$TARGET_DISK"

pkexec env TARGET_DISK="$TARGET_DISK" USER_NAME="$USER" bash -lc '
set -euo pipefail
TARGET_DISK="$TARGET_DISK"
USER_NAME="$USER_NAME"
for part in "$@"; do
  if findmnt -rn -S "$part" >/dev/null 2>&1; then
    udisksctl unmount -b "$part" >/dev/null
  fi
done
setfacl -m "u:${USER_NAME}:rw" "$TARGET_DISK"
' bash "${PARTS[@]}"

cleanup() {
  local status=$?
  if [[ -f "$TPM_PIDFILE" ]]; then
    kill "$(cat "$TPM_PIDFILE")" 2>/dev/null || true
  fi
  rm -f "$TPM_SOCKET" "$TPM_PIDFILE"
  pkexec setfacl -x "u:$USER" "$TARGET_DISK" >/dev/null 2>&1 || true
  exit $status
}
trap cleanup EXIT INT TERM

swtpm socket --tpm2 --tpmstate dir="$TPM_STATE_DIR" --ctrl type=unixio,path="$TPM_SOCKET" --daemon --pid file="$TPM_PIDFILE"

qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm,smm=on \
  -global driver=cfi.pflash01,property=secure,value=on \
  -cpu host \
  -smp "$CPUS" \
  -m "$MEMORY_MB" \
  -display gtk,gl=off \
  -serial file:"$QEMU_SERIAL_LOG" \
  -monitor unix:"$MONITOR_SOCKET",server,nowait \
  -vga std \
  -device ich9-ahci,id=sata \
  -chardev socket,id=chrtpm,path="$TPM_SOCKET" \
  -tpmdev emulator,id=tpm0,chardev=chrtpm \
  -device tpm-crb,tpmdev=tpm0 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$WINPE_ISO",if=none,media=cdrom,readonly=on,id=peiso \
  -device ide-cd,bus=sata.0,drive=peiso,bootindex=1 \
  -drive file="$WINDOWS_ISO",if=none,media=cdrom,readonly=on,id=srciso \
  -device ide-cd,bus=sata.1,drive=srciso \
  -drive file="$AUTOUNATTEND_ISO",if=none,media=cdrom,readonly=on,id=ansiso \
  -device ide-cd,bus=sata.2,drive=ansiso \
  -drive file="$TARGET_DISK",if=none,media=disk,format=raw,cache=none,aio=native,id=targetdisk \
  -device ide-hd,bus=sata.3,drive=targetdisk \
  -boot order=d,menu=on \
  -net none \
  >"$QEMU_STDOUT_LOG" 2>"$QEMU_STDERR_LOG" &
QEMU_PID=$!

for i in $(seq 1 30); do
  [[ -S "$MONITOR_SOCKET" ]] && break
  sleep 1
done

python3 - "$MONITOR_SOCKET" <<'PY'
import socket,sys,time
mon=sys.argv[1]
for _ in range(30):
    try:
        s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        s.connect(mon)
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit(0)
try:
    try:
        s.recv(4096)
    except Exception:
        pass
    s.sendall(b'sendkey ret\n')
    time.sleep(0.5)
finally:
    s.close()
PY

wait "$QEMU_PID"
