import Foundation

/// Type and size of an SMC key, from the kSMCGetKeyInfo call.
public struct SMCKeyInfo: Codable, Equatable, Sendable {
    public var size: Int
    /// Four-character type code such as "ui8 ", "ui32", "flt ", "hex_".
    public var type: String

    public init(size: Int, type: String) {
        self.size = size
        self.type = type
    }
}

public enum SMCError: Error, Equatable, CustomStringConvertible, Sendable {
    case driverUnavailable
    case keyNotFound(String)
    /// kIOReturnNotPrivileged: not root, or the key is gated by an Apple-private entitlement.
    case notPrivileged(String)
    case ioError(key: String, kernReturn: Int32, smcResult: UInt8)
    case sizeMismatch(key: String, expected: Int, actual: Int)
    /// Refused by ChargeGuard: the key was not confirmed present by a probe.
    case notProbed(String)
    /// Refused by ChargeGuard: writes are blocked (another tool running, control disabled).
    case writesBlocked(String)
    case invalidKey(String)

    public var description: String {
        switch self {
        case .driverUnavailable: return "AppleSMC driver unavailable"
        case .keyNotFound(let k): return "SMC key \(k) not found"
        case .notPrivileged(let k): return "SMC key \(k): not privileged (kIOReturnNotPrivileged)"
        case .ioError(let k, let kr, let r): return "SMC key \(k): IOKit error 0x\(String(UInt32(bitPattern: kr), radix: 16)), SMC result \(r)"
        case .sizeMismatch(let k, let e, let a): return "SMC key \(k): size \(a), expected \(e)"
        case .notProbed(let k): return "SMC key \(k) was not confirmed present by the probe; write refused"
        case .writesBlocked(let why): return "SMC writes blocked: \(why)"
        case .invalidKey(let k): return "Invalid SMC key name \(k)"
        }
    }

    public var isNotPrivileged: Bool {
        if case .notPrivileged = self { return true }
        return false
    }
}

/// Raw SMC access. Implemented by `AppleSMC` (IOKit, ChargeGuardSystem) and `SimulatedSMC` (Core).
public protocol SMCKeyIO: AnyObject {
    func keyInfo(_ key: String) throws -> SMCKeyInfo
    func read(_ key: String) throws -> [UInt8]
    func write(_ key: String, bytes: [UInt8]) throws
}

/// Four-character-code helpers. SMC keys are 4 ASCII characters packed big-endian into a UInt32.
public enum FourCC {
    public static func code(_ string: String) throws -> UInt32 {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 4, scalars.allSatisfy({ $0.isASCII }) else { throw SMCError.invalidKey(string) }
        return scalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1.value) }
    }

    public static func string(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Hex formatting used in logs, probe output and docs ("01000000").
public enum Hex {
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { byte -> String in
            let digits = String(byte, radix: 16)
            return digits.count < 2 ? "0" + digits : digits
        }.joined()
    }

    public static func bytes(_ hex: String) -> [UInt8]? {
        let clean = hex.replacingOccurrences(of: " ", with: "").lowercased()
        guard clean.count % 2 == 0 else { return nil }
        var result: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}

/// Decoding of common SMC data types, for read-only telemetry keys.
public enum SMCValueDecoder {
    /// Decodes a value by its SMC type code. Returns nil for unknown types.
    /// Apple silicon stores `flt ` little-endian; integer types (`ui8 `, `ui16`, `ui32`, `si8 `...) big-endian.
    public static func number(bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count == 4 else { return nil }
            let b0 = UInt32(bytes[0]), b1 = UInt32(bytes[1]) << 8, b2 = UInt32(bytes[2]) << 16, b3 = UInt32(bytes[3]) << 24
            let bits: UInt32 = b0 | b1 | b2 | b3
            return Double(Float(bitPattern: bits))
        case "ui8 ", "flag":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "si8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(Int8(bitPattern: bytes[0]))
        case "ui16":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "si16":
            guard bytes.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))
        case "ui32":
            guard bytes.count == 4 else { return nil }
            let b0 = UInt32(bytes[0]) << 24, b1 = UInt32(bytes[1]) << 16, b2 = UInt32(bytes[2]) << 8, b3 = UInt32(bytes[3])
            let value: UInt32 = b0 | b1 | b2 | b3
            return Double(value)
        case "sp78":
            guard bytes.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }
}
