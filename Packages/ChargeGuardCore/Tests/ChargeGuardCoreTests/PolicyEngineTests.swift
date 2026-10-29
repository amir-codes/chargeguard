import XCTest
@testable import ChargeGuardCore

final class PolicyEngineTests: XCTestCase {

    // MARK: Gates

    func testControlDisabledNeverWrites() {
        var h = EngineHarness(config: PolicyConfig())
        let d = h.step(snap(90))
        XCTAssertFalse(d.writesAllowed)
        XCTAssertEqual(d.status, .disabled)
        XCTAssertEqual(d.outputs, .normal)
    }

    func testConflictBlocksWrites() {
        var h = EngineHarness()
        h.context.conflicts = ["AlDente (app running)"]
        let d = h.step(snap(90))
        XCTAssertFalse(d.writesAllowed)
        XCTAssertEqual(d.status, .conflict(tools: ["AlDente (app running)"]))
    }

    func testNoBattery() {
        var h = EngineHarness()
        var s = snap(50)
        s.batteryInstalled = false
        let d = h.step(s)
        XCTAssertFalse(d.writesAllowed)
        XCTAssertEqual(d.status, .noBattery)
    }

    func testSuspendedRestoresNormalAndSystemLED() {
        var h = EngineHarness()
        h.state.enforcementSuspended = true
        h.state.ledManaged = true
        let d = h.step(snap(90))
        XCTAssertTrue(d.writesAllowed)
        XCTAssertFalse(d.outputs.inhibitCharging)
        XCTAssertEqual(d.outputs.led, .system)
        XCTAssertEqual(d.status, .suspended)
        XCTAssertFalse(d.nextState.ledManaged)
    }

    // MARK: Feature 1: Charge Limiter with hysteresis

    func testLimitAndHysteresisTrace() {
        var h = EngineHarness()
        XCTAssertFalse(h.step(snap(70)).outputs.inhibitCharging)
        XCTAssertEqual(h.step(snap(79)).status, .charging(target: 80))
        let atLimit = h.step(snap(80))
        XCTAssertTrue(atLimit.outputs.inhibitCharging)
        XCTAssertEqual(atLimit.status, .limitReached(limit: 80))
        XCTAssertTrue(atLimit.events.contains(.limitReached(limit: 80)))
        // Inside the 2 % band: stays blocked.
        XCTAssertTrue(h.step(snap(79)).outputs.inhibitCharging)
        XCTAssertTrue(h.step(snap(78)).outputs.inhibitCharging)
        // Below limit - 2: resumes.
        XCTAssertFalse(h.step(snap(77)).outputs.inhibitCharging)
        XCTAssertFalse(h.step(snap(79)).outputs.inhibitCharging)
        XCTAssertTrue(h.step(snap(80)).outputs.inhibitCharging)
    }

    func testAboveLimitWhenPluggedInBlocksImmediately() {
        var h = EngineHarness()
        let d = h.step(snap(93))
        XCTAssertTrue(d.outputs.inhibitCharging)
        XCTAssertFalse(d.outputs.forceDischarge, "no automatic discharge unless enabled")
    }

    func testRaisingLimitReleasesLatch() {
        var h = EngineHarness()
        XCTAssertTrue(h.step(snap(80)).outputs.inhibitCharging)
        h.config.chargeLimit = 85
        let d = h.step(snap(80))
        XCTAssertFalse(d.outputs.inhibitCharging)
        XCTAssertEqual(d.status, .charging(target: 85))
    }

    func testLimit100NeverBlocks() {
        var h = EngineHarness(config: enabledConfig(limit: 100))
        XCTAssertFalse(h.step(snap(99)).outputs.inhibitCharging)
        XCTAssertEqual(h.step(snap(100, charging: false, full: true)).status, .fullyCharged)
    }

    func testOnBatteryStatus() {
        var h = EngineHarness()
        let d = h.step(snap(60, plugged: false))
        XCTAssertEqual(d.status, .onBattery)
        XCTAssertFalse(d.outputs.forceDischarge)
    }

    func testLimitClampedToRange() {
        var h = EngineHarness(config: enabledConfig(limit: 5))
        let d = h.step(snap(25))
        XCTAssertEqual(d.effectiveLimit, 20)
        XCTAssertTrue(d.outputs.inhibitCharging)
    }

    func testHardwarePercentageOption() {
        var config = enabledConfig()
        config.useHardwarePercentage = true
        var h = EngineHarness(config: config)
        // macOS says 82 %, hardware says 78 %.
        let d = h.step(snap(82, rawCurrent: 3120, rawMax: 4000))
        XCTAssertEqual(d.controlPercentage, 78)
        XCTAssertFalse(d.outputs.inhibitCharging)
    }

    // MARK: Feature 6: Sailing

    func testSailingTrace() {
        var config = enabledConfig()
        config.sailing = SailingConfig(enabled: true, range: 5)
        var h = EngineHarness(config: config)
        let reached = h.step(snap(80))
        XCTAssertEqual(reached.status, .sailing(limit: 80, resumeAt: 75))
        XCTAssertTrue(reached.outputs.inhibitCharging)
        XCTAssertTrue(h.step(snap(77)).outputs.inhibitCharging)
        XCTAssertTrue(h.step(snap(76)).outputs.inhibitCharging)
        let resumed = h.step(snap(75))
        XCTAssertFalse(resumed.outputs.inhibitCharging)
        XCTAssertEqual(resumed.status, .charging(target: 80))
        XCTAssertEqual(resumed.outputs.resumeFloor, 75)
    }

    // MARK: Feature 5: Heat Protection

    func testHeatProtectionPausesAndResumes() {
        var config = enabledConfig()
        config.heatProtection = HeatProtectionConfig(enabled: true, maxTemperatureC: 35, resumeDeltaC: 2)
        var h = EngineHarness(config: config)
        XCTAssertFalse(h.step(snap(60, temp: 34.9)).outputs.inhibitCharging)
        let hot = h.step(snap(60, temp: 35))
        XCTAssertTrue(hot.outputs.inhibitCharging)
        XCTAssertEqual(hot.outputs.holdAtPercentage, 60)
        XCTAssertEqual(hot.status.kind, .heatPaused)
        XCTAssertTrue(hot.events.contains(.heatPaused(temperatureC: 35)))
        XCTAssertTrue(h.step(snap(60, temp: 33.5)).outputs.inhibitCharging, "resumes only at 33 °C")
        let cool = h.step(snap(60, temp: 33))
        XCTAssertFalse(cool.outputs.inhibitCharging)
        XCTAssertTrue(cool.events.contains(.heatResumed(temperatureC: 33)))
    }

    func testHeatOverridesTopUpAndCalibration() {
        var config = enabledConfig()
        config.heatProtection = HeatProtectionConfig(enabled: true, maxTemperatureC: 35)
        var h = EngineHarness(config: config)
        h.state.topUp = TopUpState(startedAt: t0, startPercentage: 80)
        XCTAssertTrue(h.step(snap(85, temp: 40)).outputs.inhibitCharging)

        var h2 = EngineHarness(config: config)
        h2.state.calibration = CalibrationMachine.start(config: config, snapshot: snap(50), now: t0, origin: "test")
        let d = h2.step(snap(50, temp: 41))
        XCTAssertTrue(d.outputs.inhibitCharging)
        XCTAssertEqual(d.status.kind, .heatPaused)
    }

    func testTurningHeatProtectionOffClearsLatch() {
        var config = enabledConfig()
        config.heatProtection.enabled = true
        var h = EngineHarness(config: config)
        h.step(snap(60, temp: 40))
        h.config.heatProtection.enabled = false
        XCTAssertFalse(h.step(snap(60, temp: 40)).outputs.inhibitCharging)
    }

    // MARK: Feature 7: Top Up

    func testTopUpChargesToFullThenReverts() {
        var h = EngineHarness()
        XCTAssertTrue(h.step(snap(80)).outputs.inhibitCharging)
        h.state.topUp = TopUpState(startedAt: t0, startPercentage: 80)
        let topping = h.step(snap(80))
        XCTAssertFalse(topping.outputs.inhibitCharging)
        XCTAssertEqual(topping.status, .toppingUp)
        XCTAssertEqual(topping.effectiveLimit, 100)
        XCTAssertFalse(h.step(snap(99)).outputs.inhibitCharging)
        let done = h.step(snap(100, charging: false, full: true))
        XCTAssertNil(done.nextState.topUp)
        XCTAssertTrue(done.events.contains(.topUpFinished(reason: "fully charged")))
        XCTAssertTrue(done.outputs.inhibitCharging, "configured limit applies again")
        XCTAssertEqual(done.effectiveLimit, 80)
    }

    func testTopUpEndsOnUnplug() {
        var h = EngineHarness()
        h.state.topUp = TopUpState(startedAt: t0, startPercentage: 80)
        let d = h.step(snap(90, plugged: false))
        XCTAssertNil(d.nextState.topUp)
        XCTAssertTrue(d.events.contains(.topUpFinished(reason: "adapter unplugged")))
    }

    func testTopUpTimesOut() {
        var h = EngineHarness()
        h.state.topUp = TopUpState(startedAt: t0, startPercentage: 80)
        let d = h.step(snap(90), advance: TopUpState.maximumDuration + 60)
        XCTAssertNil(d.nextState.topUp)
    }

    func testAutomaticDischargeWaitsAfterTopUp() {
        var config = enabledConfig()
        config.automaticDischarge = true
        var h = EngineHarness(config: config)
        h.state.topUp = TopUpState(startedAt: t0, startPercentage: 80)
        let done = h.step(snap(100, charging: false, full: true))
        XCTAssertFalse(done.outputs.forceDischarge, "top up must not be undone immediately")
        XCTAssertFalse(h.step(snap(100, charging: false)).outputs.forceDischarge)
        h.step(snap(99, plugged: false))
        XCTAssertTrue(h.step(snap(99)).outputs.forceDischarge, "after an unplug, automatic discharge works again")
    }

    // MARK: Feature 2 and 3: Discharge

    func testManualDischargeToLimitThenBlock() {
        var h = EngineHarness()
        h.state.manualDischarge = true
        let start = h.step(snap(90))
        XCTAssertTrue(start.outputs.forceDischarge)
        XCTAssertTrue(start.outputs.inhibitCharging)
        XCTAssertEqual(start.status, .discharging(target: 80, automatic: false))
        XCTAssertTrue(start.events.contains(.dischargeStarted(target: 80, automatic: false)))
        XCTAssertTrue(h.step(snap(81)).outputs.forceDischarge)
        let end = h.step(snap(80))
        XCTAssertFalse(end.outputs.forceDischarge)
        XCTAssertTrue(end.outputs.inhibitCharging, "charging stays blocked at the limit")
        XCTAssertFalse(end.nextState.manualDischarge)
        XCTAssertTrue(end.events.contains(.dischargeFinished(percentage: 80)))
        XCTAssertTrue(h.step(snap(79)).outputs.inhibitCharging)
    }

    func testDischargeNeedsAdapter() {
        var h = EngineHarness()
        h.state.manualDischarge = true
        let d = h.step(snap(90, plugged: false))
        XCTAssertFalse(d.outputs.forceDischarge)
        XCTAssertTrue(d.nextState.manualDischarge, "resumes when plugged in again")
    }

    func testDischargeUnavailableWithoutKey() {
        var h = EngineHarness()
        h.context.backend.canForceDischarge = false
        h.state.manualDischarge = true
        let d = h.step(snap(90))
        XCTAssertFalse(d.outputs.forceDischarge)
        XCTAssertEqual(d.status.kind, .discharging)
        if case .dischargePaused = d.status {} else { XCTFail("expected dischargePaused, got \(d.status)") }
    }

    func testAutomaticDischargeWhenLimitLowered() {
        var config = enabledConfig()
        config.automaticDischarge = true
        var h = EngineHarness(config: config)
        XCTAssertTrue(h.step(snap(80)).outputs.inhibitCharging)
        h.config.chargeLimit = 60
        let d = h.step(snap(80))
        XCTAssertTrue(d.outputs.forceDischarge)
        XCTAssertEqual(d.status, .discharging(target: 60, automatic: true))
        XCTAssertTrue(h.step(snap(61)).outputs.forceDischarge)
        let end = h.step(snap(60))
        XCTAssertFalse(end.outputs.forceDischarge)
        XCTAssertTrue(end.outputs.inhibitCharging)
    }

    func testNoAutomaticDischargeWhenSettingOff() {
        var h = EngineHarness()
        h.config.chargeLimit = 60
        XCTAssertFalse(h.step(snap(80)).outputs.forceDischarge)
    }

    func testAutomaticDischargeSuppressedFlag() {
        var config = enabledConfig(limit: 60)
        config.automaticDischarge = true
        var h = EngineHarness(config: config)
        h.state.autoDischargeSuppressed = true
        XCTAssertFalse(h.step(snap(80)).outputs.forceDischarge)
    }

    // MARK: Feature 4: Clamshell

    func testLidClosedPausesDischargeWithoutClamshellFeature() {
        var h = EngineHarness()
        h.state.manualDischarge = true
        h.context.lidClosed = true
        let d = h.step(snap(90))
        XCTAssertFalse(d.outputs.forceDischarge)
        XCTAssertTrue(d.outputs.inhibitCharging)
        if case .dischargePaused = d.status {} else { XCTFail("expected dischargePaused") }
        XCTAssertTrue(d.nextState.manualDischarge)
    }

    func testClamshellDischargeHoldsPreventSystemSleep() {
        var config = enabledConfig()
        config.dischargeInClamshell = true
        var h = EngineHarness(config: config)
        h.state.manualDischarge = true
        h.context.lidClosed = true
        let d = h.step(snap(90))
        XCTAssertTrue(d.outputs.forceDischarge)
        XCTAssertTrue(d.outputs.assertions.preventSystemSleep)
        XCTAssertFalse(d.outputs.holdSleepDisabled, "force-awake option is off")
    }

    func testClamshellForceAwakeNeedsExternalDisplay() {
        var config = enabledConfig()
        config.dischargeInClamshell = true
        config.clamshellForceAwake = true
        var h = EngineHarness(config: config)
        h.state.manualDischarge = true
        XCTAssertFalse(h.step(snap(90)).outputs.holdSleepDisabled)
        h.context.externalDisplayConnected = true
        XCTAssertTrue(h.step(snap(89)).outputs.holdSleepDisabled)
        let done = h.step(snap(80))
        XCTAssertFalse(done.outputs.holdSleepDisabled, "released when discharge ends")
    }

    // MARK: Feature 12: Sleep

    func testStopChargingWhenSleeping() {
        var config = enabledConfig()
        config.stopChargingWhenSleeping = true
        var h = EngineHarness(config: config)
        XCTAssertFalse(h.step(snap(50)).outputs.inhibitCharging)
        h.context.sleepImminent = true
        let d = h.step(snap(50))
        XCTAssertTrue(d.outputs.inhibitCharging)
        XCTAssertEqual(d.outputs.holdAtPercentage, 50)
        XCTAssertEqual(d.status, .sleepBlocked)
        XCTAssertFalse(d.nextState.chargeInhibitLatched, "sleep block does not touch the limit latch")
        h.context.sleepImminent = false
        XCTAssertFalse(h.step(snap(50)).outputs.inhibitCharging, "re-evaluated on wake")
    }

    func testSleepWithoutSettingKeepsCharging() {
        var h = EngineHarness()
        h.context.sleepImminent = true
        XCTAssertFalse(h.step(snap(50)).outputs.inhibitCharging)
    }

    func testDischargePausesForSleep() {
        var h = EngineHarness()
        h.state.manualDischarge = true
        h.context.sleepImminent = true
        let d = h.step(snap(90))
        XCTAssertFalse(d.outputs.forceDischarge)
        XCTAssertTrue(d.outputs.inhibitCharging)
        XCTAssertTrue(d.nextState.manualDischarge)
        h.context.sleepImminent = false
        XCTAssertTrue(h.step(snap(90)).outputs.forceDischarge, "resumes on wake")
    }

    // MARK: Adapter cutoff backend

    func testAdapterCutoffUsesMinimumBandAndReconnectsForSleep() {
        var h = EngineHarness()
        h.context.backend = BackendCapabilities(canInhibitCharging: true, canForceDischarge: true, inhibitIsAdapterCutoff: true,
                                                usesFirmwareLimit: false, canControlLED: false, enforcesDuringSleep: false)
        XCTAssertTrue(h.step(snap(80)).outputs.inhibitCharging)
        XCTAssertTrue(h.step(snap(77)).outputs.inhibitCharging, "band widened to 5 %")
        XCTAssertTrue(h.step(snap(76)).outputs.inhibitCharging)
        XCTAssertFalse(h.step(snap(74)).outputs.inhibitCharging)
        h.step(snap(80))
        h.context.sleepImminent = true
        let d = h.step(snap(80))
        XCTAssertFalse(d.outputs.inhibitCharging)
        XCTAssertFalse(d.outputs.forceDischarge)
    }

    // MARK: Features 10 and 11: sleep assertions

    func testDisableSleepUntilLimit() {
        var config = enabledConfig()
        config.disableSleepUntilLimit = true
        var h = EngineHarness(config: config)
        XCTAssertTrue(h.step(snap(70)).outputs.assertions.preventIdleSystemSleep)
        XCTAssertFalse(h.step(snap(80)).outputs.assertions.preventIdleSystemSleep)
        XCTAssertFalse(h.step(snap(70, plugged: false)).outputs.assertions.preventIdleSystemSleep)
    }

    func testKeepAwakeExpires() {
        var h = EngineHarness()
        h.state.keepAwake = KeepAwakeState(request: KeepAwakeRequest(durationSeconds: 1800, preventDisplaySleep: true),
                                           now: h.context.now)
        let d = h.step(snap(60))
        XCTAssertTrue(d.outputs.assertions.preventIdleSystemSleep)
        XCTAssertTrue(d.outputs.assertions.preventDisplaySleep)
        let expired = h.step(snap(60), advance: 1800)
        XCTAssertNil(expired.nextState.keepAwake)
        XCTAssertFalse(expired.outputs.assertions.preventIdleSystemSleep)
        XCTAssertTrue(expired.events.contains(.keepAwakeEnded))
    }

    func testKeepAwakeIndefinitely() {
        var h = EngineHarness()
        h.state.keepAwake = KeepAwakeState(request: KeepAwakeRequest(durationSeconds: nil), now: h.context.now)
        XCTAssertTrue(h.step(snap(60), advance: 100_000).outputs.assertions.preventIdleSystemSleep)
    }

    func testKeepAwakeUntilChargeLimit() {
        var h = EngineHarness()
        h.state.keepAwake = KeepAwakeState(request: KeepAwakeRequest(durationSeconds: nil, untilChargeLimit: true), now: h.context.now)
        XCTAssertTrue(h.step(snap(70)).outputs.assertions.preventIdleSystemSleep)
        let d = h.step(snap(80))
        XCTAssertNil(d.nextState.keepAwake)
        XCTAssertFalse(d.outputs.assertions.preventIdleSystemSleep)
    }

    // MARK: Feature 9: MagSafe LED

    func testLEDFollowsState() {
        var config = enabledConfig()
        config.magSafeLED = .followState
        var h = EngineHarness(config: config)
        XCTAssertEqual(h.step(snap(70)).outputs.led, .orange)
        XCTAssertEqual(h.step(snap(80)).outputs.led, .green)
        h.state.manualDischarge = true
        h.config.chargeLimit = 70
        XCTAssertEqual(h.step(snap(80)).outputs.led, .off)
        XCTAssertNil(h.step(snap(80, plugged: false)).outputs.led)
    }

    func testLEDSystemDefaultWrittenOnceWhenTurnedOff() {
        var config = enabledConfig()
        config.magSafeLED = .followState
        var h = EngineHarness(config: config)
        h.step(snap(70))
        h.config.magSafeLED = .systemDefault
        XCTAssertEqual(h.step(snap(70)).outputs.led, .system)
        XCTAssertNil(h.step(snap(70)).outputs.led)
    }

    func testLEDUntouchedWhenUnsupported() {
        var config = enabledConfig()
        config.magSafeLED = .followState
        var h = EngineHarness(config: config)
        h.context.backend.canControlLED = false
        XCTAssertNil(h.step(snap(70)).outputs.led)
    }

    // MARK: Feature 14: Low Power Mode

    func testLowPowerModePolicies() {
        XCTAssertNil(LowPowerModePolicy.unmanaged.desiredState(adapterConnected: true))
        XCTAssertEqual(LowPowerModePolicy.alwaysOn.desiredState(adapterConnected: true), true)
        XCTAssertEqual(LowPowerModePolicy.alwaysOff.desiredState(adapterConnected: false), false)
        XCTAssertEqual(LowPowerModePolicy.onlyOnBattery.desiredState(adapterConnected: false), true)
        XCTAssertEqual(LowPowerModePolicy.onlyOnBattery.desiredState(adapterConnected: true), false)
        XCTAssertEqual(LowPowerModePolicy.onlyOnAdapter.desiredState(adapterConnected: true), true)

        var config = enabledConfig()
        config.lowPowerMode = .onlyOnBattery
        var h = EngineHarness(config: config)
        XCTAssertEqual(h.step(snap(60, plugged: false)).outputs.lowPowerMode, true)
        XCTAssertEqual(h.step(snap(60)).outputs.lowPowerMode, false)
    }

    // MARK: Firmware backend hints

    func testHoldPercentageOnlyForOverrides() {
        var config = enabledConfig()
        config.stopChargingWhenSleeping = true
        var h = EngineHarness(config: config)
        XCTAssertNil(h.step(snap(80)).outputs.holdAtPercentage, "the limit itself is not an override")
        var h2 = EngineHarness(config: config)
        h2.state.manualDischarge = true
        h2.config.chargeLimit = 60
        XCTAssertEqual(h2.step(snap(80)).outputs.holdAtPercentage, 60, "discharge holds at its target")
    }

    func testDeterministic() {
        var config = enabledConfig()
        config.sailing.enabled = true
        config.heatProtection.enabled = true
        let state = ControlState(chargeInhibitLatched: true, lastEffectiveLimit: 80)
        let ctx = PolicyContext(now: t0)
        let a = PolicyEngine.evaluate(config: config, snapshot: snap(78, temp: 36), previous: state, context: ctx)
        let b = PolicyEngine.evaluate(config: config, snapshot: snap(78, temp: 36), previous: state, context: ctx)
        XCTAssertEqual(a, b)
    }
}
