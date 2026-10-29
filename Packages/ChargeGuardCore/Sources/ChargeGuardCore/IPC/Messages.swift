import Foundation

/// App/daemon protocol constants. Bump `version` on any incompatible message change;
/// the app offers to reinstall the helper on a mismatch.
public enum HelperProtocol {
    public static let version = 1
    public static let machServiceName = "com.amir.chargeguard.helper"
    public static let helperBundleIdentifier = "com.amir.chargeguard.helper"
    public static let appBundleIdentifier = "com.amir.chargeguard"
    public static let chargectlIdentifier = "com.amir.chargeguard.chargectl"
    public static let bundleIdentifierPrefix = "com.amir.chargeguard"
    public static let launchdPlistName = "com.amir.chargeguard.helper.plist"
    public static let stateDirectory = "/Library/Application Support/ChargeGuard"
}

/// Commands that change daemon state.
public enum HelperCommand: Codable, Equatable, Sendable {
    case setChargeLimit(Int)
    case updateConfig(PolicyConfig)
    case startDischarge
    case stopDischarge
    case startTopUp
    case cancelTopUp
    case startCalibration(fast: Bool, origin: String)
    case cancelCalibration
    case keepAwake(KeepAwakeRequest)
    case cancelKeepAwake
    case setSchedule([ScheduleRule])
    case runScheduleRuleNow(UUID)
    case setHeatProtection(Bool)
    case setSailing(Bool)
    case setLowPowerMode(LowPowerModePolicy)
    case setMagSafeLED(MagSafeLEDMode)
    case selectBackend(BackendPreference)
    case reprobe
    /// The first-run wizard's explicit confirmation: enables charge control.
    case confirmFirstRun
    case setControlEnabled(Bool)
    case restoreNormalCharging
    case appLaunched
    case appWillQuit
    case setExternalDisplayConnected(Bool)
    case importSettings(SettingsExport)
    /// Restore everything and stop enforcing; sent by the uninstaller before removing the daemon.
    case prepareUninstall
}

public enum HelperRequest: Codable, Equatable, Sendable {
    case hello(clientProtocolVersion: Int, client: String)
    case getStatus
    case command(HelperCommand)
    case probeKeys
    case readKey(String)
    case energySample
    case calibrationHistory(limit: Int)
    case recentEvents(limit: Int)
    case recentWrites(limit: Int)
    case exportSettings
}

public struct HelloInfo: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var daemonVersion: String
    public var simulated: Bool
    public var compatible: Bool

    public init(protocolVersion: Int, daemonVersion: String, simulated: Bool, compatible: Bool) {
        self.protocolVersion = protocolVersion
        self.daemonVersion = daemonVersion
        self.simulated = simulated
        self.compatible = compatible
    }
}

public struct KeyReadResult: Codable, Equatable, Sendable {
    public var key: String
    public var info: SMCKeyInfo?
    public var bytes: [UInt8]?
    public var error: String?

    public init(key: String, info: SMCKeyInfo?, bytes: [UInt8]?, error: String?) {
        self.key = key
        self.info = info
        self.bytes = bytes
        self.error = error
    }
}

public enum HelperResponse: Codable, Equatable, Sendable {
    case hello(HelloInfo)
    case status(DaemonStatus)
    case ok
    case probe(KeyProbeReport)
    case keyValue(KeyReadResult)
    case energy(EnergySample)
    case calibrationHistory([CalibrationRecord])
    case events([EventRecord])
    case writes([KeyWriteRecord])
    case settings(SettingsExport)
    case error(String)
}

/// Wire format: a versioned JSON envelope carried as `Data` over a single @objc XPC method.
public struct MessageEnvelope<Payload: Codable>: Codable {
    public var protocolVersion: Int
    public var payload: Payload

    public init(protocolVersion: Int = HelperProtocol.version, payload: Payload) {
        self.protocolVersion = protocolVersion
        self.payload = payload
    }
}

public enum MessageCodecError: Error, Equatable, CustomStringConvertible {
    case versionMismatch(local: Int, remote: Int)
    case malformed(String)

    public var description: String {
        switch self {
        case .versionMismatch(let local, let remote): return "protocol version mismatch (this side \(local), other side \(remote))"
        case .malformed(let why): return "malformed message: \(why)"
        }
    }
}

public enum MessageCodec {
    public static func encode(_ request: HelperRequest) throws -> Data {
        try CoreJSON.encoder().encode(MessageEnvelope(payload: request))
    }

    public static func encode(_ response: HelperResponse) throws -> Data {
        try CoreJSON.encoder().encode(MessageEnvelope(payload: response))
    }

    /// Decodes a request. `hello` is accepted from any version so the handshake can report a mismatch;
    /// everything else must match `HelperProtocol.version`.
    public static func decodeRequest(_ data: Data) throws -> HelperRequest {
        let envelope: MessageEnvelope<HelperRequest>
        do {
            envelope = try CoreJSON.decoder().decode(MessageEnvelope<HelperRequest>.self, from: data)
        } catch {
            throw MessageCodecError.malformed("\(error)")
        }
        if case .hello = envelope.payload { return envelope.payload }
        guard envelope.protocolVersion == HelperProtocol.version else {
            throw MessageCodecError.versionMismatch(local: HelperProtocol.version, remote: envelope.protocolVersion)
        }
        return envelope.payload
    }

    public static func decodeResponse(_ data: Data) throws -> HelperResponse {
        let envelope: MessageEnvelope<HelperResponse>
        do {
            envelope = try CoreJSON.decoder().decode(MessageEnvelope<HelperResponse>.self, from: data)
        } catch {
            throw MessageCodecError.malformed("\(error)")
        }
        if case .hello = envelope.payload { return envelope.payload }
        guard envelope.protocolVersion == HelperProtocol.version else {
            throw MessageCodecError.versionMismatch(local: HelperProtocol.version, remote: envelope.protocolVersion)
        }
        return envelope.payload
    }

    /// Encodes an error response; never throws (falls back to a fixed payload).
    public static func errorData(_ message: String) -> Data {
        (try? encode(.error(message))) ?? Data("{\"protocolVersion\":\(HelperProtocol.version),\"payload\":{\"error\":{\"_0\":\"encoding failed\"}}}".utf8)
    }
}
