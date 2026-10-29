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
- With ad-hoc signing there is no Team ID; validation falls back to the identifier prefix plus the executable path (`.../ChargeGuard.app/Contents/MacOS/ChargeGuard` or a binary named `chargectl`). Logged as weaker.
- `SecCSFlags(rawValue: kSecCSSigningInformation)`: if the constant's type does not match, use `SecCSFlags(rawValue: 1 << 1)`.
- SMAppService daemon plist: `ChargeGuardHelper/com.amir.chargeguard.helper.plist`, copied to `Contents/Library/LaunchDaemons/`; `BundleProgram` = `Contents/MacOS/ChargeGuardHelper`. Open questions to check on the Mac:
  - Does `SMAppService.daemon(...).register()` work with an ad-hoc signed app? If it fails (often error 1 "Operation not permitted" or the job is blocked), use `make install-helper` (scripts/install-helper.sh) during development.
  - Registration remembers the app's location: move ChargeGuard.app to /Applications before registering.
  - Do not use both install paths at once: they share the launchd label. `install-helper.sh` boots out an existing job first.
- The daemon follows sleep with `IORegisterForSystemPower` (it cannot use NSWorkspace). `systemWillSleep` blocks the power change until the pre-sleep tick has written the keys.
- SIGTERM/SIGINT run `controller.shutdown`, which restores normal charging when ChargeGuard left keys modified, releases assertions and restores `pmset disablesleep`, then exits 0. `KeepAlive` is true, so launchd restarts the helper after a crash; on start it finds `keysDirty` and either keeps enforcing or restores (restore-on-quit mode or control off).

## ChargeGuard app

- `@Observable` classes with `didSet` on stored properties (AppPreferences). If the macro rejects the observers, move the persistence into explicit setter methods.
- `AppModel` and `HelperInstaller` are `@MainActor @Observable`. `AppModel.shared` is a `static let` on a main-actor class; `AppDelegate.applicationWillTerminate` uses `MainActor.assumeIsolated` (macOS 14).
- `prepareForQuit()` blocks the main thread for up to 2 s with a semaphore while a detached task sends `appWillQuit`. If this deadlocks, send the command from `applicationShouldTerminate` and return `.terminateLater`.
- MenuBarExtra label: `HStack { Image(nsImage:) ; Text }`. If the label renders blank, use `Image(nsImage:)` only and put the percentage into the NSImage.
- `StatusIconRenderer` draws with `NSImage(size:flipped:drawingHandler:)` and SF Symbols with `NSImage.SymbolConfiguration(paletteColors:)`. SF Symbols used: bolt.fill, checkmark, wave.3.right, arrow.down, thermometer.medium, gauge.with.dots.needle.33percent, arrow.up, questionmark, exclamationmark, xmark, pause.fill, sailboat.fill, bolt.slash.fill, thermometer.high, checkmark.circle.fill, questionmark.circle, exclamationmark.triangle.fill. Check each renders.
- `SettingsLink` inside a MenuBarExtra window: the Settings window may open behind other windows; `NSApp.activate(ignoringOtherApps:)` is called through a simultaneous tap gesture. `WindowOpener` does the same for the Dashboard and the first-run window.
- The first-run window opens from `MenuBarLabel`'s `onChange(of: model.showOnboarding)`. If the label view is not kept alive, move this to the pop-up's `onAppear`, or call `openWindow` from `applicationDidFinishLaunching` through an `NSWindow`.
- `AppDelegate` handles `--unregister-helper` (used by uninstall.sh) and exits; `--simulate` runs an in-process `ChargeController` (`InProcessTransport.simulated`, 60x time).
- App Intents (Dashboard/Intents agent notes): `static let description: IntentDescription?`; `@Parameter(title:description:default:inclusiveRange:)` for Int; `@Property(title:)` assigned in `init`; `IntentDialog("\(string)")`; `Summary(...) { \.$param }`. Set MagSafe LED is an intent but not an App Shortcut (limit of 10 shortcuts).
- Dashboard: `PowerFlowSankey` is `Animatable` with an `AnimatablePair`; `context.draw(Text, at:anchor:)` in Canvas; `Date().formatted(.iso8601.year().month().day())`; `NSWorkspace.openApplication(at:configuration:)`.
- The app is not sandboxed (it must open the AppleSMC user client and a privileged Mach service). Hardened runtime is on and there are no entitlements.
- Settings window (ChargeGuard/Settings): `ShortcutsLink()` may be unavailable on macOS; if so, delete it (an "Open Shortcuts" button with the `shortcuts://` URL is next to it). `@Bindable var prefs = model.preferences` declared inside `body`. `Table` with a Toggle column and `.contextMenu(forSelectionType:menu:primaryAction:)`. `ForEach($prefs.widgets) { $entry in }.onMove` inside a List in a grouped Form. `SMAppService.mainApp.unregister()` called synchronously (needs the sync overload). `SettingsPanels` runs `NSSavePanel/NSOpenPanel.runModal()` on the main actor. The window is 760x540 so the 11 tabs fit.
- The fast-calibration test toggle is hidden: hold Option while opening the Calibration tab (or it shows when fast mode is already on).
