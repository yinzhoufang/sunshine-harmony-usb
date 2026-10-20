@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
if errorlevel 1 (
  echo Restore failed or was cancelled.
  if exist "%~dp0restore-error.txt" type "%~dp0restore-error.txt"
) else (
  echo Previous control panel restored. Current transport mode was preserved.
)
pause
