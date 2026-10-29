// SMC client over the IOKit AppleSMC user client.
//
// Adapted from SMCKit by beltex (https://github.com/beltex/SMCKit), MIT License,
// Copyright (C) 2014-2017 beltex. See THIRD_PARTY_NOTICES.md.
//
// Changes from SMCKit: instance-based and thread-safe; `dataSize` is an explicit UInt32 (SMCKit's
// `IOByteCount` is 8 bytes on arm64, which breaks the 80-byte C layout); the layout is verified at
// runtime; kIOMainPortDefault; errors map to ChargeGuardCore.SMCError.

import Foundation
import IOKit
import ChargeGuardCore

public final class AppleSMC: SMCKeyIO {
    // MARK: C layout of SMCKeyData_t (80 bytes), as in smc.h and SMCKit

    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        /// Swift packs `result` right after the 9-byte keyInfo; C pads it to offset 40.
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    enum Selector: UInt8 {
        case handleYPCEvent = 2
        case readKey = 5
        case writeKey = 6
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    static let smcSuccess: UInt8 = 0
    static let smcKeyNotFound: UInt8 = 0x84
    static let kernSuccess: kern_return_t = 0
    /// kIOReturnNotPrivileged (iokit_common_err(0x2c1)), spelled out because the macro may not import.
    static let ioReturnNotPrivileged = kern_return_t(bitPattern: 0xE000_02C1)

    /// Checks the Swift layout against the C struct. A mismatch would make every call return garbage.
    public static func layoutProblem() -> String? {
        var problems: [String] = []
        func check(_ name: String, _ actual: Int?, _ expected: Int) {
            if actual != expected { problems.append("\(name) at \(actual.map(String.init) ?? "nil"), expected \(expected)") }
        }
        check("size", MemoryLayout<SMCParamStruct>.size, 80)
        check("stride", MemoryLayout<SMCParamStruct>.stride, 80)
        check("vers", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.vers), 4)
        check("pLimitData", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.pLimitData), 12)
        check("keyInfo", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.keyInfo), 28)
        check("result", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.result), 40)
        check("data8", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.data8), 42)
        check("data32", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.data32), 44)
        check("bytes", MemoryLayout<SMCParamStruct>.offset(of: \SMCParamStruct.bytes), 48)
        return problems.isEmpty ? nil : "SMCParamStruct layout mismatch: " + problems.joined(separator: "; ")
    }

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var infoCache: [String: SMCKeyInfo] = [:]

    public init() throws {
        if let problem = Self.layoutProblem() {
            throw SMCError.ioError(key: problem, kernReturn: -1, smcResult: 0)
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverUnavailable }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == Self.kernSuccess, conn != 0 else { throw SMCError.driverUnavailable }
        connection = conn
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: SMCKeyIO

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        lock.lock(); defer { lock.unlock() }
        return try keyInfoLocked(key)
    }

    public func read(_ key: String) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        guard info.size > 0 else { throw SMCError.keyNotFound(key) }
        var input = SMCParamStruct()
        input.key = try FourCC.code(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Selector.readKey.rawValue
        let output = try call(&input, key: key)
        let size = min(info.size, 32)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
    }

    /// Raw write. Call it only through `GuardedSMCWriter`; as a second line of defence it refuses any key
    /// outside the section 5 table.
    public func write(_ key: String, bytes: [UInt8]) throws {
        guard SMCKey.writableKeys.contains(key) else { throw SMCError.invalidKey(key) }
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        guard bytes.count == info.size, bytes.count <= 32 else {
            throw SMCError.sizeMismatch(key: key, expected: info.size, actual: bytes.count)
        }
        var input = SMCParamStruct()
        input.key = try FourCC.code(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Selector.writeKey.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        _ = try call(&input, key: key)
    }

    // MARK: Driver calls

    private func keyInfoLocked(_ key: String) throws -> SMCKeyInfo {
        if let cached = infoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = try FourCC.code(key)
        input.data8 = Selector.getKeyInfo.rawValue
        let output = try call(&input, key: key)
        let info = SMCKeyInfo(size: Int(output.keyInfo.dataSize), type: FourCC.string(output.keyInfo.dataType))
        infoCache[key] = info
        return info
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, UInt32(Selector.handleYPCEvent.rawValue),
                                           &input, inputSize, &output, &outputSize)
        if kr == Self.ioReturnNotPrivileged { throw SMCError.notPrivileged(key) }
        guard kr == Self.kernSuccess else {
            throw SMCError.ioError(key: key, kernReturn: kr, smcResult: output.result)
        }
        switch output.result {
        case Self.smcSuccess: return output
        case Self.smcKeyNotFound: throw SMCError.keyNotFound(key)
        default: throw SMCError.ioError(key: key, kernReturn: kr, smcResult: output.result)
        }
    }

    // MARK: Read-only telemetry helpers

    /// A typed numeric read for telemetry keys (AC-W, PDTR, PPBR). Never used for control keys.
    public func number(_ key: String) -> Double? {
        guard let info = try? keyInfo(key), let bytes = try? read(key) else { return nil }
        return SMCValueDecoder.number(bytes: bytes, type: info.type)
    }
}
