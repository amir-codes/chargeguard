import Foundation

/// Calibration state machine (feature 8). Pure: the policy engine calls `advance` once per tick.
///
/// A: charge to 100 % and hold (default 60 min). B: discharge to the floor (10...20 %, default 15)
/// with the Mac kept awake. C: charge to 100 % and hold again. D: restore the configured limit
/// (the engine discharges to it when Automatic Discharge is on). Cancellable at any step.
public enum CalibrationMachine {
    public static let absoluteFloor = 10

    public static func start(config: PolicyConfig, snapshot: BatterySnapshot, now: Date, origin: String) -> CalibrationState {
        let cal = config.normalized().calibration
        let hold = cal.fastMode ? CalibrationConfig.fastHoldSeconds : TimeInterval(cal.holdMinutes * 60)
        return CalibrationState(startedAt: now, holdSeconds: hold, fast: cal.fastMode,
                                startPercentage: snapshot.percentage,
                                startMaxCapacityMAh: snapshot.nominalChargeCapacityMAh ?? snapshot.rawMaxCapacityMAh,
                                startCycleCount: snapshot.cycleCount, origin: origin)
    }

    /// Effective charge ceiling during a phase.
    public static func ceiling(for phase: CalibrationPhase, configuredLimit: Int) -> Int {
        switch phase {
        case .chargeToFull, .holdFull, .dischargeToFloor, .rechargeToFull, .holdFullAgain: return 100
        case .restoreLimit: return configuredLimit
        }
    }

    /// Phases that need the adapter to make progress.
    public static func needsAdapter(_ phase: CalibrationPhase) -> Bool {
        switch phase {
        case .chargeToFull, .holdFull, .rechargeToFull, .holdFullAgain: return true
        case .dischargeToFloor, .restoreLimit: return false
        }
    }

    /// Phase B target. Fast mode: current level minus 3 %. Never below 10 %.
    public static func dischargeTarget(fast: Bool, currentPercentage: Int, configuredFloor: Int) -> Int {
        if fast { return max(absoluteFloor, currentPercentage - 3) }
        return configuredFloor.clamped(to: CalibrationConfig.floorRange)
    }

    public struct Step: Equatable {
        public var state: CalibrationState?
        public var events: [PolicyEvent]
        public var finished: CalibrationRecord?
    }

    static func isFull(percentage: Int, fullyCharged: Bool) -> Bool {
        percentage >= 100 || fullyCharged
    }

    /// Advances at most one phase.
    public static func advance(_ current: CalibrationState, percentage: Int, snapshot: BatterySnapshot,
                               adapterConnected: Bool, config: PolicyConfig, now: Date) -> Step {
        var c = current
        var events: [PolicyEvent] = []

        func enter(_ phase: CalibrationPhase) {
            c.phase = phase
            c.phaseStartedAt = now
            c.holdStartedAt = (phase == .holdFull || phase == .holdFullAgain) ? now : nil
            events.append(.calibrationPhaseChanged(phase: phase))
        }

        switch c.phase {
        case .chargeToFull:
            if isFull(percentage: percentage, fullyCharged: snapshot.fullyCharged) { enter(.holdFull) }
        case .holdFull:
            if !adapterConnected {
                enter(.chargeToFull)
            } else if let start = c.holdStartedAt, now.timeIntervalSince(start) >= c.holdSeconds {
                c.dischargeTarget = dischargeTarget(fast: c.fast, currentPercentage: percentage,
                                                    configuredFloor: config.calibration.dischargeFloor)
                enter(.dischargeToFloor)
            }
        case .dischargeToFloor:
            let target = max(absoluteFloor, c.dischargeTarget ?? config.calibration.dischargeFloor)
            if percentage <= target { enter(.rechargeToFull) }
        case .rechargeToFull:
            if isFull(percentage: percentage, fullyCharged: snapshot.fullyCharged) { enter(.holdFullAgain) }
        case .holdFullAgain:
            if !adapterConnected {
                enter(.rechargeToFull)
            } else if let start = c.holdStartedAt, now.timeIntervalSince(start) >= c.holdSeconds {
                enter(.restoreLimit)
            }
        case .restoreLimit:
            let record = makeRecord(c, outcome: .completed, snapshot: snapshot, now: now)
            events.append(.calibrationFinished(record: record))
            return Step(state: nil, events: events, finished: record)
        }
        return Step(state: c, events: events, finished: nil)
    }

    public static func cancel(_ current: CalibrationState, snapshot: BatterySnapshot?, now: Date) -> CalibrationRecord {
        makeRecord(current, outcome: .cancelled, snapshot: snapshot, now: now)
    }

    static func makeRecord(_ c: CalibrationState, outcome: CalibrationOutcome, snapshot: BatterySnapshot?, now: Date) -> CalibrationRecord {
        CalibrationRecord(id: c.id, startedAt: c.startedAt, finishedAt: now, outcome: outcome, fast: c.fast,
                          lastPhase: c.phase, startMaxCapacityMAh: c.startMaxCapacityMAh,
                          endMaxCapacityMAh: snapshot.map { $0.nominalChargeCapacityMAh ?? $0.rawMaxCapacityMAh },
                          cycleCount: snapshot?.cycleCount, origin: c.origin)
    }
}
