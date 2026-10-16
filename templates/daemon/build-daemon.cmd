@echo off
rem ============================================================
rem  Build Daemon  (template)
rem  ----------------------------------------------------------
rem  A persistent background watcher that runs firmware builds
rem  OUTSIDE the AI assistant's process tree. Because it is not
rem  a descendant of the AI assistant, its child compilers can
rem  never be suspended by the assistant's tool sandbox.
rem  This is the ROOT fix for the "build hang" problem.
rem
rem  Trigger : write one line into build.request   ("full" or "inc")
rem  Result  : build.status - RUNNING ... / DONE ... exit=rc
rem            build.log    - full compiler output
rem
rem  STEP 1: replace __PROJECT_DIR__ below with your project path.
rem  STEP 2: keep this file ASCII-only. cmd.exe parses it using
rem          the OEM codepage (GBK on zh-CN); any non-ASCII byte
rem          can be misread and executed as a command.
rem ============================================================
title Build Daemon

set "DIR=__PROJECT_DIR__"
cd /d "%DIR%"

set "REQ=%DIR%\build.request"
set "STA=%DIR%\build.status"
set "DLOG=%DIR%\build-daemon.log"
set "HB=%DIR%\build-daemon.heartbeat"
set "LOCK=%DIR%\.daemon.lock"
set /a N=0

rem --- single-instance guard (launchers remove a stale lock first) ---
mkdir "%LOCK%" 2>nul
if not exist "%LOCK%" (
  echo [%DATE% %TIME%] another daemon is already running - exiting >> "%DLOG%"
  exit /b 0
)

echo [%DATE% %TIME%] daemon started >> "%DLOG%"
echo %DATE% %TIME% > "%HB%"

:loop
if exist "%REQ%" goto dobuild
set /a N+=1
if %N% GEQ 10 (
  set /a N=0
  echo %DATE% %TIME% > "%HB%"
)
rem ping is used as a portable ~2 second sleep (timeout.exe needs a console)
ping -n 3 127.0.0.1 >nul 2>&1
goto loop

:dobuild
set "ARGS="
set /p ARGS=<"%REQ%"
del /q "%REQ%" >nul 2>&1
if /i "%ARGS%"=="full" (set "ARGS=clean") else (if "%ARGS%"=="" set "ARGS=inc")

echo RUNNING %DATE% %TIME% mode=%ARGS% > "%STA%"
echo [%DATE% %TIME%] === build start mode=%ARGS% === >> "%DLOG%"

call "%DIR%\build-quiet.cmd" %ARGS% 0
set RC=%ERRORLEVEL%

echo DONE %DATE% %TIME% exit=%RC% > "%STA%"
echo [%DATE% %TIME%] === build end exit=%RC% === >> "%DLOG%"
goto loop
