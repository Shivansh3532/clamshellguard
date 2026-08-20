param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('AllUsers','CurrentUser')]
    [string]$Scope
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw 'Install.ps1 must be run as Administrator. Run Install.bat instead.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot 'src'
$configSource = Join-Path $repoRoot 'config.json'

if ($Scope -eq 'AllUsers') {
    $installDir = Join-Path $env:ProgramData 'ClamshellGuard'
    $taskName = 'ClamshellGuard'
}
else {
    $installDir = Join-Path $env:LOCALAPPDATA 'ClamshellGuard'
    $taskName = 'ClamshellGuard-CurrentUser'
}

Write-Host "Install scope : $Scope"
Write-Host "Install path  : $installDir"
Write-Host "Task name     : $taskName"

$existingTaskNames = @('ClamshellGuard','ClamshellGuard-CurrentUser')
foreach ($name in $existingTaskNames) {
    try {
        Get-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch { }
}

foreach ($existingRoot in @((Join-Path $env:ProgramData 'ClamshellGuard'), (Join-Path $env:LOCALAPPDATA 'ClamshellGuard'))) {
    if (Test-Path -LiteralPath (Join-Path $existingRoot 'src\Restore.ps1')) {
        try {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $existingRoot 'src\Restore.ps1') -Root $existingRoot | Out-Host
        }
        catch {
            Write-Warning "Could not restore a previous install at $existingRoot: $($_.Exception.Message)"
        }
    }
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installDir 'src') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installDir 'data') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installDir 'logs') -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceDir 'Core.ps1') -Destination (Join-Path $installDir 'src\Core.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'Agent.ps1') -Destination (Join-Path $installDir 'src\Agent.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'Restore.ps1') -Destination (Join-Path $installDir 'src\Restore.ps1') -Force
Copy-Item -LiteralPath $configSource -Destination (Join-Path $installDir 'config.json') -Force

[ordered]@{
    Version = '1.0.0'
    Scope = $Scope
    TaskName = $taskName
    InstalledUtc = [DateTime]::UtcNow.ToString('o')
    InstalledBy = [Security.Principal.WindowsIdentity]::GetCurrent().Name
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installDir 'install.json') -Encoding UTF8

if ($Scope -eq 'AllUsers') {
    & icacls.exe $installDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
    & icacls.exe (Join-Path $installDir 'data') /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
    & icacls.exe (Join-Path $installDir 'logs') /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
}

$agent = Join-Path $installDir 'src\Agent.ps1'
$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agent`" -Root `"$installDir`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments

if ($Scope -eq 'AllUsers') {
    $triggers = @((New-ScheduledTaskTrigger -AtStartup),(New-ScheduledTaskTrigger -AtLogOn))
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
}
else {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $triggers = @((New-ScheduledTaskTrigger -AtLogOn -User $currentUser))
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
}

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'Keeps lid-close sleep disabled only while an external display is active.'
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2

$registered = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
if ($registered.State -notin @('Running','Ready')) {
    throw "Scheduled task entered unexpected state: $($registered.State)"
}

Write-Host ''
Write-Host 'ClamshellGuard is installed.' -ForegroundColor Green
Write-Host 'External display active -> closing the lid does nothing.'
Write-Host 'No external display -> your original lid-close behavior is restored.'
Write-Host "Task state: $($registered.State)"
exit 0
