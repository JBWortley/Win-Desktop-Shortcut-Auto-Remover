Win Desktop Shortcut Auto-Remover - Windows 10/11

INSTALL
Double-click Install.cmd. A setup console shows the result; press a key to close it.
Scheduled cleanups themselves have no window, notification, console flash or UAC prompt.
The original "task schedule installer.bat" is also an alias for Install.cmd.
No downloads, administrator password or extra runtime installation are required.

UNINSTALL
Double-click Uninstall.cmd, either here or in %LOCALAPPDATA%\DesktopIconCleaner.
This removes the scheduled task and installed program. It leaves the Recycle Bin
and cleanup logs intact. Re-running either installer or uninstaller is supported.

WHAT IT DOES
Runs immediately after installation, 30 seconds after sign-in, and every 3 hours
while you are signed in. It runs on battery and AC, catches missed starts, and
does not wake the computer or overlap itself.

Only the TOP LEVEL of your personal Desktop and Public Desktop is inspected:
* Files ending in .lnk or .url (case-insensitive): recycle the shortcut itself.
* Directories named exactly "New Folder" (case-insensitive): recycle only if empty.
  Hidden/system entries count as contents. "New Folder (2)" is left alone.
* All other files and folders, shortcut targets, and nested items are left alone.
* Reparse points (including junctions/symlinks) are skipped. Network/removable
  desktops and reparse-point desktop roots are skipped and logged.

The Windows recycling API is used with UI suppressed and a pre-delete veto
against permanent deletion. Items are rechecked just before recycling. Access
denied, locked items and unavailable Recycle Bins cause a logged failure, never
an elevation prompt or a fallback to permanent deletion. Protected Public Desktop
shortcuts may require administrator rights and are intentionally left untouched.
Restore cleaned items using Windows Recycle Bin if needed.

STATUS
%LOCALAPPDATA%\DesktopIconCleaner\Logs\last-run.json contains the latest result.
history.jsonl keeps earlier results and rotates at approximately 1 MB.
The task is named DesktopIconCleaner-<your Windows SID> in Task Scheduler.
Exit code 0 = success; 1 = one or more failures (see the report).
The installed copy is independent of this source folder.

MAINTENANCE / HEADLESS USE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Uninstall
Add -NoStart to install without the initial cleanup.
Set DESKTOP_CLEANER_NO_PAUSE=1 to skip the CMD wrappers' final pause.
DesktopIconCleaner.exe --preview writes a read-only candidate report.
DesktopIconCleaner.exe --run performs a cleanup.
Launching the EXE without arguments only previews; it displays no window.
Build.ps1 rebuilds the Windows-subsystem EXE using Windows' .NET Framework compiler.
Test.ps1 runs isolated recycling and scheduler install/uninstall tests, without
changing the desktop or automating keyboard, mouse, display focus or other UI.

API references:
https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperation-setoperationflags
https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperationprogresssink-predeleteitem
