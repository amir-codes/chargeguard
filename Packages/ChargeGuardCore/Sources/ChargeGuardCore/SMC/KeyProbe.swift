import Foundation

/// Result of probing one SMC key.
public struct KeyProbeEntry: Codable, Equatable, Sendable {
    public var key: String
    public var present: Bool
    public var info: SMCKeyInfo?
    public var value: [UInt8]?
    public var error: String?

    public init(key: String, present: Bool, info: SMCKeyInfo? = nil, value: [UInt8]? = nil, error: String? = nil) {
        self.key = key
        self.present = present
        self.info = info
        self.value = value
        self.error = error
    }

    /// One line for `chargectl probe` and docs/SMC-KEYS.md.
    public var line: String {
        let pad = key.padding(toLength: 5, withPad: " ", startingAt: 0)
        guard present, let info else {
            return "\(pad) absent\(error.map { "  (\($0))" } ?? "")"
        }
        let value = value.map { Hex.string($0) } ?? "unreadable"
        return "\(pad) present  size \(info.size)  type '\(info.type)'  value \(value)"
    }
}

/// Which keys exist on this Mac, plus keys that failed at runtime with kIOReturnNotPrivileged.
public struct KeyProbeReport: Codable, Equatable, Sendable {
    public var date: Date
    public var entries: [KeyProbeEntry]
    public var notPrivileged: Set<String>

    public init(date: Date, entries: [KeyProbeEntry], notPrivileged: Set<String> = []) {
        self.date = date
        self.entries = entries
        self.notPrivileged = notPrivileged
    }

    public func entry(_ key: String) -> KeyProbeEntry? {
        entries.first { $0.key == key }
    }

    /// Present: keyInfo succeeded with a non-zero size and the read did not report "no data".
    public func isPresent(_ key: String) -> Bool {
        entry(key)?.present ?? false
    }

    public func info(_ key: String) -> SMCKeyInfo? {
        guard let e = entry(key), e.present else { return nil }
        return e.info
    }

    /// Present and not known to fail with kIOReturnNotPrivileged.
    public func isUsable(_ key: String) -> Bool {
        isPresent(key) && !notPrivileged.contains(key)
    }

    public var text: String {
        var lines = entries.map(\.line)
        if !notPrivileged.isEmpty {
            lines.append("not privileged at runtime: \(notPrivileged.sorted().joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    public static let empty = KeyProbeReport(date: Date(timeIntervalSince1970: 0), entries: [])
}

/// Probes keys by presence, as battery.sh and batt do: never by macOS version or chip name.
public enum KeyProber {
    public static func probe(_ io: SMCKeyIO, keys: [String] = SMCKey.probeKeys, now: Date = Date()) -> KeyProbeReport {
        var entries: [KeyProbeEntry] = []
        for key in keys {
            let info: SMCKeyInfo
            do {
                info = try io.keyInfo(key)
            } catch {
                entries.append(KeyProbeEntry(key: key, present: false, error: "\(error)"))
                continue
            }
            // Some firmware exposes placeholder keys with zero size: they cannot be read or written.
            guard info.size > 0 else {
                entries.append(KeyProbeEntry(key: key, present: false, info: info, error: "zero size"))
                continue
            }
            do {
                let value = try io.read(key)
                entries.append(KeyProbeEntry(key: key, present: true, info: info, value: value))
            } catch SMCError.keyNotFound(_) {
                entries.append(KeyProbeEntry(key: key, present: false, info: info, error: "no data"))
            } catch {
                // keyInfo succeeded, so the key exists; the value just could not be read here.
                entries.append(KeyProbeEntry(key: key, present: true, info: info, error: "\(error)"))
            }
        }
        return KeyProbeReport(date: now, entries: entries)
    }
}
