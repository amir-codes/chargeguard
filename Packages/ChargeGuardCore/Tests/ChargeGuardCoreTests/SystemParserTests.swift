import XCTest
@testable import ChargeGuardCore

final class SystemParserTests: XCTestCase {

    func registryFixture() -> [String: Any] {
        [
            "BatteryInstalled": true,
            "CurrentCapacity": 81,
            "MaxCapacity": 100,
            "AppleRawCurrentCapacity": 3_290,
            "AppleRawMaxCapacity": 4_120,
            "NominalChargeCapacity": 4_180,
            "DesignCapacity": 4_382,
            "CycleCount": 187,
            "Temperature": 3_056,
            "Voltage": 12_612,
            "Amperage": UInt64.max - 449, // -450 mA as AppleSmartBattery reports it
            "InstantAmperage": UInt64.max - 499,
            "IsCharging": false,
            "ExternalConnected": true,
            "FullyCharged": false,
            "TimeRemaining": 65_535,
            "AvgTimeToEmpty": 65_535,
            "Serial": "F8Y12345ABC",
            "AdapterDetails": ["Watts": 67, "Name": "67W USB-C Power Adapter", "Manufacturer": "Apple Inc."] as [String: Any],
            "PowerTelemetryData": ["SystemPowerIn": 14_250, "SystemLoad": 8_900] as [String: Any],
        ]
    }

    func testParsesAppleSmartBattery() {
        let s = BatteryRegistryParser.parse(registryFixture(), now: t0)
        XCTAssertEqual(s.percentage, 81)
        XCTAssertEqual(s.rawCurrentCapacityMAh, 3_290)
        XCTAssertEqual(s.hardwarePercentage, 3290.0 / 4120.0 * 100, accuracy: 0.001)
        XCTAssertEqual(s.temperatureC, 30.56, accuracy: 0.001)
        XCTAssertEqual(s.amperageMA, -450)
        XCTAssertEqual(s.instantAmperageMA, -500)
        XCTAssertNil(s.timeRemainingMinutes, "65535 means still calculating")
        XCTAssertEqual(s.adapter?.watts, 67)
        XCTAssertEqual(s.adapter?.name, "67W USB-C Power Adapter")
        XCTAssertEqual(s.systemPowerInW ?? 0, 14.25, accuracy: 0.001)
        XCTAssertEqual(s.systemLoadW ?? 0, 8.9, accuracy: 0.001)
        XCTAssertEqual(s.serial, "F8Y12345ABC")
        XCTAssertTrue(s.adapterPresent)
        XCTAssertEqual(s.healthPercent ?? 0, 4180.0 / 4382.0 * 100, accuracy: 0.01)
    }

    func testAdapterPresenceSurvivesForcedDischarge() {
        var d = registryFixture()
        d["ExternalConnected"] = false
        let s = BatteryRegistryParser.parse(d, now: t0, acPowerFromSMC: true)
        XCTAssertFalse(s.externalConnected)
        XCTAssertTrue(s.adapterPresent, "physical adapter still detected while the battery powers the Mac")
    }

    func testScaledPercentageWhenMaxCapacityIsNotPercent() {
        var d = registryFixture()
        d["CurrentCapacity"] = 2_000
        d["MaxCapacity"] = 4_000
        XCTAssertEqual(BatteryRegistryParser.parse(d, now: t0).percentage, 50)
    }

    func testTemperatureConversion() {
        XCTAssertEqual(BatteryRegistryParser.celsius(fromRaw: 3_056), 30.56, accuracy: 0.001)
    }

    func testPMSetParser() {
        let text = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
         lowpowermode         0
         hibernatemode        3
        """
        let settings = PMSetParser.parse(text)
        XCTAssertEqual(PMSetParser.flag(settings, "SleepDisabled"), true)
        XCTAssertEqual(PMSetParser.flag(settings, "lowpowermode"), false)
        XCTAssertNil(PMSetParser.flag(settings, "powernap"))
    }

    func testInProcessTransportRoundTrip() async throws {
        let clock = ManualTimeSource(t0)
        let (deps, _) = ControllerDependencies.makeSimulated(clock: clock, charge: 70)
        try deps.store.save(PersistedState(config: enabledConfig()))
        let transport = InProcessTransport(controller: ChargeController(dependencies: deps))
        transport.connect()
        let status = try await transport.command(.setChargeLimit(65))
        XCTAssertEqual(status?.config.chargeLimit, 65)
        let current = try await transport.status()
        XCTAssertEqual(current.effectiveLimit, 65)
        transport.invalidate()
    }
}
