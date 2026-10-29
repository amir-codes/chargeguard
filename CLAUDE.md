# ChargeGuard

macOS (Apple silicon) battery-care menu bar app plus a root helper daemon. Clean-room reimplementation of the AlDente Free and Pro feature set, MIT licensed. The full brief is `BATTERY_APP_PROMPT.md`; the phase checklist is `docs/PLAN.md`.

**Status:** Part A wrote everything on Windows with no Swift compiler and no XcodeGen. Nothing has been compiled or generated yet (not the Core package, not the macOS targets, not `project.yml`). Part B updates this line once `make build` and `make test` pass on the Mac.

## Two-part workflow

- Detect the OS first. Windows (`$env:OS` = `Windows_NT`, or `uname` prints MINGW/MSYS) = Part A. macOS (`uname` = Darwin) = Part B. Anything else: stop.
- Part A (Windows) writes all code blind and pushes. If `docs/PART-A-DONE.md` exists on Windows, Part A is finished: say so and stop.
- Part B (Mac) reads `docs/MAC-BUILD-NOTES.md` and `docs/PLAN.md`, then continues from the first unchecked Part B item. Never redo a finished phase.
- Commit at the end of every phase with a message naming the phase, and push after every commit.
- Questions: Part A asks only the start-up confirmation. Part B asks only three: start-up confirmation, before installing the root daemon, before the first SMC write.
- Never run sudo silently. Print the command with a one-line reason and ask the user to run it.
- Never claim the macOS targets compile unless `xcodebuild` actually succeeded on a Mac.

## Build commands (Mac only, except the Core tests)

```sh
make build            # xcodegen generate (when the project is missing or project.yml changed) + xcodebuild
                      # Release into build/ChargeGuard.app and build/chargectl, then codesign --verify
make project          # regenerate ChargeGuard.xcodeproj; run it after adding or removing source files
make test             # swift test: ChargeGuardCore everywhere, ChargeGuardSystem only on macOS
make run              # build and open build/ChargeGuard.app
make run-sim          # build and open the app with --simulate (no helper, no root, no SMC writes)
make install-helper   # fallback helper install: sudo scripts/install-helper.sh (asks for the password)
make uninstall        # sudo scripts/uninstall.sh: restores charging first, then removes everything
make dmg              # build/ChargeGuard.dmg
make clean            # removes build/ and the generated project
```

Core tests anywhere Swift exists: `cd Packages/ChargeGuardCore && swift test`. Only `install-helper` and `uninstall` run sudo, and both print why first.

Signing: `scripts/signing.sh` finds an Apple Development identity and its Team ID; without one the build is ad-hoc (`CODE_SIGN_IDENTITY=-`). Hardened runtime is on for every target. The app target's post-build script copies the signed `ChargeGuardHelper` and `chargectl` into `ChargeGuard.app/Contents/MacOS/` and `ChargeGuardHelper/com.amir.chargeguard.helper.plist` into `Contents/Library/LaunchDaemons/` before Xcode signs the app. Both tools embed their Info.plist (`CREATE_INFOPLIST_SECTION_IN_BINARY`).

## Layout and architecture

```
Packages/ChargeGuardCore     Foundation only, any platform. Models, PolicyEngine (pure),
                             calibration + schedule state machines, SMC key table and value
                             codecs, backends written against the SMCKeyIO protocol
                             (Legacy, FirmwareLimit, AdapterCutoff), SimulatedSMC/battery,
                             BackendSelector, ChargeController (the control loop, with injected
                             dependencies), XPC message codec, powermetrics parser, conflict rules.
Packages/ChargeGuardSystem   macOS only. Library ChargeGuardSystem (no AppKit, used by the daemon):
                             AppleSMC (IOKit SMCKeyIO), IORegistry battery reader, IOPM assertions,
                             pmset wrapper, power/sleep/lid observers, process scanner, powermetrics
                             runner, FileStateStore, XPC protocols + XPCHelperClient, os.Logger.
                             Library ChargeGuardSessionKit (AppKit/NSWorkspace observers, app only).
ChargeGuardHelper/           Root launchd daemon (XcodeGen `tool`). XPC listener com.amir.chargeguard.helper,
                             client code-signing validation, persistence in /Library/Application Support/ChargeGuard.
                             com.amir.chargeguard.helper.plist is the SMAppService launchd plist
                             (BundleProgram Contents/MacOS/ChargeGuardHelper).
ChargeGuard/                 SwiftUI menu bar app (LSUIElement). UI, settings, dashboard, App Intents.
chargectl/                   CLI (XcodeGen `tool`): status/probe/read/restore and every policy command over
                             XPC; `--direct` (status, probe, read, restore) works without the daemon,
                             `restore --direct` needs sudo.
scripts/                     install-helper.sh, uninstall.sh, make-dmg.sh, signing.sh (identity for the Makefile).
project.yml                  XcodeGen spec (the .xcodeproj is generated, never committed).
```

- The daemon is the enforcer: it owns `PersistedState` (config + control state + schedule) and runs the `ChargeController` tick every 5 s (`pollIntervalSeconds`). The app only edits settings and shows state.
- `PolicyEngine.evaluate(config, snapshot, previous, context) -> Decision` is pure and deterministic. All feature logic lives there and is unit-tested in Core.
- Backends translate the abstract decision (`inhibitCharging`, `forceDischarge`, `led`, firmware limits) into SMC key writes. They are selected by probing keys, never by OS version or chip name.
- App <-> daemon: NSXPCConnection, one `@objc` method that carries JSON-encoded `HelperRequest`/`HelperResponse` (Core codec), plus a client callback for pushed status. Protocol version handshake on connect.
- `--simulate`: the app runs a `ChargeController` in-process on `SimulatedSMC` + `SimulatedBattery`; no daemon, no root, no real keys.

## Safety rules (non-negotiable)

- Only the key names and byte values in `BATTERY_APP_PROMPT.md` section 5 (encoded in `SMCKeys.swift`). Never guess keys or values.
- Never write a key whose keyInfo probe failed. Never write while another charging tool (AlDente app, batt, battery CLI) is detected.
- Every write is logged with key, value, reason and the battery snapshot.
- On a failed write (including kIOReturnNotPrivileged) fall back to the next backend, else show an error state. Never retry faster than the control interval.
- Discharge never below 5 %. Calibration floors at 10 %. Heat Protection overrides everything.
- Restore path: `chargectl restore` (or `sudo chargectl restore --direct`) and the "Restore normal charging" menu item write the deactivate value to every present charge and discharge key and reset ACLC. A reboot also resets the keys.
- The daemon restores on SIGTERM, on uninstall, and on start with stale state when "restore on quit" is selected.
- `scripts/uninstall.sh` restores charging before it removes anything, and prints what it removed.
- Install the helper one way only: SMAppService from the app, or `scripts/install-helper.sh`. Both use the label `com.amir.chargeguard.helper`; the script refuses to run while the SMAppService job is loaded.
- Control stays disabled until the first-run wizard's explicit confirmation.
- See `docs/SAFETY.md` for every state the Mac can be left in and its recovery.

## Conventions

- Swift 5 language mode (`SWIFT_VERSION 5.0`, tools 5.10) with minimal strict concurrency; see `docs/MAC-BUILD-NOTES.md` for Swift 6 spots.
- Logging: `os.Logger(subsystem: "com.amir.chargeguard", category: <component>)` via `OSLogger` in ChargeGuardSystem; Core uses the `CoreLogger` protocol.
- Line endings LF (`.gitattributes`); shell scripts committed with the executable bit (`git update-index --chmod=+x scripts/*.sh`).
- Reference projects go in `references/` (git-ignored). batt and OpenDente are GPL: read only, never copy. battery.sh and SMCKit are MIT: adapted with attribution in THIRD_PARTY_NOTICES.md. Never decompile AlDente.
