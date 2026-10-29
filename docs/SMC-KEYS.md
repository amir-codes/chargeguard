# SMC keys on this Mac

Filled in during Part B, phase B2 (read-only probe, no writes) on 2026-10-30. Updated whenever a write test confirms or contradicts a value.

Keys are selected by presence, never by macOS version or chip name. A key is present when `keyInfo` succeeds with a non-zero size and a read does not report "no data" (`KeyProber` in ChargeGuardCore). ChargeGuard writes only the keys and values in this table (`SMCKeys.swift`), and only after the probe confirmed the key.

## Machine

| Field | Value | Command |
|---|---|---|
| Model | Mac14,2 (MacBook Air M2) | `sysctl hw.model` |
| Chip | Apple M2 | `sysctl -n machdep.cpu.brand_string` |
| macOS version and build | 15.5 (24F74) | `sw_vers` |
| System Firmware Version | 11881.121.1 | `system_profiler SPHardwareDataType \| grep -i firmware` |
| OS Loader Version | 11881.121.1 | same |
| Probe date | 2026-10-30, battery 66 %, on battery power (no adapter) | |
| ChargeGuard version | 1.0.0, protocol 1 | `chargectl version` |

## Keys

| Key | Purpose | Source | Activate | Deactivate | Present? | Size | Type | Value at probe | Notes |
|---|---|---|---|---|---|---|---|---|---|
| CHTE | Block charging (preferred) | battery.sh v1.3.4 | `01000000` | `00000000` | yes | 4 | ui32 | `00000000` | 4 bytes as expected |
| CH0B | Block charging (fallback, always with CH0C) | battery.sh | `02` | `00` | yes | 1 | hex_ | `00` | |
| CH0C | Block charging (fallback, always with CH0B) | battery.sh | `02` | `00` | yes | 1 | hex_ | `00` | |
| CHIE | Force discharge / cut adapter (preferred) | battery.sh | `08` | `00` | yes | 1 | hex_ | `00` | |
| CH0J | Force discharge (fallback 1) | battery.sh | `01` | `00` | yes | 1 | ui8 | `00` | |
| CH0I | Force discharge (fallback 2) | battery.sh | `01` | `00` | yes | 1 | ui8 | `00` | |
| ACLC | MagSafe LED | battery.sh, batt | `03` green, `04` orange, `01` off | `00` system default (unconfirmed) | yes | 1 | ui8 | `04` | **`04` was already there while unplugged, before any ChargeGuard write.** So the system itself may use `04`, and `00` as "system default" needs the B7 check. |
| bfF0 | Firmware limit activation | batt (facts) | `02` | `00` | no | — | — | — | Not on this firmware (11881.121.1) |
| bfD0 | Firmware limit upper % | batt (facts) | ui32 little-endian, 80 % = `50000000` | — | no | — | — | — | |
| bfE0 | Firmware limit lower % | batt (facts) | ui32 little-endian, 75 % = `4b000000` | — | no | — | — | — | |
| AC-W | Adapter present (read only) | batt key list | — | — | yes | 1 | si8 | `ff` | `ff` = −1 while unplugged. Never written. |
| PDTR | DC input power, W (read only) | batt key list | — | — | yes | 4 | flt | `46180c39` | Little-endian float: 0x390c1846 ≈ 0.0001 W while unplugged. Never written. |
| PPBR | Battery power, W (read only) | batt key list | — | — | yes | 4 | flt | `c7678b41` | Little-endian float: 0x418b67c7 ≈ 17.4 W, matches 11.54 V × 1.384 A discharge. Never written. |

Firmware limit write order (from batt): `bfF0 = 00`, `bfD0 = upper`, `bfE0 = lower`, `bfF0 = 02`. Lower must be below upper. Not applicable on this Mac.

## `chargectl probe` output

Full output of `build/chargectl probe --direct` (B2, helper not installed, reads only), 2026-10-30:

```
CHTE  present  size 4  type 'ui32'  value 00000000
CH0B  present  size 1  type 'hex_'  value 00
CH0C  present  size 1  type 'hex_'  value 00
CHIE  present  size 1  type 'hex_'  value 00
CH0J  present  size 1  type 'ui8 '  value 00
CH0I  present  size 1  type 'ui8 '  value 00
ACLC  present  size 1  type 'ui8 '  value 04
bfF0  absent  (SMC key bfF0 not found)
bfD0  absent  (SMC key bfD0 not found)
bfE0  absent  (SMC key bfE0 not found)
AC-W  present  size 1  type 'si8 '  value ff
PDTR  present  size 4  type 'flt '  value 46180c39
PPBR  present  size 4  type 'flt '  value c7678b41
```

`build/chargectl status --direct` at the same time: `Battery: 66 % (hardware 62.7 %), 30.5 °C, 11.54 V, -1384 mA, charging no, external power no, adapter present no`. Matches `ioreg -rn AppleSmartBattery`: CurrentCapacity 66, AppleRawCurrentCapacity 2420 / AppleRawMaxCapacity 3861 = 62.7 %, Temperature 3049, Voltage 11539, Amperage −1384 (reported unsigned-wrapped as 18446744073709550232 and decoded correctly), IsCharging No, ExternalConnected No, CycleCount 344, DesignCapacity 4563.

Selected backend once the helper runs (B3, `chargectl status`): ____

## Known firmware fragility

On macOS 27 Developer Beta 4 firmware and later (System Firmware 20457.0.125.0.2 and newer, reportedly also shipped in some macOS 15.x and 26.x security updates), the charge keys (`CHTE`, `CH0B`, `CH0C`) return `kIOReturnNotPrivileged` even to root, because Apple gated them behind the private entitlement `com.apple.private.iokit.soc-limit`. The adapter (discharge) key still works. ChargeGuard handles this at runtime: the first failed write marks the key not privileged and the controller fails over to the FirmwareLimit backend (when `bfF0`, `bfD0`, `bfE0` exist) or the AdapterCutoff backend (any discharge key). This Mac:

- Firmware version: 11881.121.1 (far below the gated 20457 series; all charge keys present with normal sizes)
- Charge-key write result (B3): ____ (ok / kIOReturnNotPrivileged)
- Backend in use after B3: ____

Apple's own charge limit in System Settings (macOS 26.4 and later, 80 to 100 %) is not available on this Mac (macOS 15.5).

## Verification items

- [ ] `ACLC = 00` returns the MagSafe LED to the system default behaviour (battery.sh marks this as unconfirmed). Note: the probe found `ACLC = 04` while unplugged with no ChargeGuard write ever made. Result: ____
- [ ] Adapter presence while `CHIE = 08` (or `CH0J`/`CH0I = 01`): `ExternalConnected` = ____, `AppleRawExternalConnected` = ____, `AdapterDetails.Watts` = ____, `AC-W` = ____. ChargeGuard's `adapterPresent` must stay true while discharging, otherwise discharge flaps every other tick.
- [ ] `CHTE` survives sleep (blocked before sleep, still blocked on wake). Result: ____
- [ ] Keys reset by a reboot (block charging, reboot, read again). Result: ____
- [x] `PowerTelemetryData` keys in `ioreg -rn AppleSmartBattery`: `SystemLoad` = 15969, `SystemPowerIn` = 0, `SystemCurrentIn` = 0, `SystemVoltageIn` = 0, `BatteryPower` = 18446744073709535647 (negative, unsigned-wrapped), plus accumulators. Units mW: SystemLoad 15.97 W ≈ 11.54 V × 1.384 A = 15.97 W. Confirmed 2026-10-30 (unplugged; `SystemPowerIn` to be re-read with the adapter).
- [x] Battery `Temperature` raw value 3049 = 30.49 °C. ChargeGuard reads hundredths of a degree Celsius (`BatteryRegistryParser.celsius`), which is correct; the brief's "hundredths of a kelvin" was wrong and section 4 of `BATTERY_APP_PROMPT.md` was corrected in B2. `chargectl status` shows 30.5 °C.
