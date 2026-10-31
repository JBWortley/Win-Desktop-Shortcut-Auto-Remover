$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath($PSScriptRoot)
$testBase = Join-Path $workspace ('test-results\' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $testBase 'Desktop fixture'
$report = Join-Path $testBase 'last-run.json'
$exe = Join-Path $workspace 'DesktopIconCleaner.exe'
$checks = New-Object 'System.Collections.Generic.List[string]'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

function Assert-True($condition, [string]$message) {
    if (-not $condition) { throw "FAILED: $message" }
    $checks.Add($message)
    Write-Output "PASS: $message"
}
function Run-Cleaner([string]$mode = '--run') {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.Arguments = "$mode --test-root `"$fixture`" --report `"$report`""
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $process = [Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit(30000)) { throw 'Cleaner did not finish within 30 seconds.' }
    $script:runExitCode = $process.ExitCode
    $process.Dispose()
    return (Get-Content -LiteralPath $report -Raw | ConvertFrom-Json)
}
function Run-Setup([string]$action, [bool]$noStart = $false) {
    $arguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', (Join-Path $workspace 'Setup.ps1'), '-Action', $action, '-TestMode', '-TestRoot', $fixture)
    if ($noStart) { $arguments += '-NoStart' }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Setup $action failed: $LASTEXITCODE" }
}
function Assert-Recycled($item) {
    Assert-True ($item.Status -eq 'Recycled') "Reported as recycled: $($item.Path)"
    Assert-True (-not (Test-Path -LiteralPath $item.Path)) 'Recycled source is absent'
    Assert-True ($item.RecyclePath -and (Test-Path -LiteralPath $item.RecyclePath)) 'Recycled data really exists in the Windows Recycle Bin'
    $leaf = [IO.Path]::GetFileName($item.RecyclePath)
    Assert-True ($leaf.StartsWith('$R')) 'Recycle Bin storage name is valid'
    $metadata = Join-Path ([IO.Path]::GetDirectoryName($item.RecyclePath)) ('$I' + $leaf.Substring(2))
    Assert-True (Test-Path -LiteralPath $metadata) 'Windows restore metadata exists'
    $metadataText = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($metadata))
    Assert-True ($metadataText.Contains($item.Path)) 'Restore metadata records the correct original path'
}

try {
    & (Join-Path $workspace 'Build.ps1')
    $bytes = [IO.File]::ReadAllBytes($exe)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    Assert-True ([BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68) -eq 2) 'Executable uses Windows subsystem (no console allocation)'

    $target = Join-Path $testBase 'shortcut target.txt'
    Set-Content -LiteralPath $target -Value 'Target must survive unchanged.'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($name in @('Application.lnk','UPPERCASE.LNK')) {
        $shortcut = $shell.CreateShortcut((Join-Path $fixture $name))
        $shortcut.TargetPath = $target
        $shortcut.Save()
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
    }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    Set-Content -LiteralPath (Join-Path $fixture 'Website.url') -Value "[InternetShortcut]`r`nURL=https://example.invalid/"
    Set-Content -LiteralPath (Join-Path $fixture 'keep.txt') -Value 'Keep this ordinary file.'
    Set-Content -LiteralPath (Join-Path $fixture 'fake.lnk.txt') -Value 'Not a shortcut.'
    Set-Content -LiteralPath (Join-Path $fixture 'desktop.ini') -Value 'Hidden file must stay.'
    [IO.File]::SetAttributes((Join-Path $fixture 'desktop.ini'), [IO.FileAttributes]::Hidden)
    foreach ($directory in @('New Folder','New Folder (2)','Other folder','Folder.lnk')) {
        New-Item -ItemType Directory -Path (Join-Path $fixture $directory) | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $fixture 'Other folder\nested.lnk') -Value 'Nested shortcuts must stay.'
    $protectedPaths = @($target, (Join-Path $fixture 'keep.txt'), (Join-Path $fixture 'fake.lnk.txt'), (Join-Path $fixture 'desktop.ini'), (Join-Path $fixture 'Other folder\nested.lnk'))
    $beforeHashes = @{}
    foreach ($path in $protectedPaths) { $beforeHashes[$path] = (Get-FileHash -LiteralPath $path).Hash }

    $preview = Run-Cleaner '--preview'
    Assert-True ($runExitCode -eq 0 -and $preview.Candidates -eq 4 -and $preview.Recycled -eq 0) 'Preview finds exactly three shortcuts and one empty New Folder without changing anything'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture 'Application.lnk')) 'Preview leaves candidates in place'
    $clean = Run-Cleaner
    Assert-True ($runExitCode -eq 0 -and $clean.Recycled -eq 4 -and $clean.Failed -eq 0) 'Real Windows recycling succeeds for all four matching items'
    foreach ($item in $clean.Items) { Assert-Recycled $item }
    foreach ($path in $protectedPaths) { Assert-True ((Get-FileHash -LiteralPath $path).Hash -eq $beforeHashes[$path]) "Protected file is unchanged: $path" }
    foreach ($name in @('New Folder (2)','Other folder','Folder.lnk')) { Assert-True (Test-Path -LiteralPath (Join-Path $fixture $name) -PathType Container) "Protected folder survives: $name" }

    $emptyName = Join-Path $fixture 'New Folder'
    New-Item -ItemType Directory -Path $emptyName | Out-Null
    $hiddenContent = Join-Path $emptyName 'hidden.txt'
    Set-Content -LiteralPath $hiddenContent -Value 'A hidden file makes this folder nonempty.'
    [IO.File]::SetAttributes($hiddenContent, [IO.FileAttributes]::Hidden)
    $nonempty = Run-Cleaner
    Assert-True ($runExitCode -eq 0 -and $nonempty.Candidates -eq 0 -and (Test-Path -LiteralPath $hiddenContent)) 'New Folder containing only a hidden file is preserved'
    Move-Item -LiteralPath $emptyName -Destination (Join-Path $fixture 'Preserved nonempty folder')
    New-Item -ItemType Junction -Path $emptyName -Target (Join-Path $fixture 'Other folder') | Out-Null
    $junction = Run-Cleaner
    Assert-True ($runExitCode -eq 0 -and $junction.Candidates -eq 0 -and (Test-Path -LiteralPath $emptyName)) 'Junction named New Folder is preserved without following it'
    # Delete only this known junction itself; no recursive operation is used.
    [IO.Directory]::Delete($emptyName)

    $lockedPath = Join-Path $fixture 'locked.lnk'
    Set-Content -LiteralPath $lockedPath -Value 'Locked shortcut fixture.'
    $lock = [IO.File]::Open($lockedPath, 'Open', 'ReadWrite', 'None')
    try {
        $locked = Run-Cleaner
        Assert-True ($runExitCode -eq 1 -and $locked.Failed -eq 1 -and (Test-Path -LiteralPath $lockedPath)) 'Locked shortcut fails silently and remains intact'
    } finally { $lock.Dispose() }
    Move-Item -LiteralPath $lockedPath -Destination (Join-Path $fixture 'unlocked fixture.txt')

    # Exercise the actual callback's refusal before the Shell can delete permanently.
    $assembly = [Reflection.Assembly]::LoadFile($exe)
    $sinkType = $assembly.GetType('RecycleSink')
    $ctor = $sinkType.GetConstructors([Reflection.BindingFlags]'Instance,NonPublic')[0]
    $sink = $ctor.Invoke([object[]]@([string](Join-Path $fixture 'keep.txt')))
    $veto = $sink.PreDeleteItem([uint32]0, $null)
    Assert-True ($veto -lt 0) 'Permanent-deletion callback is vetoed'

    Run-Setup 'Install' $true
    Run-Setup 'Install' $true
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $taskName = "DesktopIconCleaner-Test-$sid"
    $task = Get-ScheduledTask -TaskName $taskName
    Assert-True (@($task.Triggers).Count -eq 2) 'Installed task has sign-in and periodic triggers'
    Assert-True ($task.Actions.Execute.EndsWith('DesktopIconCleaner.exe') -and $task.Principal.LogonType -eq 'Interactive') 'Scheduler directly launches the windowless EXE in the correct user session'
    Assert-True (-not $task.Settings.DisallowStartIfOnBatteries -and -not $task.Settings.StopIfGoingOnBatteries -and $task.Settings.StartWhenAvailable) 'Battery and missed-start settings are correct'
    Assert-True (@($task.Triggers | Where-Object { $_.Repetition.Interval -eq 'PT3H' }).Count -eq 1) 'Three-hour repetition is configured'
    $scheduledShortcut = Join-Path $fixture 'scheduled.url'
    Set-Content -LiteralPath $scheduledShortcut -Value "[InternetShortcut]`r`nURL=https://example.invalid/scheduled"
    $installedReport = Join-Path $env:LOCALAPPDATA 'DesktopIconCleaner-Test\Logs\last-run.json'
    if (Test-Path -LiteralPath $installedReport) { Remove-Item -LiteralPath $installedReport }
    Start-ScheduledTask -TaskName $taskName
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 200
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
        $state = (Get-ScheduledTask -TaskName $taskName).State
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Scheduled run timed out.' }
    } until ((Test-Path -LiteralPath $installedReport) -and $state -ne 'Running' -and $taskInfo.LastTaskResult -ne 267009)
    $scheduled = Get-Content -LiteralPath $installedReport -Raw | ConvertFrom-Json
    Assert-True ($taskInfo.LastTaskResult -eq 0 -and $scheduled.Recycled -eq 1 -and $scheduled.Failed -eq 0) 'Live Task Scheduler execution recycles only its fixture and exits successfully'
    Assert-Recycled $scheduled.Items[0]
    Copy-Item -LiteralPath $installedReport -Destination (Join-Path $testBase 'scheduled-run.json')
    Run-Setup 'Uninstall'
    Run-Setup 'Uninstall'
    Assert-True (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) 'Uninstaller removes the scheduled task and is safe to repeat'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'DesktopIconCleaner-Test\DesktopIconCleaner.exe'))) 'Uninstaller removes the installed executable'
    @{Passed=$checks.Count; FinishedUtc=[DateTime]::UtcNow.ToString('o'); Checks=@($checks.ToArray()); Fixture=$fixture} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $testBase 'summary.json') -Encoding UTF8
    Write-Output "All $($checks.Count) checks passed. Evidence: $testBase"
}
finally {
    # A failed test must not leave a repeating test task behind.
    Run-Setup 'Uninstall'
}
