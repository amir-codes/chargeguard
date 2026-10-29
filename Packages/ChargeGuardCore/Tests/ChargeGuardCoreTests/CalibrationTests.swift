import XCTest
@testable import ChargeGuardCore

final class CalibrationTests: XCTestCase {

    // MARK: Pure state machine

    func testPhasesInOrderWithRealHolds() {
        let config = enabledConfig()
        var cal = CalibrationMachine.start(config: config, snapshot: snap(60), now: t0, origin: "test")
        XCTAssertEqual(cal.holdSeconds, 3600)
        var now = t0

        func step(_ s: BatterySnapshot, after seconds: TimeInterval = 5, adapter: Bool = true) -> CalibrationMachine.Step {
            now = now.addingTimeInterval(seconds)
            let r = CalibrationMachine.advance(cal, percentage: s.percentage, snapshot: s, adapterConnected: adapter,
                                               config: config, now: now)
            if let next = r.state { cal = next }
            return r
        }

        XCTAssertEqual(step(snap(99)).state?.phase, .chargeToFull)
        XCTAssertEqual(step(snap(100, full: true)).state?.phase, .holdFull)
        XCTAssertEqual(step(snap(100), after: 3599).state?.phase, .holdFull, "hold lasts a full hour")
        let toB = step(snap(100), after: 2)
        XCTAssertEqual(toB.state?.phase, .dischargeToFloor)
        XCTAssertEqual(toB.state?.dischargeTarget, 15)
        XCTAssertEqual(step(snap(16, plugged: false), adapter: false).state?.phase, .dischargeToFloor)
        XCTAssertEqual(step(snap(15)).state?.phase, .rechargeToFull)
        XCTAssertEqual(step(snap(100, full: true)).state?.phase, .holdFullAgain)
        XCTAssertEqual(step(snap(100), after: 3600).state?.phase, .restoreLimit)
        let done = step(snap(100))
        XCTAssertNil(done.state)
        XCTAssertEqual(done.finished?.outcome, .completed)
        XCTAssertTrue(done.events.contains { if case .calibrationFinished = $0 { return true } else { return false } })
    }

    func testHoldRestartsWhenUnplugged() {
        let config = enabledConfig()
        var cal = CalibrationMachine.start(config: config, snapshot: snap(100), now: t0, origin: "test")
        cal.phase = .holdFull
        cal.holdStartedAt = t0
        let r = CalibrationMachine.advance(cal, percentage: 99, snapshot: snap(99, plugged: false), adapterConnected: false,
                                           config: config, now: t0.addingTimeInterval(60))
        XCTAssertEqual(r.state?.phase, .chargeToFull)
    }

    func testFastModeTargetsAndHolds() {
        var config = enabledConfig()
        config.calibration.fastMode = true
        let cal = CalibrationMachine.start(config: config, snapshot: snap(97), now: t0, origin: "test")
        XCTAssertEqual(cal.holdSeconds, 120)
        XCTAssertEqual(CalibrationMachine.dischargeTarget(fast: true, currentPercentage: 100, configuredFloor: 15), 97)
        XCTAssertEqual(CalibrationMachine.dischargeTarget(fast: true, currentPercentage: 12, configuredFloor: 15), 10,
                       "calibration never goes below 10 %")
    }

    func testFloorClamped() {
        XCTAssertEqual(CalibrationMachine.dischargeTarget(fast: false, currentPercentage: 100, configuredFloor: 3), 10)
        XCTAssertEqual(CalibrationMachine.dischargeTarget(fast: false, currentPercentage: 100, configuredFloor: 40), 20)
    }

    func testEngineDuringCalibration() {
        var h = EngineHarness()
        h.state.calibration = CalibrationMachine.start(config: h.config, snapshot: snap(85), now: t0, origin: "test")
        let a = h.step(snap(85))
        XCTAssertFalse(a.outputs.inhibitCharging, "phase A charges past the limit")
        XCTAssertEqual(a.effectiveLimit, 100)
        XCTAssertTrue(a.outputs.assertions.preventIdleSystemSleep)
        h.state.calibration?.phase = .dischargeToFloor
        h.state.calibration?.dischargeTarget = 15
        let b = h.step(snap(50))
        XCTAssertTrue(b.outputs.forceDischarge)
        XCTAssertTrue(b.outputs.inhibitCharging)
        XCTAssertTrue(b.outputs.assertions.preventIdleSystemSleep, "Mac kept awake in phase B")
        XCTAssertEqual(b.status, .calibrating(phase: .dischargeToFloor, waitingForAdapter: false))
    }

    func testPhaseDDischargesWithAutomaticDischarge() {
        var config = enabledConfig()
        config.automaticDischarge = true
        var h = EngineHarness(config: config)
        h.state.calibration = CalibrationMachine.start(config: config, snapshot: snap(100), now: t0, origin: "test")
        h.state.calibration?.phase = .restoreLimit
        let d = h.step(snap(100, charging: false))
        XCTAssertNil(d.nextState.calibration)
        XCTAssertTrue(d.outputs.forceDischarge, "Phase D discharges to the limit when Automatic Discharge is on")
        XCTAssertEqual(d.effectiveLimit, 80)
    }

    // MARK: Full run in simulation with real timings

    func testFullCalibrationInSimulationWithRealTimings() {
        let sim = SimHarness(charge: 70)
        XCTAssertEqual(sim.command(.startCalibration(fast: false, origin: "test")).isError, false)
        var phaseTimes: [CalibrationPhase: Date] = [:]
        var lastPhase: CalibrationPhase? = .chargeToFull
        phaseTimes[.chargeToFull] = sim.clock.now
        let finished = sim.run(until: {
            let phase = sim.status.control.calibration?.phase
            if phase != lastPhase, let phase { phaseTimes[phase] = sim.clock.now }
            lastPhase = phase
            return phase == nil
        }, step: 30, limit: 24 * 3600)
        XCTAssertTrue(finished, "calibration finishes within a simulated day")
        let holdA = phaseTimes[.dischargeToFloor]!.timeIntervalSince(phaseTimes[.holdFull]!)
        let holdC = phaseTimes[.restoreLimit]!.timeIntervalSince(phaseTimes[.holdFullAgain]!)
        XCTAssertGreaterThanOrEqual(holdA, 3600)
        XCTAssertLessThan(holdA, 3600 + 61)
        XCTAssertGreaterThanOrEqual(holdC, 3600)
        XCTAssertEqual(sim.store.calibrations.last?.outcome, .completed)
        XCTAssertGreaterThanOrEqual(sim.store.calibrations.count, 1)
        XCTAssertFalse(sim.store.writes.isEmpty, "the simulated run wrote keys")
        XCTAssertFalse(sim.smc.dischargeForced, "discharge key back off after calibration")
    }

    func testFastCalibrationCompletesQuickly() {
        var config = enabledConfig()
        config.calibration.fastMode = true
        let sim = SimHarness(charge: 97, config: config)
        _ = sim.command(.startCalibration(fast: true, origin: "test"))
        let start = sim.clock.now
        let finished = sim.run(until: { sim.status.control.calibration == nil }, step: 5, limit: 3 * 3600)
        XCTAssertTrue(finished)
        let minutes = sim.clock.now.timeIntervalSince(start) / 60
        XCTAssertLessThan(minutes, 90, "fast mode finishes quickly even from 97 % in the simulator")
    }

    func testCalibrationSurvivesRestart() {
        let store = InMemoryStateStore()
        let clock = ManualTimeSource(t0)
        let first = SimHarness(charge: 70, store: store, clock: clock)
        _ = first.command(.startCalibration(fast: false, origin: "test"))
        first.tick()
        XCTAssertNotNil(store.state?.control.calibration)
        first.controller.shutdownSync(reason: "test restart")

        let second = SimHarness(charge: 70, config: nil, store: store, clock: clock)
        XCTAssertEqual(second.status.control.calibration?.phase, .chargeToFull)
    }

    func testCancelRecordsHistory() {
        let sim = SimHarness(charge: 70)
        _ = sim.command(.startCalibration(fast: false, origin: "test"))
        _ = sim.command(.cancelCalibration)
        XCTAssertNil(sim.status.control.calibration)
        XCTAssertEqual(sim.store.calibrations.last?.outcome, .cancelled)
    }
}

extension HelperResponse {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
