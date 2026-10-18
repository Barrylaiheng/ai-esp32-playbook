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
rem          __TOOLCHAIN_BIN__, __NODEJS_BIN__ and __PROJECT_DIR__ with your own.
rem  STEP 2: keep ALL comments/echo text in this file ASCII-only.
rem          cmd.exe parses this file using the OEM codepage (GBK on zh-CN),
rem          so non-ASCII bytes in comments can be mis-parsed and executed.
rem  STEP 3 (optional): the pre-build font guard below is a no-op unless your
rem          project generates font subsets. Delete the guard block and the
rem          nodejs PATH line if it does not.

rem  Usage:
rem    build-quiet.cmd          incremental build
rem    build-quiet.cmd clean    fullclean, then full build

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
rem nodejs on PATH so font regeneration (npx lv_font_conv) works under the daemon
set PATH=__NODEJS_BIN__;__TOOLCHAIN_BIN__;__CMAKE_BIN__;__NINJA_BIN__;%PATH%

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

rem ---- pre-build guard: regenerate stale font subsets (no-op when fresh) ----
rem CMake add_custom_command is blocked on IDF v6.0.1 by the reconfigure
rem bug (quoted IDF_VER in build_properties.temp.cmake), so generated font
rem .c files are guarded at build time instead: missing or older than their
rem generator/TTF inputs -> regenerate BEFORE compiling. Fast mtime check,
rem no npx call in the common case. Exit 98 (not 1) so build.status readers
rem can tell "guard refused" from "compiler failed".
echo --- ensure fonts up to date (pre-build guard) --- >> "%LOG%"
"%PY%" "%PROJ%\tools\ensure_fonts.py" >> "%LOG%" 2>&1
if errorlevel 1 goto font_fail

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

:font_fail
echo FONT_GUARD_FAILED >> "%LOG%"
echo EXIT=98 >> "%LOG%"
echo EXIT=98
exit /b 98
