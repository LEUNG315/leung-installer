#Requires -Version 5.1
# LEUNG CLI Installer - Remote Bootstrap
# Usage: irm https://your-server/remote-install.ps1 | iex
#
# This script runs in-memory (bypasses ExecutionPolicy), downloads the
# installer archive, unblocks all files, and launches the installer in a
# child process with -ExecutionPolicy Bypass.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# --- Configuration ---
$RepoZipUrl = 'https://your-server/win-installer.zip'  # TODO: replace with actual URL
$InstallDir = Join-Path $env:TEMP "leung-installer-$(Get-Random)"

Write-Host ''
Write-Host '  LEUNG CLI Installer' -ForegroundColor Cyan
Write-Host '  ===================' -ForegroundColor Cyan
Write-Host ''

# --- Step 1: Set ExecutionPolicy for current user (safe, no admin needed) ---
try {
    $current = Get-ExecutionPolicy -Scope CurrentUser
    if ($current -eq 'Restricted' -or $current -eq 'Undefined') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host '  [OK] ExecutionPolicy -> RemoteSigned (CurrentUser)' -ForegroundColor Green
    }
} catch {
    Write-Host '  [WARN] Could not set ExecutionPolicy, will use Bypass flag.' -ForegroundColor Yellow
}

# --- Step 2: Download and extract installer ---
Write-Host "  [*] Downloading installer..." -ForegroundColor Gray
$zipPath = "$InstallDir.zip"
try {
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipPath -UseBasicParsing
} catch {
    Write-Host "  [ERROR] Download failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "  [*] Extracting..." -ForegroundColor Gray
Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# --- Step 3: Unblock all downloaded .ps1 files (remove Zone.Identifier ADS) ---
Get-ChildItem -Path $InstallDir -Recurse -Filter '*.ps1' | ForEach-Object {
    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}

# --- Step 4: Find and launch installer ---
# Support both flat and nested zip structures (e.g. win-installer-main/...)
$entryScript = Get-ChildItem -Path $InstallDir -Recurse -Filter 'install.ps1' |
    Where-Object { $_.DirectoryName -notmatch 'internal' } |
    Select-Object -First 1

if (-not $entryScript) {
    Write-Host '  [ERROR] install.ps1 not found in archive.' -ForegroundColor Red
    exit 1
}

Write-Host "  [*] Launching installer..." -ForegroundColor Gray
Write-Host ''

# Launch in a new powershell process with Bypass to guarantee no policy issues.
$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $entryScript.FullName
) -Wait -PassThru -NoNewWindow

# --- Cleanup ---
Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

if ($proc.ExitCode -ne 0) {
    Write-Host "  [WARN] Installer exited with code $($proc.ExitCode)" -ForegroundColor Yellow
}
