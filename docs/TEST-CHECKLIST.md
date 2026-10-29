# Real-hardware test checklist (Part B)

Run on the M2 MacBook, macOS 15.5 (24F74), one item at a time, in phase order (B2 → B11). Record key values before and after every write test. Mark each item **hardware**, **simulation only** or **not working (reason)**; the final report copies these results.

## Conventions

- `chargectl` means the installed `/usr/local/bin/chargectl` or `build/chargectl`. Without `--direct` it talks to the helper, so before the helper is installed (0.1, 0.2) use `--direct`.
- "Key table": fill in only the keys `chargectl probe` reported as present; write `—` for absent keys.
- Before each test: `chargectl status` shows `backend`, `conflicts: none`, charge control enabled (except where stated).
- Emergency: `chargectl restore`, `sudo chargectl restore --direct`, or reboot (see docs/SAFETY.md).
- Long checks (30-minute hold, calibration) run in the background; continue with the next item and record the result when they finish.

Key table template (copy for each test):

| Key | Before | After | Expected after |
|---|---|---|---|
| CHTE | | | |
| CH0B | | | |
| CH0C | | | |
| CHIE | | | |
| CH0J | | | |
| CH0I | | | |
| ACLC | | | |

Read all of them at once with `for k in CHTE CH0B CH0C CHIE CH0J CH0I ACLC; do chargectl read $k --direct; done` (`--direct` reads work with or without the helper).

---

## 0. Setup checks

### 0.1 Read-only probe (B2)
- [ ] Preconditions: app built, helper not yet installed, AlDente quit.
- [x] Steps: `build/chargectl probe --direct` (no sudo, no helper; reads only). Paste output into docs/SMC-KEYS.md.
- [x] Expected: every key from SMCKey.probeKeys listed as present or absent with size and type. No writes are possible: the helper is not installed and `--direct` only writes for `restore` under sudo.
- Result: **hardware**. All 13 probe keys answered: CHTE/CH0B/CH0C/CHIE/CH0J/CH0I/ACLC/AC-W/PDTR/PPBR present, bfF0/bfD0/bfE0 absent (see docs/SMC-KEYS.md). Date: 2026-10-30

### 0.2 Live battery data without the helper (B2)
- [x] Steps: launch ChargeGuard. Compare the pop-up with `ioreg -rn AppleSmartBattery` and the macOS battery menu.
- [x] Expected: percentage, hardware percentage, temperature, voltage, amperage, cycle count match. State line says the helper is not running.
- Result: **hardware (data path)**. `build/ChargeGuard.app` launched and stayed up with no crash report; its reader is the same `BatteryReader` that `chargectl status --direct` uses, whose output matched ioreg exactly (66 %, hardware 62.7 %, 30.5 °C, 11.54 V, −1384 mA, 344 cycles, no helper). The pop-up itself could not be looked at: this Part B session has no Screen Recording or Accessibility permission (screencapture returns only the wallpaper, AppleScript is refused), so visual checks of the UI are recorded as "data path" throughout and should be eyeballed once by the user. Date: 2026-10-30

### 0.3 Helper install (B3, confirmation 2)
- [ ] Steps: first-run window → Install helper → approve in System Settings > General > Login Items. Fallback (only if SMAppService fails; never both): `make install-helper`, or `sudo scripts/install-helper.sh "$PWD/build/ChargeGuard.app"`.
- [ ] Expected: `sudo launchctl print system/com.amir.chargeguard.helper` shows it running; `chargectl status` answers; the protocol in `chargectl version` matches the `Helper:` line of `chargectl status`. Charge control is still **off**; `chargectl writes` is empty.
- Result: ____ Date: ____

### 0.4 Restore (B3)
- [ ] Preconditions: AlDente may have left keys blocked.
- [ ] Steps: record the key table, run `chargectl restore`, record again. Then `sudo chargectl restore --direct` with the helper stopped (`sudo launchctl bootout system/com.amir.chargeguard.helper`), reinstall afterwards.
- [ ] Expected: CHTE `00000000` (or CH0B/CH0C `00`), discharge keys `00`, ACLC `00`; the battery charges normally.

| Key | Before | After restore | After restore --direct |
|---|---|---|---|
| CHTE | | | |
| CH0B | | | |
| CH0C | | | |
| CHIE | | | |
| CH0J | | | |
| CH0I | | | |
| ACLC | | | |

- Result: ____ Date: ____

---

## Features

### 1. Charge Limiter (B3, confirmation 3 before the first write)
- [ ] Preconditions: plugged in, battery below 80 %.
- [ ] Steps: confirm the first-run step (enables control). Set the limit to the current level + 2 % (`chargectl limit N`). Watch `chargectl status` until the limit is reached. Lower the limit by 1 % and raise it again.
- [ ] Expected: charging stops within one tick (5 s) of reaching the limit; status "Limit reached"; resumes only below limit − 2 %; raising the limit resumes charging immediately; the slider uses 5 % steps (1 % with fine steps in Advanced); limit shown in the menu bar when that option is on.
- [ ] Key table (expected: CHTE `01000000` or CH0B/CH0C `02` at the limit).
- [ ] **30-minute hold** (background): at the limit, record percentage and `chargectl read CHTE` every 5 minutes for 30 minutes.

| Minute | 0 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|
| Percentage | | | | | | | |
| CHTE / CH0B | | | | | | | |
| IsCharging | | | | | | | |

- Result: ____ Date: ____

### 2. Discharge (B4)
- [ ] Preconditions: plugged in, limit at least 5 % below the current level.
- [ ] Steps: toggle Discharge in the pop-up (or `chargectl discharge on`). Watch until the limit.
- [ ] Expected: status "Discharging to N %"; percentage falls while plugged in; at the limit discharge stops and charging stays blocked; the UI says discharge only happens while awake.
- [ ] Key table (expected during discharge: CHIE `08` or CH0J/CH0I `01`, charge key blocked; after: discharge key `00`, charge key blocked).
- [ ] Check adapter presence: `chargectl status --json | grep -E 'externalConnected|adapterPresent'` during discharge. `adapterPresent` must stay true.
- Result: ____ Date: ____

### 3. Automatic Discharge (B4)
- [ ] Steps: enable Automatic Discharge; at the limit, lower the limit by 5 %.
- [ ] Expected: discharge starts automatically ("automatic" in the state line), stops at the new limit. After a completed Top Up it does not start until the adapter is unplugged.
- [ ] Key table.
- Result: ____ Date: ____

### 4. Discharge in Clamshell Mode (B9, external display needed)
- [ ] Steps: external display, keyboard and mouse connected. Enable Discharge in Clamshell Mode. Start a discharge, close the lid.
- [ ] Expected: `pmset -g assertions` shows PreventSystemSleep by ChargeGuardHelper; the Mac stays awake and keeps discharging. If it sleeps anyway: discharge pauses before sleep and resumes on wake (record which happened). Repeat with "Force the Mac awake during clamshell discharge" (Settings > Charging): `pmset -g | grep SleepDisabled` shows 1 during discharge and returns to the previous value afterwards.
- [ ] Without the setting: closing the lid pauses discharge ("Discharge paused: lid closed").
- Result: ____ Date: ____

### 5. Heat Protection (B5)
- [ ] Steps: enable Heat Protection, set Max Temp to just below the current battery temperature (30 °C minimum), plugged in below the limit.
- [ ] Expected: charging pauses; distinct heat icon; a notification; resumes at Max Temp − 2 °C (raise Max Temp to test). Also verify it overrides Top Up.
- [ ] Key table.
- Result: ____ Date: ____

### 6. Sailing Mode (B5)
- [ ] Steps: enable Sailing (range 5 %); reach the limit; let the battery drop (use Discharge or unplug briefly).
- [ ] Expected: status "Limit N % reached, sailing until N−5 %"; charging resumes only at limit − 5 %; the Mac runs from the adapter meanwhile.
- [ ] Key table.
- Result: ____ Date: ____

### 7. Top Up (B5)
- [ ] Steps: at the limit, press Top Up (`chargectl topup on`).
- [ ] Expected: charging resumes to 100 %; an estimated time remaining appears; at FullyCharged (or on unplug) Top Up ends and the configured limit applies again.
- [ ] Key table.
- Result: ____ Date: ____

### 8. Calibration Mode (B6)
- [ ] **fastCalibration on hardware** (target under 20 minutes): enable the hidden fast mode (`chargectl calibrate start --fast`) at about 95–97 %, plugged in.
- [ ] Expected: phases A (charge to 100 %, hold 2 min) → B (discharge to current − 3 %, Mac kept awake) → C (charge to 100 %, hold 2 min) → D (restore the limit, discharge to it if Automatic Discharge is on). A notification at each phase. Record phase start times:

| Phase | Start time | Percentage | Keys |
|---|---|---|---|
| A charge | | | |
| A hold | | | |
| B discharge | | | |
| C recharge | | | |
| C hold | | | |
| D restore | | | |

- [ ] Persistence: during phase B, quit the app and `sudo launchctl kickstart -k system/com.amir.chargeguard.helper`; calibration continues in the same phase.
- [ ] Cancel: start again, then `chargectl calibrate stop`; history records "cancelled".
- [ ] **Real timings in simulation:** `make test` runs `CalibrationTests.testFullCalibrationInSimulationWithRealTimings` (1-hour holds, floor 15 %). Also run `make run-sim` and watch a full calibration at 60× speed.
- [ ] History shows in the Dashboard.
- Result: ____ Date: ____

### 9. Control MagSafe LED (B7)
- [ ] Steps: set LED to "Show ChargeGuard's state" (`chargectl led state`). Observe while charging, at the limit, during discharge. Then "Off while plugged in" (`chargectl led off`), then "System default (not controlled)" (`chargectl led system`).
- [ ] Expected: orange while charging (`ACLC 04`), green at the limit (`03`), off while discharging (`01`); "Off while plugged in" writes `01`; "System default" writes `00` and the LED returns to normal (confirm the `00` behaviour, record in docs/SMC-KEYS.md). Quit and uninstall also reset it.
- [ ] Key table (ACLC).
- Result: ____ Date: ____

### 10. Disable Sleep until Charge Limit (B5)
- [ ] Steps: enable it; plugged in below the limit.
- [ ] Expected: `pmset -g assertions` shows PreventUserIdleSystemSleep by ChargeGuardHelper; released when the limit is reached or on unplug.
- Result: ____ Date: ____

### 11. Sleep Control (B5)
- [ ] Steps: Keep awake for 30 minutes (menu), then indefinitely, then until the charge limit, each with and without display-sleep prevention.
- [ ] Expected: assertions present (PreventUserIdleSystemSleep, plus PreventUserIdleDisplaySleep when chosen); the countdown is shown; assertions released at expiry or on cancel (`chargectl keepawake off`).
- Result: ____ Date: ____

### 12. Stop Charging when Sleeping (B4)
- [ ] Steps: enable it; plugged in below the limit; put the Mac to sleep for 10 minutes; wake.
- [ ] Expected: before sleep the charge key is set (check `chargectl writes` after wake); the percentage did not rise during sleep; on wake charging resumes. The UI explains why (nothing can enforce the limit during sleep).
- [ ] Key table (before sleep / after wake).
- Result: ____ Date: ____

### 13. Stop Charging when App Closed (B4)
- [ ] Default "Keep the limit enforced by the helper": quit the app at the limit; keys stay blocked; `chargectl status` still enforcing.
- [ ] "Restore normal charging when ChargeGuard quits": quit the app; keys return to defaults; status "suspended"; relaunching the app resumes enforcement.
- [ ] Crash: `kill -9` the app; the helper keeps enforcing in both modes.
- [ ] Key table for each case.
- Result: ____ Date: ____

### 14. Low Power Mode control (B5)
- [ ] Steps: set each policy (Always Off, Always On, Only on Battery, Only on Adapter); unplug and replug for the last two (`chargectl lpm MODE`).
- [ ] Expected: `pmset -g | grep lowpowermode` and the battery menu follow the policy on every power-source change; the app shows the current state.
- Result: ____ Date: ____

### 15. Schedule (B7)
- [ ] Steps: add a rule 2 minutes ahead "Set limit 70 %", weekly, today. Add a once-rule "Top up". Edit and delete a rule. Then test catch-up: add a rule 5 minutes ahead, sleep the Mac for 10 minutes, wake.
- [ ] Expected: rules fire on time with a notification; the "next run" column is correct; the once-rule disables itself; the missed rule runs on wake (less than 2 hours late); a rule missed by more than 2 hours is reported as missed, not run.
- Result: ____ Date: ____

### 16. Apple Shortcuts (B7)
- [ ] Steps: in the Shortcuts app, run each action: Get Battery Status, Set Charge Limit, Enable/Disable Discharge, Toggle Heat Protection, Toggle Sailing, Top Up, Start/Stop Calibration, Set Low Power Mode, Keep Awake, Set MagSafe LED. Try one App Shortcut by its phrase in Spotlight.
- [ ] Expected: each action works and Get Battery Status returns percentage, hardware percentage, temperature, state and limit.
- Result: ____ Date: ____

### 17. Live Status Icons (B9)
- [ ] Expected icon states seen: charging, limit reached, discharging, heat paused, sailing, calibrating (with phase), top up, helper missing (stop the helper), error, another tool running (start AlDente briefly with the helper running — then quit AlDente). Optional percentage text next to the icon.
- Result: ____ Date: ____

### 18. Customizable icon and pop-up (B9)
- [ ] Expected: each icon style (outline, filled, bolt, percentage only) and monochrome/coloured works; percentage show/hide works; the pop-up layout editor hides, shows and reorders widgets and the pop-up follows; settings survive a relaunch.
- Result: ____ Date: ____

### 19. Hardware Battery Percentage (B8)
- [ ] Expected: pop-up and Stats show AppleRawCurrentCapacity / AppleRawMaxCapacity × 100 next to the macOS percentage (compare with `ioreg`).
- Result: ____ Date: ____

### 20. Power Flow (B8)
- [ ] Expected: Dashboard Sankey shows Adapter → System, Adapter → Battery while charging, Battery → System while discharging (and on battery); numbers update every 2 s; cards show adapter, system and battery watts; battery W = Voltage × Amperage / 1 000 000.
- Result: ____ Date: ____

### 21. Apps Using Significant Energy (B8)
- [ ] Expected: top processes listed with the method label (powermetrics via the helper; rusage or CPU fallback without it); Quit terminates a test app (e.g. TextEdit).
- [ ] Capture real `sudo powermetrics --samplers tasks --show-process-energy -i 1000 -n 1` output (text and `-f plist`) and compare with the parser fixtures.
- Result: ____ Date: ____

### 22. Stats (B8)
- [ ] Expected: cycle count, design and maximum capacity, health %, temperature, voltage, amperage, time to full/empty, adapter name and wattage, serial — compare with System Information > Power.
- Result: ____ Date: ____

### 23. Fast User Switching (B9)
- [ ] Steps: create a second user; log both in; run ChargeGuard in both; switch users; change a setting in the active session.
- [ ] Expected: the limit stays enforced across switches; the inactive session's app is passive (refuses commands, shows no duplicate notifications).
- Result: ____ Date: ____

---

## Safety and infrastructure

### Conflict detection (B4)
- [ ] Steps: with ChargeGuard enforcing, launch AlDente. Then quit it.
- [ ] Expected: within 60 s the red "Another charging tool is running" banner appears; `chargectl writes` shows no new writes while AlDente runs; after quitting AlDente, enforcement resumes. (If batt or the battery CLI are available, repeat with them.)
- Result: ____ Date: ____

### Backends (B10)
- [ ] LegacyKeys (default on this Mac): verified by features 1–2.
- [ ] AdapterCutoff: Settings > Advanced > Backend = "Adapter cutoff (CHIE / CH0J / CH0I)". Expected: at the limit the adapter is cut (discharge key set) and reconnected 5 % lower (the default "Adapter cutoff minimum band"); before sleep the adapter is reconnected; the UI shows the limitations text.
- [ ] FirmwareLimit: only if `bfF0` is present (record if absent: "not available on this firmware", verified in unit tests only).
- [ ] Firmware detection: `chargectl status` shows the firmware version; matches `system_profiler SPHardwareDataType | grep -i firmware`.
- Result: ____ Date: ____

### --simulate (B10)
- [ ] `make run-sim`: the whole UI works without the helper; time runs 60× faster; no real keys are written (`chargectl writes` unchanged). Capture README screenshots here.
- Result: ____ Date: ____

### Unit tests (B10)
- [ ] `make test` green (ChargeGuardCore and ChargeGuardSystem tests).
- Result: ____ Date: ____

### Uninstall (B11)
- [ ] Steps: at the limit with discharge active, run `make uninstall` (or `sudo scripts/uninstall.sh /Applications/ChargeGuard.app`). Repeat once for each install path (SMAppService, then the fallback script).
- [ ] Expected: keys restored first (key table; the script prints "Charging: restored ..."), helper unloaded and removed, SMAppService registration gone from System Settings > General > Login Items, `/Library/Application Support/ChargeGuard` and `/usr/local/bin/chargectl` removed, the script prints what it removed; `pmset -g | grep SleepDisabled` is 0.
- [ ] Key table.
- Result: ____ Date: ____
