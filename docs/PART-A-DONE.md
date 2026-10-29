# Part A done

Part A (Windows) is finished. Every phase A0 to A6 is committed and pushed to the private repository https://github.com/amir-codes/chargeguard.

## Important: nothing has been compiled

This Windows machine has no Swift toolchain (`swift --version` failed; installing Swift for Windows was skipped in the start-up confirmation). So:

- The ChargeGuardCore package and its tests were **not** built or run here. Run `make test-core` (or `cd Packages/ChargeGuardCore && swift test`) first on the Mac.
- The macOS targets (ChargeGuardSystem, ChargeGuardHelper, chargectl, the ChargeGuard app) have **never** been compiled. `project.yml` has never been run through XcodeGen.
- Expect compile errors in every target. Phase B1 exists to fix them. `docs/MAC-BUILD-NOTES.md` lists every API I was unsure about, the real-hardware checks, and the concurrency spots.

## What exists

About 12,600 lines of Swift, plus scripts and docs:

| Part | Where | Contents |
|---|---|---|
| ChargeGuardCore | `Packages/ChargeGuardCore` | Models, the pure `PolicyEngine`, calibration and schedule state machines, SMC key table and values, `GuardedSMCWriter`, Legacy/FirmwareLimit/AdapterCutoff/Simulated backends, `BackendSelector`, `ChargeController` (the control loop), XPC message codec, transports, simulated SMC and battery, powermetrics/IORegistry/pmset parsers. 131 XCTest cases covering every feature trace, backends, the codec, the parsers and end-to-end simulation (including a full calibration with real one-hour holds). |
| ChargeGuardSystem | `Packages/ChargeGuardSystem` | IOKit SMC client (adapted from SMCKit, with the arm64 layout fix and a runtime layout check), IORegistry battery reader, power-source and sleep observers, IOPM assertions, pmset wrapper, process and launchd scanning for conflicts, powermetrics and rusage energy samplers, file persistence, XPC client. `ChargeGuardSessionKit` holds the AppKit observers. |
| ChargeGuardHelper | `ChargeGuardHelper/` | Root daemon: XPC Mach service `com.amir.chargeguard.helper`, client code-signing validation, sleep/wake hooks, SIGTERM restore, SMAppService launchd plist. |
| chargectl | `chargectl/` | status, probe, read, restore (`--direct` without the helper), every command, events, writes, prepare-uninstall. |
| App | `ChargeGuard/` | MenuBarExtra pop-up with customisable widgets, state icon renderer (4 styles, monochrome or coloured), Settings (11 tabs), Dashboard (Sankey power flow, energy apps, stats, history), App Intents and App Shortcuts, first-run wizard, notifications, `--simulate`. |
| Build | `project.yml`, `Makefile`, `scripts/` | XcodeGen spec, make targets (build, test, run, run-sim, install-helper, uninstall, dmg), fallback installer, uninstaller, signing and DMG scripts. |
| Docs | `README.md`, `CLAUDE.md`, `docs/` | PLAN, SAFETY, TEST-CHECKLIST, SMC-KEYS template, MAC-BUILD-NOTES, this file, THIRD_PARTY_NOTICES, MIT LICENSE. |

All 23 features from the brief are written. Written but not delivered:
- The "After macOS Calibration" stretch goal (feature 8) is not implemented.
- Discharge in Clamshell Mode depends on whether macOS honours the PreventSystemSleep assertion on battery power; the optional `pmset disablesleep` hold is the fallback. Hardware testing decides.

## Review (A6)

Five independent reviewers re-read Core, System/Helper/chargectl, the app, the Settings window, and the build configuration with the docs. They fixed many compile-level problems, among them:
- `var x` followed by `guard let x` redeclarations;
- self-referencing `let` initialisers;
- `didSet` on `@Observable` properties;
- main-thread semaphores;
- `ShortcutsLink`, which macOS lacks;
- printf-style `%` in App Intents strings;
- XPC reconnection;
- the helper's start order;
- the bash shell for the embed script;
- safer install and uninstall scripts.

Their remaining doubts are recorded in `docs/MAC-BUILD-NOTES.md`.

## Part B: start on the Mac

```sh
git clone https://github.com/amir-codes/chargeguard.git
cd chargeguard
claude
```

Claude Code detects macOS, reads `CLAUDE.md`, `docs/PLAN.md` and `docs/MAC-BUILD-NOTES.md`, and starts at B0 with the start-up confirmation. The first build steps are:

```sh
brew install xcodegen      # if missing
make test-core             # pure logic first
make project && make build # then the macOS targets
```

Safety reminder for Part B: no SMC key is written until the helper is installed (confirmation 2) and the first-write confirmation is given (confirmation 3). `chargectl restore`, `sudo chargectl restore --direct` and a reboot all return the charging keys to the macOS default.
