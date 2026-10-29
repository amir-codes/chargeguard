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
