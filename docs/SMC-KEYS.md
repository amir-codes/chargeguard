# SMC keys on this Mac

Template written in Part A. Fill it in during Part B, phase B2 (read-only probe, no writes), then update it whenever a write test confirms or contradicts a value.

Keys are selected by presence, never by macOS version or chip name. A key is present when `keyInfo` succeeds with a non-zero size and a read does not report "no data" (`KeyProber` in ChargeGuardCore). ChargeGuard writes only the keys and values in this table (`SMCKeys.swift`), and only after the probe confirmed the key.

## Machine

| Field | Value | Command |
|---|---|---|
| Model | | `sysctl hw.model` |
| Chip | | `sysctl -n machdep.cpu.brand_string` |
| macOS version and build | | `sw_vers` |
| System Firmware Version | | `system_profiler SPHardwareDataType \| grep -i firmware` |
| OS Loader Version | | same |
| Probe date | | |
| ChargeGuard version | | `chargectl version` |

## Keys

| Key | Purpose | Source | Activate | Deactivate | Present? | Size | Type | Value at probe | Notes |
|---|---|---|---|---|---|---|---|---|---|
| CHTE | Block charging (preferred) | battery.sh v1.3.4 | `01000000` | `00000000` | | | | | 4 bytes expected |
| CH0B | Block charging (fallback, always with CH0C) | battery.sh | `02` | `00` | | | | | |
| CH0C | Block charging (fallback, always with CH0B) | battery.sh | `02` | `00` | | | | | |
| CHIE | Force discharge / cut adapter (preferred) | battery.sh | `08` | `00` | | | | | |
| CH0J | Force discharge (fallback 1) | battery.sh | `01` | `00` | | | | | |
| CH0I | Force discharge (fallback 2) | battery.sh | `01` | `00` | | | | | |
| ACLC | MagSafe LED | battery.sh, batt | `03` green, `04` orange, `01` off | `00` system default (unconfirmed) | | | | | |
| bfF0 | Firmware limit activation | batt (facts) | `02` | `00` | | | | | Only on newer firmware |
| bfD0 | Firmware limit upper % | batt (facts) | ui32 little-endian, 80 % = `50000000` | — | | | | | Written only with bfF0 |
| bfE0 | Firmware limit lower % | batt (facts) | ui32 little-endian, 75 % = `4b000000` | — | | | | | Written only with bfF0 |
| AC-W | Adapter present (read only) | batt key list | — | — | | | | | Never written; used for adapter presence |
| PDTR | DC input power, W (read only) | batt key list | — | — | | | | | Never written; Power Flow fallback |
| PPBR | Battery power, W (read only) | batt key list | — | — | | | | | Never written |

Firmware limit write order (from batt): `bfF0 = 00`, `bfD0 = upper`, `bfE0 = lower`, `bfF0 = 02`. Lower must be below upper.

## `chargectl probe` output

Paste the full output here (B2, before any write):

```
(paste here)
```

Selected backend at probe time (`chargectl status`): ____

## Known firmware fragility

On macOS 27 Developer Beta 4 firmware and later (System Firmware 20457.0.125.0.2 and newer, reportedly also shipped in some macOS 15.x and 26.x security updates), the charge keys (`CHTE`, `CH0B`, `CH0C`) return `kIOReturnNotPrivileged` even to root, because Apple gated them behind the private entitlement `com.apple.private.iokit.soc-limit`. The adapter (discharge) key still works. ChargeGuard handles this at runtime: the first failed write marks the key not privileged and the controller fails over to the FirmwareLimit backend (when `bfF0`, `bfD0`, `bfE0` exist) or the AdapterCutoff backend (any discharge key). Record here whether this Mac's firmware is affected:

- Firmware version: ____
- Charge-key write result (B3): ____ (ok / kIOReturnNotPrivileged)
- Backend in use after B3: ____

Apple's own charge limit in System Settings (macOS 26.4 and later, 80 to 100 %) is not available on this Mac (macOS 15.5).

## Verification items

- [ ] `ACLC = 00` returns the MagSafe LED to the system default behaviour (battery.sh marks this as unconfirmed). Result: ____
- [ ] Adapter presence while `CHIE = 08` (or `CH0J`/`CH0I = 01`): `ExternalConnected` = ____, `AppleRawExternalConnected` = ____, `AdapterDetails.Watts` = ____, `AC-W` = ____. ChargeGuard's `adapterPresent` must stay true while discharging, otherwise discharge flaps every other tick.
- [ ] `CHTE` survives sleep (blocked before sleep, still blocked on wake). Result: ____
- [ ] Keys reset by a reboot (block charging, reboot, read again). Result: ____
- [ ] `PowerTelemetryData` keys in `ioreg -rn AppleSmartBattery` (`SystemPowerIn`, `SystemLoad`, units mW): ____
- [ ] Battery `Temperature` raw value ____ = ____ °C (ChargeGuard reads hundredths of a degree Celsius).
