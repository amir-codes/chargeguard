import Foundation

/// MagSafe LED states written to ACLC (values from battery.sh / batt, see SMCKeys).
public enum LEDState: String, Codable, CaseIterable, Sendable {
    case system
    case off
    case green
    case orange
}

/// Power assertions the daemon should hold.
public struct AssertionSet: Codable, Equatable, Sendable {
    /// PreventUserIdleSystemSleep: Sleep Control, Disable Sleep until Limit, calibration.
    public var preventIdleSystemSleep: Bool
    /// PreventUserIdleDisplaySleep: Sleep Control option.
    public var preventDisplaySleep: Bool
    /// PreventSystemSleep: discharge in clamshell mode.
    public var preventSystemSleep: Bool

    public init(preventIdleSystemSleep: Bool = false, preventDisplaySleep: Bool = false, preventSystemSleep: Bool = false) {
        self.preventIdleSystemSleep = preventIdleSystemSleep
        self.preventDisplaySleep = preventDisplaySleep
        self.preventSystemSleep = preventSystemSleep
    }

    public static let none = AssertionSet()
}

/// The hardware state the policy wants. Backends translate it into SMC key writes.
public struct ControlOutputs: Codable, Equatable, Sendable {
    /// Battery must not charge (CHTE/CH0B+CH0C, or a cut adapter on the AdapterCutoff backend).
    public var inhibitCharging: Bool
    /// Run from the battery while plugged in (CHIE/CH0J/CH0I).
    public var forceDischarge: Bool
    /// Upper bound the battery may charge to right now (100 = no limit). Used by the firmware backend.
    public var chargeCeiling: Int
    /// Lower bound of the resume band. Used by the firmware backend.
    public var resumeFloor: Int
    /// When charging is blocked by an override (heat, sleep, discharge) below the ceiling, the
    /// percentage to hold at. The firmware backend uses it as its temporary upper limit.
    public var holdAtPercentage: Int?
    /// nil = leave the LED alone.
    public var led: LEDState?
    public var assertions: AssertionSet
    /// Hold `pmset disablesleep 1` (clamshell force-awake option).
    public var holdSleepDisabled: Bool
    /// nil = do not manage Low Power Mode.
    public var lowPowerMode: Bool?

    public init(inhibitCharging: Bool = false, forceDischarge: Bool = false, chargeCeiling: Int = 100,
                resumeFloor: Int = 0, holdAtPercentage: Int? = nil, led: LEDState? = nil,
                assertions: AssertionSet = .none, holdSleepDisabled: Bool = false, lowPowerMode: Bool? = nil) {
        self.inhibitCharging = inhibitCharging
        self.forceDischarge = forceDischarge
        self.chargeCeiling = chargeCeiling
        self.resumeFloor = resumeFloor
        self.holdAtPercentage = holdAtPercentage
        self.led = led
        self.assertions = assertions
        self.holdSleepDisabled = holdSleepDisabled
        self.lowPowerMode = lowPowerMode
    }

    /// Normal macOS charging: nothing blocked, nothing forced, LED back to system default.
    public static let normal = ControlOutputs()
}

/// Display state for the status line and the menu bar icon.
public enum ChargeStatus: Codable, Equatable, Sendable {
    case disabled
    case noBattery
    case conflict(tools: [String])
    case suspended
    case error(message: String)
    case onBattery
    case charging(target: Int)
    case limitReached(limit: Int)
    case sailing(limit: Int, resumeAt: Int)
    case discharging(target: Int, automatic: Bool)
    case dischargePaused(reason: String)
    case heatPaused(temperatureC: Double, resumeAtC: Double)
    case calibrating(phase: CalibrationPhase, waitingForAdapter: Bool)
    case toppingUp
    case sleepBlocked
    case fullyCharged

    /// Short text for the pop-up state line.
    public var title: String {
        switch self {
        case .disabled: return "Charge control is off"
        case .noBattery: return "No battery found"
        case .conflict: return "Another charging tool is running"
        case .suspended: return "Normal charging (ChargeGuard closed)"
        case .error(let message): return "Error: \(message)"
        case .onBattery: return "On battery"
        case .charging(let target): return target >= 100 ? "Charging" : "Charging to \(target) %"
        case .limitReached(let limit): return "Limit reached (\(limit) %)"
        case .sailing(let limit, let resumeAt): return "Limit \(limit) % reached, sailing until \(resumeAt) %"
        case .discharging(let target, let automatic): return automatic ? "Discharging to \(target) % (automatic)" : "Discharging to \(target) %"
        case .dischargePaused(let reason): return "Discharge paused: \(reason)"
        case .heatPaused(let t, let resume): return String(format: "Heat paused at %.1f °C, resumes at %.1f °C", t, resume)
        case .calibrating(let phase, let waiting): return waiting ? "Calibration: waiting for the adapter" : "Calibration phase \(phase.letter): \(phase.title)"
        case .toppingUp: return "Topping up to 100 %"
        case .sleepBlocked: return "Charging paused for sleep"
        case .fullyCharged: return "Fully charged"
        }
    }

    /// Icon-level category used by the menu bar renderer.
    public var kind: StatusKind {
        switch self {
        case .disabled, .suspended: return .idle
        case .noBattery, .error: return .error
        case .conflict: return .conflict
        case .onBattery: return .onBattery
        case .charging: return .charging
        case .limitReached, .fullyCharged, .sleepBlocked: return .limitReached
        case .sailing: return .sailing
        case .discharging, .dischargePaused: return .discharging
        case .heatPaused: return .heatPaused
        case .calibrating: return .calibrating
        case .toppingUp: return .topUp
        }
    }
}

/// Coarse status used for icons and colours.
public enum StatusKind: String, Codable, CaseIterable, Sendable {
    case idle, onBattery, charging, limitReached, sailing, discharging, heatPaused
    case calibrating, topUp, helperMissing, error, conflict
}

/// Things that happened during a tick. The daemon logs them and forwards them to the app,
/// which turns some into user notifications.
public enum PolicyEvent: Codable, Equatable, Sendable {
    case limitReached(limit: Int)
    case heatPaused(temperatureC: Double)
    case heatResumed(temperatureC: Double)
    case dischargeStarted(target: Int, automatic: Bool)
    case dischargeFinished(percentage: Int)
    case topUpFinished(reason: String)
    case calibrationPhaseChanged(phase: CalibrationPhase)
    case calibrationFinished(record: CalibrationRecord)
    case keepAwakeEnded
    case scheduleRan(ruleID: UUID, summary: String)
    case scheduleMissed(ruleID: UUID, summary: String)
    case backendChanged(from: String, to: String, reason: String)
    case backendError(message: String)
    case conflictDetected(tools: [String])
    case conflictCleared
    case restoredNormalCharging(reason: String)

    /// Whether the app should show a user notification for this event.
    public var notifiesUser: Bool {
        switch self {
        case .heatPaused, .heatResumed, .calibrationPhaseChanged, .calibrationFinished, .scheduleRan,
             .scheduleMissed, .backendError, .conflictDetected, .backendChanged, .topUpFinished:
            return true
        default:
            return false
        }
    }

    public var summary: String {
        switch self {
        case .limitReached(let limit): return "Charge limit \(limit) % reached"
        case .heatPaused(let t): return String(format: "Charging paused: battery at %.1f °C", t)
        case .heatResumed(let t): return String(format: "Charging resumed: battery cooled to %.1f °C", t)
        case .dischargeStarted(let target, let automatic): return "\(automatic ? "Automatic discharge" : "Discharge") to \(target) % started"
        case .dischargeFinished(let p): return "Discharge finished at \(p) %"
        case .topUpFinished(let reason): return "Top up finished: \(reason)"
        case .calibrationPhaseChanged(let phase): return "Calibration phase \(phase.letter): \(phase.title)"
        case .calibrationFinished(let record): return record.outcome == .completed ? "Calibration completed" : "Calibration cancelled"
        case .keepAwakeEnded: return "Keep awake ended"
        case .scheduleRan(_, let summary): return "Schedule ran: \(summary)"
        case .scheduleMissed(_, let summary): return "Schedule missed: \(summary)"
        case .backendChanged(let from, let to, let reason): return "Backend changed from \(from) to \(to): \(reason)"
        case .backendError(let message): return "Charge control error: \(message)"
        case .conflictDetected(let tools): return "Another charging tool is running: \(tools.joined(separator: ", "))"
        case .conflictCleared: return "No other charging tool detected"
        case .restoredNormalCharging(let reason): return "Normal charging restored: \(reason)"
        }
    }
}

/// Inputs the engine needs besides config, snapshot and previous state.
public struct PolicyContext: Equatable, Sendable {
    public var now: Date
    /// Between "system will sleep" and "did wake".
    public var sleepImminent: Bool
    public var lidClosed: Bool
    /// Reported by the app (the daemon cannot see displays). Used by the clamshell force-awake option.
    public var externalDisplayConnected: Bool
    public var conflicts: [String]
    public var backend: BackendCapabilities

    public init(now: Date, sleepImminent: Bool = false, lidClosed: Bool = false,
                externalDisplayConnected: Bool = false, conflicts: [String] = [],
                backend: BackendCapabilities = .legacy) {
        self.now = now
        self.sleepImminent = sleepImminent
        self.lidClosed = lidClosed
        self.externalDisplayConnected = externalDisplayConnected
        self.conflicts = conflicts
        self.backend = backend
    }
}

/// Output of one policy evaluation.
public struct Decision: Equatable, Sendable {
    public var outputs: ControlOutputs
    public var nextState: ControlState
    public var status: ChargeStatus
    public var events: [PolicyEvent]
    /// Human-readable reasons, logged with every key write.
    public var reasons: [String]
    /// False while charge control is off or another tool is running: the controller must not write.
    public var writesAllowed: Bool
    /// The limit currently enforced (configured limit, 100 during top up, phase target during calibration).
    public var effectiveLimit: Int
    /// The percentage the decision was based on.
    public var controlPercentage: Int

    public var reasonText: String { reasons.joined(separator: "; ") }
}
