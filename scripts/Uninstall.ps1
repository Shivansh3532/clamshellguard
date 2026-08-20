Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw 'Uninstall.ps1 must be run as Administrator. Run Uninstall.bat instead.'
}

$roots = @((Join-Path $env:ProgramData 'ClamshellGuard'),(Join-Path $env:LOCALAPPDATA 'ClamshellGuard'))

foreach ($key in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    try { Remove-ItemProperty -Path $key -Name 'ClamshellGuard' -ErrorAction SilentlyContinue } catch { }
}

foreach ($taskName in @('ClamshellGuard','ClamshellGuard-CurrentUser')) {
    try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch { }
    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
}

foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    try { New-Item -ItemType File -Path (Join-Path $root 'stop.request') -Force | Out-Null } catch { }
}

Start-Sleep -Seconds 3

foreach ($root in $roots) {
    $restore = Join-Path $root 'src\Restore.ps1'
    if (Test-Path -LiteralPath $restore) {
        try { & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $restore -Root $root | Out-Host }
        catch { Write-Warning "Restore failed at ${root}: $($_.Exception.Message)" }
    }
}

try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -match 'ClamshellGuard' -and $_.CommandLine -match 'Agent\.ps1'
    } | ForEach-Object {
        try { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null } catch { }
    }
}
catch { }

foreach ($root in $roots) {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host 'ClamshellGuard uninstalled and current-user lid settings restored.' -ForegroundColor Green
exit 0
