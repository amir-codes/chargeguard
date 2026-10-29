import Foundation

/// A battery model that reacts to the simulated SMC keys. Time comes from a `TimeSource`, so a
/// scaled clock makes hours pass in minutes for `--simulate`, and a manual clock drives tests.
public final class SimulatedBattery: BatteryReading {
    public struct ScriptStep: Sendable {
        /// Seconds of simulated time after start.
        public var at: TimeInterval
        public var adapterConnected: Bool?
        public var temperatureC: Double?
        public var systemLoadW: Double?

        public init(at: TimeInterval, adapterConnected: Bool? = nil, temperatureC: Double? = nil, systemLoadW: Double? = nil) {
            self.at = at
            self.adapterConnected = adapterConnected
            self.temperatureC = temperatureC
            self.systemLoadW = systemLoadW
        }
    }

    private let lock = NSLock()
    public let smc: SimulatedSMC
    public let clock: TimeSource
    private var lastStep: Date
    private let start: Date

    /// Exact charge in percent of the full-charge capacity.
    public private(set) var charge: Double
    public var adapterConnected: Bool
    public var adapterWatts: Int
    public var temperatureC: Double
    /// Extra temperature imposed by a script step (heat test); decays toward the model temperature.
    private var temperatureOverride: Double?
    public var systemLoadW: Double
    public var script: [ScriptStep]
    private var nextScriptIndex = 0

    public let designCapacityMAh = 4_382
    public let fullChargeCapacityMAh = 4_105
    public let cycleCount = 187
    public let nominalVoltageMV = 12_600

    public init(smc: SimulatedSMC, clock: TimeSource, charge: Double = 62, adapterConnected: Bool = true,
                adapterWatts: Int = 67, temperatureC: Double = 30, systemLoadW: Double = 9, script: [ScriptStep] = []) {
        self.smc = smc
        self.clock = clock
        self.charge = charge
        self.adapterConnected = adapterConnected
        self.adapterWatts = adapterWatts
        self.temperatureC = temperatureC
        self.systemLoadW = systemLoadW
        self.script = script.sorted { $0.at < $1.at }
        self.start = clock.now
        self.lastStep = clock.now
    }

    /// A curve for `--simulate` screenshots: plugged in at 62 %, a warm spell, an unplug and a replug.
    public static func demoScript() -> [ScriptStep] {
        [
            ScriptStep(at: 40 * 60, temperatureC: 37),
            ScriptStep(at: 55 * 60, temperatureC: 31),
            ScriptStep(at: 3 * 3600, adapterConnected: false),
            ScriptStep(at: 3 * 3600 + 30 * 60, adapterConnected: true),
        ]
    }

    public func setCharge(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        charge = min(100, max(0, value))
    }

    /// Pins the temperature (heat-protection tests). `nil` returns to the load-based model.
    public func setTemperature(_ value: Double?) {
        lock.lock(); defer { lock.unlock() }
        temperatureOverride = value
        if let value { temperatureC = value }
    }

    /// Current flowing into the battery in mA (negative = discharging) for the present key state.
    private func currentMA() -> Int {
        let onAdapter = adapterConnected && !smc.dischargeForced
        if onAdapter {
            var inhibited = smc.chargingInhibited
            if let upper = smc.firmwareUpperLimit, charge >= Double(upper) { inhibited = true }
            if inhibited || charge >= 100 { return 0 }
            // Taper above 80 %.
            let base = Double(adapterWatts) * 0.5 / (Double(nominalVoltageMV) / 1000) * 1000
            let taper = charge < 80 ? 1.0 : max(0.15, (100 - charge) / 20)
            return Int(min(base, 4_500) * taper)
        }
        return -Int(systemLoadW / (Double(nominalVoltageMV) / 1000) * 1000)
    }

    private func applyScript(elapsed: TimeInterval) {
        while nextScriptIndex < script.count, script[nextScriptIndex].at <= elapsed {
            let step = script[nextScriptIndex]
            if let a = step.adapterConnected { adapterConnected = a }
            if let t = step.temperatureC { temperatureOverride = t }
            if let w = step.systemLoadW { systemLoadW = w }
            nextScriptIndex += 1
        }
    }

    /// Advances the model to the clock's current time.
    public func advance() {
        lock.lock(); defer { lock.unlock() }
        let now = clock.now
        var remaining = now.timeIntervalSince(lastStep)
        guard remaining > 0 else { return }
        var elapsed = lastStep.timeIntervalSince(start)
        // Integrate in steps of at most 10 simulated seconds.
        while remaining > 0 {
            let dt = min(10, remaining)
            elapsed += dt
            applyScript(elapsed: elapsed)
            let current = Double(currentMA())
            charge += current * dt / 3600 / Double(fullChargeCapacityMAh) * 100
            charge = min(100, max(0, charge))
            let target: Double
            if let override = temperatureOverride {
                target = override
            } else if current > 500 {
                target = 33.5
            } else if current < -200 {
                target = 31
            } else {
                target = 29
            }
            temperatureC += (target - temperatureC) * min(1, dt / 300)
            remaining -= dt
        }
        lastStep = now
    }

    public func readSnapshot() throws -> BatterySnapshot {
        advance()
        lock.lock(); defer { lock.unlock() }
        let current = currentMA()
        let pct = Int(charge.rounded())
        let rawCurrent = Int(Double(fullChargeCapacityMAh) * charge / 100)
        let onAdapter = adapterConnected && !smc.dischargeForced
        let voltage = nominalVoltageMV - 600 + Int(charge * 12)
        let toFull: Int? = current > 0 ? Int(Double(fullChargeCapacityMAh - rawCurrent) / Double(current) * 60) : nil
        let toEmpty: Int? = current < 0 ? Int(Double(rawCurrent) / Double(-current) * 60) : nil
        return BatterySnapshot(timestamp: clock.now,
                               batteryInstalled: true,
                               percentage: pct,
                               rawCurrentCapacityMAh: rawCurrent,
                               rawMaxCapacityMAh: fullChargeCapacityMAh + 40,
                               nominalChargeCapacityMAh: fullChargeCapacityMAh,
                               designCapacityMAh: designCapacityMAh,
                               cycleCount: cycleCount,
                               temperatureC: (temperatureC * 10).rounded() / 10,
                               voltageMV: voltage,
                               amperageMA: current,
                               instantAmperageMA: current,
                               isCharging: current > 0,
                               externalConnected: onAdapter,
                               adapterPresent: adapterConnected,
                               fullyCharged: pct >= 100 && current == 0,
                               timeRemainingMinutes: toFull ?? toEmpty,
                               timeToFullMinutes: toFull,
                               timeToEmptyMinutes: toEmpty,
                               adapter: adapterConnected ? AdapterInfo(watts: adapterWatts, name: "Simulated USB-C Power Adapter",
                                                                       manufacturer: "ChargeGuard") : nil,
                               serial: "SIM0000CHARGEGUARD",
                               systemPowerInW: onAdapter ? systemLoadW + max(0, Double(current) * Double(voltage) / 1_000_000) : 0,
                               systemLoadW: systemLoadW,
                               smcBatteryPowerW: Double(current) * Double(voltage) / 1_000_000)
    }
}
