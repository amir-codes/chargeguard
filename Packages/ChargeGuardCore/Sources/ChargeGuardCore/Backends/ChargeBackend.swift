import Foundation

public enum BackendKind: String, Codable, CaseIterable, Sendable {
    case legacyKeys
    case firmwareLimit
    case adapterCutoff
    case simulated
    case none

    public var displayName: String {
        switch self {
        case .legacyKeys: return "Charge keys (CHTE / CH0B+CH0C)"
        case .firmwareLimit: return "Firmware charge limit (bfD0/bfE0)"
        case .adapterCutoff: return "Adapter cutoff (CHIE / CH0J / CH0I)"
        case .simulated: return "Simulated"
        case .none: return "None (unsupported)"
        }
    }
}

/// What the active backend can do. The policy engine adapts its decisions to it.
public struct BackendCapabilities: Codable, Equatable, Sendable {
    public var canInhibitCharging: Bool
    public var canForceDischarge: Bool
    /// Blocking charging is done by cutting the adapter (the battery discharges slowly instead of idling).
    public var inhibitIsAdapterCutoff: Bool
    public var usesFirmwareLimit: Bool
    public var canControlLED: Bool
    /// The limit keeps holding while the Mac sleeps (firmware limit only).
    public var enforcesDuringSleep: Bool

    public init(canInhibitCharging: Bool, canForceDischarge: Bool, inhibitIsAdapterCutoff: Bool,
                usesFirmwareLimit: Bool, canControlLED: Bool, enforcesDuringSleep: Bool) {
        self.canInhibitCharging = canInhibitCharging
        self.canForceDischarge = canForceDischarge
        self.inhibitIsAdapterCutoff = inhibitIsAdapterCutoff
        self.usesFirmwareLimit = usesFirmwareLimit
        self.canControlLED = canControlLED
        self.enforcesDuringSleep = enforcesDuringSleep
    }

    public static let legacy = BackendCapabilities(canInhibitCharging: true, canForceDischarge: true, inhibitIsAdapterCutoff: false,
                                                   usesFirmwareLimit: false, canControlLED: true, enforcesDuringSleep: false)
    public static let none = BackendCapabilities(canInhibitCharging: false, canForceDischarge: false, inhibitIsAdapterCutoff: false,
                                                 usesFirmwareLimit: false, canControlLED: false, enforcesDuringSleep: false)
}

/// Current values of the control keys, for the UI and diagnostics.
public struct BackendHardwareState: Codable, Equatable, Sendable {
    public var chargingInhibited: Bool?
    public var dischargeForced: Bool?
    public var ledRaw: UInt8?
    public var firmwareLimitActive: Bool?
    public var firmwareUpper: Int?
    public var firmwareLower: Int?

    public init(chargingInhibited: Bool? = nil, dischargeForced: Bool? = nil, ledRaw: UInt8? = nil,
                firmwareLimitActive: Bool? = nil, firmwareUpper: Int? = nil, firmwareLower: Int? = nil) {
        self.chargingInhibited = chargingInhibited
        self.dischargeForced = dischargeForced
        self.ledRaw = ledRaw
        self.firmwareLimitActive = firmwareLimitActive
        self.firmwareUpper = firmwareUpper
        self.firmwareLower = firmwareLower
    }
}

/// Translates policy outputs into SMC key writes.
public protocol ChargeBackend: AnyObject {
    var kind: BackendKind { get }
    var capabilities: BackendCapabilities { get }
    /// Shown in the UI (Advanced tab and pop-up footnote).
    var limitations: [String] { get }
    /// Makes the hardware match `outputs`. Throws on the first failed control write; LED failures are
    /// logged by the writer but never thrown.
    func apply(_ outputs: ControlOutputs, reason: String) throws -> [KeyWriteRecord]
    func readState() -> BackendHardwareState
    var writer: GuardedSMCWriter { get }
}

/// Helpers shared by the SMC backends.
enum BackendSupport {
    /// First usable discharge key in the brief's preference order: CHIE, CH0J, CH0I.
    static func dischargeKey(_ writer: GuardedSMCWriter) -> String? {
        SMCKey.dischargeKeys.first { writer.isUsable($0) }
    }

    /// CHTE when usable, else CH0B + CH0C when both are usable.
    static func inhibitKeys(_ writer: GuardedSMCWriter) -> [String] {
        if writer.isUsable(SMCKey.chargeInhibitTahoe) { return [SMCKey.chargeInhibitTahoe] }
        if writer.isUsable(SMCKey.chargeInhibitB) && writer.isUsable(SMCKey.chargeInhibitC) {
            return [SMCKey.chargeInhibitB, SMCKey.chargeInhibitC]
        }
        return []
    }

    static func setInhibit(_ inhibit: Bool, keys: [String], writer: GuardedSMCWriter, reason: String) throws -> [KeyWriteRecord] {
        var records: [KeyWriteRecord] = []
        for key in keys {
            let value: [UInt8]
            if key == SMCKey.chargeInhibitTahoe {
                value = inhibit ? SMCValue.chteInhibit : SMCValue.chteAllow
            } else {
                value = inhibit ? SMCValue.ch0bcInhibit : SMCValue.ch0bcAllow
            }
            if let r = try writer.ensure(key, value, reason: reason) { records.append(r) }
        }
        return records
    }

    static func setDischarge(_ on: Bool, key: String, writer: GuardedSMCWriter, reason: String) throws -> [KeyWriteRecord] {
        let value = on ? (SMCValue.dischargeOn(for: key) ?? SMCValue.dischargeOff) : SMCValue.dischargeOff
        if let r = try writer.ensure(key, value, reason: reason) { return [r] }
        return []
    }

    /// LED writes never fail the tick: a broken LED must not stop charge control.
    static func setLED(_ led: LEDState?, writer: GuardedSMCWriter, reason: String) -> [KeyWriteRecord] {
        guard let led, writer.isUsable(SMCKey.magSafeLED) else { return [] }
        if let r = try? writer.ensure(SMCKey.magSafeLED, SMCValue.led(led), reason: reason) { return [r] }
        return []
    }

    static func readInhibit(_ writer: GuardedSMCWriter) -> Bool? {
        let keys = inhibitKeys(writer)
        guard let first = keys.first, let bytes = try? writer.io.read(first) else { return nil }
        return bytes.contains { $0 != 0 }
    }

    static func readDischarge(_ writer: GuardedSMCWriter) -> Bool? {
        guard let key = dischargeKey(writer), let bytes = try? writer.io.read(key) else { return nil }
        return bytes.contains { $0 != 0 }
    }

    static func readLED(_ writer: GuardedSMCWriter) -> UInt8? {
        guard writer.isUsable(SMCKey.magSafeLED), let bytes = try? writer.io.read(SMCKey.magSafeLED) else { return nil }
        return bytes.first
    }
}

/// CHTE or CH0B/CH0C for charging, CHIE/CH0J/CH0I for discharge.
public final class LegacyKeysBackend: ChargeBackend {
    public let writer: GuardedSMCWriter
    public let kind: BackendKind

    public init?(writer: GuardedSMCWriter, kind: BackendKind = .legacyKeys) {
        guard !BackendSupport.inhibitKeys(writer).isEmpty else { return nil }
        self.writer = writer
        self.kind = kind
    }

    public var capabilities: BackendCapabilities {
        BackendCapabilities(canInhibitCharging: true,
                            canForceDischarge: BackendSupport.dischargeKey(writer) != nil,
                            inhibitIsAdapterCutoff: false,
                            usesFirmwareLimit: false,
                            canControlLED: writer.isUsable(SMCKey.magSafeLED),
                            enforcesDuringSleep: false)
    }

    public var limitations: [String] {
        var notes = ["The limit is enforced while the Mac is awake. During sleep nothing can stop charging that already started; use Stop Charging when Sleeping."]
        if BackendSupport.dischargeKey(writer) == nil { notes.append("No discharge key found: Discharge is unavailable.") }
        return notes
    }

    public func apply(_ outputs: ControlOutputs, reason: String) throws -> [KeyWriteRecord] {
        var records: [KeyWriteRecord] = []
        let inhibitKeys = BackendSupport.inhibitKeys(writer)
        let dischargeKey = BackendSupport.dischargeKey(writer)
        if outputs.forceDischarge, let dk = dischargeKey {
            // Block charging first, then cut the adapter.
            records += try BackendSupport.setInhibit(true, keys: inhibitKeys, writer: writer, reason: reason)
            records += try BackendSupport.setDischarge(true, key: dk, writer: writer, reason: reason)
        } else {
            // Reconnect the adapter first, then set charging.
            if let dk = dischargeKey {
                records += try BackendSupport.setDischarge(false, key: dk, writer: writer, reason: reason)
            }
            records += try BackendSupport.setInhibit(outputs.inhibitCharging, keys: inhibitKeys, writer: writer, reason: reason)
        }
        records += BackendSupport.setLED(outputs.led, writer: writer, reason: reason)
        return records
    }

    public func readState() -> BackendHardwareState {
        BackendHardwareState(chargingInhibited: BackendSupport.readInhibit(writer),
                             dischargeForced: BackendSupport.readDischarge(writer),
                             ledRaw: BackendSupport.readLED(writer))
    }
}

/// Firmware-managed limit (bfF0 activation, bfD0 upper %, bfE0 lower %), per batt's firmware mode:
/// the firmware runs the hysteresis itself, also during sleep. Writes go bfF0=00, bfD0, bfE0, bfF0=02.
public final class FirmwareLimitBackend: ChargeBackend {
    public let writer: GuardedSMCWriter
    public let kind: BackendKind = .firmwareLimit

    public init?(writer: GuardedSMCWriter) {
        guard SMCKey.firmwareKeys.allSatisfy({ writer.isUsable($0) }) else { return nil }
        self.writer = writer
    }

    public var capabilities: BackendCapabilities {
        BackendCapabilities(canInhibitCharging: true,
                            canForceDischarge: BackendSupport.dischargeKey(writer) != nil,
                            inhibitIsAdapterCutoff: false,
                            usesFirmwareLimit: true,
                            canControlLED: writer.isUsable(SMCKey.magSafeLED),
                            enforcesDuringSleep: true)
    }

    public var limitations: [String] {
        ["The firmware decides when charging resumes inside the band; short pauses (heat, sleep) move the firmware limit to the current level."]
    }

    /// The (lower, upper) pair to program, or nil to deactivate the firmware limit.
    public static func target(for outputs: ControlOutputs) -> (lower: Int, upper: Int)? {
        if let hold = outputs.holdAtPercentage, outputs.inhibitCharging {
            let upper = hold.clamped(to: 1...100)
            return (max(0, upper - 1), upper)
        }
        guard outputs.chargeCeiling < 100 else { return nil }
        let upper = outputs.chargeCeiling.clamped(to: 1...99)
        let lower = min(outputs.resumeFloor, upper - 1).clamped(to: 0...(upper - 1))
        return (lower, upper)
    }

    public func apply(_ outputs: ControlOutputs, reason: String) throws -> [KeyWriteRecord] {
        var records: [KeyWriteRecord] = []
        let dischargeKey = BackendSupport.dischargeKey(writer)
        if !outputs.forceDischarge, let dk = dischargeKey {
            records += try BackendSupport.setDischarge(false, key: dk, writer: writer, reason: reason)
        }
        if let target = Self.target(for: outputs) {
            let state = readState()
            let correct = state.firmwareLimitActive == true && state.firmwareUpper == target.upper && state.firmwareLower == target.lower
            if !correct {
                if let r = try writer.ensure(SMCKey.firmwareActivation, SMCValue.firmwareInactive, reason: reason) { records.append(r) }
                if let r = try writer.ensure(SMCKey.firmwareUpper, SMCValue.firmwarePercent(target.upper), reason: reason) { records.append(r) }
                if let r = try writer.ensure(SMCKey.firmwareLower, SMCValue.firmwarePercent(target.lower), reason: reason) { records.append(r) }
                if let r = try writer.ensure(SMCKey.firmwareActivation, SMCValue.firmwareActive, reason: reason) { records.append(r) }
            }
        } else {
            if let r = try writer.ensure(SMCKey.firmwareActivation, SMCValue.firmwareInactive, reason: reason) { records.append(r) }
        }
        if outputs.forceDischarge, let dk = dischargeKey {
            records += try BackendSupport.setDischarge(true, key: dk, writer: writer, reason: reason)
        }
        records += BackendSupport.setLED(outputs.led, writer: writer, reason: reason)
        return records
    }

    public func readState() -> BackendHardwareState {
        let active = (try? writer.io.read(SMCKey.firmwareActivation))?.first.map { $0 == 0x02 }
        let upper = (try? writer.io.read(SMCKey.firmwareUpper)).flatMap(SMCValue.decodeFirmwarePercent)
        let lower = (try? writer.io.read(SMCKey.firmwareLower)).flatMap(SMCValue.decodeFirmwarePercent)
        return BackendHardwareState(chargingInhibited: nil,
                                    dischargeForced: BackendSupport.readDischarge(writer),
                                    ledRaw: BackendSupport.readLED(writer),
                                    firmwareLimitActive: active, firmwareUpper: upper, firmwareLower: lower)
    }
}

/// Holds the limit by cutting wall power with the discharge (adapter) key, with hysteresis.
/// Used when the charge keys are absent or gated (kIOReturnNotPrivileged). Awake-only.
public final class AdapterCutoffBackend: ChargeBackend {
    public let writer: GuardedSMCWriter
    public let kind: BackendKind = .adapterCutoff

    public init?(writer: GuardedSMCWriter) {
        guard BackendSupport.dischargeKey(writer) != nil else { return nil }
        self.writer = writer
    }

    public var capabilities: BackendCapabilities {
        BackendCapabilities(canInhibitCharging: true,
                            canForceDischarge: true,
                            inhibitIsAdapterCutoff: true,
                            usesFirmwareLimit: false,
                            canControlLED: writer.isUsable(SMCKey.magSafeLED),
                            enforcesDuringSleep: false)
    }

    public var limitations: [String] {
        ["Charging cannot be paused directly on this Mac. ChargeGuard holds the limit by switching the Mac to battery power at the limit and back to the adapter a few percent lower, so the battery cycles within a small band.",
         "This only works while the Mac is awake. Before sleep the adapter is reconnected, so the battery may charge past the limit while asleep."]
    }

    public func apply(_ outputs: ControlOutputs, reason: String) throws -> [KeyWriteRecord] {
        guard let dk = BackendSupport.dischargeKey(writer) else { return [] }
        let cut = outputs.forceDischarge || outputs.inhibitCharging
        var records = try BackendSupport.setDischarge(cut, key: dk, writer: writer, reason: reason)
        records += BackendSupport.setLED(outputs.led, writer: writer, reason: reason)
        return records
    }

    public func readState() -> BackendHardwareState {
        let cut = BackendSupport.readDischarge(writer)
        return BackendHardwareState(chargingInhibited: cut, dischargeForced: cut, ledRaw: BackendSupport.readLED(writer))
    }
}

/// The legacy key mapping running on `SimulatedSMC`. Used by unit tests and `--simulate`.
public final class SimulatedBackend: ChargeBackend {
    private let inner: LegacyKeysBackend
    public let kind: BackendKind = .simulated
    public var writer: GuardedSMCWriter { inner.writer }

    public init?(writer: GuardedSMCWriter) {
        guard writer.io is SimulatedSMC, let inner = LegacyKeysBackend(writer: writer, kind: .simulated) else { return nil }
        self.inner = inner
    }

    public var capabilities: BackendCapabilities { inner.capabilities }
    public var limitations: [String] { ["Simulation: no real SMC keys are touched."] }

    public func apply(_ outputs: ControlOutputs, reason: String) throws -> [KeyWriteRecord] {
        try inner.apply(outputs, reason: reason)
    }

    public func readState() -> BackendHardwareState { inner.readState() }
}
