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
$taskNames = @('ClamshellGuard','ClamshellGuard-CurrentUser')

foreach ($taskName in $taskNames) {
    try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch { }
}
Start-Sleep -Milliseconds 600

foreach ($root in $roots) {
    $restore = Join-Path $root 'src\Restore.ps1'
    if (Test-Path -LiteralPath $restore) {
        try { & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $restore -Root $root | Out-Host }
        catch { Write-Warning "Restore failed at ${root}: $($_.Exception.Message)" }
    }
}

foreach ($taskName in $taskNames) {
    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
}

foreach ($root in $roots) {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host 'ClamshellGuard uninstalled.' -ForegroundColor Green
exit 0
