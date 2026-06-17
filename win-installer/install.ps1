#Requires -Version 5.1
# LEUNG Codex Installer - Entry Point
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
& (Join-Path $ScriptDir 'internal\windows\install.ps1') @args
