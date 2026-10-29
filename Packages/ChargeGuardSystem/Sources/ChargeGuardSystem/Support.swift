import Foundation
import os
import ChargeGuardCore

/// os.Logger with subsystem com.amir.chargeguard and one category per component.
public final class OSLogger: CoreLogger {
    public static let subsystem = "com.amir.chargeguard"
    private let lock = NSLock()
    private var loggers: [String: Logger] = [:]
    /// Mirrors every line to stderr (chargectl --verbose, the daemon under launchd's StandardErrorPath).
    public var echoToStderr: Bool

    public init(echoToStderr: Bool = false) {
        self.echoToStderr = echoToStderr
    }

    private func logger(_ category: String) -> Logger {
        lock.lock(); defer { lock.unlock() }
        if let existing = loggers[category] { return existing }
        let created = Logger(subsystem: Self.subsystem, category: category)
        loggers[category] = created
        return created
    }

    public func log(_ level: LogLevel, _ category: String, _ message: String) {
        let osLogger = logger(category)
        switch level {
        case .debug: osLogger.debug("\(message, privacy: .public)")
        case .info: osLogger.info("\(message, privacy: .public)")
        case .notice: osLogger.notice("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        case .fault: osLogger.fault("\(message, privacy: .public)")
        }
        if echoToStderr {
            FileHandle.standardError.write(Data("[\(level.rawValue)] \(category): \(message)\n".utf8))
        }
    }
}

/// Machine facts: Apple silicon check, firmware version, model.
public enum MachineInfo {
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }

    public static var modelIdentifier: String? {
        sysctlString("hw.model")
    }

    public static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// "System Firmware Version" from `system_profiler SPHardwareDataType -json` (boot_rom_version).
    public static func firmwareVersion(runner: ProcessRunner = ProcessRunner()) -> String? {
        guard let result = try? runner.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], timeout: 20),
              result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: result.stdoutData) as? [String: Any],
              let items = json["SPHardwareDataType"] as? [[String: Any]],
              let first = items.first else { return nil }
        return first["boot_rom_version"] as? String
    }
}

/// state.json, events.jsonl, calibration.jsonl and writes.jsonl in /Library/Application Support/ChargeGuard.
/// state.json is written atomically. The folder is root-owned (the daemon runs as root).
public final class FileStateStore: StateStoring {
    public let directory: URL
    private let lock = NSLock()
    private let logger: CoreLogger?
    /// Set when state.json is from a newer build: it is never overwritten.
    private var readOnly = false
    static let maxLogBytes = 2_000_000

    public init(directory: URL = URL(fileURLWithPath: HelperProtocol.stateDirectory, isDirectory: true), logger: CoreLogger? = nil) {
        self.directory = directory
        self.logger = logger
    }

    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var eventsURL: URL { directory.appendingPathComponent("events.jsonl") }
    var calibrationURL: URL { directory.appendingPathComponent("calibration.jsonl") }
    var writesURL: URL { directory.appendingPathComponent("writes.jsonl") }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
    }

    public func load() throws -> PersistedState? {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        let data = try Data(contentsOf: stateURL)
        do {
            return try PersistedState.decode(data)
        } catch PersistenceError.newerSchema(let version) {
            readOnly = true
            throw PersistenceError.newerSchema(version)
        } catch {
            // Keep the unreadable file for diagnosis and start fresh.
            let backup = stateURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: stateURL, to: backup)
            throw PersistenceError.unreadable("\(error)")
        }
    }

    public func save(_ state: PersistedState) throws {
        lock.lock(); defer { lock.unlock() }
        guard !readOnly else { return }
        try ensureDirectory()
        try state.encoded().write(to: stateURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stateURL.path)
    }

    private func append<T: Encodable>(_ value: T, to url: URL) {
        lock.lock(); defer { lock.unlock() }
        do {
            try ensureDirectory()
            var line = try CoreJSON.encoder().encode(value)
            line.append(0x0A)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int, size > Self.maxLogBytes {
                let rotated = url.appendingPathExtension("1")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: url, to: rotated)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o644])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            logger?.error(LogCategory.persistence, "append to \(url.lastPathComponent) failed: \(error)")
        }
    }

    private func readLast<T: Decodable>(_ type: T.Type, from url: URL, limit: Int) -> [T] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = CoreJSON.decoder()
        let lines = data.split(separator: 0x0A).suffix(limit)
        return lines.compactMap { try? decoder.decode(T.self, from: Data($0)) }
    }

    public func appendEvent(_ record: EventRecord) { append(record, to: eventsURL) }
    public func appendCalibration(_ record: CalibrationRecord) { append(record, to: calibrationURL) }
    public func appendWrite(_ record: KeyWriteRecord) { append(record, to: writesURL) }
    public func calibrationHistory(limit: Int) -> [CalibrationRecord] { readLast(CalibrationRecord.self, from: calibrationURL, limit: limit) }
    public func recentEvents(limit: Int) -> [EventRecord] { readLast(EventRecord.self, from: eventsURL, limit: limit) }
    public func recentWrites(limit: Int) -> [KeyWriteRecord] { readLast(KeyWriteRecord.self, from: writesURL, limit: limit) }
}
