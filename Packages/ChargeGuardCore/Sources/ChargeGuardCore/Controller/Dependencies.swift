import Foundation

/// Clock seam. (Not named `Clock` to avoid clashing with Swift's concurrency `Clock` protocol.)
public protocol TimeSource: AnyObject {
    var now: Date { get }
}

public final class SystemTimeSource: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// A clock tests advance by hand.
public final class ManualTimeSource: TimeSource {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }

    public func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        current = date
    }
}

/// Simulated time running `scale` times faster than real time (for `--simulate`).
public final class ScaledTimeSource: TimeSource {
    private let realStart = Date()
    private let virtualStart: Date
    public let scale: Double

    public init(scale: Double, start: Date = Date()) {
        self.scale = max(1, scale)
        self.virtualStart = start
    }

    public var now: Date {
        virtualStart.addingTimeInterval(Date().timeIntervalSince(realStart) * scale)
    }
}

public protocol BatteryReading: AnyObject {
    func readSnapshot() throws -> BatterySnapshot
}

/// Holds the IOPM assertions the policy asks for. `apply` is idempotent.
public protocol PowerAssertionControlling: AnyObject {
    func apply(_ assertions: AssertionSet)
    func releaseAll()
}

/// `pmset -a lowpowermode` and `pmset -g`.
public protocol LowPowerModeControlling: AnyObject {
    func isLowPowerModeEnabled() -> Bool?
    func setLowPowerMode(_ enabled: Bool) throws
}

/// `pmset -a disablesleep` and the SleepDisabled value from `pmset -g`.
public protocol SleepDisableControlling: AnyObject {
    func isSleepDisabled() -> Bool?
    func setSleepDisabled(_ disabled: Bool) throws
}

public protocol StateStoring: AnyObject {
    func load() throws -> PersistedState?
    func save(_ state: PersistedState) throws
    func appendEvent(_ record: EventRecord)
    func appendCalibration(_ record: CalibrationRecord)
    func appendWrite(_ record: KeyWriteRecord)
    func calibrationHistory(limit: Int) -> [CalibrationRecord]
    func recentEvents(limit: Int) -> [EventRecord]
    func recentWrites(limit: Int) -> [KeyWriteRecord]
}

public protocol ConflictScanning: AnyObject {
    func scan() -> ConflictReport
}

public protocol EnergySampling: AnyObject {
    func sample() -> EnergySample
}

public protocol LidStateReading: AnyObject {
    func isLidClosed() -> Bool?
}

/// Everything the controller talks to. The helper wires the real implementations
/// (ChargeGuardSystem); tests and `--simulate` wire the simulated ones below.
public struct ControllerDependencies {
    public var smc: SMCKeyIO
    public var battery: BatteryReading
    public var assertions: PowerAssertionControlling
    public var lowPowerMode: LowPowerModeControlling
    public var sleepDisable: SleepDisableControlling
    public var store: StateStoring
    public var conflicts: ConflictScanning
    public var energy: EnergySampling
    public var lid: LidStateReading
    public var clock: TimeSource
    public var calendar: Calendar
    public var logger: CoreLogger
    public var simulated: Bool
    public var daemonVersion: String
    public var firmwareVersion: String?

    public init(smc: SMCKeyIO, battery: BatteryReading, assertions: PowerAssertionControlling,
                lowPowerMode: LowPowerModeControlling, sleepDisable: SleepDisableControlling, store: StateStoring,
                conflicts: ConflictScanning, energy: EnergySampling, lid: LidStateReading, clock: TimeSource,
                calendar: Calendar = Calendar.current, logger: CoreLogger, simulated: Bool, daemonVersion: String,
                firmwareVersion: String? = nil) {
        self.smc = smc
        self.battery = battery
        self.assertions = assertions
        self.lowPowerMode = lowPowerMode
        self.sleepDisable = sleepDisable
        self.store = store
        self.conflicts = conflicts
        self.energy = energy
        self.lid = lid
        self.clock = clock
        self.calendar = calendar
        self.logger = logger
        self.simulated = simulated
        self.daemonVersion = daemonVersion
        self.firmwareVersion = firmwareVersion
    }

    /// A fully simulated set: SimulatedSMC + SimulatedBattery + in-memory everything.
    public static func makeSimulated(profile: SimulatedSMC.Profile = .tahoe, clock: TimeSource, charge: Double = 62,
                                 script: [SimulatedBattery.ScriptStep] = [], logger: CoreLogger = MemoryLogger(),
                                 calendar: Calendar = Calendar.current) -> (ControllerDependencies, SimulatedBattery) {
        let smc = SimulatedSMC(profile: profile)
        let battery = SimulatedBattery(smc: smc, clock: clock, charge: charge, script: script)
        let deps = ControllerDependencies(smc: smc, battery: battery, assertions: RecordingAssertions(),
                                          lowPowerMode: SimulatedPowerSettings(), sleepDisable: SimulatedPowerSettings(),
                                          store: InMemoryStateStore(), conflicts: StaticConflictScanner(),
                                          energy: SimulatedEnergySampler(clock: clock), lid: SimulatedLid(),
                                          clock: clock, calendar: calendar, logger: logger, simulated: true,
                                          daemonVersion: "simulated", firmwareVersion: "simulated")
        return (deps, battery)
    }
}

// MARK: - Simulated and in-memory implementations

public final class RecordingAssertions: PowerAssertionControlling {
    public private(set) var current = AssertionSet.none
    public private(set) var history: [AssertionSet] = []
    public init() {}
    public func apply(_ assertions: AssertionSet) {
        if assertions != current { history.append(assertions) }
        current = assertions
    }
    public func releaseAll() { apply(.none) }
}

public final class SimulatedPowerSettings: LowPowerModeControlling, SleepDisableControlling {
    public var lowPowerMode = false
    public var sleepDisabled = false
    public private(set) var lowPowerWrites: [Bool] = []
    public private(set) var sleepDisabledWrites: [Bool] = []
    public init() {}
    public func isLowPowerModeEnabled() -> Bool? { lowPowerMode }
    public func setLowPowerMode(_ enabled: Bool) throws { lowPowerMode = enabled; lowPowerWrites.append(enabled) }
    public func isSleepDisabled() -> Bool? { sleepDisabled }
    public func setSleepDisabled(_ disabled: Bool) throws { sleepDisabled = disabled; sleepDisabledWrites.append(disabled) }
}

public final class InMemoryStateStore: StateStoring {
    private let lock = NSLock()
    public var state: PersistedState?
    public private(set) var events: [EventRecord] = []
    public private(set) var calibrations: [CalibrationRecord] = []
    public private(set) var writes: [KeyWriteRecord] = []
    public private(set) var saveCount = 0

    public init(state: PersistedState? = nil) { self.state = state }

    public func load() throws -> PersistedState? { lock.lock(); defer { lock.unlock() }; return state }
    public func save(_ state: PersistedState) throws { lock.lock(); defer { lock.unlock() }; self.state = state; saveCount += 1 }
    public func appendEvent(_ record: EventRecord) { lock.lock(); defer { lock.unlock() }; events.append(record) }
    public func appendCalibration(_ record: CalibrationRecord) { lock.lock(); defer { lock.unlock() }; calibrations.append(record) }
    public func appendWrite(_ record: KeyWriteRecord) {
        lock.lock(); defer { lock.unlock() }
        writes.append(record)
        if writes.count > 2000 { writes.removeFirst(writes.count - 2000) }
    }
    public func calibrationHistory(limit: Int) -> [CalibrationRecord] { lock.lock(); defer { lock.unlock() }; return Array(calibrations.suffix(limit)) }
    public func recentEvents(limit: Int) -> [EventRecord] { lock.lock(); defer { lock.unlock() }; return Array(events.suffix(limit)) }
    public func recentWrites(limit: Int) -> [KeyWriteRecord] { lock.lock(); defer { lock.unlock() }; return Array(writes.suffix(limit)) }
}

public final class StaticConflictScanner: ConflictScanning {
    public var report: ConflictReport
    public init(report: ConflictReport = .none) { self.report = report }
    public func scan() -> ConflictReport { report }
}

public final class SimulatedLid: LidStateReading {
    public var closed = false
    public init() {}
    public func isLidClosed() -> Bool? { closed }
}

public final class SimulatedEnergySampler: EnergySampling {
    let clock: TimeSource
    public init(clock: TimeSource) { self.clock = clock }
    public func sample() -> EnergySample {
        let t = clock.now.timeIntervalSince1970
        let wobble = { (phase: Double) in 1 + 0.3 * sin(t / 37 + phase) }
        let processes = [
            ProcessEnergy(pid: 4101, name: "Safari", energy: 18.4 * wobble(0), cpuMsPerSecond: 120),
            ProcessEnergy(pid: 4102, name: "Xcode", energy: 12.1 * wobble(1), cpuMsPerSecond: 95),
            ProcessEnergy(pid: 4103, name: "Music", energy: 4.2 * wobble(2), cpuMsPerSecond: 21),
            ProcessEnergy(pid: 4104, name: "Slack", energy: 3.7 * wobble(3), cpuMsPerSecond: 30),
            ProcessEnergy(pid: 4105, name: "Finder", energy: 0.9 * wobble(4), cpuMsPerSecond: 4),
        ]
        return EnergySample(date: clock.now, method: .powermetrics, processes: processes, note: "Simulated")
    }
}
