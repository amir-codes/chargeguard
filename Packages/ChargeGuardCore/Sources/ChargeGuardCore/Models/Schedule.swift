import Foundation

public enum ScheduleRepeat: String, Codable, CaseIterable, Sendable {
    case weekly
    case once
}

/// What a schedule rule does when it fires (feature 15).
public enum ScheduleAction: Codable, Equatable, Hashable, Sendable {
    case startCalibration
    case topUp
    case setLimit(Int)
    case enableDischarge
    case disableDischarge
    case setLowPowerMode(LowPowerModePolicy)

    public var summary: String {
        switch self {
        case .startCalibration: return "Start calibration"
        case .topUp: return "Top up to 100 %"
        case .setLimit(let limit): return "Set limit to \(limit) %"
        case .enableDischarge: return "Start discharge"
        case .disableDischarge: return "Stop discharge"
        case .setLowPowerMode(let mode): return "Low Power Mode: \(mode.title)"
        }
    }
}

extension LowPowerModePolicy {
    public var title: String {
        switch self {
        case .unmanaged: return "Not managed"
        case .alwaysOff: return "Always off"
        case .alwaysOn: return "Always on"
        case .onlyOnBattery: return "Only on battery"
        case .onlyOnAdapter: return "Only on adapter"
        }
    }
}

public struct ScheduleRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var enabled: Bool
    /// Calendar weekdays, 1 = Sunday ... 7 = Saturday. Empty = every day.
    public var weekdays: Set<Int>
    public var hour: Int
    public var minute: Int
    public var action: ScheduleAction
    public var repeats: ScheduleRepeat
    /// When the rule last fired (or was recorded as missed). Occurrences at or before this never fire again.
    public var lastRun: Date?
    public var createdAt: Date

    public init(id: UUID = UUID(), enabled: Bool = true, weekdays: Set<Int> = [], hour: Int, minute: Int,
                action: ScheduleAction, repeats: ScheduleRepeat = .weekly, lastRun: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.enabled = enabled
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
        self.action = action
        self.repeats = repeats
        self.lastRun = lastRun
        self.createdAt = createdAt
    }

    public var summary: String {
        "\(action.summary) at " + String(format: "%02ld:%02ld", hour, minute)
    }
}

/// A due or missed occurrence.
public struct ScheduledOccurrence: Equatable, Sendable {
    public var ruleID: UUID
    public var scheduledAt: Date
    public var action: ScheduleAction
}
