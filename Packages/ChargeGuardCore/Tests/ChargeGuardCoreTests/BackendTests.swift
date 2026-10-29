import XCTest
@testable import ChargeGuardCore

final class BackendTests: XCTestCase {

    func writer(_ profile: SimulatedSMC.Profile) -> (GuardedSMCWriter, SimulatedSMC) {
        let smc = SimulatedSMC(profile: profile)
        let report = KeyProber.probe(smc, now: t0)
        return (GuardedSMCWriter(io: smc, report: report), smc)
    }

    // MARK: Probe

    func testProbeDetectsPresenceAndSize() {
        let smc = SimulatedSMC(profile: .tahoe)
        smc.addKey("CH0J", type: "ui8 ", bytes: [])
        let report = KeyProber.probe(smc, now: t0)
        XCTAssertTrue(report.isPresent("CHTE"))
        XCTAssertEqual(report.info("CHTE")?.size, 4)
        XCTAssertFalse(report.isPresent("CH0B"), "absent key")
        XCTAssertFalse(report.isPresent("CH0J"), "zero-size key counts as absent")
        XCTAssertTrue(report.text.contains("CHTE  present  size 4"))
    }

    // MARK: Selection

    func testSelectionByPresence() {
        func select(_ p: SimulatedSMC.Profile, _ pref: BackendPreference = .automatic) -> BackendKind {
            BackendSelector.select(report: KeyProber.probe(SimulatedSMC(profile: p), now: t0), preference: pref)
        }
        XCTAssertEqual(select(.tahoe), .legacyKeys)
        XCTAssertEqual(select(.legacy), .legacyKeys)
        XCTAssertEqual(select(.adapterOnly), .adapterCutoff)
        XCTAssertEqual(select(.unsupported), .none)
        XCTAssertEqual(select(.firmwareGated), .legacyKeys, "gating is only known after a failed write")
        XCTAssertEqual(select(.firmwareGated, .firmwareLimit), .firmwareLimit)
        XCTAssertEqual(select(.tahoe, .adapterCutoff), .adapterCutoff)
        XCTAssertEqual(select(.tahoe, .firmwareLimit), .legacyKeys, "unsupported preference falls back")
    }

    func testSelectionSkipsNotPrivilegedKeys() {
        var report = KeyProber.probe(SimulatedSMC(profile: .firmwareGated), now: t0)
        report.notPrivileged = ["CHTE"]
        XCTAssertEqual(BackendSelector.select(report: report, preference: .automatic), .firmwareLimit)
        report.notPrivileged = ["CHTE", "bfF0"]
        XCTAssertEqual(BackendSelector.select(report: report, preference: .automatic), .adapterCutoff)
        XCTAssertEqual(BackendSelector.candidates(report: report, preference: .automatic), [.adapterCutoff])
    }

    // MARK: Legacy keys

    func testLegacyTahoeValues() throws {
        let (w, smc) = writer(.tahoe)
        let backend = try XCTUnwrap(LegacyKeysBackend(writer: w))
        _ = try backend.apply(ControlOutputs(inhibitCharging: true), reason: "test")
        XCTAssertEqual(smc.value("CHTE"), [0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(smc.value("CHIE"), [0x00])
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, forceDischarge: true), reason: "test")
        XCTAssertEqual(smc.value("CHIE"), [0x08])
        _ = try backend.apply(.normal, reason: "test")
        XCTAssertEqual(smc.value("CHTE"), [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(smc.value("CHIE"), [0x00])
    }

    func testLegacyWritesBothCH0BAndCH0C() throws {
        let (w, smc) = writer(.legacy)
        let backend = try XCTUnwrap(LegacyKeysBackend(writer: w))
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, forceDischarge: true), reason: "test")
        XCTAssertEqual(smc.value("CH0B"), [0x02])
        XCTAssertEqual(smc.value("CH0C"), [0x02])
        XCTAssertEqual(smc.value("CH0J"), [0x01], "CH0J preferred over CH0I")
        XCTAssertEqual(smc.value("CH0I"), [0x00])
    }

    func testDischargeOrdering() throws {
        let (w, smc) = writer(.tahoe)
        let backend = try XCTUnwrap(LegacyKeysBackend(writer: w))
        smc.clearWriteLog()
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, forceDischarge: true), reason: "start")
        XCTAssertEqual(smc.writeLog.map { $0.key }, ["CHTE", "CHIE"], "block charging before cutting the adapter")
        smc.clearWriteLog()
        _ = try backend.apply(.normal, reason: "stop")
        XCTAssertEqual(smc.writeLog.map { $0.key }, ["CHIE", "CHTE"], "reconnect the adapter before re-enabling charging")
    }

    func testNoRedundantWrites() throws {
        let (w, smc) = writer(.tahoe)
        let backend = try XCTUnwrap(LegacyKeysBackend(writer: w))
        _ = try backend.apply(ControlOutputs(inhibitCharging: true), reason: "a")
        smc.clearWriteLog()
        let records = try backend.apply(ControlOutputs(inhibitCharging: true), reason: "b")
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(smc.writeLog.isEmpty)
    }

    func testLEDValues() throws {
        let (w, smc) = writer(.tahoe)
        let backend = try XCTUnwrap(LegacyKeysBackend(writer: w))
        _ = try backend.apply(ControlOutputs(led: .green), reason: "t")
        XCTAssertEqual(smc.value("ACLC"), [0x03])
        _ = try backend.apply(ControlOutputs(led: .orange), reason: "t")
        XCTAssertEqual(smc.value("ACLC"), [0x04])
        _ = try backend.apply(ControlOutputs(led: .off), reason: "t")
        XCTAssertEqual(smc.value("ACLC"), [0x01])
        _ = try backend.apply(ControlOutputs(led: .system), reason: "t")
        XCTAssertEqual(smc.value("ACLC"), [0x00])
    }

    // MARK: Firmware limit

    func testFirmwareLimitSequenceAndEncoding() throws {
        let (w, smc) = writer(.firmwareGated)
        let backend = try XCTUnwrap(FirmwareLimitBackend(writer: w))
        smc.clearWriteLog()
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, chargeCeiling: 80, resumeFloor: 75), reason: "t")
        XCTAssertEqual(smc.writeLog.map { $0.key }, ["bfD0", "bfE0", "bfF0"], "bfF0 already 00, then upper, lower, activate")
        XCTAssertEqual(smc.value("bfD0"), [0x50, 0x00, 0x00, 0x00], "80 % little-endian")
        XCTAssertEqual(smc.value("bfE0"), [0x4b, 0x00, 0x00, 0x00])
        XCTAssertEqual(smc.value("bfF0"), [0x02])
        XCTAssertEqual(backend.readState().firmwareUpper, 80)

        smc.clearWriteLog()
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, chargeCeiling: 80, resumeFloor: 75), reason: "t")
        XCTAssertTrue(smc.writeLog.isEmpty, "unchanged limit is not rewritten")

        smc.clearWriteLog()
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, chargeCeiling: 70, resumeFloor: 65), reason: "t")
        XCTAssertEqual(smc.writeLog.map { $0.key }, ["bfF0", "bfD0", "bfE0", "bfF0"], "deactivate, write, reactivate")

        _ = try backend.apply(.normal, reason: "t")
        XCTAssertEqual(smc.value("bfF0"), [0x00], "limit 100 deactivates")
    }

    func testFirmwareTargetForOverrides() {
        let hold = FirmwareLimitBackend.target(for: ControlOutputs(inhibitCharging: true, chargeCeiling: 80, resumeFloor: 78, holdAtPercentage: 55))
        XCTAssertEqual(hold?.upper, 55)
        XCTAssertEqual(hold?.lower, 54)
        XCTAssertNil(FirmwareLimitBackend.target(for: .normal))
        let band = FirmwareLimitBackend.target(for: ControlOutputs(chargeCeiling: 80, resumeFloor: 80))
        XCTAssertEqual(band?.lower, 79, "lower is always below upper")
    }

    // MARK: Adapter cutoff

    func testAdapterCutoffMapsInhibitToAdapterKey() throws {
        let (w, smc) = writer(.adapterOnly)
        let backend = try XCTUnwrap(AdapterCutoffBackend(writer: w))
        XCTAssertTrue(backend.capabilities.inhibitIsAdapterCutoff)
        _ = try backend.apply(ControlOutputs(inhibitCharging: true), reason: "t")
        XCTAssertEqual(smc.value("CHIE"), [0x08])
        _ = try backend.apply(.normal, reason: "t")
        XCTAssertEqual(smc.value("CHIE"), [0x00])
        XCTAssertNil(LegacyKeysBackend(writer: w), "no charge keys")
    }

    // MARK: Guarded writer

    func testWriterRefusesUnprobedKeys() {
        let smc = SimulatedSMC(profile: .tahoe)
        let w = GuardedSMCWriter(io: smc, report: .empty)
        XCTAssertThrowsError(try w.ensure("CHTE", SMCValue.chteInhibit, reason: "t")) { error in
            XCTAssertEqual(error as? SMCError, .notProbed("CHTE"))
        }
        XCTAssertEqual(smc.value("CHTE"), SMCValue.chteAllow)
    }

    func testWriterRefusesUnknownKeysAndWrongSizes() {
        let (w, _) = writer(.tahoe)
        XCTAssertThrowsError(try w.ensure("AC-W", [0x00], reason: "t")) { error in
            XCTAssertEqual(error as? SMCError, .invalidKey("AC-W"))
        }
        XCTAssertThrowsError(try w.ensure("CHTE", [0x01], reason: "t")) { error in
            XCTAssertEqual(error as? SMCError, .sizeMismatch(key: "CHTE", expected: 4, actual: 1))
        }
    }

    func testWriterBlockedByConflictUnlessExplicitRestore() throws {
        let (w, smc) = writer(.tahoe)
        try w.ensure("CHTE", SMCValue.chteInhibit, reason: "t")
        w.blockedReason = "AlDente running"
        XCTAssertThrowsError(try w.ensure("CHTE", SMCValue.chteAllow, reason: "t"))
        XCTAssertEqual(smc.value("CHTE"), SMCValue.chteInhibit)
        let result = w.restoreAll(reason: "user", bypassBlock: true)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(smc.value("CHTE"), SMCValue.chteAllow)
    }

    func testNotPrivilegedIsRecorded() {
        let (w, _) = writer(.firmwareGated)
        XCTAssertThrowsError(try w.ensure("CHTE", SMCValue.chteInhibit, reason: "t"))
        XCTAssertTrue(w.report.notPrivileged.contains("CHTE"))
        XCTAssertFalse(w.isUsable("CHTE"))
    }

    func testRestoreAllWritesEveryPresentKey() throws {
        let (w, smc) = writer(.legacy)
        try w.ensure("CH0B", SMCValue.ch0bcInhibit, reason: "t")
        try w.ensure("CH0C", SMCValue.ch0bcInhibit, reason: "t")
        try w.ensure("CH0I", SMCValue.ch0iOn, reason: "t")
        try w.ensure("ACLC", SMCValue.ledGreen, reason: "t")
        let result = w.restoreAll(reason: "restore")
        XCTAssertTrue(result.errors.isEmpty)
        for key in ["CH0B", "CH0C", "CH0I", "CH0J", "ACLC"] {
            XCTAssertEqual(smc.value(key), [0x00], key)
        }
    }

    func testRestoreDeactivatesFirmwareLimit() throws {
        let (w, smc) = writer(.firmwareGated)
        let backend = try XCTUnwrap(FirmwareLimitBackend(writer: w))
        _ = try backend.apply(ControlOutputs(inhibitCharging: true, chargeCeiling: 80, resumeFloor: 75), reason: "t")
        let result = w.restoreAll(reason: "restore")
        XCTAssertEqual(smc.value("bfF0"), [0x00])
        XCTAssertTrue(result.errors.isEmpty, "gated CHTE already holds the allow value, so it needs no write")
    }

    func testRestoreReportsGatedKeyThatNeedsAWrite() throws {
        let smc = SimulatedSMC(profile: .firmwareGated)
        let w = GuardedSMCWriter(io: smc, report: KeyProber.probe(smc, now: t0))
        smc.setGated("CHTE", false)
        try w.ensure("CHTE", SMCValue.chteInhibit, reason: "t")
        smc.setGated("CHTE", true)
        let result = w.restoreAll(reason: "restore")
        XCTAssertEqual(result.errors.count, 1, "one failing key does not stop the others")
        XCTAssertEqual(smc.value("bfF0"), [0x00])
    }

    // MARK: Values

    func testFourCC() throws {
        XCTAssertEqual(try FourCC.code("CHTE"), 0x4348_5445)
        XCTAssertEqual(FourCC.string(0x4348_5445), "CHTE")
        XCTAssertThrowsError(try FourCC.code("TOOLONG"))
        XCTAssertEqual(Hex.string([0x01, 0x00, 0xab]), "0100ab")
        XCTAssertEqual(Hex.bytes("01 00 ab"), [0x01, 0x00, 0xab])
        XCTAssertNil(Hex.bytes("0"))
    }

    func testValueDecoding() {
        XCTAssertEqual(SMCValueDecoder.number(bytes: [0x00, 0x00, 0x40, 0x41], type: "flt "), 12.0)
        XCTAssertEqual(SMCValueDecoder.number(bytes: [0x01, 0x02], type: "ui16"), 258)
        XCTAssertEqual(SMCValueDecoder.number(bytes: [0xff], type: "si8 "), -1)
        XCTAssertEqual(SMCValue.decodeFirmwarePercent([0x50, 0, 0, 0]), 80)
        XCTAssertEqual(SMCValue.firmwarePercent(50), [0x32, 0, 0, 0])
    }
}
