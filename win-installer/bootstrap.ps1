#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$Installer = Join-Path $ScriptDir 'install.ps1'
if (-not (Test-Path $Installer)) {
    Write-Host "[bootstrap] 缺少 install.ps1" -ForegroundColor Red
    exit 1
}

& $Installer @args
