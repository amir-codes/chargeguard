import Foundation
import XCTest
@testable import ChargeGuardCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func snap(_ pct: Int, plugged: Bool = true, temp: Double = 30, charging: Bool? = nil, full: Bool = false,
          rawCurrent: Int? = nil, rawMax: Int = 4000, adapterPresent: Bool? = nil) -> BatterySnapshot {
    BatterySnapshot(timestamp: t0,
                    percentage: pct,
                    rawCurrentCapacityMAh: rawCurrent ?? rawMax * pct / 100,
                    rawMaxCapacityMAh: rawMax,
                    designCapacityMAh: 4382,
                    cycleCount: 100,
                    temperatureC: temp,
                    voltageMV: 12_500,
                    amperageMA: (charging ?? (plugged && pct < 100)) ? 2000 : (plugged ? 0 : -700),
                    isCharging: charging ?? (plugged && pct < 100),
                    externalConnected: plugged,
                    adapterPresent: adapterPresent ?? plugged,
                    fullyCharged: full)
}

func enabledConfig(limit: Int = 80) -> PolicyConfig {
    var c = PolicyConfig()
    c.controlEnabled = true
    c.chargeLimit = limit
    return c
}

/// Feeds a trace of snapshots through the pure engine, carrying state between ticks.
struct EngineHarness {
    var config: PolicyConfig
    var state = ControlState()
    var context = PolicyContext(now: t0)

    init(config: PolicyConfig = enabledConfig()) {
        self.config = config
    }

    @discardableResult
    mutating func step(_ snapshot: BatterySnapshot, advance seconds: TimeInterval = 5) -> Decision {
        context.now = context.now.addingTimeInterval(seconds)
        let d = PolicyEngine.evaluate(config: config, snapshot: snapshot, previous: state, context: context)
        state = d.nextState
        return d
    }
}

func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// A controller on a simulated Mac, driven by a manual clock.
final class SimHarness {
    let clock: ManualTimeSource
    let deps: ControllerDependencies
    let battery: SimulatedBattery
    let controller: ChargeController
    var smc: SimulatedSMC { battery.smc }
    var store: InMemoryStateStore { deps.store as! InMemoryStateStore }
    var assertions: RecordingAssertions { deps.assertions as! RecordingAssertions }
    var power: SimulatedPowerSettings { deps.lowPowerMode as! SimulatedPowerSettings }
    var conflicts: StaticConflictScanner { deps.conflicts as! StaticConflictScanner }
    var lid: SimulatedLid { deps.lid as! SimulatedLid }
    var events: [EventRecord] = []

    init(profile: SimulatedSMC.Profile = .tahoe, charge: Double = 62, config: PolicyConfig? = enabledConfig(),
         store: InMemoryStateStore? = nil, clock: ManualTimeSource = ManualTimeSource(t0)) {
        self.clock = clock
        var (deps, battery) = ControllerDependencies.makeSimulated(profile: profile, clock: clock, charge: charge,
                                                                   calendar: utcCalendar())
        if let store { deps.store = store }
        if let config, (try? deps.store.load()) == nil {
            try? deps.store.save(PersistedState(config: config))
        }
        self.deps = deps
        self.battery = battery
        self.controller = ChargeController(dependencies: deps)
        controller.onEvents = { [weak self] records in self?.events += records }
        controller.startSync(startTimer: false)
    }

    func tick(_ seconds: TimeInterval = 5) {
        clock.advance(by: seconds)
        controller.tickSync()
    }

    /// Advances simulated time in ticks of `step` seconds until `condition` holds or `limit` passes.
    @discardableResult
    func run(until condition: () -> Bool, step: TimeInterval = 30, limit: TimeInterval) -> Bool {
        var elapsed: TimeInterval = 0
        while elapsed < limit {
            if condition() { return true }
            tick(step)
            elapsed += step
        }
        return condition()
    }

    func command(_ c: HelperCommand) -> HelperResponse {
        controller.handleSync(.command(c))
    }

    var status: DaemonStatus { controller.statusSync() }
    var percentage: Int { status.snapshot?.percentage ?? -1 }
}
