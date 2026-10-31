[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Install','Uninstall')][string]$Action,
    [switch]$NoStart,
    [switch]$TestMode,
    [string]$TestRoot
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$suffix = if ($TestMode) { '-Test' } else { '' }
$installRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "DesktopIconCleaner$suffix"))
$taskName = "DesktopIconCleaner$suffix-$($identity.User.Value)"
$marker = 'ManagedBy:jbw-DesktopIconCleaner/v1'
$ownedFiles = @('DesktopIconCleaner.exe', 'Setup.ps1', 'Uninstall.cmd', 'installation.json')

try {
    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($existing -and -not $existing.Description.StartsWith($marker)) {
        throw "Refusing to alter an unrelated task named $taskName."
    }
    if ($TestRoot -and -not $TestMode) { throw 'TestRoot requires TestMode.' }
    if ($existing) {
        # Stop new launches, then allow an in-progress recycle operation to finish.
        Disable-ScheduledTask -TaskName $taskName | Out-Null
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running') {
            if ([DateTime]::UtcNow -gt $deadline) {
                Enable-ScheduledTask -TaskName $taskName | Out-Null
                throw 'Cleaner is still running. Try again after it finishes.'
            }
            Start-Sleep -Milliseconds 200
        }
    }
    if ($Action -eq 'Uninstall') {
        if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
        # Delete only known application files, never recurse through user data.
        foreach ($name in $ownedFiles) {
            $file = [IO.Path]::GetFullPath((Join-Path $installRoot $name))
            if ([IO.Path]::GetDirectoryName($file) -ne $installRoot) { throw 'Unsafe uninstall path.' }
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        Write-Output "Uninstalled. No further cleanups will run. Logs retained at $installRoot\Logs. Recycle Bin items are untouched."
        exit 0
    }

    if ($TestMode -and (-not $TestRoot -or -not (Test-Path -LiteralPath $TestRoot -PathType Container))) {
        throw 'Test installation requires an existing TestRoot directory.'
    }
    $sourceExe = Join-Path $PSScriptRoot 'DesktopIconCleaner.exe'
    if (-not (Test-Path -LiteralPath $sourceExe)) { & (Join-Path $PSScriptRoot 'Build.ps1') }
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    foreach ($name in @('DesktopIconCleaner.exe','Setup.ps1','Uninstall.cmd')) {
        $source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $name))
        $destination = Join-Path $installRoot $name
        if ($source -ne $destination) { Copy-Item -LiteralPath $source -Destination $destination -Force }
    }
    $arguments = '--run'
    if ($TestMode) {
        $arguments += ' --test-root "' + [IO.Path]::GetFullPath($TestRoot) + '" --report "' + (Join-Path $installRoot 'Logs\last-run.json') + '"'
    }
    $taskAction = New-ScheduledTaskAction -Execute (Join-Path $installRoot 'DesktopIconCleaner.exe') -Argument $arguments -WorkingDirectory $installRoot
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $logon.Delay = 'PT30S'
    $repeat = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddHours(3)) -RepetitionInterval (New-TimeSpan -Hours 3)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $task = New-ScheduledTask -Action $taskAction -Trigger @($logon,$repeat) -Settings $settings -Principal $principal -Description "$marker; recycle top-level desktop .lnk/.url shortcuts and empty New Folder directories. No UI."
    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
    @{TaskName=$taskName; InstalledUtc=[DateTime]::UtcNow.ToString('o'); TestMode=[bool]$TestMode} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installRoot 'installation.json') -Encoding UTF8
    if (-not $NoStart) { Start-ScheduledTask -TaskName $taskName }
    Write-Output "Installed: $taskName"
    Write-Output 'Runs silently at sign-in (30-second delay) and every 3 hours while signed in, on battery or AC.'
    Write-Output "Status: $installRoot\Logs\last-run.json"
    Write-Output 'No administrator prompt is requested. Protected items that require elevation are left in place and logged.'
}
catch {
    # Restore the previous task's ability to run if an update failed.
    if ($existing -and $Action -eq 'Install') {
        Enable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Error $_ -ErrorAction Continue
    exit 1
}
