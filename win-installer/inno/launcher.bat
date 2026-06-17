@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "..\install.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo Installation encountered an error. Press any key to exit.
    pause >nul
)
endlocal
