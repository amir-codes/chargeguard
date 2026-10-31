import XCTest
@testable import ChargeGuardCore

final class AdHocClientRuleTests: XCTestCase {

    func testAppIsMatchedByItsBundlePath() {
        // What SecCodeCopyPath returns for the running app (seen on the M2 with the 1.0.0 draft build).
        XCTAssertTrue(AdHocClientRule.accepts(identifier: "com.amir.chargeguard", path: "/Applications/ChargeGuard.app"))
        XCTAssertTrue(AdHocClientRule.accepts(identifier: "com.amir.chargeguard", path: "/Users/me/Applications/ChargeGuard.app"))
        XCTAssertTrue(AdHocClientRule.accepts(identifier: "com.amir.chargeguard",
                                              path: "/Applications/ChargeGuard.app/Contents/MacOS/ChargeGuard"))
    }

    func testChargectlIsMatchedByItsExecutableName() {
        XCTAssertTrue(AdHocClientRule.accepts(identifier: "com.amir.chargeguard.chargectl",
                                              path: "/Applications/ChargeGuard.app/Contents/MacOS/chargectl"))
        XCTAssertTrue(AdHocClientRule.accepts(identifier: "com.amir.chargeguard.chargectl", path: "/usr/local/bin/chargectl"))
    }

    func testIdentifierAndPathMustBelongTogether() {
        XCTAssertFalse(AdHocClientRule.accepts(identifier: "com.amir.chargeguard", path: "/usr/local/bin/chargectl"))
        XCTAssertFalse(AdHocClientRule.accepts(identifier: "com.amir.chargeguard.chargectl", path: "/Applications/ChargeGuard.app"))
    }

    func testOtherCodeIsRejected() {
        XCTAssertFalse(AdHocClientRule.accepts(identifier: "com.example.other", path: "/Applications/ChargeGuard.app"))
        XCTAssertFalse(AdHocClientRule.accepts(identifier: "com.amir.chargeguard", path: "/Applications/Other.app"))
        XCTAssertFalse(AdHocClientRule.accepts(identifier: "com.amir.chargeguard", path: "/Applications/NotChargeGuard.app.zip"))
        XCTAssertFalse(AdHocClientRule.accepts(identifier: "", path: ""))
    }
}
