import XCTest
@testable import ChargeGuardCore

/// End-to-end: ChargeController + backend + SimulatedSMC + SimulatedBattery.
final class ControllerTests: XCTestCase {

    func testFirstRunNeverWrites() {
        let sim = SimHarness(charge: 90, config: PolicyConfig())
        sim.run(until: { false }, step: 60, limit: 3600)
        XCTAssertTrue(sim.smc.writeLog.isEmpty, "no SMC write before the first-run confirmation")
        XCTAssertEqual(sim.status.chargeStatus, .disabled)
        _ = sim.command(.confirmFirstRun)
        XCTAssertTrue(sim.smc.chargingInhibited, "first write happens after confirmation")
    }

    func testLimitHoldsForHours() {
        let sim = SimHarness(charge: 60)
        XCTAssertTrue(sim.run(until: { sim.percentage >= 80 }, step: 30, limit: 3 * 3600))
        sim.run(until: { false }, step: 30, limit: 2 * 3600)
        XCTAssertGreaterThanOrEqual(sim.percentage, 78)
        XCTAssertLessThanOrEqual(sim.percentage, 81)
        XCTAssertTrue(sim.smc.chargingInhibited)
        XCTAssertEqual(sim.status.chargeStatus, .limitReached(limit: 80))
    }

    func testDischargeCommandEndToEnd() {
        let sim = SimHarness(charge: 90)
        _ = sim.command(.setChargeLimit(70))
        _ = sim.command(.startDischarge)
        XCTAssertTrue(sim.smc.dischargeForced)
        XCTAssertTrue(sim.run(until: { !sim.smc.dischargeForced }, step: 30, limit: 3 * 3600))
        XCTAssertEqual(sim.percentage, 70)
        XCTAssertTrue(sim.smc.chargingInhibited)
    }

    func testStartDischargeRejectedDuringCalibration() {
        let sim = SimHarness(charge: 70)
        _ = sim.command(.startCalibration(fast: false, origin: "t"))
        XCTAssertTrue(sim.command(.startDischarge).isError)
    }

    func testConflictBlocksAllWrites() {
        let sim = SimHarness(charge: 90)
        XCTAssertTrue(sim.smc.chargingInhibited)
        sim.conflicts.report = ConflictReport(active: ["AlDente (app running)"])
        sim.controller.systemDidWake() // forces a rescan
        sim.smc.clearWriteLog()
        sim.tick()
        sim.tick(120)
        XCTAssertTrue(sim.smc.writeLog.isEmpty, "never write while another tool runs")
        if case .conflict = sim.status.chargeStatus {} else { XCTFail("expected conflict, got \(sim.status.chargeStatus)") }
        sim.conflicts.report = .none
        sim.tick(61)
        XCTAssertEqual(sim.status.chargeStatus, .limitReached(limit: 80))
    }

    func testRestoreCommandWritesDeactivateValuesAndStopsControl() {
        let sim = SimHarness(charge: 90)
        XCTAssertTrue(sim.smc.chargingInhibited)
        _ = sim.command(.restoreNormalCharging)
        XCTAssertFalse(sim.smc.chargingInhibited)
        XCTAssertFalse(sim.smc.dischargeForced)
        XCTAssertEqual(sim.smc.value("ACLC"), [0x00])
        sim.tick(60)
        XCTAssertFalse(sim.smc.chargingInhibited, "control stays off after a restore")
        XCTAssertFalse(sim.status.config.controlEnabled)
        XCTAssertFalse(sim.status.keysDirty)
    }

    func testAppQuitRestoreOnQuit() {
        var config = enabledConfig()
        config.appClosedBehavior = .restoreOnQuit
        let sim = SimHarness(charge: 90, config: config)
        XCTAssertTrue(sim.smc.chargingInhibited)
        _ = sim.command(.appWillQuit)
        XCTAssertFalse(sim.smc.chargingInhibited)
        XCTAssertEqual(sim.status.chargeStatus, .suspended)
        _ = sim.command(.appLaunched)
        XCTAssertTrue(sim.smc.chargingInhibited)
    }

    func testAppQuitKeepEnforced() {
        let sim = SimHarness(charge: 90)
        _ = sim.command(.appWillQuit)
        XCTAssertTrue(sim.smc.chargingInhibited, "the helper keeps enforcing by default")
    }

    func testShutdownRestores() {
        let sim = SimHarness(charge: 90)
        XCTAssertTrue(sim.smc.chargingInhibited)
        sim.controller.shutdownSync(reason: "SIGTERM")
        XCTAssertFalse(sim.smc.chargingInhibited)
        XCTAssertEqual(sim.store.state?.keysDirty, false)
    }

    func testStaleStateRestoredOnStartWithRestoreOnQuit() {
        let clock = ManualTimeSource(t0)
        var config = enabledConfig()
        config.appClosedBehavior = .restoreOnQuit
        var state = PersistedState(config: config)
        state.keysDirty = true
        state.control.enforcementSuspended = true
        let store = InMemoryStateStore(state: state)
        // A previous run left CHTE set.
        let (deps, _) = ControllerDependencies.makeSimulated(clock: clock, charge: 90)
        (deps.smc as! SimulatedSMC).addKey("CHTE", type: "hex_", bytes: SMCValue.chteInhibit)
        var d = deps
        d.store = store
        let controller = ChargeController(dependencies: d)
        controller.startSync(startTimer: false)
        XCTAssertFalse((deps.smc as! SimulatedSMC).chargingInhibited)
        XCTAssertEqual(store.state?.keysDirty, false)
    }

    func testFailoverToFirmwareOnNotPrivileged() {
        let sim = SimHarness(profile: .firmwareGated, charge: 90)
        // The first write to CHTE fails with kIOReturnNotPrivileged; the next tick uses the firmware limit.
        XCTAssertEqual(sim.status.backend, .firmwareLimit)
        sim.tick(10)
        XCTAssertEqual(sim.smc.firmwareUpperLimit, 80)
        XCTAssertTrue(sim.events.contains { if case .backendChanged = $0.event { return true } else { return false } })
    }

    func testUnsupportedMacShowsError() {
        let sim = SimHarness(profile: .unsupported, charge: 90)
        XCTAssertEqual(sim.status.backend, .none)
        if case .error = sim.status.chargeStatus {} else { XCTFail("expected error state, got \(sim.status.chargeStatus)") }
    }

    func testWritesNotRetriedFasterThanInterval() {
        let sim = SimHarness(charge: 90)
        _ = sim.command(.restoreNormalCharging)
        sim.smc.failAllWrites = true
        _ = sim.command(.setControlEnabled(true)) // wants CHTE inhibited: the write fails
        let attempts = sim.store.writes.filter { !$0.success }.count
        XCTAssertEqual(attempts, 1)
        _ = sim.command(.setChargeLimit(75)) // immediate tick right after a failure
        XCTAssertEqual(sim.store.writes.filter { !$0.success }.count, attempts, "no retry inside one interval")
        sim.tick(5)
        XCTAssertGreaterThan(sim.store.writes.filter { !$0.success }.count, attempts)
        if case .error = sim.status.chargeStatus {} else { XCTFail("visible error state expected") }
    }

    func testLowPowerModeAppliedOnPowerSourceChange() {
        var config = enabledConfig()
        config.lowPowerMode = .onlyOnBattery
        let sim = SimHarness(charge: 60, config: config)
        XCTAssertFalse(sim.power.lowPowerMode)
        sim.battery.adapterConnected = false
        sim.tick()
        XCTAssertTrue(sim.power.lowPowerMode)
        sim.battery.adapterConnected = true
        sim.tick()
        XCTAssertFalse(sim.power.lowPowerMode)
        XCTAssertEqual(sim.power.lowPowerWrites, [true, false])
    }

    func testHeatPauseInSimulation() {
        var config = enabledConfig()
        config.heatProtection.enabled = true
        let sim = SimHarness(charge: 50, config: config)
        XCTAssertFalse(sim.smc.chargingInhibited)
        sim.battery.setTemperature(38)
        sim.tick()
        XCTAssertTrue(sim.smc.chargingInhibited)
        XCTAssertEqual(sim.status.chargeStatus.kind, .heatPaused)
        sim.battery.setTemperature(32)
        sim.tick()
        XCTAssertFalse(sim.smc.chargingInhibited)
    }

    func testSleepHooks() {
        var config = enabledConfig()
        config.stopChargingWhenSleeping = true
        let sim = SimHarness(charge: 50, config: config)
        XCTAssertFalse(sim.smc.chargingInhibited)
        let done = expectation(description: "sleep prepared")
        sim.controller.systemWillSleep { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(sim.smc.chargingInhibited, "blocked before sleep")
        sim.controller.systemDidWake()
        sim.controller.tickSync()
        XCTAssertFalse(sim.smc.chargingInhibited, "re-evaluated on wake")
    }

    func testClamshellSleepHoldRestoresPreviousValue() {
        var config = enabledConfig(limit: 60)
        config.dischargeInClamshell = true
        config.clamshellForceAwake = true
        let sim = SimHarness(charge: 90, config: config)
        _ = sim.command(.setExternalDisplayConnected(true))
        _ = sim.command(.startDischarge)
        XCTAssertTrue(sim.power.sleepDisabled)
        XCTAssertEqual(sim.store.state?.sleepDisabledSnapshot, false)
        XCTAssertTrue(sim.assertions.current.preventSystemSleep)
        _ = sim.command(.stopDischarge)
        XCTAssertFalse(sim.power.sleepDisabled)
        XCTAssertNil(sim.store.state?.sleepDisabledSnapshot)
    }

    func testKeepAwakeCommand() {
        let sim = SimHarness(charge: 60)
        _ = sim.command(.keepAwake(KeepAwakeRequest(durationSeconds: 3600, preventDisplaySleep: true)))
        XCTAssertTrue(sim.assertions.current.preventIdleSystemSleep)
        XCTAssertTrue(sim.assertions.current.preventDisplaySleep)
        sim.tick(3601)
        XCTAssertFalse(sim.assertions.current.preventIdleSystemSleep)
    }

    func testTopUpCommand() {
        let sim = SimHarness(charge: 80)
        sim.tick()
        XCTAssertTrue(sim.smc.chargingInhibited)
        _ = sim.command(.startTopUp)
        XCTAssertFalse(sim.smc.chargingInhibited)
        XCTAssertEqual(sim.status.chargeStatus, .toppingUp)
        sim.tick()
        XCTAssertNotNil(sim.status.topUpMinutesRemaining, "estimate once charging current flows")
        XCTAssertTrue(sim.run(until: { sim.status.control.topUp == nil }, step: 30, limit: 4 * 3600))
        XCTAssertGreaterThanOrEqual(sim.percentage, 100)
    }

    func testMagSafeLEDFollowsState() {
        var config = enabledConfig()
        config.magSafeLED = .followState
        let sim = SimHarness(charge: 70, config: config)
        XCTAssertEqual(sim.smc.value("ACLC"), SMCValue.ledOrange)
        _ = sim.command(.setChargeLimit(70))
        XCTAssertEqual(sim.smc.value("ACLC"), SMCValue.ledGreen)
        _ = sim.command(.setMagSafeLED(.systemDefault))
        XCTAssertEqual(sim.smc.value("ACLC"), SMCValue.ledSystem)
    }

    func testImportKeepsControlState() {
        let sim = SimHarness(charge: 60)
        let export = SettingsExport(exportedAt: t0, config: PolicyConfig(controlEnabled: false, chargeLimit: 70), schedule: [])
        _ = sim.command(.importSettings(export))
        XCTAssertTrue(sim.status.config.controlEnabled)
        XCTAssertEqual(sim.status.config.chargeLimit, 70)
    }

    func testPrepareUninstall() {
        let sim = SimHarness(charge: 90)
        _ = sim.command(.keepAwake(KeepAwakeRequest(durationSeconds: nil)))
        _ = sim.command(.prepareUninstall)
        XCTAssertFalse(sim.smc.chargingInhibited)
        XCTAssertEqual(sim.assertions.current, .none)
        XCTAssertFalse(sim.status.config.controlEnabled)
    }

    func testSimulatedBackendIsUsedInSimulation() {
        let sim = SimHarness()
        XCTAssertEqual(sim.status.backend, .simulated)
        XCTAssertTrue(sim.status.simulated)
    }
}
