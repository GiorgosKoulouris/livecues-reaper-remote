@echo off
rem Double-click to install or update LiveCues ReaperRemote into REAPER's web root (runs install.ps1 next to this file).
rem From a prompt, arguments pass through: install.bat -Link, install.bat -Uninstall, install.bat -Root D:\www -Port 9000
rem The window may warn about a UNC current directory when run from \\wsl$\...; harmless, the script uses its own path.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "rc=%errorlevel%"
echo.
if not "%rc%"=="0" echo Install failed (exit code %rc%).
pause
exit /b %rc%
