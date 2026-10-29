# ChargeGuard

ChargeGuard is a battery-care menu bar app for Apple silicon MacBooks. It limits charging to a level you choose, discharges to that level while plugged in, pauses charging when the battery is hot, calibrates the battery, runs schedules, and exposes everything to the Shortcuts app. A small root helper daemon enforces the policy, also while the app is closed.

It is an original, clean-room implementation of the feature set of AlDente Free and AlDente Pro. ChargeGuard has no tiers and no paywall: every feature is included. It is not affiliated with AppHouseKitchen.

> **Status:** the code was written in Part A on Windows without a Swift compiler, so it has not been compiled yet. Part B compiles it on a Mac, verifies every feature on real hardware, and updates this README. See `docs/PLAN.md` for progress.

## Features

Equivalents of AlDente Free:

1. **Charge Limiter**: limit from 20 to 100 % (5 % steps, 1 % steps in Advanced). Charging stops at the limit and resumes below limit − 2 % (or the sailing range).
2. **Discharge**: run from the battery while plugged in until the limit, then hold. Only while the Mac is awake.

Equivalents of AlDente Pro:

3. **Automatic Discharge**: discharge to the limit whenever the battery is above it while plugged in.
4. **Discharge in Clamshell Mode**: keep discharging with the lid closed and an external display.
5. **Heat Protection**: pause charging at or above Max Temp (30 to 50 °C, default 35 °C), resume 2 °C lower.
6. **Sailing Mode**: after reaching the limit, run from the adapter until the battery falls by the sailing range (1 to 20 %, default 5 %).
7. **Top Up**: charge to 100 % once, with an estimated time remaining.
8. **Calibration Mode**: charge to 100 % and hold, discharge to 15 %, charge to 100 % and hold, restore the limit. Persistent, cancellable, schedulable.
9. **Control MagSafe LED**: green at the limit, orange while charging, off while discharging.
10. **Disable Sleep until Charge Limit**.
11. **Sleep Control**: keep awake for 30 minutes, 1, 2 or 4 hours, indefinitely or until the limit, optionally with the display on.
12. **Stop Charging when Sleeping**: block charging just before sleep, since nothing can enforce the limit while asleep.
13. **Stop Charging when App Closed**: keep enforcing with the helper (default) or restore normal charging when ChargeGuard quits.
14. **Low Power Mode control**: always off, always on, only on battery, only on adapter.
15. **Schedule**: weekly or one-off rules (start calibration, top up, set limit, discharge on/off, Low Power Mode) with catch-up after sleep or boot when less than 2 hours late.
16. **Apple Shortcuts**: App Intents for status, limit, discharge, heat, sailing, top up, calibration, Low Power Mode, keep awake and the LED, with App Shortcuts phrases.
17. **Live Status Icons**: charging, limit reached, discharging, heat paused, sailing, calibrating, top up, helper missing, error, another tool running.
18. **Customizable menu bar icon and pop-up**: icon styles, monochrome or coloured, percentage on or off, a pop-up layout editor.
19. **Hardware Battery Percentage**: the raw percentage next to the macOS one.
20. **Power Flow**: live Sankey diagram of adapter, system and battery power.
21. **Apps Using Significant Energy**: top processes by energy (powermetrics, with fallbacks), with a Quit button.
22. **Stats**: cycle count, capacities and health, temperature, voltage, amperage, time to full or empty, adapter, serial.
23. **Fast User Switching**: the helper owns all state; the app in an inactive session goes passive.

Plus notifications, a Settings window, a Dashboard window, a first-run wizard, settings export and import, a command-line tool and a `--simulate` mode.

## Screenshots

Captured in Part B with `make run-sim` (no real battery or helper needed):

- `docs/screenshots/popup.png` (menu bar pop-up)
- `docs/screenshots/dashboard.png` (Power Flow, apps, stats)
- `docs/screenshots/settings-charging.png`
- `docs/screenshots/calibration.png`
- `docs/screenshots/icons.png` (status icon states)

## Requirements

- A MacBook with Apple silicon. Intel Macs show an "unsupported" screen.
- macOS 14 Sonoma or later.
- To build: Xcode 15.4 or later (Swift 5.10), XcodeGen (`brew install xcodegen`).

## Build

```sh
make build            # xcodegen generate (when the project is missing) + xcodebuild into build/
make test             # unit tests (ChargeGuardCore runs on any platform with Swift)
make run              # build and open build/ChargeGuard.app
make run-sim          # open the app with --simulate: simulated battery, no helper, no SMC writes
make install-helper   # fallback helper install: sudo scripts/install-helper.sh
make uninstall        # sudo scripts/uninstall.sh (restores charging first)
make dmg              # build/ChargeGuard.dmg
```

Signing uses an Apple Development certificate when one is in the keychain, otherwise ad-hoc. The hardened runtime is on. The `.xcodeproj` is generated from `project.yml` and never committed.

## Installing the helper

The first-run window explains what the helper does, installs it, probes the SMC keys, shows the result and asks for confirmation before it enables charge control. Until you confirm, nothing is written.

- **Primary path:** the app registers the helper with `SMAppService`. Approve it in **System Settings > General > Login Items**. Move ChargeGuard.app to /Applications first.
- **Fallback:** `sudo scripts/install-helper.sh /Applications/ChargeGuard.app`. It copies the helper to `/Library/PrivilegedHelperTools/`, writes `/Library/LaunchDaemons/com.amir.chargeguard.helper.plist`, bootstraps it, and installs `chargectl` to `/usr/local/bin`. Use one path, not both.

## chargectl

```sh
chargectl status [--json]     # state, backend, keys, conflicts
chargectl probe               # every SMC key: present or absent, size, type, value
chargectl read KEY            # read one key (e.g. CHTE)
chargectl restore [--direct]  # restore normal charging (--direct: sudo, without the helper)
chargectl limit N             # set the charge limit
chargectl discharge on|off
chargectl topup on|off
chargectl calibrate start [--fast] | stop
chargectl heat on|off
chargectl sailing on|off
chargectl lpm MODE            # unmanaged, alwaysOff, alwaysOn, onlyOnBattery, onlyOnAdapter
chargectl led MODE            # systemDefault, followState, alwaysOff
chargectl keepawake MINUTES|off
chargectl enable | disable    # charge control on or off
chargectl events              # recent events
chargectl writes              # recent SMC writes with reasons
chargectl prepare-uninstall
chargectl version
```

## Safety

ChargeGuard writes only the SMC keys and values documented in `docs/SMC-KEYS.md`, and only keys a probe confirmed present. It never writes while another charging tool (AlDente, batt, the battery CLI) is running. Every write is logged with its reason and a battery snapshot. Discharge never goes below 5 %, calibration never below 10 %, and Heat Protection overrides everything else.

If charging looks wrong:

1. Menu bar pop-up → **Restore normal charging**, or `chargectl restore`.
2. Without the helper: `sudo chargectl restore --direct`.
3. A reboot resets every SMC charging key to the macOS default.
4. If the Mac never sleeps after clamshell discharge with "Force clamshell awake": `sudo pmset -a disablesleep 0`.

`docs/SAFETY.md` lists every state ChargeGuard can leave the Mac in and how to recover from each.

## Uninstall

```sh
sudo scripts/uninstall.sh /Applications/ChargeGuard.app
```

It restores normal charging first (through the helper, or directly), unloads and removes the helper (both install paths, including the SMAppService registration), restores `pmset disablesleep` if ChargeGuard held it, removes `/Library/Application Support/ChargeGuard` and `/usr/local/bin/chargectl`, and prints what it removed. Then drag ChargeGuard.app to the Trash. App preferences can be removed with `defaults delete com.amir.chargeguard`. Low Power Mode is left as it is.

## macOS 27 and firmware notes

- On macOS 27 Developer Beta 4 firmware and later (System Firmware 20457.0.125.0.2 and newer, reportedly also in some macOS 15.x and 26.x security updates), the charge keys `CHTE`, `CH0B` and `CH0C` return `kIOReturnNotPrivileged` even to root: Apple gated them behind the private entitlement `com.apple.private.iokit.soc-limit`.
- ChargeGuard selects its backend by key presence and fails over at runtime:
  - **LegacyKeys** (`CHTE` or `CH0B`+`CH0C`, discharge with `CHIE`/`CH0J`/`CH0I`): the default where the charge keys work.
  - **FirmwareLimit** (`bfD0` upper and `bfE0` lower, when `bfF0` exists): the firmware holds the limit itself, also during sleep.
  - **AdapterCutoff** (only a discharge key): holds the limit by cutting wall power at the limit and reconnecting it at least 5 % lower, so the battery cycles in a small band. It works only while the Mac is awake; the adapter is reconnected before sleep, so the battery may charge past the limit while asleep.
- Apple's own charge limit in System Settings (macOS 26.4 and later, 80 to 100 %) is not used. It is not available on the Part B test Mac (macOS 15.5).
- Check your firmware with `system_profiler SPHardwareDataType | grep -i firmware` and the keys with `chargectl probe`.

## Two-part workflow

This repository is built in two parts, described in `BATTERY_APP_PROMPT.md`:

- **Part A (Windows):** all code, scripts and docs written without a Mac or compiler, reviewed carefully, pushed. `docs/MAC-BUILD-NOTES.md` lists every uncertain API and hardware check. `docs/PART-A-DONE.md` marks the end.
- **Part B (Mac):** clone, generate the project, fix compile errors, install the helper, verify every feature on the M2 (`docs/TEST-CHECKLIST.md`), record the SMC probe (`docs/SMC-KEYS.md`), package, push.

`docs/PLAN.md` tracks both parts. `CLAUDE.md` holds the build commands, the architecture and the safety rules for future sessions.

## Project layout

```
BATTERY_APP_PROMPT.md        the brief
project.yml, Makefile        XcodeGen spec and build entry points
Packages/ChargeGuardCore     Foundation-only logic: models, PolicyEngine, calibration and schedule
                             state machines, SMC key table, backends, simulation, ChargeController,
                             XPC message codec, powermetrics parser; unit tests
Packages/ChargeGuardSystem   macOS layer: AppleSMC (IOKit), battery reader, power management, pmset,
                             process scanning, energy samplers, persistence, XPC client;
                             ChargeGuardSessionKit (AppKit/NSWorkspace observers)
ChargeGuardHelper/           root launchd daemon (XPC service com.amir.chargeguard.helper)
ChargeGuard/                 SwiftUI menu bar app, Settings, Dashboard, App Intents, onboarding
chargectl/                   command-line tool
scripts/                     install-helper.sh, uninstall.sh, packaging
docs/                        PLAN, SAFETY, TEST-CHECKLIST, SMC-KEYS, MAC-BUILD-NOTES
```

## License and credits

MIT, see `LICENSE`. ChargeGuard adapts code from SMCKit (MIT) and the SMC key table from actuallymentor/battery (MIT), and uses facts learned from reading batt (GPL-2.0, no code copied). Details and full license texts are in `THIRD_PARTY_NOTICES.md`.
