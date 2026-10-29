import Foundation

/// Calibration phases. A = chargeToFull + holdFull, B = dischargeToFloor,
/// C = rechargeToFull + holdFullAgain, D = restoreLimit.
public enum CalibrationPhase: String, Codable, CaseIterable, Sendable {
    case chargeToFull
    case holdFull
    case dischargeToFloor
    case rechargeToFull
    case holdFullAgain
    case restoreLimit

    /// The letter shown in the UI ("Phase A").
    public var letter: String {
        switch self {
        case .chargeToFull, .holdFull: return "A"
        case .dischargeToFloor: return "B"
        case .rechargeToFull, .holdFullAgain: return "C"
        case .restoreLimit: return "D"
        }
    }

    public var title: String {
        switch self {
        case .chargeToFull: return "Charging to 100 %"
        case .holdFull: return "Holding at 100 %"
        case .dischargeToFloor: return "Discharging"
        case .rechargeToFull: return "Recharging to 100 %"
        case .holdFullAgain: return "Holding at 100 %"
        case .restoreLimit: return "Restoring the limit"
        }
    }

    /// 1-based step number out of `CalibrationPhase.allCases.count`.
    public var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// Persisted calibration progress. Survives app and daemon restarts.
public struct CalibrationState: Codable, Equatable, Sendable {
    public var id: UUID
    public var phase: CalibrationPhase
    public var startedAt: Date
    public var phaseStartedAt: Date
    /// Set when a hold phase starts counting (battery reached 100 %).
    public var holdStartedAt: Date?
    public var holdSeconds: TimeInterval
    /// Phase B target, computed when phase B starts. Never below 10 %.
    public var dischargeTarget: Int?
    public var fast: Bool
    public var startPercentage: Int
    public var startMaxCapacityMAh: Int?
    public var startCycleCount: Int?
    /// What started it: "user", "schedule", "shortcut".
    public var origin: String

    public init(id: UUID = UUID(), phase: CalibrationPhase = .chargeToFull, startedAt: Date,
                holdSeconds: TimeInterval, fast: Bool, startPercentage: Int,
                startMaxCapacityMAh: Int? = nil, startCycleCount: Int? = nil, origin: String = "user") {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.phaseStartedAt = startedAt
        self.holdStartedAt = nil
        self.holdSeconds = holdSeconds
        self.dischargeTarget = nil
        self.fast = fast
        self.startPercentage = startPercentage
        self.startMaxCapacityMAh = startMaxCapacityMAh
        self.startCycleCount = startCycleCount
        self.origin = origin
    }

    /// Seconds left in the current hold, nil outside a hold.
    public func holdRemaining(now: Date) -> TimeInterval? {
        guard phase == .holdFull || phase == .holdFullAgain, let start = holdStartedAt else { return nil }
        return max(0, holdSeconds - now.timeIntervalSince(start))
    }
}

public enum CalibrationOutcome: String, Codable, Sendable {
    case completed
    case cancelled
}

/// One line of the calibration history (calibration.jsonl).
public struct CalibrationRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: CalibrationOutcome
    public var fast: Bool
    public var lastPhase: CalibrationPhase
    public var startMaxCapacityMAh: Int?
    public var endMaxCapacityMAh: Int?
    public var cycleCount: Int?
    public var origin: String

    public init(id: UUID, startedAt: Date, finishedAt: Date, outcome: CalibrationOutcome, fast: Bool,
                lastPhase: CalibrationPhase, startMaxCapacityMAh: Int?, endMaxCapacityMAh: Int?,
                cycleCount: Int?, origin: String) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.fast = fast
        self.lastPhase = lastPhase
        self.startMaxCapacityMAh = startMaxCapacityMAh
        self.endMaxCapacityMAh = endMaxCapacityMAh
        self.cycleCount = cycleCount
        self.origin = origin
    }
}

/// One-shot charge to 100 % (feature 7).
public struct TopUpState: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var startPercentage: Int

    public init(startedAt: Date, startPercentage: Int) {
        self.startedAt = startedAt
        self.startPercentage = startPercentage
    }

    /// Safety net: a top up never lasts longer than this.
    public static let maximumDuration: TimeInterval = 12 * 3600
}

/// Sleep Control request (feature 11).
public struct KeepAwakeRequest: Codable, Equatable, Sendable {
    /// nil = indefinitely (or until the charge limit when `untilChargeLimit`).
    public var durationSeconds: TimeInterval?
    public var untilChargeLimit: Bool
    public var preventDisplaySleep: Bool

    public init(durationSeconds: TimeInterval?, untilChargeLimit: Bool = false, preventDisplaySleep: Bool = false) {
        self.durationSeconds = durationSeconds
        self.untilChargeLimit = untilChargeLimit
        self.preventDisplaySleep = preventDisplaySleep
    }

    public static let presets: [KeepAwakePreset] = [
        KeepAwakePreset(title: "30 minutes", seconds: 30 * 60),
        KeepAwakePreset(title: "1 hour", seconds: 3600),
        KeepAwakePreset(title: "2 hours", seconds: 7200),
        KeepAwakePreset(title: "4 hours", seconds: 14_400),
    ]
}

/// A Sleep Control menu entry.
public struct KeepAwakePreset: Hashable, Identifiable, Sendable {
    public let title: String
    public let seconds: TimeInterval
    public var id: TimeInterval { seconds }

    public init(title: String, seconds: TimeInterval) {
        self.title = title
        self.seconds = seconds
    }
}

public struct KeepAwakeState: Codable, Equatable, Sendable {
    public var startedAt: Date
    /// nil = no time limit.
    public var until: Date?
    public var untilChargeLimit: Bool
    public var preventDisplaySleep: Bool

    public init(startedAt: Date, until: Date?, untilChargeLimit: Bool, preventDisplaySleep: Bool) {
        self.startedAt = startedAt
        self.until = until
        self.untilChargeLimit = untilChargeLimit
        self.preventDisplaySleep = preventDisplaySleep
    }

    public init(request: KeepAwakeRequest, now: Date) {
        self.init(startedAt: now,
                  until: request.durationSeconds.map { now.addingTimeInterval($0) },
                  untilChargeLimit: request.untilChargeLimit,
                  preventDisplaySleep: request.preventDisplaySleep)
    }

    public func remaining(now: Date) -> TimeInterval? {
        until.map { max(0, $0.timeIntervalSince(now)) }
    }
}

/// The daemon's dynamic control state, carried from one control-loop tick to the next
/// (the "PreviousState" input of the policy engine). Persisted in state.json.
public struct ControlState: Codable, Equatable, Sendable {
    /// Hysteresis/sailing latch: true once the limit was reached, until the battery falls below the band.
    public var chargeInhibitLatched: Bool
    /// Ceiling used on the previous tick; raising it releases the latch.
    public var lastEffectiveLimit: Int?
    /// Manual discharge (feature 2), one-shot until the limit is reached.
    public var manualDischarge: Bool
    /// Whether forced discharge was active on the previous tick (for start/finish events).
    public var dischargeActive: Bool
    /// Heat protection latch (feature 5).
    public var heatPaused: Bool
    public var topUp: TopUpState?
    /// Set when a top up finishes at full charge: Automatic Discharge waits until the adapter is
    /// unplugged (or the limit changes), otherwise it would undo the top up immediately.
    public var autoDischargeSuppressed: Bool
    public var calibration: CalibrationState?
    public var keepAwake: KeepAwakeState?
    /// True after the app quit with `.restoreOnQuit`; enforcement resumes when the app launches again.
    public var enforcementSuspended: Bool
    /// True while ChargeGuard owns the LED, so turning the setting off writes "system default" once.
    public var ledManaged: Bool

    public init(chargeInhibitLatched: Bool = false, lastEffectiveLimit: Int? = nil, manualDischarge: Bool = false,
                dischargeActive: Bool = false, heatPaused: Bool = false, topUp: TopUpState? = nil,
                autoDischargeSuppressed: Bool = false,
                calibration: CalibrationState? = nil, keepAwake: KeepAwakeState? = nil,
                enforcementSuspended: Bool = false, ledManaged: Bool = false) {
        self.chargeInhibitLatched = chargeInhibitLatched
        self.lastEffectiveLimit = lastEffectiveLimit
        self.manualDischarge = manualDischarge
        self.dischargeActive = dischargeActive
        self.heatPaused = heatPaused
        self.topUp = topUp
        self.autoDischargeSuppressed = autoDischargeSuppressed
        self.calibration = calibration
        self.keepAwake = keepAwake
        self.enforcementSuspended = enforcementSuspended
        self.ledManaged = ledManaged
    }

    private enum CodingKeys: String, CodingKey {
        case chargeInhibitLatched, lastEffectiveLimit, manualDischarge, dischargeActive, heatPaused, topUp, calibration
        case autoDischargeSuppressed, keepAwake, enforcementSuspended, ledManaged
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chargeInhibitLatched = try c.decode(Bool.self, forKey: .chargeInhibitLatched, default: false)
        lastEffectiveLimit = try c.decodeIfPresent(Int.self, forKey: .lastEffectiveLimit)
        manualDischarge = try c.decode(Bool.self, forKey: .manualDischarge, default: false)
        dischargeActive = try c.decode(Bool.self, forKey: .dischargeActive, default: false)
        heatPaused = try c.decode(Bool.self, forKey: .heatPaused, default: false)
        topUp = try c.decodeIfPresent(TopUpState.self, forKey: .topUp)
        autoDischargeSuppressed = try c.decode(Bool.self, forKey: .autoDischargeSuppressed, default: false)
        calibration = try c.decodeIfPresent(CalibrationState.self, forKey: .calibration)
        keepAwake = try c.decodeIfPresent(KeepAwakeState.self, forKey: .keepAwake)
        enforcementSuspended = try c.decode(Bool.self, forKey: .enforcementSuspended, default: false)
        ledManaged = try c.decode(Bool.self, forKey: .ledManaged, default: false)
    }
}
