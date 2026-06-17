@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0gui.ps1" %*
endlocal
