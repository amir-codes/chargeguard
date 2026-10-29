import Foundation

// SMC key names and byte values for Apple silicon.
//
// Sources (see THIRD_PARTY_NOTICES.md and docs/SMC-KEYS.md):
// - actuallymentor/battery, battery.sh v1.3.4 (MIT): CHTE, CH0B/CH0C, CHIE, CH0J, CH0I, ACLC values
//   and key-presence detection.
// - charlie0129/batt README and key list (GPL-2.0, facts only, no code): firmware charge-limit keys
//   bfF0/bfD0/bfE0, their little-endian ui32 encoding and write order, and read-only telemetry keys.
//
// Never add a key or value here that does not come from those sources (BATTERY_APP_PROMPT.md section 5).
// Every write goes through `GuardedSMCWriter`, which refuses keys that the probe did not confirm.

public enum SMCKey {
    // Block charging. CHTE (4 bytes) preferred, else CH0B + CH0C (1 byte each, always both).
    public static let chargeInhibitTahoe = "CHTE"
    public static let chargeInhibitB = "CH0B"
    public static let chargeInhibitC = "CH0C"

    // Force discharge (cut the adapter). Preference order CHIE, CH0J, CH0I.
    public static let dischargeCHIE = "CHIE"
    public static let dischargeCH0J = "CH0J"
    public static let dischargeCH0I = "CH0I"

    // MagSafe LED.
    public static let magSafeLED = "ACLC"

    // Firmware charge limit (macOS 27-era firmware), only when bfF0 exists.
    public static let firmwareActivation = "bfF0"
    public static let firmwareUpper = "bfD0"
    public static let firmwareLower = "bfE0"

    // Read-only telemetry (never written).
    public static let acPower = "AC-W"
    public static let dcInPower = "PDTR"
    public static let batteryPower = "PPBR"

    public static let chargeKeys = [chargeInhibitTahoe, chargeInhibitB, chargeInhibitC]
    public static let dischargeKeys = [dischargeCHIE, dischargeCH0J, dischargeCH0I]
    public static let firmwareKeys = [firmwareActivation, firmwareUpper, firmwareLower]
    public static let telemetryKeys = [acPower, dcInPower, batteryPower]

    /// Every key ChargeGuard may write.
    public static let writableKeys: Set<String> = Set(chargeKeys + dischargeKeys + firmwareKeys + [magSafeLED])

    /// Every key `chargectl probe` reports.
    public static let probeKeys: [String] = chargeKeys + dischargeKeys + [magSafeLED] + firmwareKeys + telemetryKeys
}

public enum SMCValue {
    // CHTE
    public static let chteInhibit: [UInt8] = [0x01, 0x00, 0x00, 0x00]
    public static let chteAllow: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    // CH0B and CH0C
    public static let ch0bcInhibit: [UInt8] = [0x02]
    public static let ch0bcAllow: [UInt8] = [0x00]
    // Discharge keys
    public static let chieOn: [UInt8] = [0x08]
    public static let ch0jOn: [UInt8] = [0x01]
    public static let ch0iOn: [UInt8] = [0x01]
    public static let dischargeOff: [UInt8] = [0x00]
    // ACLC. 0x00 "system default" is marked unconfirmed by battery.sh: verify on the Mac (docs/SMC-KEYS.md).
    public static let ledSystem: [UInt8] = [0x00]
    public static let ledOff: [UInt8] = [0x01]
    public static let ledGreen: [UInt8] = [0x03]
    public static let ledOrange: [UInt8] = [0x04]
    // bfF0
    public static let firmwareInactive: [UInt8] = [0x00]
    public static let firmwareActive: [UInt8] = [0x02]

    public static func dischargeOn(for key: String) -> [UInt8]? {
        switch key {
        case SMCKey.dischargeCHIE: return chieOn
        case SMCKey.dischargeCH0J: return ch0jOn
        case SMCKey.dischargeCH0I: return ch0iOn
        default: return nil
        }
    }

    public static func led(_ state: LEDState) -> [UInt8] {
        switch state {
        case .system: return ledSystem
        case .off: return ledOff
        case .green: return ledGreen
        case .orange: return ledOrange
        }
    }

    /// bfD0/bfE0 hold a ui32 percentage stored little-endian (80 % = 50 00 00 00), per batt.
    public static func firmwarePercent(_ percent: Int) -> [UInt8] {
        let p = UInt32(percent.clamped(to: 0...100))
        return [UInt8(p & 0xff), UInt8((p >> 8) & 0xff), UInt8((p >> 16) & 0xff), UInt8((p >> 24) & 0xff)]
    }

    public static func decodeFirmwarePercent(_ bytes: [UInt8]) -> Int? {
        guard bytes.count == 4 else { return nil }
        let b0 = UInt32(bytes[0]), b1 = UInt32(bytes[1]) << 8, b2 = UInt32(bytes[2]) << 16, b3 = UInt32(bytes[3]) << 24
        let value: UInt32 = b0 | b1 | b2 | b3
        return Int(value)
    }
}
