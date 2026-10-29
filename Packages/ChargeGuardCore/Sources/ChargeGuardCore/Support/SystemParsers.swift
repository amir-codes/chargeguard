import Foundation

/// Turns the AppleSmartBattery IORegistry property dictionary into a `BatterySnapshot`.
/// Pure, so it is unit-tested on any platform; ChargeGuardSystem only fetches the dictionary.
public enum BatteryRegistryParser {
    /// macOS reports 65535 for "still calculating".
    static let unknownTime = 65_535

    public static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Int64: return Int(truncatingIfNeeded: v)
        case let v as UInt64: return Int(truncatingIfNeeded: Int64(bitPattern: v))
        case let v as Int32: return Int(v)
        case let v as NSNumber: return Int(truncatingIfNeeded: v.int64Value)
        case let v as Double: return Int(v)
        default: return nil
        }
    }

    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let v as Bool: return v
        case let v as NSNumber: return v.boolValue
        case let v as Int: return v != 0
        default: return nil
        }
    }

    /// AppleSmartBattery reports some signed values (Amperage) as unsigned 64-bit numbers.
    static func signed(_ value: Any?) -> Int? {
        guard let v = int(value) else { return nil }
        if v > Int(Int32.max) && v <= Int(UInt32.max) { return Int(Int32(truncatingIfNeeded: v)) }
        return v
    }

    static func minutes(_ value: Any?) -> Int? {
        guard let v = int(value), v >= 0, v < unknownTime else { return nil }
        return v
    }

    /// Temperature is read as hundredths of a degree Celsius (3056 = 30.56 °C), which is what Apple
    /// silicon reports as far as I know. The brief says "hundredths of a kelvin", which would give
    /// impossible values. Verify against coconutBattery or `ioreg -rn AppleSmartBattery` on the Mac
    /// (docs/MAC-BUILD-NOTES.md) and change only this function if it is wrong.
    public static func celsius(fromRaw raw: Int) -> Double {
        Double(raw) / 100
    }

    public static func parse(_ d: [String: Any], now: Date, acPowerFromSMC: Bool? = nil,
                             dcInPowerFromSMC: Double? = nil, batteryPowerFromSMC: Double? = nil) -> BatterySnapshot {
        let installed = bool(d["BatteryInstalled"]) ?? true
        let current = int(d["CurrentCapacity"]) ?? 0
        let maxCapacity = int(d["MaxCapacity"]) ?? 100
        let percentage = maxCapacity > 0 && maxCapacity != 100
            ? Int((Double(current) / Double(maxCapacity) * 100).rounded()) : current
        let rawCurrent = int(d["AppleRawCurrentCapacity"]) ?? 0
        let rawMax = int(d["AppleRawMaxCapacity"]) ?? 0
        let externalConnected = bool(d["ExternalConnected"]) ?? false

        var adapter: AdapterInfo?
        if let details = d["AdapterDetails"] as? [String: Any], !details.isEmpty {
            let watts = int(details["Watts"])
            let name = details["Name"] as? String ?? details["Description"] as? String
            if (watts ?? 0) > 0 || name != nil {
                adapter = AdapterInfo(watts: watts, name: name,
                                      manufacturer: details["Manufacturer"] as? String,
                                      voltageMV: int(details["AdapterVoltage"]),
                                      currentMA: int(details["Current"]),
                                      isWireless: bool(details["IsWireless"]))
            }
        }

        let rawExternal = bool(d["AppleRawExternalConnected"])
        let adapterPresent = externalConnected || rawExternal == true || acPowerFromSMC == true
            || (adapter?.watts ?? 0) > 0

        var systemPowerIn: Double?
        var systemLoad: Double?
        if let telemetry = d["PowerTelemetryData"] as? [String: Any] {
            if let mW = int(telemetry["SystemPowerIn"]), mW > 0 { systemPowerIn = Double(mW) / 1000 }
            if let mW = int(telemetry["SystemLoad"]), mW > 0 { systemLoad = Double(mW) / 1000 }
        }
        if systemPowerIn == nil, let w = dcInPowerFromSMC, w > 0 { systemPowerIn = w }

        let isCharging = bool(d["IsCharging"]) ?? false
        let timeRemaining = minutes(d["TimeRemaining"])
        let toFull = minutes(d["AvgTimeToFull"]) ?? (isCharging ? timeRemaining : nil)
        let toEmpty = minutes(d["AvgTimeToEmpty"]) ?? (!externalConnected ? timeRemaining : nil)

        return BatterySnapshot(timestamp: now,
                               batteryInstalled: installed,
                               percentage: percentage,
                               rawCurrentCapacityMAh: rawCurrent,
                               rawMaxCapacityMAh: rawMax,
                               nominalChargeCapacityMAh: int(d["NominalChargeCapacity"]),
                               designCapacityMAh: int(d["DesignCapacity"]) ?? 0,
                               cycleCount: int(d["CycleCount"]) ?? 0,
                               temperatureC: celsius(fromRaw: int(d["Temperature"]) ?? 3000),
                               voltageMV: int(d["Voltage"]) ?? 0,
                               amperageMA: signed(d["Amperage"]) ?? 0,
                               instantAmperageMA: signed(d["InstantAmperage"]) ?? signed(d["Amperage"]) ?? 0,
                               isCharging: isCharging,
                               externalConnected: externalConnected,
                               adapterPresent: adapterPresent,
                               fullyCharged: bool(d["FullyCharged"]) ?? false,
                               timeRemainingMinutes: timeRemaining,
                               timeToFullMinutes: toFull,
                               timeToEmptyMinutes: toEmpty,
                               adapter: adapter,
                               serial: d["Serial"] as? String ?? d["BatterySerialNumber"] as? String,
                               systemPowerInW: systemPowerIn,
                               systemLoadW: systemLoad,
                               smcBatteryPowerW: batteryPowerFromSMC)
    }
}

/// Parses `pmset -g` ("lowpowermode 0", "SleepDisabled 1", ...).
public enum PMSetParser {
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }

    public static func flag(_ settings: [String: String], _ key: String) -> Bool? {
        guard let value = settings[key] else { return nil }
        return value == "1"
    }
}
