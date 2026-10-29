import Foundation

/// What happens to enforcement when the ChargeGuard app quits (feature 13).
public enum AppClosedBehavior: String, Codable, CaseIterable, Sendable {
    /// The helper keeps enforcing the limit (default). Also what happens when the app crashes.
    case keepEnforced
    /// The helper restores normal charging when the app quits normally.
    case restoreOnQuit
}

/// Low Power Mode policy applied by the daemon on every power-source change (feature 14).
public enum LowPowerModePolicy: String, Codable, CaseIterable, Sendable {
    case unmanaged
    case alwaysOff
    case alwaysOn
    case onlyOnBattery
    case onlyOnAdapter

    /// Desired Low Power Mode state, or nil when ChargeGuard should not touch it.
    public func desiredState(adapterConnected: Bool) -> Bool? {
        switch self {
        case .unmanaged: return nil
        case .alwaysOff: return false
        case .alwaysOn: return true
        case .onlyOnBattery: return !adapterConnected
        case .onlyOnAdapter: return adapterConnected
        }
    }
}

/// MagSafe LED behaviour (feature 9).
public enum MagSafeLEDMode: String, Codable, CaseIterable, Sendable {
    /// ChargeGuard does not touch ACLC.
    case systemDefault
    /// Green when the limit is reached or charging is blocked, orange while charging, off while discharging.
    case followState
    /// LED off while plugged in.
    case alwaysOff
}

/// Which backend the daemon should use. `.automatic` selects by key probing.
public enum BackendPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case legacyKeys
    case firmwareLimit
    case adapterCutoff
}

public struct HeatProtectionConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Charging pauses at or above this temperature. Range 30...50 °C.
    public var maxTemperatureC: Double
    /// Charging resumes at or below maxTemperatureC - resumeDeltaC.
    public var resumeDeltaC: Double

    public init(enabled: Bool = false, maxTemperatureC: Double = 35, resumeDeltaC: Double = 2) {
        self.enabled = enabled
        self.maxTemperatureC = maxTemperatureC
        self.resumeDeltaC = resumeDeltaC
    }

    public static let temperatureRange: ClosedRange<Double> = 30...50
}

public struct SailingConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Charging resumes when the battery falls to limit - range. Range 1...20.
    public var range: Int

    public init(enabled: Bool = false, range: Int = 5) {
        self.enabled = enabled
        self.range = range
    }

    public static let rangeLimits: ClosedRange<Int> = 1...20
}

public struct CalibrationConfig: Codable, Equatable, Sendable {
    /// Hold at 100 % in phases A and C, in minutes.
    public var holdMinutes: Int
    /// Discharge target of phase B. Range 10...20.
    public var dischargeFloor: Int
    /// Hidden test setting: 2-minute holds and a discharge target of (current - 3) %.
    public var fastMode: Bool

    public init(holdMinutes: Int = 60, dischargeFloor: Int = 15, fastMode: Bool = false) {
        self.holdMinutes = holdMinutes
        self.dischargeFloor = dischargeFloor
        self.fastMode = fastMode
    }

    public static let floorRange: ClosedRange<Int> = 10...20
    public static let holdRange: ClosedRange<Int> = 1...240
    public static let fastHoldSeconds: TimeInterval = 120
}

/// The user's policy. Owned by the daemon, edited by the app.
public struct PolicyConfig: Codable, Equatable, Sendable {
    /// False until the first-run wizard's explicit confirmation. While false nothing is written.
    public var controlEnabled: Bool
    /// Charge limit, 20...100. 100 means "no limit".
    public var chargeLimit: Int
    /// Charging resumes when the battery falls below limit - hysteresis (replaced by sailing when on).
    public var resumeHysteresis: Int
    /// Enforce on the raw hardware percentage instead of the macOS percentage.
    public var useHardwarePercentage: Bool
    /// Advanced: allow 1 % steps on the limit slider (UI only).
    public var fineLimitSteps: Bool
    public var automaticDischarge: Bool
    public var dischargeInClamshell: Bool
    /// Advanced, off by default: also hold `pmset disablesleep 1` while discharging in clamshell with an
    /// external display, for Macs that ignore the PreventSystemSleep assertion on battery power.
    public var clamshellForceAwake: Bool
    public var heatProtection: HeatProtectionConfig
    public var sailing: SailingConfig
    public var calibration: CalibrationConfig
    public var magSafeLED: MagSafeLEDMode
    public var disableSleepUntilLimit: Bool
    public var stopChargingWhenSleeping: Bool
    public var appClosedBehavior: AppClosedBehavior
    public var lowPowerMode: LowPowerModePolicy
    /// Control loop interval in seconds, 2...60.
    public var pollIntervalSeconds: Double
    public var backendPreference: BackendPreference
    /// Minimum hysteresis band when the AdapterCutoff backend holds the limit by cutting wall power.
    public var adapterCutoffMinBand: Int

    public init(controlEnabled: Bool = false,
                chargeLimit: Int = 80,
                resumeHysteresis: Int = 2,
                useHardwarePercentage: Bool = false,
                fineLimitSteps: Bool = false,
                automaticDischarge: Bool = false,
                dischargeInClamshell: Bool = false,
                clamshellForceAwake: Bool = false,
                heatProtection: HeatProtectionConfig = HeatProtectionConfig(),
                sailing: SailingConfig = SailingConfig(),
                calibration: CalibrationConfig = CalibrationConfig(),
                magSafeLED: MagSafeLEDMode = .systemDefault,
                disableSleepUntilLimit: Bool = false,
                stopChargingWhenSleeping: Bool = false,
                appClosedBehavior: AppClosedBehavior = .keepEnforced,
                lowPowerMode: LowPowerModePolicy = .unmanaged,
                pollIntervalSeconds: Double = 5,
                backendPreference: BackendPreference = .automatic,
                adapterCutoffMinBand: Int = 5) {
        self.controlEnabled = controlEnabled
        self.chargeLimit = chargeLimit
        self.resumeHysteresis = resumeHysteresis
        self.useHardwarePercentage = useHardwarePercentage
        self.fineLimitSteps = fineLimitSteps
        self.automaticDischarge = automaticDischarge
        self.dischargeInClamshell = dischargeInClamshell
        self.clamshellForceAwake = clamshellForceAwake
        self.heatProtection = heatProtection
        self.sailing = sailing
        self.calibration = calibration
        self.magSafeLED = magSafeLED
        self.disableSleepUntilLimit = disableSleepUntilLimit
        self.stopChargingWhenSleeping = stopChargingWhenSleeping
        self.appClosedBehavior = appClosedBehavior
        self.lowPowerMode = lowPowerMode
        self.pollIntervalSeconds = pollIntervalSeconds
        self.backendPreference = backendPreference
        self.adapterCutoffMinBand = adapterCutoffMinBand
    }

    public static let limitRange: ClosedRange<Int> = 20...100
    public static let hysteresisRange: ClosedRange<Int> = 1...10
    public static let pollIntervalRange: ClosedRange<Double> = 2...60

    /// A copy with every value forced into its valid range. The daemon normalizes every config it receives.
    public func normalized() -> PolicyConfig {
        var c = self
        c.chargeLimit = chargeLimit.clamped(to: Self.limitRange)
        c.resumeHysteresis = resumeHysteresis.clamped(to: Self.hysteresisRange)
        c.heatProtection.maxTemperatureC = heatProtection.maxTemperatureC.clamped(to: HeatProtectionConfig.temperatureRange)
        c.heatProtection.resumeDeltaC = heatProtection.resumeDeltaC.clamped(to: 0.5...10)
        c.sailing.range = sailing.range.clamped(to: SailingConfig.rangeLimits)
        c.calibration.dischargeFloor = calibration.dischargeFloor.clamped(to: CalibrationConfig.floorRange)
        c.calibration.holdMinutes = calibration.holdMinutes.clamped(to: CalibrationConfig.holdRange)
        c.pollIntervalSeconds = pollIntervalSeconds.clamped(to: Self.pollIntervalRange)
        c.adapterCutoffMinBand = adapterCutoffMinBand.clamped(to: 1...20)
        return c
    }

    /// The resume band below the limit: the sailing range when sailing is on, else the hysteresis.
    public var resumeBand: Int {
        sailing.enabled ? sailing.range : resumeHysteresis
    }

    // MARK: Codable with defaults, so older state files keep loading.

    private enum CodingKeys: String, CodingKey {
        case controlEnabled, chargeLimit, resumeHysteresis, useHardwarePercentage, fineLimitSteps
        case automaticDischarge, dischargeInClamshell, clamshellForceAwake, heatProtection, sailing
        case calibration, magSafeLED, disableSleepUntilLimit, stopChargingWhenSleeping
        case appClosedBehavior, lowPowerMode, pollIntervalSeconds, backendPreference, adapterCutoffMinBand
    }

    public init(from decoder: Decoder) throws {
        let d = PolicyConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        controlEnabled = try c.decode(Bool.self, forKey: .controlEnabled, default: d.controlEnabled)
        chargeLimit = try c.decode(Int.self, forKey: .chargeLimit, default: d.chargeLimit)
        resumeHysteresis = try c.decode(Int.self, forKey: .resumeHysteresis, default: d.resumeHysteresis)
        useHardwarePercentage = try c.decode(Bool.self, forKey: .useHardwarePercentage, default: d.useHardwarePercentage)
        fineLimitSteps = try c.decode(Bool.self, forKey: .fineLimitSteps, default: d.fineLimitSteps)
        automaticDischarge = try c.decode(Bool.self, forKey: .automaticDischarge, default: d.automaticDischarge)
        dischargeInClamshell = try c.decode(Bool.self, forKey: .dischargeInClamshell, default: d.dischargeInClamshell)
        clamshellForceAwake = try c.decode(Bool.self, forKey: .clamshellForceAwake, default: d.clamshellForceAwake)
        heatProtection = try c.decode(HeatProtectionConfig.self, forKey: .heatProtection, default: d.heatProtection)
        sailing = try c.decode(SailingConfig.self, forKey: .sailing, default: d.sailing)
        calibration = try c.decode(CalibrationConfig.self, forKey: .calibration, default: d.calibration)
        magSafeLED = try c.decode(MagSafeLEDMode.self, forKey: .magSafeLED, default: d.magSafeLED)
        disableSleepUntilLimit = try c.decode(Bool.self, forKey: .disableSleepUntilLimit, default: d.disableSleepUntilLimit)
        stopChargingWhenSleeping = try c.decode(Bool.self, forKey: .stopChargingWhenSleeping, default: d.stopChargingWhenSleeping)
        appClosedBehavior = try c.decode(AppClosedBehavior.self, forKey: .appClosedBehavior, default: d.appClosedBehavior)
        lowPowerMode = try c.decode(LowPowerModePolicy.self, forKey: .lowPowerMode, default: d.lowPowerMode)
        pollIntervalSeconds = try c.decode(Double.self, forKey: .pollIntervalSeconds, default: d.pollIntervalSeconds)
        backendPreference = try c.decode(BackendPreference.self, forKey: .backendPreference, default: d.backendPreference)
        adapterCutoffMinBand = try c.decode(Int.self, forKey: .adapterCutoffMinBand, default: d.adapterCutoffMinBand)
    }
}
