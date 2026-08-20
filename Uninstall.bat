@echo off
setlocal EnableExtensions
cd /d "%~dp0"

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cls
echo ============================================================
echo                ClamshellGuard Uninstaller
echo ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1"
set "CG_EXIT=%errorlevel%"
echo.
if "%CG_EXIT%"=="0" (
    echo ClamshellGuard was removed and managed lid settings were restored.
) else (
    echo Uninstall failed with exit code %CG_EXIT%.
)
echo.
pause
exit /b %CG_EXIT%
