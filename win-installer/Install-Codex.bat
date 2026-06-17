@echo off
:: LEUNG CLI Installer - Double-click to launch GUI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\windows\gui.ps1"
pause
