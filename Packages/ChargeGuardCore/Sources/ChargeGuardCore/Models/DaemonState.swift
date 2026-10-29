import Foundation

/// Everything the daemon persists in /Library/Application Support/ChargeGuard/state.json.
/// Versioned: `schemaVersion` is bumped on incompatible changes and `migrate` upgrades old files.
public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var config: PolicyConfig
    public var control: ControlState
    public var schedule: [ScheduleRule]
    public var scheduleLastCheck: Date?
    /// True while ChargeGuard has written non-default values to the SMC (stale-state detection on start).
    public var keysDirty: Bool
    /// The SleepDisabled value before ChargeGuard set `pmset disablesleep 1`, restored on release.
    public var sleepDisabledSnapshot: Bool?
    /// The last outputs that were applied successfully.
    public var lastApplied: ControlOutputs?
    public var savedAt: Date?

    public init(schemaVersion: Int = PersistedState.currentSchemaVersion, config: PolicyConfig = PolicyConfig(),
                control: ControlState = ControlState(), schedule: [ScheduleRule] = [], scheduleLastCheck: Date? = nil,
                keysDirty: Bool = false, sleepDisabledSnapshot: Bool? = nil, lastApplied: ControlOutputs? = nil,
                savedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.config = config
        self.control = control
        self.schedule = schedule
        self.scheduleLastCheck = scheduleLastCheck
        self.keysDirty = keysDirty
        self.sleepDisabledSnapshot = sleepDisabledSnapshot
        self.lastApplied = lastApplied
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, config, control, schedule, scheduleLastCheck, keysDirty, sleepDisabledSnapshot
        case lastApplied, savedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion, default: 1)
        config = try c.decode(PolicyConfig.self, forKey: .config, default: PolicyConfig())
        control = try c.decode(ControlState.self, forKey: .control, default: ControlState())
        schedule = try c.decode([ScheduleRule].self, forKey: .schedule, default: [])
        scheduleLastCheck = try c.decodeIfPresent(Date.self, forKey: .scheduleLastCheck)
        keysDirty = try c.decode(Bool.self, forKey: .keysDirty, default: false)
        sleepDisabledSnapshot = try c.decodeIfPresent(Bool.self, forKey: .sleepDisabledSnapshot)
        lastApplied = try c.decodeIfPresent(ControlOutputs.self, forKey: .lastApplied)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
    }

    /// Decodes and migrates a state file. Unknown future versions are rejected so they are never
    /// silently overwritten with fewer fields.
    public static func decode(_ data: Data) throws -> PersistedState {
        let state = try CoreJSON.decoder().decode(PersistedState.self, from: data)
        guard state.schemaVersion <= currentSchemaVersion else {
            throw PersistenceError.newerSchema(state.schemaVersion)
        }
        return migrate(state)
    }

    public static func migrate(_ state: PersistedState) -> PersistedState {
        var s = state
        // Version 1 is the first schema. Future migrations go here, one version at a time.
        s.schemaVersion = currentSchemaVersion
        s.config = s.config.normalized()
        return s
    }

    public func encoded() throws -> Data {
        try CoreJSON.encoder(pretty: true).encode(self)
    }
}

public enum PersistenceError: Error, Equatable, CustomStringConvertible {
    case newerSchema(Int)
    case unreadable(String)

    public var description: String {
        switch self {
        case .newerSchema(let v): return "state.json has schema \(v), newer than this build supports (\(PersistedState.currentSchemaVersion))"
        case .unreadable(let why): return "state.json unreadable: \(why)"
        }
    }
}

/// One line of events.jsonl.
public struct EventRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var event: PolicyEvent

    public init(id: UUID = UUID(), date: Date, event: PolicyEvent) {
        self.id = id
        self.date = date
        self.event = event
    }
}

/// Settings export/import (section 10). Contains the policy and the schedule, never runtime state.
public struct SettingsExport: Codable, Equatable, Sendable {
    public static let formatIdentifier = "com.amir.chargeguard.settings"
    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var config: PolicyConfig
    public var schedule: [ScheduleRule]
    /// App-side preferences (appearance, pop-up layout) as opaque JSON, filled in by the app.
    public var appPreferences: Data?

    public init(exportedAt: Date, config: PolicyConfig, schedule: [ScheduleRule], appPreferences: Data? = nil) {
        self.format = Self.formatIdentifier
        self.version = 1
        self.exportedAt = exportedAt
        self.config = config
        self.schedule = schedule
        self.appPreferences = appPreferences
    }

    /// The config to apply on import. `controlEnabled` is never imported: the first-run
    /// confirmation on this Mac decides it.
    public func configForImport(keepingControlEnabled current: Bool) -> PolicyConfig {
        var c = config.normalized()
        c.controlEnabled = current
        return c
    }
}

/// Next scheduled run, for the UI.
public struct ScheduledRunInfo: Codable, Equatable, Sendable {
    public var ruleID: UUID
    public var date: Date
    public var summary: String

    public init(ruleID: UUID, date: Date, summary: String) {
        self.ruleID = ruleID
        self.date = date
        self.summary = summary
    }
}

/// The state the daemon publishes to clients after every tick.
public struct DaemonStatus: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var daemonVersion: String
    public var simulated: Bool
    public var date: Date
    public var snapshot: BatterySnapshot?
    public var config: PolicyConfig
    public var control: ControlState
    public var chargeStatus: ChargeStatus
    public var effectiveLimit: Int
    public var controlPercentage: Int?
    public var lastOutputs: ControlOutputs?
    public var backend: BackendKind
    public var backendCapabilities: BackendCapabilities
    public var backendLimitations: [String]
    public var backendError: String?
    public var hardware: BackendHardwareState?
    public var conflicts: ConflictReport
    public var probe: KeyProbeReport?
    public var schedule: [ScheduleRule]
    public var nextScheduledRun: ScheduledRunInfo?
    public var lowPowerModeActive: Bool?
    public var keysDirty: Bool
    public var sleepImminent: Bool
    public var lidClosed: Bool
    public var topUpMinutesRemaining: Int?
    public var firmwareVersion: String?
    public var lastWrites: [KeyWriteRecord]

    public init(protocolVersion: Int = HelperProtocol.version, daemonVersion: String, simulated: Bool, date: Date,
                snapshot: BatterySnapshot?, config: PolicyConfig, control: ControlState, chargeStatus: ChargeStatus,
                effectiveLimit: Int, controlPercentage: Int?, lastOutputs: ControlOutputs?, backend: BackendKind,
                backendCapabilities: BackendCapabilities, backendLimitations: [String], backendError: String?,
                hardware: BackendHardwareState?, conflicts: ConflictReport, probe: KeyProbeReport?,
                schedule: [ScheduleRule], nextScheduledRun: ScheduledRunInfo?, lowPowerModeActive: Bool?,
                keysDirty: Bool, sleepImminent: Bool, lidClosed: Bool, topUpMinutesRemaining: Int?,
                firmwareVersion: String?, lastWrites: [KeyWriteRecord]) {
        self.protocolVersion = protocolVersion
        self.daemonVersion = daemonVersion
        self.simulated = simulated
        self.date = date
        self.snapshot = snapshot
        self.config = config
        self.control = control
        self.chargeStatus = chargeStatus
        self.effectiveLimit = effectiveLimit
        self.controlPercentage = controlPercentage
        self.lastOutputs = lastOutputs
        self.backend = backend
        self.backendCapabilities = backendCapabilities
        self.backendLimitations = backendLimitations
        self.backendError = backendError
        self.hardware = hardware
        self.conflicts = conflicts
        self.probe = probe
        self.schedule = schedule
        self.nextScheduledRun = nextScheduledRun
        self.lowPowerModeActive = lowPowerModeActive
        self.keysDirty = keysDirty
        self.sleepImminent = sleepImminent
        self.lidClosed = lidClosed
        self.topUpMinutesRemaining = topUpMinutesRemaining
        self.firmwareVersion = firmwareVersion
        self.lastWrites = lastWrites
    }
}
