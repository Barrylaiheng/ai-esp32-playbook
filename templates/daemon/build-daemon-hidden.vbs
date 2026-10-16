' Launch the build daemon with a hidden console window.
' STEP 1: replace __PROJECT_DIR__ with your project path.
' NOTE: keep the path ASCII-only and free of spaces so quoting stays simple.
Set sh = CreateObject("WScript.Shell")
sh.Run "__PROJECT_DIR__\build-daemon.cmd", 0, False
