@echo off
rem ============================================================
rem  Build Daemon - one-time installer
rem  ----------------------------------------------------------
rem  Double-click ONCE.
rem    1. stops any running daemon
rem    2. registers the daemon to auto-start at every login
rem    3. starts the daemon right now (hidden)
rem
rem  IMPORTANT: this MUST be run by a human, outside the AI
rem  assistant's sandbox. If the daemon is launched from the
rem  assistant's background it INHERITS the sandbox and the
rem  original hang comes back.
rem
rem  STEP 1: replace __PROJECT_DIR__ below.
rem  STEP 2: keep this file ASCII-only.
rem ============================================================
setlocal
set "DIR=__PROJECT_DIR__"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo ==========================================
echo    Build Daemon - installer
echo ==========================================
echo.

if not exist "%DIR%\build-daemon.cmd" (
  echo   [FAIL] build-daemon.cmd not found in:
  echo          %DIR%
  echo.
  pause
  exit /b 1
)

echo   [1/4] stopping any running daemon ...
taskkill /f /fi "WINDOWTITLE eq Build Daemon" >nul 2>&1

echo   [2/4] clearing stale lock ...
rmdir /s /q "%DIR%\.daemon.lock" >nul 2>&1

echo   [3/4] registering auto-start at login ...
copy /y "%DIR%\build-daemon-autostart.vbs" "%STARTUP%\BuildDaemon.vbs" >nul 2>&1
if exist "%STARTUP%\BuildDaemon.vbs" (
  echo         ok: BuildDaemon.vbs
) else (
  echo         [WARN] could not write to the Startup folder.
)

echo   [4/4] starting daemon now ^(hidden^) ...
start "" wscript.exe "%DIR%\build-daemon-hidden.vbs"

echo.
echo   Done.
echo   - daemon is running now
echo   - it will auto-start at every login
echo   - heartbeat file: build-daemon.heartbeat
echo.
pause
endlocal
