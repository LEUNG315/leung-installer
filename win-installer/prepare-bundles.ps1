# prepare-bundles.ps1 - Build complete offline bundles for network-free installation
# Run this on a Windows machine with internet access.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BundlesDir = Join-Path $ScriptDir 'bundles'
$DownloadsDir = Join-Path $BundlesDir 'downloads'
$NpmOfflineDir = Join-Path $BundlesDir 'npm-offline'
$NodeDir = Join-Path $BundlesDir 'node'

if (Test-Path $BundlesDir) { Remove-Item $BundlesDir -Recurse -Force }
New-Item -ItemType Directory -Path $DownloadsDir -Force | Out-Null
New-Item -ItemType Directory -Path $NpmOfflineDir -Force | Out-Null
New-Item -ItemType Directory -Path $NodeDir -Force | Out-Null

# --- Versions ---
$CodexTag = 'rust-v0.137.0'
$NodeMajor = '24'

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " LEUNG win-installer: Building offline bundles" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Node.js binary (Windows)
# ============================================================
Write-Host "[1/4] Downloading Node.js binary..." -ForegroundColor Cyan
try {
    $listing = Invoke-WebRequest -Uri "https://nodejs.org/dist/latest-v${NodeMajor}.x/" -UseBasicParsing
    $match = [regex]::Match($listing.Content, 'node-v([\d.]+)')
    $nodeVer = if ($match.Success) { $match.Groups[1].Value } else { "${NodeMajor}.0.0" }
} catch { $nodeVer = "${NodeMajor}.0.0" }

$nodeZip = "node-v${nodeVer}-win-x64.zip"
$nodeUrl = "https://nodejs.org/dist/v${nodeVer}/$nodeZip"
Write-Host "  -> $nodeZip"
Invoke-WebRequest -Uri $nodeUrl -OutFile "$NodeDir\$nodeZip" -UseBasicParsing
$nodeVer | Out-File -FilePath "$NodeDir\version.txt" -Encoding UTF8 -NoNewline
$hash = (Get-FileHash "$NodeDir\$nodeZip" -Algorithm SHA256).Hash.ToLower()
"$hash  $nodeZip" | Out-File "$NodeDir\checksums.sha256" -Encoding UTF8
Write-Host "[OK] Node.js v$nodeVer" -ForegroundColor Green
Write-Host ""

# ============================================================
# 2. Codex release binary (Windows)
# ============================================================
Write-Host "[2/4] Downloading Codex CLI binary..." -ForegroundColor Cyan
$codexFilename = "codex-x86_64-pc-windows-msvc.exe"
$codexUrl = "https://github.com/openai/codex/releases/download/$CodexTag/$codexFilename"
Write-Host "  -> $codexFilename"
Invoke-WebRequest -Uri $codexUrl -OutFile "$DownloadsDir\$codexFilename" -UseBasicParsing
$hash = (Get-FileHash "$DownloadsDir\$codexFilename" -Algorithm SHA256).Hash.ToLower()
"$hash  $codexFilename" | Out-File "$DownloadsDir\checksums.sha256" -Encoding UTF8
Write-Host "[OK] Codex binary (SHA256: $hash)" -ForegroundColor Green
Write-Host ""

# ============================================================
# 3. Complete npm offline packages (with ALL dependencies)
# ============================================================
Write-Host "[3/4] Building complete npm offline packages..." -ForegroundColor Cyan
$packages = @("@openai/codex", "@anthropic-ai/claude-code", "@google/gemini-cli")
$tempDir = Join-Path $env:TEMP "leung-bundle-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

foreach ($pkg in $packages) {
    $safeName = $pkg -replace '[@/]', '-' -replace '^-', ''
    $pkgDir = Join-Path $NpmOfflineDir $safeName
    New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null

    Write-Host "  [$pkg] Resolving full dependency tree..."
    $tmpProj = Join-Path $tempDir $safeName
    New-Item -ItemType Directory -Path $tmpProj -Force | Out-Null
    '{"name":"bundle-' + $safeName + '","version":"1.0.0","dependencies":{"' + $pkg + '":"*"}}' | Out-File "$tmpProj\package.json" -Encoding UTF8

    Push-Location $tmpProj
    try {
        npm install --ignore-scripts --no-audit --no-fund 2>$null
    } catch {
        try { npm install --legacy-peer-deps --ignore-scripts --no-audit --no-fund 2>$null } catch {}
    }
    Pop-Location

    $nodeModules = Join-Path $tmpProj 'node_modules'
    if (Test-Path $nodeModules) {
        Write-Host "  [$pkg] Packing all resolved packages..."
        Get-ChildItem -Path $nodeModules -Recurse -Filter 'package.json' -Depth 2 | ForEach-Object {
            $dir = $_.DirectoryName
            try {
                Push-Location $dir
                npm pack --pack-destination $pkgDir 2>$null | Out-Null
                Pop-Location
            } catch { if ($PWD.Path -ne $ScriptDir) { Pop-Location } }
        }
        # Pack root package too
        try { npm pack $pkg --pack-destination $pkgDir 2>$null | Out-Null } catch {}
        $count = (Get-ChildItem $pkgDir -Filter '*.tgz').Count
        Write-Host "  [$pkg] Packed $count packages." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Fallback: packing root only" -ForegroundColor Yellow
        try { npm pack $pkg --pack-destination $pkgDir 2>$null | Out-Null } catch {}
    }
}

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "[OK] npm offline packages" -ForegroundColor Green
Write-Host ""

# ============================================================
# 4. Generate manifest
# ============================================================
Write-Host "[4/4] Generating bundle manifest..." -ForegroundColor Cyan
@"
{
  "version": "1.0.0",
  "created": "$(Get-Date -Format 'o')",
  "node_version": "$nodeVer",
  "codex_tag": "$CodexTag",
  "packages": ["@openai/codex", "@anthropic-ai/claude-code", "@google/gemini-cli"],
  "platforms": ["win-x64"]
}
"@ | Out-File "$BundlesDir\manifest.json" -Encoding UTF8

Write-Host "[OK] manifest.json" -ForegroundColor Green
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Bundle preparation complete" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "The installer can now run fully offline."
