param(
    [Parameter(Mandatory = $true)][string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Core.ps1')

$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$DataDir = Join-Path (Join-Path $Root 'data') $userSid
$LogDir = Join-Path (Join-Path $Root 'logs') $userSid
$ConfigPath = Join-Path $Root 'config.json'
$StatusPath = Join-Path $DataDir 'status.json'
$StopPath = Join-Path $Root 'stop.request'
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$config = [pscustomobject]@{
    PollMilliseconds = 1000
    DisconnectDebounceMilliseconds = 4500
    AutoSuspendWhenNoDisplays = $false
    IncludeWirelessDisplays = $true
    LogMaxBytes = 1048576
}
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($name in @('PollMilliseconds','DisconnectDebounceMilliseconds','AutoSuspendWhenNoDisplays','IncludeWirelessDisplays','LogMaxBytes')) {
            if ($null -ne $loaded.$name) { $config.$name = $loaded.$name }
        }
    }
    catch { }
}

$logPath = Join-Path $LogDir 'clamshellguard.log'
function Write-CGLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt [int64]$config.LogMaxBytes) {
            $old = "$logPath.old"
            Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $logPath -Destination $old -Force
        }
        "{0} [{1}] {2}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message | Add-Content -LiteralPath $logPath -Encoding UTF8
    }
    catch { }
}

$createdNew = $false
$mutexName = 'Local\ClamshellGuard-Agent-' + ($userSid -replace '[^A-Za-z0-9-]','_')
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    exit 0
}

$guardActive = $false
$managedScheme = $null
$disconnectSince = $null
$lastExternalCount = -1
$lastDisplayError = $null

function Write-CGStatus {
    param($Display, $Scheme, [string]$Mode, [string]$Message = '')
    try {
        $lid = $null
        try { if ($null -ne $Scheme) { $lid = Get-CGLidValues -SchemeGuid $Scheme } } catch { }
        $temp = "$StatusPath.tmp"
        [ordered]@{
            Version = '1.1.0'
            TimestampUtc = [DateTime]::UtcNow.ToString('o')
            User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            UserSid = $userSid
            Mode = $Mode
            Message = $Message
            ActiveScheme = if ($null -ne $Scheme) { $Scheme.ToString('D') } else { $null }
            LidAC = if ($null -ne $lid) { $lid.AC } else { $null }
            LidDC = if ($null -ne $lid) { $lid.DC } else { $null }
            DisplayQuerySucceeded = $Display.QuerySucceeded
            ActiveDisplays = $Display.ActiveCount
            ExternalDisplays = $Display.ExternalCount
            InternalDisplays = $Display.InternalCount
            PowerSource = Get-CGPowerSource
            Monitors = $Display.Monitors
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temp -Encoding UTF8
        Move-Item -LiteralPath $temp -Destination $StatusPath -Force
    }
    catch { }
}

Write-CGLog ("Agent starting as {0} ({1})." -f [Security.Principal.WindowsIdentity]::GetCurrent().Name, $userSid)

try {
    while ($true) {
        if (Test-Path -LiteralPath $StopPath) {
            Write-CGLog 'Stop request detected.'
            break
        }

        try {
            $display = Get-CGDisplayState -IncludeWirelessDisplays ([bool]$config.IncludeWirelessDisplays)
            if (-not $display.QuerySucceeded) {
                if ($display.Error -ne $lastDisplayError) {
                    Write-CGLog ("Display query failed: {0}" -f $display.Error) 'WARN'
                    $lastDisplayError = $display.Error
                }
                Start-Sleep -Milliseconds ([Math]::Max(500, [int]$config.PollMilliseconds))
                continue
            }
            $lastDisplayError = $null

            $scheme = Get-CGActiveSchemeGuid
            $hasExternal = $display.ExternalCount -gt 0

            if ($display.ExternalCount -ne $lastExternalCount) {
                Write-CGLog ("Display topology: active={0}, external={1}, internal={2}." -f $display.ActiveCount, $display.ExternalCount, $display.InternalCount)
                $lastExternalCount = $display.ExternalCount
            }

            if ($hasExternal) {
                $disconnectSince = $null

                if ($null -ne $managedScheme -and $managedScheme -ne $scheme) {
                    try {
                        [void](Restore-CGPlan -DataDir $DataDir -SchemeGuid $managedScheme)
                        Write-CGLog ("Restored previous power plan {0} after active-plan change." -f $managedScheme)
                    }
                    catch {
                        Write-CGLog ("Could not restore previous power plan {0}: {1}" -f $managedScheme, $_.Exception.Message) 'WARN'
                    }
                }

                [void](Restore-CGManagedPlans -DataDir $DataDir -ExceptScheme $scheme)
                Enable-CGPlanGuard -DataDir $DataDir -SchemeGuid $scheme

                $verified = Get-CGLidValues -SchemeGuid $scheme
                if ($verified.AC -ne 0 -or $verified.DC -ne 0) {
                    throw "Lid policy verification failed after write. AC=$($verified.AC) DC=$($verified.DC)"
                }

                $managedScheme = $scheme
                if (-not $guardActive) {
                    Write-CGLog ("Clamshell mode enabled and verified on plan {0}." -f $scheme)
                }
                $guardActive = $true
                Write-CGStatus -Display $display -Scheme $scheme -Mode 'CLAMSHELL' -Message 'External display active; lid-close policy is verified as Do nothing.'
            }
            else {
                if ($guardActive) {
                    if ($null -eq $disconnectSince) {
                        $disconnectSince = Get-Date
                        Write-CGLog 'Last external display disappeared; starting disconnect debounce.'
                    }

                    $elapsed = ((Get-Date) - $disconnectSince).TotalMilliseconds
                    if ($elapsed -ge [int]$config.DisconnectDebounceMilliseconds) {
                        if ($null -ne $managedScheme) {
                            try {
                                [void](Restore-CGPlan -DataDir $DataDir -SchemeGuid $managedScheme)
                                Write-CGLog ("Restored lid settings for plan {0}." -f $managedScheme)
                            }
                            catch {
                                Write-CGLog ("Restore failed for plan {0}: {1}" -f $managedScheme, $_.Exception.Message) 'ERROR'
                            }
                        }
                        [void](Restore-CGManagedPlans -DataDir $DataDir)
                        $guardActive = $false
                        $managedScheme = $null
                        $disconnectSince = $null
                    }
                }
                else {
                    [void](Restore-CGManagedPlans -DataDir $DataDir)
                }

                Write-CGStatus -Display $display -Scheme $scheme -Mode 'NORMAL' -Message 'No external display active; original lid-close policy is in effect.'
            }
        }
        catch {
            Write-CGLog $_.Exception.ToString() 'ERROR'
            try {
                $schemeForError = Get-CGActiveSchemeGuid
                $failedDisplay = [pscustomobject]@{ QuerySucceeded=$false; Error=$_.Exception.Message; ActiveCount=0; ExternalCount=0; InternalCount=0; Monitors=@() }
                Write-CGStatus -Display $failedDisplay -Scheme $schemeForError -Mode 'ERROR' -Message $_.Exception.Message
            }
            catch { }
        }

        Start-Sleep -Milliseconds ([Math]::Max(500, [int]$config.PollMilliseconds))
    }
}
finally {
    try {
        [void](Restore-CGManagedPlans -DataDir $DataDir)
        Write-CGLog 'Restored managed power plans before exit.'
    }
    catch {
        Write-CGLog ("Final restore failed: {0}" -f $_.Exception.Message) 'ERROR'
    }
    Write-CGLog 'Agent exiting.'
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
