import Foundation

/// How the energy list was measured (shown in the UI, feature 21).
public enum EnergyMethod: String, Codable, CaseIterable, Sendable {
    case powermetrics
    case rusageEnergy
    case cpuPercent
    case unavailable

    public var label: String {
        switch self {
        case .powermetrics: return "Energy impact (powermetrics)"
        case .rusageEnergy: return "Energy counters (proc_pid_rusage)"
        case .cpuPercent: return "CPU usage (fallback)"
        case .unavailable: return "Unavailable"
        }
    }
}

public struct ProcessEnergy: Codable, Equatable, Identifiable, Sendable {
    public var pid: Int32
    public var name: String
    /// powermetrics "Energy Impact" or watts from rusage counters, depending on the method.
    public var energy: Double
    public var cpuMsPerSecond: Double?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, energy: Double, cpuMsPerSecond: Double? = nil) {
        self.pid = pid
        self.name = name
        self.energy = energy
        self.cpuMsPerSecond = cpuMsPerSecond
    }
}

public struct EnergySample: Codable, Equatable, Sendable {
    public var date: Date
    public var method: EnergyMethod
    public var processes: [ProcessEnergy]
    public var note: String?

    public init(date: Date, method: EnergyMethod, processes: [ProcessEnergy], note: String? = nil) {
        self.date = date
        self.method = method
        self.processes = processes
        self.note = note
    }

    public func top(_ count: Int) -> [ProcessEnergy] {
        Array(processes.sorted { $0.energy > $1.energy }.prefix(count))
    }
}

/// Parses `powermetrics --samplers tasks --show-process-energy` output, in plist (`-f plist`) or text form.
/// The daemon runs it as root (ChargeGuardSystem.PowermetricsRunner). Fixtures are in the Core tests;
/// docs/MAC-BUILD-NOTES.md asks Part B to check them against real output.
public enum PowermetricsParser {
    /// Plist output. powermetrics separates samples with a NUL byte; the first complete plist is used.
    /// Each task dictionary is expected to carry "pid", "name", "energy_impact" (or
    /// "energy_impact_per_s") and "cputime_ms_per_s".
    public static func parsePlist(_ data: Data) -> [ProcessEnergy] {
        let chunks = data.split(separator: 0, omittingEmptySubsequences: true)
        for chunk in chunks {
            guard let object = try? PropertyListSerialization.propertyList(from: Data(chunk), options: [], format: nil),
                  let root = object as? [String: Any],
                  let tasks = root["tasks"] as? [[String: Any]] else { continue }
            return tasks.compactMap { task -> ProcessEnergy? in
                guard let pid = number(task["pid"]), pid > 0 else { return nil }
                let name = (task["name"] as? String) ?? "pid \(Int(pid))"
                let energy = number(task["energy_impact"]) ?? number(task["energy_impact_per_s"]) ?? 0
                return ProcessEnergy(pid: Int32(pid), name: name, energy: energy,
                                     cpuMsPerSecond: number(task["cputime_ms_per_s"]))
            }
        }
        return []
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as Int64: return Double(v)
        case let v as NSNumber: return v.doubleValue
        case let v as String: return Double(v)
        default: return nil
        }
    }

    /// Text output: the "*** Running tasks ***" table. Process names may contain spaces and digits, so
    /// the trailing run of numeric columns is measured per line and the shortest run across lines is
    /// taken as the column count (a name ending in a number only lengthens its own line's run).
    public static func parseText(_ text: String) -> [ProcessEnergy] {
        let lines = text.components(separatedBy: .newlines)
        guard let headerIndex = lines.firstIndex(where: { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("Name") && t.contains("ID") && t.contains("CPU ms/s")
        }) else { return [] }
        let header = lines[headerIndex]
        let hasEnergy = header.contains("Energy Impact")

        var rows: [[String]] = []
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            rows.append(trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init))
        }
        func numericRun(_ tokens: [String]) -> Int {
            var count = 0
            for token in tokens.reversed() {
                if Double(token) != nil { count += 1 } else { break }
            }
            return count
        }
        let runs = rows.map(numericRun).filter { $0 >= 2 }
        guard let columns = runs.min() else { return [] }

        var result: [ProcessEnergy] = []
        for tokens in rows where tokens.count > columns {
            let numbers = Array(tokens.suffix(columns))
            let nameTokens = tokens.dropLast(columns)
            guard let pid = Int32(numbers[0]), pid > 0 else { continue }
            let cpu = numbers.count > 1 ? Double(numbers[1]) : nil
            let energy = hasEnergy ? (Double(numbers[numbers.count - 1]) ?? 0) : (cpu ?? 0)
            result.append(ProcessEnergy(pid: pid, name: nameTokens.joined(separator: " "), energy: energy, cpuMsPerSecond: cpu))
        }
        return result
    }
}
