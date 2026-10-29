import Foundation

/// Power flow numbers for the Sankey diagram (feature 20). All values in watts, never negative.
public struct PowerFlow: Codable, Equatable, Sendable {
    public var adapterW: Double
    public var systemW: Double
    public var adapterToSystemW: Double
    public var adapterToBatteryW: Double
    public var batteryToSystemW: Double
    /// Where the adapter number came from.
    public var adapterSource: AdapterPowerSource

    public enum AdapterPowerSource: String, Codable, Sendable {
        /// PowerTelemetryData SystemPowerIn or the PDTR SMC key: live input power.
        case measured
        /// Derived from the system load and the battery flow.
        case derived
        /// AdapterDetails "Watts": the adapter's rating, an upper bound.
        case rated
        case none
    }

    public static let zero = PowerFlow(adapterW: 0, systemW: 0, adapterToSystemW: 0, adapterToBatteryW: 0,
                                       batteryToSystemW: 0, adapterSource: .none)

    /// Battery power = Voltage * Amperage / 1_000_000 (positive = charging).
    /// System power = adapter power - battery charging power, or + battery discharge power.
    public static func compute(from s: BatterySnapshot) -> PowerFlow {
        let battery = s.batteryPowerW
        let charging = max(0, battery)
        let discharging = max(0, -battery)
        let adapterConnected = s.externalConnected

        guard adapterConnected else {
            return PowerFlow(adapterW: 0, systemW: discharging, adapterToSystemW: 0, adapterToBatteryW: 0,
                             batteryToSystemW: discharging, adapterSource: .none)
        }

        var adapter: Double
        var source: AdapterPowerSource
        if let measured = s.systemPowerInW, measured > 0 {
            adapter = measured
            source = .measured
        } else if let load = s.systemLoadW, load > 0 {
            adapter = load + charging - discharging
            source = .derived
        } else if let rated = s.adapter?.watts, rated > 0 {
            adapter = Double(rated)
            source = .rated
        } else {
            adapter = charging
            source = .derived
        }
        adapter = max(0, adapter)

        let toBattery = min(charging, adapter)
        let toSystem = max(0, adapter - toBattery)
        let system = toSystem + discharging
        return PowerFlow(adapterW: adapter, systemW: system, adapterToSystemW: toSystem, adapterToBatteryW: toBattery,
                         batteryToSystemW: discharging, adapterSource: source)
    }
}

/// Time estimates (feature 7 top-up estimate, feature 22 stats).
public enum TimeEstimates {
    /// Minutes until full, from macOS when it has an estimate, else capacity / current.
    public static func minutesToFull(_ s: BatterySnapshot) -> Int? {
        if let t = s.timeToFullMinutes, t > 0 { return t }
        guard s.amperageMA > 0, s.rawMaxCapacityMAh > 0 else { return nil }
        let remaining = Double(max(0, s.rawMaxCapacityMAh - s.rawCurrentCapacityMAh))
        return Int((remaining / Double(s.amperageMA) * 60).rounded())
    }

    public static func minutesToEmpty(_ s: BatterySnapshot) -> Int? {
        if let t = s.timeToEmptyMinutes, t > 0 { return t }
        guard s.amperageMA < 0 else { return nil }
        return Int((Double(s.rawCurrentCapacityMAh) / Double(-s.amperageMA) * 60).rounded())
    }

    public static func format(minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "—" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
