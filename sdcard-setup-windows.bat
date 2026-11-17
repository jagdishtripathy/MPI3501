@echo off
REM ============================================================================
REM sdcard-setup-windows.bat — 1-Click Windows SD Card Setup for MPI3501 Display
REM ============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sdcard-setup-windows.ps1" %*
echo.
pause
