# Mac build notes (read first in Part B)

Part A was written on Windows with no Swift compiler (Swift for Windows was not installed). **Nothing in this repository has been compiled yet.** Expect compile errors in every target. This file lists every API I was not sure about, every place that needs a real-hardware check, and the Swift concurrency spots that may need fixes.

Language mode: everything is Swift 5 mode (`SWIFT_VERSION 5.0` in project.yml, swift-tools-version 5.10 in the packages) with `SWIFT_STRICT_CONCURRENCY: minimal`. That avoids most Swift 6 data-race errors. If Xcode forces Swift 6 mode, see "Concurrency" below.

## ChargeGuardCore (Packages/ChargeGuardCore)

Foundation only. Run `cd Packages/ChargeGuardCore && swift test` first: it is the fastest way to find logic errors.

Uncertain spots:
- `KeyedDecodingContainer.decode(_:forKey:default:)` is a custom overload (Support/CodingHelpers.swift). If the compiler picks the wrong overload, rename it to `decodeOrDefault`.
- `SimulatedSMC.init` uses a nested function that writes `keys` before `init` returns. Every stored property has a default value, so this should be allowed for a class; if not, move the setup to a `static func entries(for:)`.
- `PowermetricsParser.parsePlist` splits `Data` on NUL bytes with `Data.split(separator:)`.
- Tests compare `Date`s after a JSON round trip (`secondsSince1970`). Test clocks use whole seconds, so this is exact; real dates may differ in the last bit.
- `String(format:)` is only used with numeric arguments (`%ld`, `%.1f`, `%02x`), never `%@`, so Core also builds on Linux and Windows.

Logic to double-check against the brief while tests run:
- Hysteresis resumes at `pct < limit - hysteresis`; sailing resumes at `pct <= limit - range` (the brief words them differently: "falls below" and "falls to").
- Heat Protection blocks charging only; it does not stop a forced discharge (discharge adds no charge).
- Top Up ends at FullyCharged or unplug. Afterwards Automatic Discharge is held off until the adapter is unplugged or the limit changes, otherwise it would undo the top up at once. (Design choice, not in the brief.)
- "Restore normal charging" also turns charge control off (`controlEnabled = false`), otherwise the next tick would re-apply the limit. The user re-enables control from the pop-up.
- Conflict detection: an installed but stopped battery CLI (`/usr/local/co.palokaj.battery` exists, no process or label) is shown as information and does not block writes. A running process or a loaded label blocks.
- Calibration keeps the Mac awake (PreventUserIdleSystemSleep) in every phase, not only phase B, so the control loop keeps running through the holds.
- The "After macOS Calibration" stretch goal is **not implemented**.

## Real-hardware checks for Part B

- `BatterySnapshot.adapterPresent`: while ChargeGuard forces discharge with CHIE=08, does `ExternalConnected` turn false? The reader also uses `AppleRawExternalConnected`, `AdapterDetails` and the `AC-W` SMC key. If adapter presence flips while discharging, the engine stops discharging every other tick. Check with `chargectl status` while discharging.
- ACLC `00` = system default is unconfirmed (battery.sh says so). Verify the LED goes back to normal.
- Firmware limit keys (bfF0/bfD0/bfE0) are not expected on the M2 with macOS 15.5. Record the probe.
- PowermetricsParser fixtures are hand-written from the documented format. Capture real output (`sudo powermetrics --samplers tasks --show-process-energy -i 1000 -n 1` and the same with `-f plist`) and adjust the parser and the fixtures if the columns or plist keys differ (`energy_impact`, `energy_impact_per_s`, `cputime_ms_per_s`, `pid`, `name`).

## ChargeGuardSystem (Packages/ChargeGuardSystem)

Two targets: `ChargeGuardSystem` (IOKit, Security; used by the daemon, chargectl and the app) and `ChargeGuardSessionKit` (AppKit/NSWorkspace; app only, so the root daemon never links AppKit).

Uncertain APIs:
- `AppleSMC`: `IOConnectCallStructMethod(connection, 2, &input, stride, &output, &outputSize)` with inout-to-raw-pointer conversion. `AppleSMC.layoutProblem()` checks the 80-byte layout; `swift test` in this package runs it (`testParamStructLayout`). If it fails, fix the struct before anything else.
- `kIOReturnNotPrivileged` and the `kIOMessage...` sleep message values are spelled out as constants (0xE00002C1, 0xE0000270/280/290/300) because those macros may not import into Swift.
- IOPM assertion type names are string literals ("PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "PreventSystemSleep").
- `IOPSNotificationCreateRunLoopSource` and `IORegisterForSystemPower` use `@convention(c)` closures with `Unmanaged` context; check the closure types compile (`IOPowerSourceCallbackType`, `IOServiceInterestCallback`).
- `proc_listallpids`, `proc_name`, `proc_pidpath`, `proc_pid_rusage` come from `import Darwin` (libproc). If they do not resolve, add a bridging module map for `<libproc.h>`.
- `rusage_info_v4.ri_billed_energy` and the user/system times are in Mach ticks on Apple silicon; RusageSampler converts with `mach_timebase_info`. Check that the numbers look sane.
- `ConsoleUser.uid()` uses `stat("/dev/console")`. `launchctl asuser <uid> launchctl list` (root only) lists the GUI domain, where the battery CLI's LaunchAgent (`com.battery.app`) lives.
- `FileStateStore` writes state.json atomically and appends JSON lines with rotation at 2 MB.

Hardware checks:
- `AC-W` (adapter present), `PDTR` (input power, W) and `PPBR` (battery power) are read-only telemetry keys taken from batt's key list. Record whether they exist in docs/SMC-KEYS.md. They are never written.
- `PowerTelemetryData` (`SystemPowerIn`, `SystemLoad`, in mW) inside AppleSmartBattery: confirm the keys and units with `ioreg -rn AppleSmartBattery`.
- Temperature: `BatteryRegistryParser.celsius` reads hundredths of a degree Celsius. Compare with `ioreg -rn AppleSmartBattery | grep Temperature` and a known reading.
- `MachineInfo.firmwareVersion()` reads `boot_rom_version` from `system_profiler SPHardwareDataType -json` (shown as "System Firmware Version").

## ChargeGuardHelper (root daemon)

- Entry point `ChargeGuardHelper/main.swift` (top-level code, `RunLoop.main.run()`). Needs `CREATE_INFOPLIST_SECTION_IN_BINARY = YES` so `Bundle.main.infoDictionary` has the version and the code signature carries the identifier `com.amir.chargeguard.helper`.
- Client validation (`ClientValidator.swift`): the audit token is read with KVC (`connection.value(forKey: "auditToken")`), which is private API used by most privileged helpers. If it returns nil, the code falls back to the pid (racy, logged). `NSXPCConnection.setCodeSigningRequirement` (macOS 13+) is also applied when a Team ID exists.
- With ad-hoc signing there is no Team ID; validation falls back to an exact identifier match (com.amir.chargeguard or com.amir.chargeguard.chargectl) plus the executable path (`.../ChargeGuard.app/Contents/MacOS/ChargeGuard` or a binary named `chargectl`). Logged as weaker.
- `SecCSFlags(rawValue: kSecCSSigningInformation)`: if the constant's type does not match, use `SecCSFlags(rawValue: 1 << 1)`.
- SMAppService daemon plist: `ChargeGuardHelper/com.amir.chargeguard.helper.plist`, copied to `Contents/Library/LaunchDaemons/`; `BundleProgram` = `Contents/MacOS/ChargeGuardHelper`. Open questions to check on the Mac:
  - Does `SMAppService.daemon(...).register()` work with an ad-hoc signed app? If it fails (often error 1 "Operation not permitted" or the job is blocked), use `make install-helper` (scripts/install-helper.sh) during development.
  - Registration remembers the app's location: move ChargeGuard.app to /Applications before registering.
  - Do not use both install paths at once: they share the launchd label. `install-helper.sh` refuses to run while the app-registered (SMAppService) helper is loaded, and replaces an earlier fallback install.
- The daemon follows sleep with `IORegisterForSystemPower` (it cannot use NSWorkspace). `systemWillSleep` blocks the power change until the pre-sleep tick has written the keys.
- SIGTERM/SIGINT run `controller.shutdown`, which restores normal charging when ChargeGuard left keys modified, releases assertions and restores `pmset disablesleep`, then exits 0. `KeepAlive` is true, so launchd restarts the helper after a crash; on start it finds `keysDirty` and either keeps enforcing or restores (restore-on-quit mode or control off).

## ChargeGuard app

- `AppPreferences` (@Observable) keeps private tracked `stored…` properties behind computed get/set wrappers that write UserDefaults (no `didSet` on @Observable stored properties).
- `AppModel` and `HelperInstaller` are `@MainActor @Observable`; `AppDelegate` and `WindowOpener` are `@MainActor`. Timers and bookkeeping in AppModel are `@ObservationIgnored`. Transport callbacks hop to the main actor with `Task { @MainActor in }` (Swift 6 would need them `@Sendable`).
- `prepareForQuit()` blocks the main thread for up to 2 s with a semaphore while a detached task sends `appWillQuit`. If this deadlocks, send the command from `applicationShouldTerminate` and return `.terminateLater`.
- MenuBarExtra label: `HStack { Image(nsImage:) ; Text }`. If the label renders blank, use `Image(nsImage:)` only and put the percentage into the NSImage.
- `StatusIconRenderer` draws with `NSImage(size:flipped:drawingHandler:)` and SF Symbols with `NSImage.SymbolConfiguration(paletteColors:)`. SF Symbols used: bolt.fill, checkmark, wave.3.right, arrow.down, thermometer.medium, gauge.with.dots.needle.33percent, arrow.up, questionmark, exclamationmark, xmark, pause.fill, sailboat.fill, bolt.slash.fill, thermometer.high, checkmark.circle.fill, questionmark.circle, exclamationmark.triangle.fill. Check each renders.
- `SettingsLink` inside a MenuBarExtra window: the Settings window may open behind other windows; `NSApp.activate(ignoringOtherApps:)` is called through a simultaneous tap gesture. `WindowOpener` does the same for the Dashboard and the first-run window.
- The first-run window opens from `MenuBarLabel`'s `onChange(of: model.showOnboarding, initial: true)`. If the label view is not kept alive, move this to the pop-up's `onAppear`. Runtime check: the Dashboard or onboarding `Window` scene might open by itself at launch; `.defaultLaunchBehavior(.suppressed)` fixes that but needs macOS 15, so on macOS 14 close it in `applicationDidFinishLaunching` if it happens.
- `AppDelegate` handles `--unregister-helper` (used by uninstall.sh): it exits from the SMAppService completion handler with status 0 or 1, with a 10 s fallback, and never blocks the main thread. `--simulate` runs an in-process `ChargeController` (`InProcessTransport.simulated`, 60x time).
- App Intents (Dashboard/Intents agent notes): `static let description: IntentDescription?`; `@Parameter(title:description:default:inclusiveRange:)` for Int; `@Property(title:)` assigned in `init`; `IntentDialog("\(string)")`; `Summary(...) { \.$param }`. Set MagSafe LED is an intent but not an App Shortcut (limit of 10 shortcuts).
- Dashboard: `PowerFlowSankey` is `Animatable` with an `AnimatablePair`; `context.draw(Text, at:anchor:)` in Canvas; `Date().formatted(.iso8601.year().month().day())`; `NSWorkspace.openApplication(at:configuration:)`.
- The app is not sandboxed (it must open the AppleSMC user client and a privileged Mach service). Hardened runtime is on and there are no entitlements.
- Settings window (ChargeGuard/Settings): `ShortcutsLink()` was removed in review (not available on macOS); the Shortcuts tab opens the Shortcuts app with the `shortcuts://` URL. The 11 tabs are split into two `Group`s (6 + 5). Doubts: `Binding(get:set:)` closures reading main-actor state; the local `@Bindable var prefs` captured by `.onMove`; `try SMAppService.mainApp.unregister()` must pick the sync overload; `tabItem` may warn on the macOS 15 SDK (still needed for macOS 14). `@Bindable var prefs = model.preferences` declared inside `body`. `Table` with a Toggle column and `.contextMenu(forSelectionType:menu:primaryAction:)`. `ForEach($prefs.widgets) { $entry in }.onMove` inside a List in a grouped Form. `SMAppService.mainApp.unregister()` called synchronously (needs the sync overload). `SettingsPanels` runs `NSSavePanel/NSOpenPanel.runModal()` on the main actor. The window is 760x540 so the 11 tabs fit.
- The fast-calibration test toggle is hidden: hold Option while opening the Calibration tab (or it shows when fast mode is already on).

## A6 review notes (helper and System)

- Helper start order: signal handlers, then `controller.start()`, then `listener.resume()`, so no XPC command is handled before state.json is loaded.
- `AppleSMC.write` refuses any key outside `SMCKey.writableKeys` (second safeguard behind `GuardedSMCWriter`).
- `ProcessRunner` sends SIGKILL 2 s after a timeout's SIGTERM, so a hung `pmset` cannot block the control queue.
- `XPCHelperClient` re-subscribes for pushed status after the helper restarts; handlers of an old connection never clear a newer one.
- Swift pitfall fixed in several files: `var x: T?` followed by `guard let x else` in the same scope is a redeclaration error. Look for it first if the compiler reports "invalid redeclaration" or "definition conflicts with previous value".
- `AppleSMCLayoutTests` skips the probe test when AppleSMC cannot be opened (CI, VMs).
- Remaining doubts: libproc via `import Darwin`; `kSecCSSigningInformation` type; audit token through KVC; SMC result codes other than 0x84 map to `ioError`; rusage CPU-time units; PreventSystemSleep on battery.

## A6 review notes (build configuration)

- `project.yml` has never been run through XcodeGen. Run `xcodegen generate` (or `make project`) first and fix whatever it rejects.
- The embed script (`shell: /bin/bash`) declares the helper, chargectl and the launchd plist as inputs and must run before the app is signed. `make build` checks that all three are inside the bundle and runs `codesign --verify --deep --strict`.
- Tool dependencies use `link: false`; the run scheme uses `executable: ChargeGuard`.
- `scripts/signing.sh` parses the certificate subject with `openssl x509 -nameopt multiline` (LibreSSL on macOS); check it prints the Team ID.
- `uninstall.sh` unregisters the SMAppService helper by running `ChargeGuard --unregister-helper` as the console user (`launchctl asuser`), then boots out the job and restores the keys directly if the helper did not.

## A6 review notes (Core)

- Core tests were traced by hand; simulated timings fit their limits (full calibration about 9.7 h of 24 h, fast about 41 min of 90, discharge 90 to 70 % about 67 min).
- On start the controller scans for conflicts before any stale-state restore. Automatic restores are throttled like normal writes.
- While another charging tool runs, the helper refuses every write including "Restore normal charging" and `prepare-uninstall`; `sudo chargectl restore --direct` is the only override (it warns). `uninstall.sh` falls back to it.
- The adapter-cutoff backend never runs the battery below 5 %: at 5 % forced discharge stops and the cutoff releases, even during a heat pause.
- state.json is rewritten only when the state changes; the schedule's last-check time alone is checkpointed once a minute.
- Doubts: `PropertyListSerialization` returning `NSDictionary`/`NSNumber` on Linux/Windows; exact `Double` JSON round trips in `testStatusResponseRoundTrips`; Sendable warnings with a Swift 6 toolchain.
