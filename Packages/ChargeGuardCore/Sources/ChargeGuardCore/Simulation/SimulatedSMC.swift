import Foundation

/// In-memory SMC used by unit tests and `--simulate`. Thread-safe.
public final class SimulatedSMC: SMCKeyIO {
    /// Key sets that mimic the firmware generations the backends are written for.
    public enum Profile: String, CaseIterable, Sendable {
        /// CHTE + CHIE + ACLC (current Apple silicon firmware).
        case tahoe
        /// CH0B + CH0C + CH0I + CH0J + ACLC (older firmware).
        case legacy
        /// macOS 27-era firmware: charge keys present but gated, firmware limit keys and CHIE usable.
        case firmwareGated
        /// Only an adapter key: charge keys absent.
        case adapterOnly
        /// No control keys at all.
        case unsupported
    }

    private struct Entry {
        var info: SMCKeyInfo
        var bytes: [UInt8]
    }

    private let lock = NSLock()
    private var keys: [String: Entry] = [:]
    /// Keys whose writes fail with kIOReturnNotPrivileged.
    public private(set) var gatedKeys: Set<String> = []
    /// Every successful write, in order (for tests).
    public private(set) var writeLog: [(key: String, bytes: [UInt8])] = []
    public var failAllWrites = false

    public init(profile: Profile = .tahoe) {
        func add(_ key: String, _ type: String, _ bytes: [UInt8]) {
            keys[key] = Entry(info: SMCKeyInfo(size: bytes.count, type: type), bytes: bytes)
        }
        add(SMCKey.acPower, "si8 ", [0x01])
        add(SMCKey.dcInPower, "flt ", [0x00, 0x00, 0x40, 0x41]) // 12.0 W little-endian float
        switch profile {
        case .tahoe:
            add(SMCKey.chargeInhibitTahoe, "hex_", SMCValue.chteAllow)
            add(SMCKey.dischargeCHIE, "hex_", SMCValue.dischargeOff)
            add(SMCKey.magSafeLED, "ui8 ", SMCValue.ledSystem)
        case .legacy:
            add(SMCKey.chargeInhibitB, "ui8 ", SMCValue.ch0bcAllow)
            add(SMCKey.chargeInhibitC, "ui8 ", SMCValue.ch0bcAllow)
            add(SMCKey.dischargeCH0J, "ui8 ", SMCValue.dischargeOff)
            add(SMCKey.dischargeCH0I, "ui8 ", SMCValue.dischargeOff)
            add(SMCKey.magSafeLED, "ui8 ", SMCValue.ledSystem)
        case .firmwareGated:
            add(SMCKey.chargeInhibitTahoe, "hex_", SMCValue.chteAllow)
            add(SMCKey.dischargeCHIE, "hex_", SMCValue.dischargeOff)
            add(SMCKey.magSafeLED, "ui8 ", SMCValue.ledSystem)
            add(SMCKey.firmwareActivation, "ui8 ", SMCValue.firmwareInactive)
            add(SMCKey.firmwareUpper, "ui32", SMCValue.firmwarePercent(100))
            add(SMCKey.firmwareLower, "ui32", SMCValue.firmwarePercent(0))
            gatedKeys = [SMCKey.chargeInhibitTahoe]
        case .adapterOnly:
            add(SMCKey.dischargeCHIE, "hex_", SMCValue.dischargeOff)
        case .unsupported:
            break
        }
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        lock.lock(); defer { lock.unlock() }
        guard let entry = keys[key] else { throw SMCError.keyNotFound(key) }
        return entry.info
    }

    public func read(_ key: String) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        guard let entry = keys[key] else { throw SMCError.keyNotFound(key) }
        return entry.bytes
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        guard var entry = keys[key] else { throw SMCError.keyNotFound(key) }
        if failAllWrites { throw SMCError.ioError(key: key, kernReturn: -536_870_212, smcResult: 1) }
        if gatedKeys.contains(key) { throw SMCError.notPrivileged(key) }
        guard bytes.count == entry.info.size else {
            throw SMCError.sizeMismatch(key: key, expected: entry.info.size, actual: bytes.count)
        }
        entry.bytes = bytes
        keys[key] = entry
        writeLog.append((key, bytes))
    }

    // MARK: Test and simulation hooks

    public func setGated(_ key: String, _ gated: Bool) {
        lock.lock(); defer { lock.unlock() }
        if gated { gatedKeys.insert(key) } else { gatedKeys.remove(key) }
    }

    public func addKey(_ key: String, type: String, bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        keys[key] = Entry(info: SMCKeyInfo(size: bytes.count, type: type), bytes: bytes)
    }

    public func removeKey(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        keys.removeValue(forKey: key)
    }

    public func value(_ key: String) -> [UInt8]? {
        lock.lock(); defer { lock.unlock() }
        return keys[key]?.bytes
    }

    public func clearWriteLog() {
        lock.lock(); defer { lock.unlock() }
        writeLog.removeAll()
    }

    /// True when any present charge-inhibit key holds a non-zero value.
    public var chargingInhibited: Bool {
        if let firmware = value(SMCKey.firmwareActivation), firmware == SMCValue.firmwareActive { return false }
        return SMCKey.chargeKeys.contains { key in (value(key) ?? []).contains { $0 != 0 } }
    }

    /// True when any present discharge key holds a non-zero value.
    public var dischargeForced: Bool {
        SMCKey.dischargeKeys.contains { key in (value(key) ?? []).contains { $0 != 0 } }
    }

    /// Firmware limit (upper) when active.
    public var firmwareUpperLimit: Int? {
        guard value(SMCKey.firmwareActivation) == SMCValue.firmwareActive,
              let upper = value(SMCKey.firmwareUpper) else { return nil }
        return SMCValue.decodeFirmwarePercent(upper)
    }

    public var firmwareLowerLimit: Int? {
        guard value(SMCKey.firmwareActivation) == SMCValue.firmwareActive,
              let lower = value(SMCKey.firmwareLower) else { return nil }
        return SMCValue.decodeFirmwarePercent(lower)
    }
}
