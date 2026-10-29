import XCTest
@testable import ChargeGuardCore

final class CodecTests: XCTestCase {

    func roundTrip(_ request: HelperRequest, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try MessageCodec.encode(request)
        XCTAssertEqual(try MessageCodec.decodeRequest(data), request, file: file, line: line)
    }

    func testRequestRoundTrips() throws {
        try roundTrip(.hello(clientProtocolVersion: 1, client: "app"))
        try roundTrip(.getStatus)
        try roundTrip(.command(.setChargeLimit(75)))
        try roundTrip(.command(.updateConfig(enabledConfig())))
        try roundTrip(.command(.keepAwake(KeepAwakeRequest(durationSeconds: 3600, untilChargeLimit: false, preventDisplaySleep: true))))
        try roundTrip(.command(.setSchedule([ScheduleRule(weekdays: [2, 3], hour: 7, minute: 15, action: .setLimit(60),
                                                         createdAt: t0)])))
        try roundTrip(.command(.startCalibration(fast: true, origin: "shortcut")))
        try roundTrip(.command(.setLowPowerMode(.onlyOnBattery)))
        try roundTrip(.command(.importSettings(SettingsExport(exportedAt: t0, config: enabledConfig(), schedule: []))))
        try roundTrip(.readKey("CHTE"))
        try roundTrip(.recentWrites(limit: 20))
    }

    func testStatusResponseRoundTrips() throws {
        let sim = SimHarness(charge: 80)
        let status = sim.status
        let data = try MessageCodec.encode(.status(status))
        XCTAssertEqual(try MessageCodec.decodeResponse(data), .status(status))
    }

    func testVersionMismatchRejected() throws {
        let envelope = MessageEnvelope(protocolVersion: HelperProtocol.version + 1, payload: HelperRequest.getStatus)
        let data = try CoreJSON.encoder().encode(envelope)
        XCTAssertThrowsError(try MessageCodec.decodeRequest(data)) { error in
            XCTAssertEqual(error as? MessageCodecError,
                           .versionMismatch(local: HelperProtocol.version, remote: HelperProtocol.version + 1))
        }
    }

    func testHelloAcceptedFromOtherVersions() throws {
        let envelope = MessageEnvelope(protocolVersion: 99, payload: HelperRequest.hello(clientProtocolVersion: 99, client: "future app"))
        let data = try CoreJSON.encoder().encode(envelope)
        XCTAssertEqual(try MessageCodec.decodeRequest(data), .hello(clientProtocolVersion: 99, client: "future app"))
    }

    func testMalformed() {
        XCTAssertThrowsError(try MessageCodec.decodeRequest(Data("not json".utf8)))
        XCTAssertNoThrow(try MessageCodec.decodeResponse(MessageCodec.errorData("boom")))
    }

    func testHandshakeReportsCompatibility() {
        let sim = SimHarness()
        guard case .hello(let info) = sim.controller.handleSync(.hello(clientProtocolVersion: HelperProtocol.version, client: "test")) else {
            return XCTFail("expected hello")
        }
        XCTAssertTrue(info.compatible)
        guard case .hello(let old) = sim.controller.handleSync(.hello(clientProtocolVersion: 0, client: "old")) else {
            return XCTFail("expected hello")
        }
        XCTAssertFalse(old.compatible)
    }
}

final class PersistenceTests: XCTestCase {

    func testOlderFileWithMissingFieldsLoads() throws {
        let json = #"{"schemaVersion":1,"config":{"chargeLimit":70,"controlEnabled":true},"control":{"manualDischarge":true}}"#
        let state = try PersistedState.decode(Data(json.utf8))
        XCTAssertEqual(state.config.chargeLimit, 70)
        XCTAssertTrue(state.config.controlEnabled)
        XCTAssertEqual(state.config.sailing.range, 5, "defaults fill missing fields")
        XCTAssertTrue(state.control.manualDischarge)
        XCTAssertFalse(state.keysDirty)
    }

    func testNewerSchemaRejected() {
        let json = #"{"schemaVersion":99}"#
        XCTAssertThrowsError(try PersistedState.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? PersistenceError, .newerSchema(99))
        }
    }

    func testRoundTrip() throws {
        var state = PersistedState(config: enabledConfig(limit: 65))
        state.control.calibration = CalibrationMachine.start(config: state.config, snapshot: snap(60), now: t0, origin: "t")
        state.schedule = [ScheduleRule(hour: 6, minute: 0, action: .topUp, createdAt: t0)]
        state.keysDirty = true
        XCTAssertEqual(try PersistedState.decode(state.encoded()), state)
    }

    func testImportNeverEnablesControl() {
        let export = SettingsExport(exportedAt: t0, config: enabledConfig(limit: 300), schedule: [])
        let imported = export.configForImport(keepingControlEnabled: false)
        XCTAssertFalse(imported.controlEnabled)
        XCTAssertEqual(imported.chargeLimit, 100, "normalized")
    }
}

final class PowermetricsParserTests: XCTestCase {

    let textFixture = """
    *** Sampled system activity (Thu Oct 29 10:00:00 2026 +0100) (1003.21ms elapsed) ***

    *** Running tasks ***

    Name                               ID     CPU ms/s  User%  Deadlines (<2 ms, 2-5 ms)  Wakeups (Intr, Pkg idle)  Energy Impact
    WindowServer                       153    45.12     60.10  12.96   0.00              150.55  20.94             32.10
    Google Chrome Helper (Renderer)    4501   80.40     90.00  0.00    0.00              40.00   3.00              55.70
    Code Helper 2                      912    10.00     80.00  0.00    0.00              10.00   1.00              7.25
    kernel_task                        0      30.00     0.00   0.00    0.00              900.00  100.00            40.00
    ALL_TASKS                          -2     300.00    50.00  20.00   1.00              2000.00 300.00            200.00

    **** Battery and backlight usage ****
    """

    func testTextParserHandlesSpacesAndDigitsInNames() {
        let tasks = PowermetricsParser.parseText(textFixture)
        XCTAssertEqual(tasks.map(\.name), ["WindowServer", "Google Chrome Helper (Renderer)", "Code Helper 2"])
        XCTAssertEqual(tasks.map(\.pid), [153, 4501, 912])
        XCTAssertEqual(tasks[1].energy, 55.70, accuracy: 0.001)
        XCTAssertEqual(tasks[0].cpuMsPerSecond ?? 0, 45.12, accuracy: 0.001)
        let sample = EnergySample(date: t0, method: .powermetrics, processes: tasks)
        XCTAssertEqual(sample.top(1).first?.name, "Google Chrome Helper (Renderer)")
    }

    func testTextParserWithoutTable() {
        XCTAssertTrue(PowermetricsParser.parseText("nothing here").isEmpty)
    }

    func testPlistParser() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>tasks</key>
          <array>
            <dict>
              <key>pid</key><integer>4501</integer>
              <key>name</key><string>Safari</string>
              <key>cputime_ms_per_s</key><real>80.5</real>
              <key>energy_impact</key><real>42.25</real>
            </dict>
            <dict>
              <key>pid</key><integer>-2</integer>
              <key>name</key><string>ALL_TASKS</string>
              <key>energy_impact</key><real>100</real>
            </dict>
            <dict>
              <key>pid</key><integer>77</integer>
              <key>name</key><string>mds</string>
              <key>energy_impact_per_s</key><real>3.5</real>
            </dict>
          </array>
        </dict>
        </plist>
        """
        var data = Data(plist.utf8)
        data.append(0)
        data.append(Data(plist.utf8))
        let tasks = PowermetricsParser.parsePlist(data)
        XCTAssertEqual(tasks.map(\.name), ["Safari", "mds"])
        XCTAssertEqual(tasks[0].energy, 42.25, accuracy: 0.001)
        XCTAssertEqual(tasks[1].energy, 3.5, accuracy: 0.001)
        XCTAssertEqual(tasks[0].cpuMsPerSecond ?? 0, 80.5, accuracy: 0.001)
    }
}

final class ConflictRulesTests: XCTestCase {
    func testDetectsEachTool() {
        XCTAssertEqual(ConflictRules.evaluate(ConflictScanInput(processNames: ["Finder", "AlDente"])).active,
                       ["AlDente (app running)"])
        XCTAssertEqual(ConflictRules.evaluate(ConflictScanInput(launchdLabels: ["cc.chlc.batt"])).active, ["batt (cc.chlc.batt)"])
        XCTAssertEqual(ConflictRules.evaluate(ConflictScanInput(launchdLabels: ["homebrew.mxcl.batt"])).active.count, 1)
        XCTAssertEqual(ConflictRules.evaluate(ConflictScanInput(processNames: ["batt"])).active, ["batt (process running)"])
        XCTAssertEqual(ConflictRules.evaluate(ConflictScanInput(launchdLabels: ["com.battery.app"])).active.count, 1)
        XCTAssertEqual(ConflictRules.evaluate(ConflictScanInput(processCommandLines: ["/bin/bash /usr/local/co.palokaj.battery/battery maintain 80"])).active.count, 1)
    }

    func testAlDenteHelperAloneIsNotAConflict() {
        let input = ConflictScanInput(processNames: ["com.apphousekitchen.aldente-pro.helper"],
                                      launchdLabels: ["com.apphousekitchen.aldente-pro.helper"])
        XCTAssertTrue(ConflictRules.evaluate(input).active.isEmpty)
    }

    func testInstalledButStoppedBatteryCLIIsInformational() {
        let report = ConflictRules.evaluate(ConflictScanInput(existingPaths: ["/usr/local/co.palokaj.battery"]))
        XCTAssertTrue(report.active.isEmpty)
        XCTAssertEqual(report.installedOnly.count, 1)
    }
}

final class PowerFlowTests: XCTestCase {
    func testChargingFlow() {
        var s = snap(60)
        s.voltageMV = 12_000
        s.amperageMA = 2_000 // 24 W into the battery
        s.systemPowerInW = 40
        let flow = PowerFlow.compute(from: s)
        XCTAssertEqual(flow.adapterW, 40, accuracy: 0.01)
        XCTAssertEqual(flow.adapterToBatteryW, 24, accuracy: 0.01)
        XCTAssertEqual(flow.adapterToSystemW, 16, accuracy: 0.01)
        XCTAssertEqual(flow.systemW, 16, accuracy: 0.01)
        XCTAssertEqual(flow.adapterSource, .measured)
    }

    func testDischargingFlow() {
        var s = snap(60, plugged: false)
        s.voltageMV = 12_000
        s.amperageMA = -1_000
        let flow = PowerFlow.compute(from: s)
        XCTAssertEqual(flow.batteryToSystemW, 12, accuracy: 0.01)
        XCTAssertEqual(flow.systemW, 12, accuracy: 0.01)
        XCTAssertEqual(flow.adapterW, 0)
    }

    func testRatedFallback() {
        var s = snap(80, charging: false)
        s.amperageMA = 0
        s.adapter = AdapterInfo(watts: 67)
        let flow = PowerFlow.compute(from: s)
        XCTAssertEqual(flow.adapterSource, .rated)
        XCTAssertEqual(flow.adapterToSystemW, 67, accuracy: 0.01)
    }

    func testBatterySnapshotMath() {
        let s = snap(50, rawCurrent: 2000, rawMax: 4000)
        XCTAssertEqual(s.hardwarePercentage, 50, accuracy: 0.001)
        XCTAssertEqual(s.healthPercent ?? 0, 4000.0 / 4382.0 * 100, accuracy: 0.01)
        XCTAssertEqual(TimeEstimates.format(minutes: 125), "2 h 5 min")
        XCTAssertEqual(TimeEstimates.format(minutes: nil), "—")
    }
}
