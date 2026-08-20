Set-StrictMode -Version 2.0

if (-not ("ClamshellGuard.NativePower" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ClamshellGuard
{
    public static class NativePower
    {
        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);

        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerReadACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, out UInt32 AcValueIndex);

        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerReadDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, out UInt32 DcValueIndex);

        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerWriteACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, UInt32 AcValueIndex);

        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerWriteDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, UInt32 DcValueIndex);

        [DllImport("powrprof.dll")]
        public static extern UInt32 PowerSetActiveScheme(IntPtr UserRootPowerKey, ref Guid SchemeGuid);

        [DllImport("powrprof.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.U1)]
        public static extern bool SetSuspendState([MarshalAs(UnmanagedType.U1)] bool Hibernate, [MarshalAs(UnmanagedType.U1)] bool ForceCritical, [MarshalAs(UnmanagedType.U1)] bool DisableWakeEvent);

        [DllImport("kernel32.dll")]
        public static extern IntPtr LocalFree(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);

        [StructLayout(LayoutKind.Sequential)]
        public struct SYSTEM_POWER_STATUS
        {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public UInt32 BatteryLifeTime;
            public UInt32 BatteryFullLifeTime;
        }
    }
}
'@
}

$script:SubButtonsGuid = [Guid]'4f971e89-eebd-4455-a8de-9e59040e7347'
$script:LidActionGuid = [Guid]'5ca83367-6e45-459f-a27b-476b1d01c936'

function Get-CGActiveSchemeGuid {
    $ptr = [IntPtr]::Zero
    $rc = [ClamshellGuard.NativePower]::PowerGetActiveScheme([IntPtr]::Zero, [ref]$ptr)
    if ($rc -ne 0 -or $ptr -eq [IntPtr]::Zero) {
        throw "PowerGetActiveScheme failed with code $rc."
    }

    try {
        return [Guid][Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][Guid])
    }
    finally {
        [void][ClamshellGuard.NativePower]::LocalFree($ptr)
    }
}

function Get-CGLidValues {
    param([Parameter(Mandatory = $true)][Guid]$SchemeGuid)

    [uint32]$ac = 0
    [uint32]$dc = 0
    $scheme = $SchemeGuid
    $sub = $script:SubButtonsGuid
    $setting = $script:LidActionGuid

    $rcAc = [ClamshellGuard.NativePower]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$setting, [ref]$ac)
    $rcDc = [ClamshellGuard.NativePower]::PowerReadDCValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$setting, [ref]$dc)
    if ($rcAc -ne 0 -or $rcDc -ne 0) {
        throw "Unable to read lid-close settings. AC=$rcAc DC=$rcDc"
    }

    [pscustomobject]@{
        AC = [int]$ac
        DC = [int]$dc
    }
}

function Set-CGLidValues {
    param(
        [Parameter(Mandatory = $true)][Guid]$SchemeGuid,
        [Parameter(Mandatory = $true)][uint32]$AC,
        [Parameter(Mandatory = $true)][uint32]$DC
    )

    $scheme = $SchemeGuid
    $sub = $script:SubButtonsGuid
    $setting = $script:LidActionGuid

    $rcAc = [ClamshellGuard.NativePower]::PowerWriteACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$setting, $AC)
    $rcDc = [ClamshellGuard.NativePower]::PowerWriteDCValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$setting, $DC)
    if ($rcAc -ne 0 -or $rcDc -ne 0) {
        throw "Unable to write lid-close settings. AC=$rcAc DC=$rcDc"
    }

    $rcApply = [ClamshellGuard.NativePower]::PowerSetActiveScheme([IntPtr]::Zero, [ref]$scheme)
    if ($rcApply -ne 0) {
        throw "PowerSetActiveScheme failed with code $rcApply."
    }
}

function Get-CGPowerSource {
    $sps = New-Object 'ClamshellGuard.NativePower+SYSTEM_POWER_STATUS'
    if (-not [ClamshellGuard.NativePower]::GetSystemPowerStatus([ref]$sps)) {
        return 'Unknown'
    }
    if ($sps.ACLineStatus -eq 1) { return 'AC' }
    if ($sps.ACLineStatus -eq 0) { return 'DC' }
    return 'Unknown'
}

function Get-CGDisplayState {
    param([bool]$IncludeWirelessDisplays = $true)

    $internalTech = @(6, 11, 13, 2147483648)
    $wirelessTech = 15
    $items = @()

    try {
        $raw = @(Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorConnectionParams' -ErrorAction Stop)
        foreach ($monitor in $raw) {
            $tech = [uint64]$monitor.VideoOutputTechnology
            $active = [bool]$monitor.Active
            $isInternal = $internalTech -contains $tech
            $isWireless = $tech -eq $wirelessTech
            $isExternal = $active -and -not $isInternal -and ($IncludeWirelessDisplays -or -not $isWireless)

            $items += [pscustomobject]@{
                InstanceName = [string]$monitor.InstanceName
                Active = $active
                Technology = $tech
                TechnologyName = Get-CGTechnologyName -Technology $tech
                IsInternal = $isInternal
                IsExternal = $isExternal
            }
        }
    }
    catch {
        return [pscustomobject]@{
            QuerySucceeded = $false
            Error = $_.Exception.Message
            ActiveCount = 0
            ExternalCount = 0
            InternalCount = 0
            Monitors = @()
        }
    }

    $activeItems = @($items | Where-Object { $_.Active })
    [pscustomobject]@{
        QuerySucceeded = $true
        Error = $null
        ActiveCount = $activeItems.Count
        ExternalCount = @($activeItems | Where-Object { $_.IsExternal }).Count
        InternalCount = @($activeItems | Where-Object { $_.IsInternal }).Count
        Monitors = $items
    }
}

function Get-CGTechnologyName {
    param([uint64]$Technology)
    switch ($Technology) {
        0 { 'VGA' }
        1 { 'S-Video' }
        2 { 'Composite' }
        3 { 'Component' }
        4 { 'DVI' }
        5 { 'HDMI' }
        6 { 'LVDS/MIPI (internal)' }
        8 { 'D-JPN' }
        9 { 'SDI' }
        10 { 'DisplayPort' }
        11 { 'Embedded DisplayPort' }
        12 { 'UDI external' }
        13 { 'UDI embedded' }
        14 { 'SDTV dongle' }
        15 { 'Miracast' }
        16 { 'Indirect wired / USB display' }
        2147483648 { 'Internal' }
        4294967294 { 'Uninitialized' }
        4294967295 { 'Other' }
        default { "Technology $Technology" }
    }
}

function Get-CGPlanStatePath {
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Parameter(Mandatory = $true)][Guid]$SchemeGuid
    )
    Join-Path $DataDir ("plan-{0}.json" -f $SchemeGuid.ToString('D'))
}

function Get-CGPlanState {
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Parameter(Mandatory = $true)][Guid]$SchemeGuid
    )

    $path = Get-CGPlanStatePath -DataDir $DataDir -SchemeGuid $SchemeGuid
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Save-CGPlanState {
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Parameter(Mandatory = $true)][Guid]$SchemeGuid,
        [Parameter(Mandatory = $true)][int]$OriginalAC,
        [Parameter(Mandatory = $true)][int]$OriginalDC,
        [Parameter(Mandatory = $true)][bool]$Managed
    )

    if (-not (Test-Path -LiteralPath $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }
    $path = Get-CGPlanStatePath -DataDir $DataDir -SchemeGuid $SchemeGuid
    $temp = "$path.tmp"
    [ordered]@{
        SchemeGuid = $SchemeGuid.ToString('D')
        OriginalAC = $OriginalAC
        OriginalDC = $OriginalDC
        Managed = $Managed
        UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
}

function Enable-CGPlanGuard {
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Parameter(Mandatory = $true)][Guid]$SchemeGuid
    )

    $state = Get-CGPlanState -DataDir $DataDir -SchemeGuid $SchemeGuid
    if ($null -eq $state -or -not [bool]$state.Managed) {
        $current = Get-CGLidValues -SchemeGuid $SchemeGuid
        Save-CGPlanState -DataDir $DataDir -SchemeGuid $SchemeGuid -OriginalAC $current.AC -OriginalDC $current.DC -Managed $true
    }

    $now = Get-CGLidValues -SchemeGuid $SchemeGuid
    if ($now.AC -ne 0 -or $now.DC -ne 0) {
        Set-CGLidValues -SchemeGuid $SchemeGuid -AC 0 -DC 0
    }
}

function Restore-CGPlan {
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Parameter(Mandatory = $true)][Guid]$SchemeGuid
    )

    $state = Get-CGPlanState -DataDir $DataDir -SchemeGuid $SchemeGuid
    if ($null -eq $state -or -not [bool]$state.Managed) { return $null }

    Set-CGLidValues -SchemeGuid $SchemeGuid -AC ([uint32]$state.OriginalAC) -DC ([uint32]$state.OriginalDC)
    Save-CGPlanState -DataDir $DataDir -SchemeGuid $SchemeGuid -OriginalAC ([int]$state.OriginalAC) -OriginalDC ([int]$state.OriginalDC) -Managed $false
    return $state
}

function Restore-CGManagedPlans {
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Nullable[Guid]]$ExceptScheme
    )

    if (-not (Test-Path -LiteralPath $DataDir)) { return @() }
    $restored = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $DataDir -Filter 'plan-*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if (-not [bool]$state.Managed) { continue }
            $guid = [Guid]$state.SchemeGuid
            if ($null -ne $ExceptScheme -and $ExceptScheme.HasValue -and $guid -eq $ExceptScheme.Value) { continue }
            $result = Restore-CGPlan -DataDir $DataDir -SchemeGuid $guid
            if ($null -ne $result) { $restored += $result }
        }
        catch {
        }
    }
    return $restored
}

function Invoke-CGOriginalClosedAction {
    param(
        [Parameter(Mandatory = $true)]$PlanState,
        [string]$PowerSource = 'Unknown'
    )

    if ($null -eq $PlanState) { return 'None' }
    $action = if ($PowerSource -eq 'DC') { [int]$PlanState.OriginalDC } else { [int]$PlanState.OriginalAC }

    switch ($action) {
        1 {
            [void][ClamshellGuard.NativePower]::SetSuspendState($false, $false, $false)
            return 'Sleep'
        }
        2 {
            [void][ClamshellGuard.NativePower]::SetSuspendState($true, $false, $false)
            return 'Hibernate'
        }
        default {
            return 'None'
        }
    }
}
