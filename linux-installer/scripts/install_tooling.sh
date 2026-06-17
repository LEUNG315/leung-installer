#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_BIN_DIR="${1:-${LEUNG_TOOLS_BIN_DIR:-$ROOT_DIR/.tools/bin}}"
SHELLCHECK_VERSION="${LEUNG_SHELLCHECK_VERSION:-0.10.0}"
SHFMT_VERSION="${LEUNG_SHFMT_VERSION:-3.8.0}"
SHELLCHECK_SHA256_X86_64="${LEUNG_SHELLCHECK_SHA256_X86_64:-6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87}"
SHELLCHECK_SHA256_AARCH64="${LEUNG_SHELLCHECK_SHA256_AARCH64:-324a7e89de8fa2aed0d0c28f3dab59cf84c6d74264022c00c22af665ed1a09bb}"
SHFMT_SHA256_AMD64="${LEUNG_SHFMT_SHA256_AMD64:-27b3c6f9d9592fc5b4856c341d1ff2c88856709b9e76469313642a1d7b558fe0}"
SHFMT_SHA256_ARM64="${LEUNG_SHFMT_SHA256_ARM64:-27e1f69b0d57c584bcbf5c882b4c4f78ffcf945d0efef45c1fbfc6692213c7c3}"
WORK_DIR="$(mktemp -d)"

cleanup() {
	rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() {
	printf '[TOOLS] %s\n' "$*" >&2
}

sha256_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

verify_checksum() {
	local label="$1" path="$2" expected="$3" actual=""
	actual="$(sha256_file "$path")"
	[[ "$actual" == "$expected" ]] || {
		printf '[TOOLS] checksum mismatch for %s expected=%s actual=%s\n' "$label" "$expected" "$actual" >&2
		return 1
	}
}

detect_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) printf '%s\n' 'x86_64' ;;
	aarch64 | arm64) printf '%s\n' 'aarch64' ;;
	*)
		printf 'unsupported arch: %s\n' "$(uname -m)" >&2
		return 1
		;;
	esac
}

install_shellcheck() {
	local arch archive url extract_dir expected_sha
	arch="$(detect_arch)"
	archive="$WORK_DIR/shellcheck.tar.xz"
	url="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${arch}.tar.xz"
	case "$arch" in
	x86_64) expected_sha="$SHELLCHECK_SHA256_X86_64" ;;
	aarch64) expected_sha="$SHELLCHECK_SHA256_AARCH64" ;;
	esac
	log "install shellcheck v${SHELLCHECK_VERSION}"
	curl -fsSL "$url" -o "$archive"
	verify_checksum "shellcheck" "$archive" "$expected_sha"
	tar -xJf "$archive" -C "$WORK_DIR"
	extract_dir="$(find "$WORK_DIR" -maxdepth 1 -type d -name "shellcheck-v${SHELLCHECK_VERSION}" | head -n 1)"
	install -m 755 "$extract_dir/shellcheck" "$TOOLS_BIN_DIR/shellcheck"
}

install_shfmt() {
	local arch suffix url expected_sha
	case "$(uname -m)" in
	x86_64 | amd64) suffix='amd64'; expected_sha="$SHFMT_SHA256_AMD64" ;;
	aarch64 | arm64) suffix='arm64'; expected_sha="$SHFMT_SHA256_ARM64" ;;
	*)
		printf 'unsupported arch: %s\n' "$(uname -m)" >&2
		return 1
		;;
	esac
	url="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${suffix}"
	log "install shfmt v${SHFMT_VERSION}"
	curl -fsSL "$url" -o "$TOOLS_BIN_DIR/shfmt"
	verify_checksum "shfmt" "$TOOLS_BIN_DIR/shfmt" "$expected_sha"
	chmod 755 "$TOOLS_BIN_DIR/shfmt"
}

mkdir -p "$TOOLS_BIN_DIR"
install_shellcheck
install_shfmt
log "installed to $TOOLS_BIN_DIR"
