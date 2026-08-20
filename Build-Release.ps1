param([string]$Version = '1.1.0')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$outDir = Join-Path $root 'dist'
$stage = Join-Path $outDir 'ClamshellGuard'
$zip = Join-Path $outDir ("ClamshellGuard-{0}.zip" -f $Version)

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stage -Force | Out-Null

foreach ($file in @('Install.bat','Uninstall.bat','Status.bat','config.json','README.md','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage -Force
}
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts') -Destination $stage -Recurse -Force

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host $zip
