import Foundation
import Darwin
import ChargeGuardCore

/// Running processes via libproc and sysctl (no shelling out).
public enum ProcessList {
    public struct Entry: Sendable {
        public var pid: pid_t
        public var name: String
        public var path: String?
    }

    public static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled))).filter { $0 > 0 }
    }

    public static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    public static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    public static func entries() -> [Entry] {
        allPIDs().compactMap { pid in
            let path = path(of: pid)
            guard let name = name(of: pid) ?? path.map({ ($0 as NSString).lastPathComponent }) else { return nil }
            return Entry(pid: pid, name: name, path: path)
        }
    }

    /// argv of a process joined by spaces, via KERN_PROCARGS2. Root can read every process.
    public static func commandLine(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and the NUL padding after it.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var args: [String] = []
        var start = index
        while index < size, args.count < Int(argc) {
            if buffer[index] == 0 {
                args.append(String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return args.joined(separator: " ")
    }
}

/// Detects AlDente (app process), batt and the battery CLI (section 6).
public final class ConflictScanner: ConflictScanning {
    private let runner = ProcessRunner()
    /// Shells whose command lines are checked for the battery CLI script.
    private static let scriptHosts: Set<String> = ["bash", "sh", "zsh", "battery"]

    public init() {}

    public func scan() -> ConflictReport {
        var input = ConflictScanInput()
        let entries = ProcessList.entries()
        input.processNames = entries.map(\.name)
        input.processCommandLines = entries
            .filter { Self.scriptHosts.contains($0.name) }
            .compactMap { ProcessList.commandLine(of: $0.pid) }
        input.launchdLabels = launchdLabels()
        if FileManager.default.fileExists(atPath: ConflictRules.batteryCLIFolder) {
            input.existingPaths.insert(ConflictRules.batteryCLIFolder)
        }
        return ConflictRules.evaluate(input)
    }

    /// Labels from `launchctl list` (the system domain when root, else the user's domain), plus the
    /// console user's GUI domain when running as root (where the battery CLI's LaunchAgent lives).
    func launchdLabels() -> [String] {
        var labels = Self.parseLaunchctlList((try? runner.run("/bin/launchctl", ["list"], timeout: 5))?.stdout ?? "")
        if getuid() == 0, let uid = ConsoleUser.uid(), uid != 0 {
            let output = (try? runner.run("/bin/launchctl", ["asuser", String(uid), "/bin/launchctl", "list"], timeout: 5))?.stdout ?? ""
            labels += Self.parseLaunchctlList(output)
        }
        return labels
    }

    /// `launchctl list` prints "PID\tStatus\tLabel".
    static func parseLaunchctlList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).dropFirst().compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return nil }
            return String(parts[2]).trimmingCharacters(in: .whitespaces)
        }
    }
}

/// The user logged in at the console (for the root daemon).
public enum ConsoleUser {
    public static func uid() -> uid_t? {
        var info = stat()
        guard stat("/dev/console", &info) == 0 else { return nil }
        return info.st_uid
    }
}
