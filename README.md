# Win Desktop Shortcut Auto-Remover

Keep your Windows desktop clear of shortcuts without interrupting your work.

Win Desktop Shortcut Auto-Remover automatically sends desktop shortcuts and empty folders named **New Folder** to the Windows Recycle Bin. Scheduled cleanups run without console flashes, popups, or focus changes.

## What gets cleaned?

The cleaner checks only the **top level** of your personal Desktop and the shared Public Desktop.

| Item | Action |
| --- | --- |
| `.lnk` shortcuts | Recycle the shortcut; leave its target untouched |
| `.url` internet shortcuts | Recycle the shortcut |
| An empty folder named exactly `New Folder` | Recycle the folder |
| A `New Folder` containing anything, including hidden or system files | Leave untouched |
| Numbered folders such as `New Folder (2)` | Leave untouched |
| Other files and folders | Leave untouched |
| Items inside subfolders | Leave untouched |
| Symbolic links, junctions, and other reparse points | Skip |

Names and extensions are matched without regard to capitalization. There is no exclusion list: every matching shortcut at the desktop's top level is eligible.

## Install

1. Download and extract the [installer package](DesktopIconCleaner.zip), or download the repository files.
2. Double-click **`Install.cmd`** from the extracted folder.
3. Check the setup result, then press a key to close the setup console.

**Installation starts a cleanup immediately.** After that, the cleaner runs:

- 30 seconds after you sign in.
- Every three hours while you are signed in.

It works on battery and AC power, catches missed scheduled starts when available, and prevents overlapping runs. It does not wake the computer.

The setup console appears only when you manually run the installer or uninstaller. Scheduled cleanups launch a windowless executable directly through Windows Task Scheduler.

The installed files live in `%LOCALAPPDATA%\DesktopIconCleaner`, independently of the downloaded folder. Running the installer again updates the existing installation.

### Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1, .NET Framework 4.x, and Windows Task Scheduler.
- A local desktop on a fixed drive with Recycle Bin support.

The installer uses your current Windows account and does not request administrator elevation. Protected Public Desktop items that your account cannot remove are left in place and logged. Network/removable desktops and desktop roots that are reparse points are skipped and logged.

## Uninstall

Double-click **`Uninstall.cmd`** in the extracted folder or in `%LOCALAPPDATA%\DesktopIconCleaner`.

This removes the scheduled task and installed program files. Cleanup logs and existing Recycle Bin items are retained. Uninstalling does not restore previously recycled shortcuts; use the Windows Recycle Bin to restore them.

## Recycling and silent operation

The cleaner uses the Windows Shell recycling API with progress dialogs, error dialogs, and elevation prompts suppressed. It rechecks each candidate immediately before recycling and cancels deletion if Windows proposes permanent deletion.

Locked files, access-denied errors, and recycling failures are logged. Other candidates can still be processed. The cleaner does not fall back to permanently deleting desktop items.

The background executable creates no application window and does not simulate keyboard or mouse input, activate applications, or change display focus.

## Preview and logs

To inspect what would be cleaned without moving anything, run this from the extracted folder in PowerShell:

```powershell
Start-Process -FilePath .\DesktopIconCleaner.exe -ArgumentList '--preview' -Wait
Get-Content "$env:LOCALAPPDATA\DesktopIconCleaner\Logs\last-run.json"
```

Launching the executable without arguments also performs a preview. Preview writes a report but does not install a task or recycle items. An already installed task continues to run on its normal schedule.

| Location | Contents |
| --- | --- |
| `%LOCALAPPDATA%\DesktopIconCleaner\Logs\last-run.json` | Latest cleanup or preview result |
| `%LOCALAPPDATA%\DesktopIconCleaner\Logs\history.jsonl` | Run history, rotated at approximately 1 MB |
| `%LOCALAPPDATA%\DesktopIconCleaner\installation.json` | Installed task name and installation details |

The task is named `DesktopIconCleaner-<your Windows SID>`. Exit code `0` indicates success; `1` indicates a failure. Check the report for affected paths and error messages.

The internal executable, task, and installation directory retain the name `DesktopIconCleaner`.

## Command-line setup

Run these commands from the extracted folder:

```powershell
# Install and start the first cleanup.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Install

# Install without the immediate cleanup; future scheduled runs remain enabled.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Install -NoStart

# Uninstall.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Uninstall
```

For automation using the `.cmd` wrappers, set `DESKTOP_CLEANER_NO_PAUSE=1` to disable their final pause. The legacy `task schedule installer.bat` forwards to `Install.cmd`.

## Build and test

From a source checkout, use the .NET Framework compiler included with Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test.ps1
```

The test suite creates temporary fixture files and a separate scheduled task. It performs real Recycle Bin operations on those fixtures without cleaning your desktop. Fixture files and reports remain under `test-results`; recycled test items remain in the Recycle Bin. The test task is removed afterward.

Validation completed during development:

- **53 checks passed**, including restore metadata, preservation of unrelated files and shortcut targets, nonempty folders, junctions, locked-file handling, and the permanent-deletion veto.
- Installation, repeat installation, scheduled execution, and repeat uninstallation passed.
- A live desktop run recycled five shortcuts and preserved eight other top-level items. Recycled contents and restore metadata were verified.
- Monitoring during that live run detected no visible worker windows or foreground focus from the worker.

The sign-in trigger was inspected; testing did not sign the user out or restart the computer.
