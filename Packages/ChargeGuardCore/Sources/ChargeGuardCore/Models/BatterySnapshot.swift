import Foundation

/// Power adapter details as reported by AppleSmartBattery's `AdapterDetails`.
public struct AdapterInfo: Codable, Equatable, Sendable {
    /// Rated wattage of the adapter (not the live draw).
    public var watts: Int?
    public var name: String?
    public var manufacturer: String?
    public var voltageMV: Int?
    public var currentMA: Int?
    public var isWireless: Bool?

    public init(watts: Int? = nil, name: String? = nil, manufacturer: String? = nil,
                voltageMV: Int? = nil, currentMA: Int? = nil, isWireless: Bool? = nil) {
        self.watts = watts
        self.name = name
        self.manufacturer = manufacturer
        self.voltageMV = voltageMV
        self.currentMA = currentMA
        self.isWireless = isWireless
    }
}

/// One reading of the battery, taken from the IORegistry (and optionally SMC power keys).
/// Units follow AppleSmartBattery: mAh, mV, mA (negative while discharging).
public struct BatterySnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var batteryInstalled: Bool
    /// The percentage macOS shows (CurrentCapacity, scaled by MaxCapacity when that is not 100).
    public var percentage: Int
    public var rawCurrentCapacityMAh: Int
    public var rawMaxCapacityMAh: Int
    public var nominalChargeCapacityMAh: Int?
    public var designCapacityMAh: Int
    public var cycleCount: Int
    public var temperatureC: Double
    public var voltageMV: Int
    public var amperageMA: Int
    public var instantAmperageMA: Int
    public var isCharging: Bool
    /// What macOS reports as the power source (false while ChargeGuard forces discharge on some firmware).
    public var externalConnected: Bool
    /// Best-effort physical adapter presence: ExternalConnected, AppleRawExternalConnected,
    /// AdapterDetails and the AC-W SMC key combined by the reader.
    public var adapterPresent: Bool
    public var fullyCharged: Bool
    /// Minutes, nil while macOS is still calculating (65535).
    public var timeRemainingMinutes: Int?
    public var timeToFullMinutes: Int?
    public var timeToEmptyMinutes: Int?
    public var adapter: AdapterInfo?
    public var serial: String?
    /// Live power numbers from PowerTelemetryData or SMC power keys, in watts, when readable.
    public var systemPowerInW: Double?
    public var systemLoadW: Double?
    public var smcBatteryPowerW: Double?

    public init(timestamp: Date = Date(),
                batteryInstalled: Bool = true,
                percentage: Int,
                rawCurrentCapacityMAh: Int = 0,
                rawMaxCapacityMAh: Int = 0,
                nominalChargeCapacityMAh: Int? = nil,
                designCapacityMAh: Int = 0,
                cycleCount: Int = 0,
                temperatureC: Double = 30,
                voltageMV: Int = 12_000,
                amperageMA: Int = 0,
                instantAmperageMA: Int = 0,
                isCharging: Bool = false,
                externalConnected: Bool = false,
                adapterPresent: Bool? = nil,
                fullyCharged: Bool = false,
                timeRemainingMinutes: Int? = nil,
                timeToFullMinutes: Int? = nil,
                timeToEmptyMinutes: Int? = nil,
                adapter: AdapterInfo? = nil,
                serial: String? = nil,
                systemPowerInW: Double? = nil,
                systemLoadW: Double? = nil,
                smcBatteryPowerW: Double? = nil) {
        self.timestamp = timestamp
        self.batteryInstalled = batteryInstalled
        self.percentage = percentage
        self.rawCurrentCapacityMAh = rawCurrentCapacityMAh
        self.rawMaxCapacityMAh = rawMaxCapacityMAh
        self.nominalChargeCapacityMAh = nominalChargeCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.cycleCount = cycleCount
        self.temperatureC = temperatureC
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
        self.instantAmperageMA = instantAmperageMA
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.adapterPresent = adapterPresent ?? externalConnected
        self.fullyCharged = fullyCharged
        self.timeRemainingMinutes = timeRemainingMinutes
        self.timeToFullMinutes = timeToFullMinutes
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.adapter = adapter
        self.serial = serial
        self.systemPowerInW = systemPowerInW
        self.systemLoadW = systemLoadW
        self.smcBatteryPowerW = smcBatteryPowerW
    }

    /// Raw hardware charge: AppleRawCurrentCapacity / AppleRawMaxCapacity * 100.
    public var hardwarePercentage: Double {
        guard rawMaxCapacityMAh > 0 else { return Double(percentage) }
        return min(100, max(0, Double(rawCurrentCapacityMAh) / Double(rawMaxCapacityMAh) * 100))
    }

    /// Battery health: full-charge capacity relative to the design capacity.
    public var healthPercent: Double? {
        guard designCapacityMAh > 0 else { return nil }
        let full = nominalChargeCapacityMAh ?? rawMaxCapacityMAh
        guard full > 0 else { return nil }
        return Double(full) / Double(designCapacityMAh) * 100
    }

    /// Battery power in watts, positive while charging, negative while discharging.
    /// Voltage (mV) * Amperage (mA) / 1_000_000.
    public var batteryPowerW: Double {
        Double(voltageMV) * Double(amperageMA) / 1_000_000
    }

    /// The percentage the policy works with.
    public func controlPercentage(useHardware: Bool) -> Int {
        useHardware ? Int(hardwarePercentage.rounded(.down)) : percentage
    }
}
