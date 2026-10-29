import XCTest
import ChargeGuardCore
@testable import ChargeGuardSystem

final class AppleSMCLayoutTests: XCTestCase {
    /// The Swift struct must match the 80-byte C SMCKeyData_t exactly.
    func testParamStructLayout() {
        XCTAssertNil(AppleSMC.layoutProblem())
    }

    func testLaunchctlListParsing() {
        let text = "PID\tStatus\tLabel\n123\t0\tcc.chlc.batt\n-\t0\tcom.apple.something\n"
        XCTAssertEqual(ConflictScanner.parseLaunchctlList(text), ["cc.chlc.batt", "com.apple.something"])
    }

    /// Read-only: opens AppleSMC and probes the section 5 keys. Never writes. Works without root.
    func testProbeIsReadOnly() throws {
        // CI runners and VMs have no AppleSMC user client.
        guard let smc = try? AppleSMC() else { throw XCTSkip("AppleSMC unavailable on this machine") }
        let report = KeyProber.probe(smc)
        XCTAssertEqual(report.entries.count, SMCKey.probeKeys.count)
        print(report.text)
    }

    func testBatteryReaderReadsSomething() throws {
        let snapshot = try IORegistryBatteryReader().readSnapshot()
        if snapshot.batteryInstalled {
            XCTAssertTrue((0...100).contains(snapshot.percentage))
            XCTAssertGreaterThan(snapshot.voltageMV, 0)
        }
    }
}
