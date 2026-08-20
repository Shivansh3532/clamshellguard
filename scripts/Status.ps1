Set-StrictMode -Version 2.0
$ErrorActionPreference = 'SilentlyContinue'

$roots = @((Join-Path $env:ProgramData 'ClamshellGuard'),(Join-Path $env:LOCALAPPDATA 'ClamshellGuard'))
$root = $roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($null -eq $root) {
    Write-Host 'ClamshellGuard is not installed.'
    exit 1
}

$install = Get-Content -LiteralPath (Join-Path $root 'install.json') -Raw | ConvertFrom-Json
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$userData = Join-Path (Join-Path $root 'data') $sid
$statusPath = Join-Path $userData 'status.json'
$status = if (Test-Path -LiteralPath $statusPath) { Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json } else { $null }

$runMachine = (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ClamshellGuard' -ErrorAction SilentlyContinue).ClamshellGuard
$runUser = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ClamshellGuard' -ErrorAction SilentlyContinue).ClamshellGuard
$startup = if ($runMachine) { 'All users (HKLM Run)' } elseif ($runUser) { 'Current user (HKCU Run)' } else { 'NOT REGISTERED' }

Write-Host 'ClamshellGuard'
Write-Host '--------------'
Write-Host ("Version           : {0}" -f $install.Version)
Write-Host ("Scope             : {0}" -f $install.Scope)
Write-Host ("Startup           : {0}" -f $startup)
Write-Host ("Current user      : {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-Host ("Current SID       : {0}" -f $sid)
Write-Host ("Install path      : {0}" -f $root)
if ($null -ne $status) {
    Write-Host ("Mode              : {0}" -f $status.Mode)
    Write-Host ("External displays : {0}" -f $status.ExternalDisplays)
    Write-Host ("Internal displays : {0}" -f $status.InternalDisplays)
    Write-Host ("Active displays   : {0}" -f $status.ActiveDisplays)
    Write-Host ("Power source      : {0}" -f $status.PowerSource)
    Write-Host ("Lid action AC     : {0}" -f $status.LidAC)
    Write-Host ("Lid action DC     : {0}" -f $status.LidDC)
    Write-Host ("Updated UTC       : {0}" -f $status.TimestampUtc)
    Write-Host ''
    Write-Host $status.Message
    if ($status.Monitors) {
        Write-Host ''
        Write-Host 'Detected monitors:'
        foreach ($monitor in $status.Monitors) {
            Write-Host ("  Active={0} External={1} Internal={2} Tech={3} ({4}) Instance={5}" -f $monitor.Active,$monitor.IsExternal,$monitor.IsInternal,$monitor.Technology,$monitor.TechnologyName,$monitor.InstanceName)
        }
    }
}
else {
    Write-Host 'Agent status has not been written for this user yet.' -ForegroundColor Yellow
}

$logPath = Join-Path (Join-Path (Join-Path $root 'logs') $sid) 'clamshellguard.log'
Write-Host ''
Write-Host ("Log path          : {0}" -f $logPath)
if (Test-Path -LiteralPath $logPath) {
    Write-Host 'Last log lines:'
    Get-Content -LiteralPath $logPath -Tail 12 | ForEach-Object { Write-Host "  $_" }
}
