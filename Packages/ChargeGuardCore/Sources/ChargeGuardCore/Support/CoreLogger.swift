import Foundation

public enum LogLevel: String, Codable, Sendable {
    case debug, info, notice, error, fault
}

/// Logging seam for Core. ChargeGuardSystem provides an os.Logger implementation
/// (subsystem com.amir.chargeguard, one category per component); tests use `MemoryLogger`.
public protocol CoreLogger: AnyObject {
    func log(_ level: LogLevel, _ category: String, _ message: String)
}

public extension CoreLogger {
    func info(_ category: String, _ message: String) { log(.info, category, message) }
    func error(_ category: String, _ message: String) { log(.error, category, message) }
    func debug(_ category: String, _ message: String) { log(.debug, category, message) }
    func notice(_ category: String, _ message: String) { log(.notice, category, message) }
}

/// Collects lines in memory. Used by tests and by the simulated in-process controller.
public final class MemoryLogger: CoreLogger {
    private let lock = NSLock()
    private var storage: [String] = []
    public let echo: Bool

    public init(echo: Bool = false) { self.echo = echo }

    public func log(_ level: LogLevel, _ category: String, _ message: String) {
        let line = "[\(level.rawValue)] \(category): \(message)"
        lock.lock()
        storage.append(line)
        if storage.count > 5000 { storage.removeFirst(storage.count - 5000) }
        lock.unlock()
        if echo { print(line) }
    }

    public var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Component categories used across the project.
public enum LogCategory {
    public static let controller = "controller"
    public static let policy = "policy"
    public static let smc = "smc"
    public static let writes = "writes"
    public static let xpc = "xpc"
    public static let schedule = "schedule"
    public static let persistence = "persistence"
    public static let power = "power"
    public static let conflicts = "conflicts"
    public static let energy = "energy"
    public static let app = "app"
}
