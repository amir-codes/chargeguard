import Foundation

/// One SMC write attempt, logged with key, value, reason and the battery snapshot (section 8).
public struct KeyWriteRecord: Codable, Equatable, Sendable {
    public var date: Date
    public var key: String
    public var previous: [UInt8]?
    public var value: [UInt8]
    public var reason: String
    public var snapshot: String
    public var success: Bool
    public var error: String?

    public init(date: Date, key: String, previous: [UInt8]?, value: [UInt8], reason: String,
                snapshot: String, success: Bool, error: String?) {
        self.date = date
        self.key = key
        self.previous = previous
        self.value = value
        self.reason = reason
        self.snapshot = snapshot
        self.success = success
        self.error = error
    }

    public var line: String {
        let prev = previous.map { Hex.string($0) } ?? "?"
        let status = success ? "ok" : "FAILED \(error ?? "")"
        return "write \(key) \(prev) -> \(Hex.string(value)) [\(status)] reason: \(reason) | \(snapshot)"
    }
}

/// The only path to an SMC write. It refuses:
/// - keys outside the section 5 table (`SMCKey.writableKeys`),
/// - keys the probe did not confirm present (never write a key whose keyInfo probe failed),
/// - keys known to fail with kIOReturnNotPrivileged,
/// - values whose length differs from the probed key size,
/// - any write while `blockedReason` is set (another charging tool running), unless the caller is an
///   explicit user restore.
/// It reads before writing and skips the write when the key already holds the value.
public final class GuardedSMCWriter {
    public let io: SMCKeyIO
    public private(set) var report: KeyProbeReport
    public var blockedReason: String?
    /// Describes the battery for the write log; set by the controller before applying.
    public var snapshotSummary: String = ""
    public var now: () -> Date = { Date() }
    /// Called for every attempted write (successful or not).
    public var onWrite: ((KeyWriteRecord) -> Void)?

    public init(io: SMCKeyIO, report: KeyProbeReport) {
        self.io = io
        self.report = report
    }

    public func updateReport(_ report: KeyProbeReport) {
        let known = self.report.notPrivileged
        self.report = report
        self.report.notPrivileged.formUnion(known)
    }

    public func isUsable(_ key: String) -> Bool {
        report.isUsable(key)
    }

    /// Ensures `key` holds `bytes`. Returns the record when a write happened, nil when the value was already set.
    @discardableResult
    public func ensure(_ key: String, _ bytes: [UInt8], reason: String, bypassBlock: Bool = false) throws -> KeyWriteRecord? {
        guard SMCKey.writableKeys.contains(key) else { throw SMCError.invalidKey(key) }
        if let blocked = blockedReason, !bypassBlock { throw SMCError.writesBlocked(blocked) }
        guard report.isPresent(key), let info = report.info(key) else { throw SMCError.notProbed(key) }
        guard !report.notPrivileged.contains(key) else { throw SMCError.notPrivileged(key) }
        guard info.size == bytes.count else {
            throw SMCError.sizeMismatch(key: key, expected: info.size, actual: bytes.count)
        }

        let current = try? io.read(key)
        if current == bytes { return nil }

        do {
            try io.write(key, bytes: bytes)
        } catch let error as SMCError {
            if error.isNotPrivileged { report.notPrivileged.insert(key) }
            let record = KeyWriteRecord(date: now(), key: key, previous: current, value: bytes, reason: reason,
                                        snapshot: snapshotSummary, success: false, error: error.description)
            onWrite?(record)
            throw error
        } catch {
            let record = KeyWriteRecord(date: now(), key: key, previous: current, value: bytes, reason: reason,
                                        snapshot: snapshotSummary, success: false, error: "\(error)")
            onWrite?(record)
            throw error
        }
        let record = KeyWriteRecord(date: now(), key: key, previous: current, value: bytes, reason: reason,
                                    snapshot: snapshotSummary, success: true, error: nil)
        onWrite?(record)
        return record
    }

    /// Writes the deactivate value to every present charge key, discharge key and the firmware
    /// limit, and resets ACLC to the system default. Best effort: one failure does not stop the rest.
    /// Returns the attempted writes (successful and failed) and the errors.
    @discardableResult
    public func restoreAll(reason: String, bypassBlock: Bool = false) -> (records: [KeyWriteRecord], errors: [String]) {
        var records: [KeyWriteRecord] = []
        var errors: [String] = []
        var plan: [(String, [UInt8])] = []
        // Discharge off first, so the Mac is back on the adapter before charging is re-enabled.
        for key in SMCKey.dischargeKeys where report.isPresent(key) {
            plan.append((key, SMCValue.dischargeOff))
        }
        if report.isPresent(SMCKey.chargeInhibitTahoe) {
            plan.append((SMCKey.chargeInhibitTahoe, SMCValue.chteAllow))
        }
        for key in [SMCKey.chargeInhibitB, SMCKey.chargeInhibitC] where report.isPresent(key) {
            plan.append((key, SMCValue.ch0bcAllow))
        }
        if report.isPresent(SMCKey.firmwareActivation) {
            plan.append((SMCKey.firmwareActivation, SMCValue.firmwareInactive))
        }
        if report.isPresent(SMCKey.magSafeLED) {
            plan.append((SMCKey.magSafeLED, SMCValue.ledSystem))
        }
        for (key, value) in plan {
            do {
                // A restore retries keys previously marked not privileged: the user asked for it explicitly.
                let wasNotPrivileged = report.notPrivileged.remove(key) != nil
                do {
                    if let record = try ensure(key, value, reason: reason, bypassBlock: bypassBlock) {
                        records.append(record)
                    }
                } catch {
                    if wasNotPrivileged { report.notPrivileged.insert(key) }
                    throw error
                }
            } catch {
                errors.append("\(key): \(error)")
            }
        }
        return (records, errors)
    }
}
