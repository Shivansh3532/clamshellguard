# ClamshellGuard

ClamshellGuard keeps a Windows laptop awake when the lid is closed **only while an external display is active**. When the last external display disappears, it restores the power plan's original lid-close behavior.

## Install

1. Download or clone this repository, or download the release ZIP.
2. Extract the ZIP.
3. Right-click **`Install.bat`** and choose **Run as administrator**.
4. Choose whether to install for **all users** or only the **current user**.
5. Done. No tray app has to remain open.

**All users** is recommended. It installs a SYSTEM scheduled task that starts at boot and survives logouts. **Current user** starts at that user's logon.

## What it detects

ClamshellGuard uses Windows' `WmiMonitorConnectionParams` data rather than searching for a literal HDMI device. That allows it to work with active displays connected through HDMI, DisplayPort, USB-C/DisplayPort Alt Mode, Thunderbolt docks, DVI/VGA, DisplayLink/indirect wired adapters, and optionally Miracast.

Internal LVDS/eDP/embedded display connections are excluded from the external-display count.

## Behavior

| State | Lid-close policy |
| --- | --- |
| At least one active external display | Temporarily **Do nothing** on AC and battery |
| No active external display | Restore the power plan's original AC/DC values |
| Active power plan changes while guarded | Restore the old plan, save the new plan, then guard the new plan |
| Brief monitor handshake/dropout | Debounced before restoring |
| Last display disappears and Windows reports zero active displays | Restore policy; if the original action was Sleep/Hibernate, request that action |
| Reboot/crash with a managed plan left behind | State files allow the next run or uninstaller to restore it |

ClamshellGuard does **not** block Sleep chosen from the Start menu or a power button. It changes only the Windows lid-close action while an external monitor is active.

## Status

Run **`Status.bat`** to see the scheduled task state, current mode, monitor counts, power source, and current lid action values.

Lid action values used by Windows are normally:

- `0` — Do nothing
- `1` — Sleep
- `2` — Hibernate
- `3` — Shut down

ClamshellGuard preserves the actual original value instead of assuming Sleep.

## Uninstall

Right-click **`Uninstall.bat`** and choose **Run as administrator**. The uninstaller stops the agent, restores every power plan ClamshellGuard marked as managed, removes the scheduled task, and removes the installed files.

## Configuration

`config.json` contains:

- `PollMilliseconds` — monitor topology check interval.
- `DisconnectDebounceMilliseconds` — protects against HDMI/DP handshake flicker.
- `AutoSuspendWhenNoDisplays` — if the last display disappears and no display returns after recheck, mimic an original Sleep/Hibernate lid action.
- `IncludeWirelessDisplays` — count Miracast as an external display.
- `LogMaxBytes` — log rotation threshold.

Edit configuration in the installed directory, not only in the extracted ZIP.

Default install locations:

- All users: `%ProgramData%\ClamshellGuard`
- Current user: `%LOCALAPPDATA%\ClamshellGuard`

## Reliability and safety

- Original AC and battery lid actions are recorded **per power-plan GUID** before ClamshellGuard changes them.
- Writes use Windows `powrprof.dll` APIs instead of parsing localized `powercfg` output.
- A global mutex prevents duplicate agents.
- The scheduled task is configured to restart after unexpected exits.
- All-users files executed as SYSTEM are ACL-hardened so normal users cannot replace the agent script.
- Disconnect handling is debounced to avoid reacting to short HDMI/DisplayPort renegotiations.
- Automatic last-display handling only requests Sleep or Hibernate. It deliberately does not automatically shut down the PC from a zero-display heuristic.

## Limitations

Some laptop firmware, OEM power utilities, enterprise Group Policy, or Modern Standby implementations can override Windows lid policy. No user-mode utility can guarantee control over firmware that ignores the Windows power setting. ClamshellGuard fails conservatively: monitor-query failures do not cause it to newly change the lid policy.

## Build a ZIP

On Windows PowerShell:

```powershell
.\Build-Release.ps1
```

The package is written to `dist\ClamshellGuard-1.0.0.zip`.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Administrator rights for installation

## License

MIT
