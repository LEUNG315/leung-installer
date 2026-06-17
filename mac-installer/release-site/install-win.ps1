#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$BaseUrl = if ($env:BASE_URL) { $env:BASE_URL } else { 'https://static.example.com/installers' }
$ArchiveUrl = if ($env:ARCHIVE_URL) { $env:ARCHIVE_URL } else { "$BaseUrl/win-installer.zip" }
$InstallDir = Join-Path $env:TEMP "leung-installer-$([guid]::NewGuid().ToString('N'))"
$ZipPath = "$InstallDir.zip"

Write-Host ''
Write-Host '  LEUNG CLI Installer' -ForegroundColor Cyan
Write-Host '  ===================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  [*] Downloading installer: $ArchiveUrl" -ForegroundColor Gray

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Invoke-WebRequest -Uri $ArchiveUrl -OutFile $ZipPath -UseBasicParsing
Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

Get-ChildItem -Path $InstallDir -Recurse -Filter '*.ps1' | ForEach-Object {
    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}

$EntryScript = Get-ChildItem -Path $InstallDir -Recurse -Filter 'install.ps1' |
    Where-Object { $_.DirectoryName -notmatch 'internal' } |
    Select-Object -First 1

if (-not $EntryScript) {
    Write-Host '  [ERROR] install.ps1 not found in archive.' -ForegroundColor Red
    exit 1
}

Write-Host '  [*] Launching installer...' -ForegroundColor Gray
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EntryScript.FullName @args
