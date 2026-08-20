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
    $runKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
}
else {
    $installDir = Join-Path $env:LOCALAPPDATA 'ClamshellGuard'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
}

Write-Host "Install scope : $Scope"
Write-Host "Install path  : $installDir"

foreach ($name in @('ClamshellGuard','ClamshellGuard-CurrentUser')) {
    try {
        Get-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch { }
}

foreach ($key in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    try { Remove-ItemProperty -Path $key -Name 'ClamshellGuard' -ErrorAction SilentlyContinue } catch { }
}

foreach ($existingRoot in @((Join-Path $env:ProgramData 'ClamshellGuard'), (Join-Path $env:LOCALAPPDATA 'ClamshellGuard'))) {
    if (Test-Path -LiteralPath (Join-Path $existingRoot 'src\Restore.ps1')) {
        try {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $existingRoot 'src\Restore.ps1') -Root $existingRoot | Out-Host
        }
        catch {
            Write-Warning "Could not restore a previous install at ${existingRoot}: $($_.Exception.Message)"
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

$stopFile = Join-Path $installDir 'stop.request'
Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue

[ordered]@{
    Version = '1.1.0'
    Scope = $Scope
    Startup = 'RunKey'
    InstalledUtc = [DateTime]::UtcNow.ToString('o')
    InstalledBy = [Security.Principal.WindowsIdentity]::GetCurrent().Name
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installDir 'install.json') -Encoding UTF8

if ($Scope -eq 'AllUsers') {
    & icacls.exe $installDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /C | Out-Null
    & icacls.exe (Join-Path $installDir 'data') /grant '*S-1-5-32-545:(OI)(CI)M' /T /C | Out-Null
    & icacls.exe (Join-Path $installDir 'logs') /grant '*S-1-5-32-545:(OI)(CI)M' /T /C | Out-Null
}

$agent = Join-Path $installDir 'src\Agent.ps1'
$runCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Root "{1}"' -f $agent, $installDir
New-Item -Path $runKey -Force | Out-Null
Set-ItemProperty -Path $runKey -Name 'ClamshellGuard' -Value $runCommand -Type String

Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$agent,'-Root',$installDir)
Start-Sleep -Seconds 3

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$statusPath = Join-Path (Join-Path $installDir 'data') (Join-Path $sid 'status.json')
if (-not (Test-Path -LiteralPath $statusPath)) {
    Write-Warning 'Agent started but did not write status yet. Run Status.bat for diagnostics.'
}

Write-Host ''
Write-Host 'ClamshellGuard 1.1.0 is installed.' -ForegroundColor Green
Write-Host 'The agent now runs inside each signed-in user session, so it controls that user''s active power scheme.'
Write-Host 'External display active -> lid close is set to Do nothing.'
Write-Host 'No external display -> original lid-close behavior is restored.'
exit 0
