#!/usr/bin/env bash
# prepare-bundles.sh - Build complete offline bundles for network-free installation
# Run this on a macOS machine with internet access.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/internal/macos/lib/node-config.sh"
BUNDLES_DIR="$SCRIPT_DIR/bundles"
DOWNLOADS_DIR="$BUNDLES_DIR/downloads"
NPM_OFFLINE_DIR="$BUNDLES_DIR/npm-offline"
NODE_DIR="$BUNDLES_DIR/node"

rm -rf "$BUNDLES_DIR"
mkdir -p "$DOWNLOADS_DIR" "$NPM_OFFLINE_DIR" "$NODE_DIR"

# --- Versions ---
NVM_VERSION="v0.40.4"
CODEX_TAG="rust-v0.137.0"
NODE_MAJOR="${NODE_LTS_MAJOR}"
NODE_VERSION="${NODE_LTS_VERSION}"
NODE_SHA256_DARWIN_X64="${NODE_LTS_SHA256_DARWIN_X64}"
NODE_SHA256_DARWIN_ARM64="${NODE_LTS_SHA256_DARWIN_ARM64}"
CODEX_DESKTOP_VERSION="26.609.41114"

echo "============================================"
echo " LEUNG mac-installer: Building offline bundles"
echo "============================================"
echo ""

# ============================================================
# 1. Node.js binaries (direct install, bypass nvm/brew)
# ============================================================
echo "[1/5] Downloading Node.js binaries..."
NODE_VER="$NODE_VERSION"
NODE_FULL="node-v${NODE_VER}"

for arch in darwin-x64 darwin-arm64; do
    filename="${NODE_FULL}-${arch}.tar.gz"
    url="https://nodejs.org/dist/v${NODE_VER}/${filename}"
    echo "  -> $filename"
    curl -fSL --progress-bar "$url" -o "$NODE_DIR/$filename"
    sha256="$(shasum -a 256 "$NODE_DIR/$filename" | awk '{print $1}')"
    case "$arch" in
        darwin-x64) expected_sha="$NODE_SHA256_DARWIN_X64" ;;
        darwin-arm64) expected_sha="$NODE_SHA256_DARWIN_ARM64" ;;
        *) expected_sha="" ;;
    esac
    if [[ -n "$expected_sha" && "$sha256" != "$expected_sha" ]]; then
        echo "     ERROR: SHA256 mismatch for $filename" >&2
        echo "     expected: $expected_sha" >&2
        echo "     actual:   $sha256" >&2
        exit 1
    fi
    echo "     SHA256: $sha256"
    echo "$sha256  $filename" >> "$NODE_DIR/checksums.sha256"
done
echo "$NODE_VER" > "$NODE_DIR/version.txt"
echo "[OK] Node.js v${NODE_VER}"
echo ""

# ============================================================
# 2. NVM install script (fallback)
# ============================================================
echo "[2/5] Downloading nvm install script..."
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" \
    -o "$DOWNLOADS_DIR/nvm-install.sh"
echo "[OK] nvm-install.sh"
echo ""

# ============================================================
# 3. Codex release binaries (macOS)
# ============================================================
echo "[3/5] Downloading Codex release binaries..."
for target in x86_64-apple-darwin aarch64-apple-darwin; do
    filename="codex-${target}.tar.gz"
    url="https://github.com/openai/codex/releases/download/${CODEX_TAG}/${filename}"
    echo "  -> $filename"
    curl -fSL --progress-bar "$url" -o "$DOWNLOADS_DIR/$filename"
    sha256="$(shasum -a 256 "$DOWNLOADS_DIR/$filename" | awk '{print $1}')"
    echo "     SHA256: $sha256"
    echo "$sha256  $filename" >> "$DOWNLOADS_DIR/checksums.sha256"
done
echo "[OK] Codex binaries"
echo ""

# ============================================================
# 3b. Codex Desktop app (Electron, from OpenAI CDN)
# ============================================================
echo "[3b/5] Downloading Codex Desktop app..."
for arch_label in x64 arm64; do
    filename="Codex-darwin-${arch_label}-${CODEX_DESKTOP_VERSION}.zip"
    url="https://persistent.oaistatic.com/codex-app-prod/${filename}"
    echo "  -> $filename"
    curl -fSL --progress-bar --max-time 1800 "$url" -o "$DOWNLOADS_DIR/$filename"
    sha256="$(shasum -a 256 "$DOWNLOADS_DIR/$filename" | awk '{print $1}')"
    echo "     SHA256: $sha256"
    echo "$sha256  $filename" >> "$DOWNLOADS_DIR/checksums.sha256"
done
echo "[OK] Codex Desktop"
echo ""

# ============================================================
# 4. Complete npm offline packages (with ALL dependencies)
# ============================================================
echo "[4/5] Building complete npm offline packages..."

TEMP_INSTALL_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_INSTALL_DIR"' EXIT

for pkg in "@openai/codex" "@anthropic-ai/claude-code" "@google/gemini-cli"; do
    safe_name="$(printf '%s' "$pkg" | tr '/' '-' | tr '@' '' | sed 's/^-//')"
    pkg_dir="$NPM_OFFLINE_DIR/$safe_name"
    mkdir -p "$pkg_dir"

    echo "  [$pkg] Resolving full dependency tree..."
    tmp_proj="$TEMP_INSTALL_DIR/$safe_name"
    mkdir -p "$tmp_proj"
    cat > "$tmp_proj/package.json" <<EOF
{"name":"bundle-$safe_name","version":"1.0.0","dependencies":{"$pkg":"*"}}
EOF

    (cd "$tmp_proj" && npm install --ignore-scripts --no-audit --no-fund 2>/dev/null) || \
    (cd "$tmp_proj" && npm install --legacy-peer-deps --ignore-scripts --no-audit --no-fund 2>/dev/null) || true

    if [[ -d "$tmp_proj/node_modules" ]]; then
        echo "  [$pkg] Packing all resolved packages..."
        find "$tmp_proj/node_modules" -name "package.json" -maxdepth 3 | while read -r pjson; do
            local_dir="$(dirname "$pjson")"
            local_name="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('name',''))" "$pjson" 2>/dev/null || true)"
            if [[ -n "$local_name" && "$local_name" != "bundle-$safe_name" ]]; then
                (cd "$local_dir" && npm pack --pack-destination "$pkg_dir" 2>/dev/null) || true
            fi
        done
        npm pack "$pkg" --pack-destination "$pkg_dir" 2>/dev/null || true
        count="$(find "$pkg_dir" -name "*.tgz" | wc -l)"
        echo "  [$pkg] Packed $count packages."
    else
        npm pack "$pkg" --pack-destination "$pkg_dir" 2>/dev/null || true
    fi
    echo ""
done
echo "[OK] npm offline packages"
echo ""

# ============================================================
# 5. Generate manifest
# ============================================================
echo "[5/5] Generating bundle manifest..."
cat > "$BUNDLES_DIR/manifest.json" <<EOF
{
  "version": "1.0.0",
  "created": "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')",
  "node_version": "$NODE_VER",
  "codex_tag": "$CODEX_TAG",
  "codex_desktop_version": "$CODEX_DESKTOP_VERSION",
  "nvm_version": "$NVM_VERSION",
  "packages": ["@openai/codex", "@anthropic-ai/claude-code", "@google/gemini-cli"],
  "platforms": ["darwin-x64", "darwin-arm64"]
}
EOF
echo "[OK] manifest.json"
echo ""
echo "Total size: $(du -sh "$BUNDLES_DIR" | awk '{print $1}')"
echo ""
echo "The installer can now run fully offline."
