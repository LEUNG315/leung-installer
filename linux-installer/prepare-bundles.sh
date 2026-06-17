#!/usr/bin/env bash
# prepare-bundles.sh - Build complete offline bundles for network-free installation
# Run this on a machine with internet access.
# After running, the entire linux-installer directory can be used offline.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLES_DIR="$SCRIPT_DIR/bundles"
DOWNLOADS_DIR="$BUNDLES_DIR/downloads"
NPM_OFFLINE_DIR="$BUNDLES_DIR/npm-offline"
NODE_DIR="$BUNDLES_DIR/node"

rm -rf "$BUNDLES_DIR"
mkdir -p "$DOWNLOADS_DIR" "$NPM_OFFLINE_DIR" "$NODE_DIR"

# --- Versions ---
NVM_VERSION="v0.40.4"
CODEX_TAG="rust-v0.137.0"
NODE_MAJOR="24"

echo "============================================"
echo " LEUNG linux-installer: Building offline bundles"
echo "============================================"
echo ""

# ============================================================
# 1. Node.js binaries (direct install, bypass nvm in offline mode)
# ============================================================
echo "[1/5] Downloading Node.js binaries..."
NODE_INDEX="$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/" 2>/dev/null)"
NODE_VER="$(printf '%s' "$NODE_INDEX" | grep -oP 'node-v\K[\d.]+' | head -1)"
NODE_FULL="node-v${NODE_VER}"

for arch in linux-x64 linux-arm64; do
    filename="${NODE_FULL}-${arch}.tar.xz"
    url="https://nodejs.org/dist/v${NODE_VER}/${filename}"
    echo "  -> $filename"
    curl -fSL --progress-bar "$url" -o "$NODE_DIR/$filename"
    sha256="$(sha256sum "$NODE_DIR/$filename" | awk '{print $1}')"
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
# 3. Codex release binaries
# ============================================================
echo "[3/5] Downloading Codex release binaries..."
for target in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    filename="codex-${target}.tar.gz"
    url="https://github.com/openai/codex/releases/download/${CODEX_TAG}/${filename}"
    echo "  -> $filename"
    curl -fSL --progress-bar "$url" -o "$DOWNLOADS_DIR/$filename"
    sha256="$(sha256sum "$DOWNLOADS_DIR/$filename" | awk '{print $1}')"
    echo "     SHA256: $sha256"
    echo "$sha256  $filename" >> "$DOWNLOADS_DIR/checksums.sha256"
done
echo "[OK] Codex binaries"
echo ""

# ============================================================
# 4. Complete npm offline packages (with ALL dependencies)
# ============================================================
echo "[4/5] Building complete npm offline packages..."
echo "  This downloads all transitive dependencies for offline install."
echo ""

TEMP_INSTALL_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_INSTALL_DIR"' EXIT

for pkg in "@openai/codex" "@anthropic-ai/claude-code" "@google/gemini-cli"; do
    safe_name="$(printf '%s' "$pkg" | tr '/' '-' | tr -d '@' | sed 's/^-//')"
    pkg_dir="$NPM_OFFLINE_DIR/$safe_name"
    mkdir -p "$pkg_dir"

    echo "  [$pkg] Resolving full dependency tree..."

    # Create temp package.json and install all deps
    tmp_proj="$TEMP_INSTALL_DIR/$safe_name"
    mkdir -p "$tmp_proj"
    cat > "$tmp_proj/package.json" <<EOF
{"name":"bundle-$safe_name","version":"1.0.0","dependencies":{"$pkg":"*"}}
EOF

    # Install with full dependency resolution
    (cd "$tmp_proj" && npm install --ignore-scripts --no-audit --no-fund 2>/dev/null) || {
        echo "  [WARN] npm install for $pkg failed, trying alternative..."
        (cd "$tmp_proj" && npm install --legacy-peer-deps --ignore-scripts --no-audit --no-fund 2>/dev/null) || true
    }

    # Pack all packages from node_modules into tarballs
    if [[ -d "$tmp_proj/node_modules" ]]; then
        echo "  [$pkg] Packing all resolved packages..."
        find "$tmp_proj/node_modules" -name "package.json" -maxdepth 3 | while read -r pjson; do
            local_dir="$(dirname "$pjson")"
            local_name="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('name',''))" "$pjson" 2>/dev/null || true)"
            if [[ -n "$local_name" && "$local_name" != "bundle-$safe_name" ]]; then
                (cd "$local_dir" && npm pack --pack-destination "$pkg_dir" 2>/dev/null) || true
            fi
        done

        # Also pack the root package itself
        npm pack "$pkg" --pack-destination "$pkg_dir" 2>/dev/null || true

        # Count packaged files
        count="$(find "$pkg_dir" -name "*.tgz" | wc -l)"
        echo "  [$pkg] Packed $count packages."
    else
        echo "  [WARN] No node_modules for $pkg, falling back to root-only pack"
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
  "created": "$(date -Iseconds)",
  "node_version": "$NODE_VER",
  "codex_tag": "$CODEX_TAG",
  "nvm_version": "$NVM_VERSION",
  "packages": ["@openai/codex", "@anthropic-ai/claude-code", "@google/gemini-cli"],
  "platforms": ["linux-x64", "linux-arm64"]
}
EOF
echo "[OK] manifest.json"

echo ""
echo "============================================"
echo " Bundle preparation complete"
echo "============================================"
echo ""
echo "Structure:"
echo "  bundles/"
echo "    downloads/     - Codex binaries, nvm script"
echo "    node/          - Node.js v${NODE_VER} binaries"
echo "    npm-offline/   - Complete npm packages with deps"
echo "    manifest.json  - Bundle metadata"
echo ""
echo "Total size: $(du -sh "$BUNDLES_DIR" | awk '{print $1}')"
echo ""
echo "The installer can now run fully offline."
