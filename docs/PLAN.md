# ChargeGuard plan

Tick each box when its done criteria in `BATTERY_APP_PROMPT.md` section 13 are met. Part A runs on Windows without a compiler, so its boxes mean "written and reviewed", never "compiles".

## Part A (Windows): write everything, push

- [x] A0 Setup and repo: .gitattributes, .gitignore, CLAUDE.md, this plan, private GitHub repo, first push
- [x] A1 Core: models, policy engine, calibration and schedule state machines, backend selection, codec, simulated backend, powermetrics parser, unit tests
- [x] A2 System: SMC client, battery reader, assertions, pmset wrapper, observers
- [x] A3 Helper: XPC service, client validation, control loop, persistence, restore paths, SMAppService plist, install and uninstall scripts
- [x] A4 App: menu bar pop-up, Settings, Dashboard with Sankey, icon sets, notifications, App Intents, first-run wizard, --simulate
- [x] A5 Tooling and docs: chargectl, project.yml, Makefile, SAFETY, TEST-CHECKLIST, SMC-KEYS template, THIRD_PARTY_NOTICES, LICENSE, README
- [x] A6 Self-review, MAC-BUILD-NOTES complete, PART-A-DONE written, Part B commands printed

## Part B (Mac): compile, install, verify on hardware, push

- [ ] B0 Setup: toolchain, REA, Ghidra, AlDente quit, docs/ENVIRONMENT.md
- [ ] B1 Compile: xcodegen generate, make build green for every target, make test green, commit "compiles on macOS"
- [ ] B2 Read-only run: live battery data in the menu bar, `chargectl probe` output, docs/SMC-KEYS.md filled in
- [ ] B3 Helper and limit: daemon installed (confirmation 2), `chargectl restore` works, Charge Limiter end to end (confirmation 3), 30-minute hold at the limit
- [ ] B4 Discharge, Automatic Discharge, Stop Charging when Sleeping, Stop Charging when App Closed, conflict detection
- [ ] B5 Heat Protection, Sailing Mode, Top Up, Disable Sleep until Limit, Sleep Control, Low Power Mode
- [ ] B6 Calibration with fastCalibration on hardware, real timings in simulation, persistence, notifications, history
- [ ] B7 Schedule, Apple Shortcuts in the Shortcuts app, MagSafe LED
- [ ] B8 Dashboard: Power Flow, Apps Using Significant Energy, Stats, Hardware Percentage
- [ ] B9 Live status icons, appearance and pop-up customisation, Fast User Switching, clamshell discharge with an external display
- [ ] B10 FirmwareLimitBackend, AdapterCutoffBackend, firmware detection, --simulate, full unit tests, hardware checklist fully executed
- [ ] B11 Packaging: DMG, uninstall verified, README screenshots, SAFETY final, optional notarization and Sparkle, final report

## Features (section 7)

Columns: written in Part A / verified on the Mac (hardware or simulation, see the final report).

| # | Feature | Part A written | Part B verified |
|---|---|---|---|
| 1 | Charge Limiter | [x] | [ ] |
| 2 | Discharge | [x] | [ ] |
| 3 | Automatic Discharge | [x] | [ ] |
| 4 | Discharge in Clamshell Mode | [x] | [ ] |
| 5 | Heat Protection | [x] | [ ] |
| 6 | Sailing Mode | [x] | [ ] |
| 7 | Top Up | [x] | [ ] |
| 8 | Calibration Mode (the "After macOS Calibration" stretch goal is not implemented) | [x] | [ ] |
| 9 | Control MagSafe LED | [x] | [ ] |
| 10 | Disable Sleep until Charge Limit | [x] | [ ] |
| 11 | Sleep Control | [x] | [ ] |
| 12 | Stop Charging when Sleeping | [x] | [ ] |
| 13 | Stop Charging when App Closed | [x] | [ ] |
| 14 | Low Power Mode control | [x] | [ ] |
| 15 | Schedule | [x] | [ ] |
| 16 | Apple Shortcuts integration | [x] | [ ] |
| 17 | Live Status Icons | [x] | [ ] |
| 18 | Customizable menu bar icon and pop-up | [x] | [ ] |
| 19 | Hardware Battery Percentage | [x] | [ ] |
| 20 | Power Flow | [x] | [ ] |
| 21 | Apps Using Significant Energy | [x] | [ ] |
| 22 | Stats | [x] | [ ] |
| 23 | Fast User Switching | [x] | [ ] |
