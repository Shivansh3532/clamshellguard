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
echo                     ClamshellGuard
echo ============================================================
echo.
echo Keeps a Windows laptop awake when an external display is
echo active, while preserving normal lid-close behavior otherwise.
echo.
choice /C YN /N /M "Install for ALL users on this PC? [Y/N]: "
if errorlevel 2 (
    set "CG_SCOPE=CurrentUser"
) else (
    set "CG_SCOPE=AllUsers"
)

echo.
echo Installing ClamshellGuard (%CG_SCOPE%)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" -Scope "%CG_SCOPE%"
set "CG_EXIT=%errorlevel%"

echo.
if "%CG_EXIT%"=="0" (
    echo ClamshellGuard installation completed successfully.
    echo You can close this window.
) else (
    echo Installation failed with exit code %CG_EXIT%.
    echo See the error above for details.
)
echo.
pause
exit /b %CG_EXIT%
