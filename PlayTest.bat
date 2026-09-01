@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "l10n\zh-TW\launch-test.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "l10n\zh-TW\launch-test.ps1"
)

if errorlevel 1 (
  echo.
  echo Launch failed. Press any key to close.
  pause >nul
)
