@echo off
rem ===========================================================================
rem  build-quiet.cmd - build with output redirected to a file (no pipe/pty)
rem
rem  Why this script exists:
rem  Piping build output through a pseudo-terminal risks a ninja hang, because
rem  ninja waits for pipe EOF. Redirecting output straight to a plain file
rem  (a normal file handle, not a pipe) removes that whole class of risk.
rem
rem  STEP 1: replace __IDF_PATH__, __IDF_TOOLS_PATH__, __PYTHON_ENV__,
rem          __TOOLCHAIN_BIN__ and __PROJECT_DIR__ with your own values.
rem  STEP 2: keep ALL comments/echo text in this file ASCII-only.
rem          cmd.exe parses this file using the OEM codepage (GBK on zh-CN),
rem          so non-ASCII bytes in comments can be mis-parsed and executed.
rem
rem  Usage:
rem    build-quiet.cmd          incremental build
rem    build-quiet.cmd clean    fullclean, then full build
rem
rem  After it finishes, read build.log; the script writes EXIT=code at the end.
rem ===========================================================================
setlocal

set MSYSTEM=
set OSTYPE=
set IDF_PATH=__IDF_PATH__
set IDF_TOOLS_PATH=__IDF_TOOLS_PATH__
set ESP_IDF_VERSION=__IDF_VERSION__
set IDF_MAINTAINER=1
set IDF_PYTHON_ENV_PATH=__PYTHON_ENV__
set PATH=__TOOLCHAIN_BIN__;__CMAKE_BIN__;__NINJA_BIN__;%PATH%

set PY=__PYTHON_ENV__\Scripts\python.exe
set PROJ=__PROJECT_DIR__
set LOG=%PROJ%\build.log

rem ---- allow overriding parallel jobs:  build-quiet.cmd clean 4 --------------
set JOBS=%2
if "%JOBS%"=="" set JOBS=0

echo === build start %DATE% %TIME% (arg=%~1 jobs=%JOBS%) === > "%LOG%"

if /i "%~1"=="clean" (
    echo --- fullclean --- >> "%LOG%"
    "%PY%" "%IDF_PATH%\tools\idf.py" -C "%PROJ%" fullclean >> "%LOG%" 2>&1
)

rem idf.py does NOT accept -j; reconfigure once (to refresh build.ninja),
rem then drive ninja directly so we can control the job count.
"%PY%" "%IDF_PATH%\tools\idf.py" -C "%PROJ%" reconfigure >> "%LOG%" 2>&1

rem Ninja MUST be launched through tools/run_ninja.py (python), NOT directly.
rem Reason: when ninja is started directly by cmd.exe it inherits this
rem (hidden) console as stdin, and the ldgen step then dies with errorcode -1.
rem Going through python with stdin=DEVNULL makes the same step succeed.
if "%JOBS%"=="0" (
    "%PY%" "%PROJ%\tools\run_ninja.py" -C "%PROJ%\build" >> "%LOG%" 2>&1
) else (
    "%PY%" "%PROJ%\tools\run_ninja.py" -C "%PROJ%\build" -j %JOBS% >> "%LOG%" 2>&1
)
set RC=%ERRORLEVEL%
echo EXIT=%RC% >> "%LOG%"
echo EXIT=%RC%
exit /b %RC%
