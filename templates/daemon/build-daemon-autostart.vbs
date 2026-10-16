' Auto-start shim: clear any stale lock, then launch the daemon hidden.
' Copy this file into the Startup folder (or use install-build-daemon.cmd).
' STEP 1: replace __PROJECT_DIR__ with your project path.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If fso.FolderExists("__PROJECT_DIR__\.daemon.lock") Then
  fso.DeleteFolder "__PROJECT_DIR__\.daemon.lock", True
End If

sh.Run "__PROJECT_DIR__\build-daemon.cmd", 0, False
