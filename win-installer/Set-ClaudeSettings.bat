@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo Configure Claude settings.json
echo.

set "TARGET="
if exist "%USERPROFILE%\.claude\settings.json" set "TARGET=%USERPROFILE%\.claude\settings.json"
if not defined TARGET if exist "%USERPROFILE%\.config\claude\settings.json" set "TARGET=%USERPROFILE%\.config\claude\settings.json"
if not defined TARGET if exist "%USERPROFILE%\AppData\Roaming\Claude\settings.json" set "TARGET=%USERPROFILE%\AppData\Roaming\Claude\settings.json"
if not defined TARGET if exist "%USERPROFILE%\AppData\Local\Claude\settings.json" set "TARGET=%USERPROFILE%\AppData\Local\Claude\settings.json"
if not defined TARGET set "TARGET=%USERPROFILE%\.claude\settings.json"

for %%I in ("%TARGET%") do set "TARGET_DIR=%%~dpI"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo Target file:
echo %TARGET%
echo.

set "BASE_URL="
set /p BASE_URL=Enter ANTHROPIC_BASE_URL [default: https://api.example.com]: 
if "%BASE_URL%"=="" set "BASE_URL=https://api.example.com"

:ASK_APIKEY
set "API_KEY="
set /p API_KEY=Enter ANTHROPIC_API_KEY: 
if "%API_KEY%"=="" (
  echo API key cannot be empty.
  goto ASK_APIKEY
)

if exist "%TARGET%" (
  set "STAMP=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
  set "STAMP=!STAMP: =0!"
  copy /y "%TARGET%" "%TARGET%.bak-!STAMP!" >nul
  echo Backup created: %TARGET%.bak-!STAMP!
) else (
  echo Existing settings.json not found. A new file will be created.
)

(
  echo {
  echo   "env": {
  echo     "ANTHROPIC_BASE_URL": "%BASE_URL%",
  echo     "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
  echo     "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
  echo     "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
  echo     "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
  echo     "CLAUDE_CODE_EFFORT_LEVEL": "max",
  echo     "ANTHROPIC_API_KEY": "%API_KEY%",
  echo     "ANTHROPIC_MODEL": "claude-sonnet-4-6",
  echo     "ANTHROPIC_SMALL_FAST_MODEL": "claude-sonnet-4-6",
  echo     "CLAUDE_CODE_SIMPLE": "1"
  echo   },
  echo   "theme": "dark",
  echo   "hasCompletedOnboarding": true,
  echo   "claude_code_login": false,
  echo   "skip_login": true
  echo }
) > "%TARGET%"

echo.
echo Done.
echo Wrote: %TARGET%
echo.
pause
