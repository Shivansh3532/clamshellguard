param(
    [Parameter(Mandatory = $true)][string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')

$dataDir = Join-Path $Root 'data'
$restored = @(Restore-CGManagedPlans -DataDir $dataDir)
Write-Output ("Restored {0} managed power plan(s)." -f $restored.Count)
