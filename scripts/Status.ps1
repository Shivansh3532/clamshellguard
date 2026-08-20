Set-StrictMode -Version 2.0
$ErrorActionPreference = 'SilentlyContinue'

$roots = @((Join-Path $env:ProgramData 'ClamshellGuard'),(Join-Path $env:LOCALAPPDATA 'ClamshellGuard'))
$root = $roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($null -eq $root) {
    Write-Host 'ClamshellGuard is not installed.'
    exit 1
}

$install = Get-Content -LiteralPath (Join-Path $root 'install.json') -Raw | ConvertFrom-Json
$statusPath = Join-Path $root 'data\status.json'
$status = if (Test-Path -LiteralPath $statusPath) { Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json } else { $null }
$task = Get-ScheduledTask -TaskName $install.TaskName

Write-Host 'ClamshellGuard 1.0.0'
Write-Host '-------------------'
Write-Host ("Scope             : {0}" -f $install.Scope)
Write-Host ("Task              : {0}" -f $install.TaskName)
Write-Host ("Task state        : {0}" -f $task.State)
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
}
else {
    Write-Host 'Agent status has not been written yet.'
}
