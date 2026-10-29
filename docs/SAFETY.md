# ChargeGuard safety

This file lists every state ChargeGuard can leave a Mac in, how to recognise it, and how to get back to normal. It also lists the safety rules from section 8 of the brief and where the code enforces each one.

**The short version:** a reboot resets every SMC charging key to the macOS default. If anything looks wrong, run `chargectl restore` (or `sudo chargectl restore --direct` if the helper is not running), or reboot.

## Restore tools

| Tool | Needs | What it does |
|---|---|---|
| Menu item "Restore normal charging" | helper running | Turns charge control off, cancels discharge, top up and calibration, then writes the deactivate value to every present charge, discharge and firmware-limit key and resets `ACLC` to `00`. Refused while another charging tool runs. |
| `chargectl restore` | helper running | Same as the menu item, over XPC. |
| `sudo chargectl restore --direct` | root, no helper needed | Opens AppleSMC directly, probes the keys and writes the same deactivate values. Use when the helper is gone or stuck. |
| `chargectl prepare-uninstall` | helper running | Restore, release all assertions and the sleep hold, stop enforcing. Used by `scripts/uninstall.sh`. |
| `sudo pmset -a disablesleep 0` | root | Clears a `SleepDisabled` hold left behind. |
| Reboot | nothing | The SMC resets `CHTE`, `CH0B`, `CH0C`, `CHIE`, `CH0J`, `CH0I` and `ACLC` at boot (as battery.sh documents; Part B confirms it on the M2, see the verification items in `docs/SMC-KEYS.md`). It does **not** reset `pmset` settings (`disablesleep`, `lowpowermode`). |

Deactivate values written by every restore path (`GuardedSMCWriter.restoreAll`), in this order:

1. `CHIE`, `CH0J`, `CH0I` → `00` (adapter reconnected first)
2. `CHTE` → `00000000`
3. `CH0B`, `CH0C` → `00`
4. `bfF0` → `00` (firmware limit off)
5. `ACLC` → `00` (system default)

Only keys the probe found present are written. A key that fails does not stop the others; the failures are reported.

## How to check the current state

```sh
chargectl status            # policy state, backend, last outputs, key values, conflicts
chargectl status --json     # the full DaemonStatus
chargectl probe             # every key: present/absent, size, type, current value
chargectl probe --direct    # the same without the helper (reads only, no sudo)
chargectl read CHTE         # one key (add --direct without the helper)
chargectl writes            # the last SMC writes with reason and battery snapshot
pmset -g                    # look for SleepDisabled and lowpowermode
pmset -g assertions         # assertions held by ChargeGuardHelper
ioreg -rn AppleSmartBattery | grep -E 'ExternalConnected|IsCharging|CurrentCapacity|Temperature'
```

## States and recovery

### 1. Charging blocked

- **Cause:** the limit was reached (or a heat pause, sleep block, discharge, calibration phase B). `CHTE = 01000000`, or `CH0B = 02` and `CH0C = 02`.
- **Symptom:** plugged in, battery below 100 %, not charging. The menu bar shows "Limit reached", "Sailing", "Heat paused" or "Charging paused for sleep".
- **Check:** `chargectl read CHTE` (or `CH0B`, `CH0C`), `ioreg ... IsCharging`.
- **Expected:** this is normal while charge control is on.
- **Recovery:** raise the limit, Top Up, turn charge control off, "Restore normal charging", `chargectl restore`, `sudo chargectl restore --direct`, or reboot.

### 2. Forced discharge

- **Cause:** Discharge, Automatic Discharge, calibration phase B, or the AdapterCutoff backend holding the limit. `CHIE = 08`, `CH0J = 01` or `CH0I = 01`.
- **Symptom:** plugged in, but the Mac runs from the battery and the percentage falls. macOS may show "Power Source: Battery".
- **Check:** `chargectl read CHIE` (or `CH0J`, `CH0I`).
- **Limits:** discharge never goes below 5 % (`PolicyEngine.minimumDischargeFloor`), calibration never below 10 % (`CalibrationMachine.absoluteFloor`). Discharge pauses before sleep and when the lid closes without Discharge in Clamshell Mode.
- **Recovery:** turn Discharge off, "Restore normal charging", `chargectl discharge off`, `chargectl restore`, `sudo chargectl restore --direct`, or reboot. Unplugging and replugging does not clear the key.

### 3. Firmware charge limit active

- **Cause:** the FirmwareLimit backend (only on firmware that has `bfF0`). `bfF0 = 02`, `bfD0` = upper %, `bfE0` = lower %.
- **Symptom:** charging stops at the upper value even while the Mac sleeps or after the helper quits.
- **Check:** `chargectl read bfF0`, `chargectl read bfD0`, `chargectl read bfE0`.
- **Recovery:** set the limit to 100 % (the backend writes `bfF0 = 00`), `chargectl restore`, `sudo chargectl restore --direct`. Whether a reboot resets the firmware limit is unknown; verify on hardware that has these keys before relying on it.

### 4. MagSafe LED overridden

- **Cause:** Control MagSafe LED set to "Show ChargeGuard's state" or "Off while plugged in" (`chargectl led state` / `off`). `ACLC` = `03` green, `04` orange, `01` off.
- **Symptom:** the LED colour does not match what macOS would show.
- **Recovery:** set the LED option back to "System default (not controlled)" (`chargectl led system`; writes `ACLC = 00` once), restore, or reboot. `ACLC = 00` as "system default" is unconfirmed upstream; Part B verifies it (docs/SMC-KEYS.md).

### 5. Power assertions held

- **Cause:** Sleep Control (keep awake), Disable Sleep until Charge Limit, calibration (all phases), Discharge in Clamshell Mode. Types: `PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep`, `PreventSystemSleep`.
- **Symptom:** the Mac does not idle-sleep; the display stays on.
- **Check:** `pmset -g assertions | grep -i chargeguard`.
- **Recovery:** cancel keep-awake (`chargectl keepawake off`), finish or cancel calibration, turn the setting off. Assertions belong to the helper process and disappear when it exits, crashes or is unloaded. Nothing persists across a reboot.

### 6. `pmset disablesleep 1` held (clamshell force-awake)

- **Cause:** the option "Force the Mac awake during clamshell discharge" (Settings > Charging, under Discharge in Clamshell Mode) while discharging in clamshell mode with an external display. Off by default.
- **Symptom:** the Mac never sleeps, even with the lid closed and no display.
- **Check:** `pmset -g | grep SleepDisabled`; `sleepDisabledSnapshot` in `/Library/Application Support/ChargeGuard/state.json` holds the value from before the hold.
- **Automatic recovery:** the helper restores the snapshot when discharge ends, on SIGTERM, on start after a crash (a snapshot left in state.json is applied and cleared) and in `chargectl prepare-uninstall`. `scripts/uninstall.sh` also restores it from state.json.
- **Manual recovery:** `sudo pmset -a disablesleep 0`. A reboot does **not** clear this setting.

### 7. Low Power Mode changed by policy

- **Cause:** Low Power Mode control set to Always On/Off, Only on Battery or Only on Adapter. The helper runs `pmset -a lowpowermode 0|1` on power-source changes.
- **Symptom:** Low Power Mode turns on or off by itself.
- **Recovery:** set the policy to "Not managed" and change Low Power Mode in System Settings > Battery, or `sudo pmset -a lowpowermode 0`. ChargeGuard never reverts this setting on quit or uninstall: it is a user preference that macOS keeps across reboots.

### 8. Helper crashed

- **Symptom:** the menu bar shows "Helper missing"; the keys keep their last values (charging may stay blocked or the Mac may keep discharging).
- **What happens:** launchd restarts the helper (`KeepAlive = true`). On start it loads state.json, sees `keysDirty`, and either keeps enforcing (default "Keep the limit enforced by the helper") or restores (when "Restore normal charging when ChargeGuard quits" is selected or charge control is off). Power assertions were released when the process died.
- **Recovery if it keeps crashing:** `sudo chargectl restore --direct`, then `sudo launchctl bootout system/com.amir.chargeguard.helper` and check crash logs in `~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports`.

### 9. Helper removed while keys were modified

- **Cause:** the app was deleted, or the daemon was unloaded without SIGTERM (for example `kill -9`).
- **Symptom:** charging stays blocked, or forced discharge continues, with no ChargeGuard process.
- **Recovery:** `sudo chargectl restore --direct` (chargectl is in `/usr/local/bin` after a fallback install, in `ChargeGuard.app/Contents/MacOS/`, and in `build/` after `make build`) or reboot. A normal unload (`launchctl bootout`) sends SIGTERM, and the helper restores before exiting.

### 10. App quit

| AppClosedBehavior | What happens when the app quits normally | When the app crashes |
|---|---|---|
| `keepEnforced` (default) | Nothing changes. The helper keeps enforcing. | Same. |
| `restoreOnQuit` | The app sends `appWillQuit`; the helper sets `enforcementSuspended`, writes normal values and shows "Normal charging (ChargeGuard closed)". Enforcement resumes when the app starts again (`appLaunched`). | The helper keeps enforcing: a crash is not a quit. |

### 11. Another charging tool is running

- **Cause:** the AlDente app process, a batt process or launchd label (`cc.chlc.batt`, `homebrew.mxcl.batt`), or the battery CLI (a `co.palokaj.battery` / `com.battery.app` label or its maintain process).
- **Symptom:** red banner "Another charging tool is running". ChargeGuard writes nothing, not even a restore, while the other tool runs (two tools writing the same keys fight each other). The keys are whatever the other tool or ChargeGuard last wrote.
- **Recovery:** quit the other tool. The helper rescans every 60 s and on wake. While the conflict lasts the helper refuses every write, including "Restore normal charging", `chargectl restore` and `chargectl prepare-uninstall` (which still turns charge control off): the other tool would rewrite the keys anyway. The only override is `sudo chargectl restore --direct`, which warns and then writes the default values. On SIGTERM the helper also skips its restore while another tool runs. A battery CLI that is installed but not running is shown as information only.

### 12. Write failures and backend failover

- **Cause:** a write returns `kIOReturnNotPrivileged` (charge keys gated by `com.apple.private.iokit.soc-limit` on newer firmware) or another IOKit error.
- **What happens:** the key is marked not privileged, and the controller switches to the next supported backend: LegacyKeys → FirmwareLimit → AdapterCutoff. With no backend left, the status turns to an error state with the message. Writes are never retried faster than the control interval (default 5 s).
- **Symptom:** a "Backend changed" notification, or a red error state in the menu bar.
- **Recovery:** check `chargectl probe` and `chargectl writes`. A failed write leaves the key at its previous value. `chargectl restore` retries keys that were marked not privileged, because the user asked for it explicitly.

### 13. Sleep

- Nothing can enforce the limit while the Mac sleeps on the LegacyKeys or AdapterCutoff backends: the helper only runs while awake.
- If the battery was already at the limit, charging stays blocked during sleep (the key keeps its value).
- If it was below the limit, it can charge past the limit during sleep, unless **Stop Charging when Sleeping** is on: then charging is blocked just before sleep and re-evaluated on wake.
- Forced discharge always pauses before sleep and resumes on wake.
- The FirmwareLimit backend keeps holding during sleep (the firmware runs the hysteresis).

### 14. AdapterCutoff backend limits

- Used when the charge keys are absent or gated. It holds the limit by cutting wall power at the limit and reconnecting it a few percent lower (minimum band 5 %), so the battery cycles in a small band instead of idling.
- Before sleep the adapter is always reconnected: the Mac must not sleep on battery with nothing able to reconnect it. The battery may charge past the limit while asleep.
- Recovery is the same as state 2.

## Safety rules (section 8) and where they are enforced

| Rule | Enforcement |
|---|---|
| Restore path writes deactivate values to every present charge and discharge key and resets ACLC | `GuardedSMCWriter.restoreAll` (Core), used by the "Restore normal charging" command, `chargectl restore`, `chargectl restore --direct`, SIGTERM and uninstall |
| Restore on SIGTERM | `ChargeGuardHelper/main.swift` signal sources call `ChargeController.shutdown`, which restores when `keysDirty` and no other tool runs, releases assertions and the sleep hold, saves, exits |
| Restore on uninstall | `HelperCommand.prepareUninstall`; `scripts/uninstall.sh` runs it first, else `restore --direct` |
| Restore on start with stale state and "restore on quit" | `ChargeController.startOnQueue`: `keysDirty` + (`restoreOnQuit` or control off) → restore |
| Never write a key whose probe failed | `GuardedSMCWriter.ensure` refuses keys not confirmed present by `KeyProber` (`SMCError.notProbed`), keys outside the section 5 table (`invalidKey`), wrong sizes (`sizeMismatch`) |
| Never write while another tool runs | `PolicyEngine` gate returns `writesAllowed = false`; `GuardedSMCWriter.blockedReason` refuses every write except an explicit user restore |
| Pure, deterministic engine | `PolicyEngine.evaluate(config:snapshot:previous:context:)` has no side effects; unit-tested in `PolicyEngineTests` |
| Log every write with key, value, reason and snapshot | `KeyWriteRecord` from `GuardedSMCWriter`, logged by the controller (category `writes`) and appended to `writes.jsonl` |
| Fail over on write errors, else visible error | `ChargeController.handleWriteFailure` + `BackendSelector`; status `.error` |
| Never retry faster than the control interval | `ChargeController.apply` skips writes within 0.9 × poll interval of the last failure |
| Discharge never below 5 %, calibration never below 10 % | `PolicyEngine.minimumDischargeFloor`, `CalibrationMachine.absoluteFloor`; limit range 20–100 |
| Heat Protection overrides everything | Heat latch applied after calibration and top up in `PolicyEngine`; forces `inhibitCharging` |
| First-run confirmation before control | `PolicyConfig.controlEnabled` defaults to false; the engine returns `writesAllowed = false` until `HelperCommand.confirmFirstRun`; settings import never enables it |

## Files ChargeGuard creates

| Path | Owner | Removed by uninstall |
|---|---|---|
| `/Library/Application Support/ChargeGuard/state.json` | root | yes |
| `/Library/Application Support/ChargeGuard/events.jsonl`, `calibration.jsonl`, `writes.jsonl` (+ `.1` rotations) | root | yes |
| `/Library/PrivilegedHelperTools/com.amir.chargeguard.helper` (fallback install) | root | yes |
| `/Library/LaunchDaemons/com.amir.chargeguard.helper.plist` (fallback install) | root | yes |
| `/usr/local/bin/chargectl` (fallback install) | root | yes |
| SMAppService registration (Login Items) | system | yes (app runs `--unregister-helper`) |
| App preferences (`defaults read com.amir.chargeguard`) | user | no (`defaults delete com.amir.chargeguard`) |
