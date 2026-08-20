param(
    [Parameter(Mandatory = $true)][string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$dataDir = Join-Path (Join-Path $Root 'data') $sid
$restored = @(Restore-CGManagedPlans -DataDir $dataDir)
Write-Output ("Restored {0} managed power plan(s) for {1}." -f $restored.Count, $sid)
