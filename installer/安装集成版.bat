@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
if errorlevel 1 (
  echo Installation failed or was cancelled. No transport switch was requested.
  if exist "%~dp0installation-error.txt" type "%~dp0installation-error.txt"
) else (
  echo Installation completed. Open Sunshine Control Panel - Device Hub.
)
pause
