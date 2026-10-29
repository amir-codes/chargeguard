import Foundation
import Darwin
import ChargeGuardCore

/// Feature 21. Preferred: `powermetrics --samplers tasks` (root, run by the daemon).
/// Fallbacks: proc_pid_rusage energy counters, then CPU time. Each sample says which method it used.
public final class PowermetricsSampler: EnergySampling {
    private let runner = ProcessRunner()
    private let fallback = RusageSampler()

    public init() {}

    public func sample() -> EnergySample {
        if getuid() == 0 {
            let base = ["--samplers", "tasks", "--show-process-energy", "-i", "1000", "-n", "1"]
            if let result = try? runner.run("/usr/bin/powermetrics", base + ["-f", "plist"], timeout: 15), result.status == 0 {
                let tasks = PowermetricsParser.parsePlist(result.stdoutData)
                if !tasks.isEmpty { return EnergySample(date: Date(), method: .powermetrics, processes: tasks) }
            }
            if let result = try? runner.run("/usr/bin/powermetrics", base, timeout: 15), result.status == 0 {
                let tasks = PowermetricsParser.parseText(result.stdout)
                if !tasks.isEmpty { return EnergySample(date: Date(), method: .powermetrics, processes: tasks) }
            }
        }
        return fallback.sample()
    }
}

/// proc_pid_rusage sampler. Takes two readings one second apart. Works without root for the
/// user's own processes, which covers the apps a user can quit.
public final class RusageSampler: EnergySampling {
    private struct Reading {
        var energyNJ: UInt64
        var cpuTicks: UInt64
    }

    private let timebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (info.numer, info.denom == 0 ? 1 : info.denom)
    }()

    public init() {}

    private func read(_ pid: pid_t) -> Reading? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return nil }
        return Reading(energyNJ: info.ri_billed_energy, cpuTicks: info.ri_user_time + info.ri_system_time)
    }

    public func sample() -> EnergySample {
        let entries = ProcessList.entries()
        var first: [pid_t: Reading] = [:]
        for entry in entries { first[entry.pid] = read(entry.pid) }
        let start = Date()
        Thread.sleep(forTimeInterval: 1)
        let elapsed = max(0.001, Date().timeIntervalSince(start))

        var withEnergy: [ProcessEnergy] = []
        var withCPU: [ProcessEnergy] = []
        for entry in entries {
            guard let a = first[entry.pid], let b = read(entry.pid) else { continue }
            // Mach ticks to nanoseconds (Apple silicon reports rusage times in ticks).
            let cpuNs = Double(b.cpuTicks &- a.cpuTicks) * Double(timebase.numer) / Double(timebase.denom)
            let cpuMsPerSecond = cpuNs / 1_000_000 / elapsed
            let watts = Double(b.energyNJ &- a.energyNJ) / 1_000_000_000 / elapsed
            if watts > 0 {
                withEnergy.append(ProcessEnergy(pid: entry.pid, name: entry.name, energy: watts, cpuMsPerSecond: cpuMsPerSecond))
            }
            if cpuMsPerSecond > 0 {
                withCPU.append(ProcessEnergy(pid: entry.pid, name: entry.name, energy: cpuMsPerSecond / 10, cpuMsPerSecond: cpuMsPerSecond))
            }
        }
        if !withEnergy.isEmpty {
            return EnergySample(date: Date(), method: .rusageEnergy, processes: withEnergy, note: "Watts from billed-energy counters")
        }
        if !withCPU.isEmpty {
            return EnergySample(date: Date(), method: .cpuPercent, processes: withCPU, note: "CPU percent")
        }
        return EnergySample(date: Date(), method: .unavailable, processes: [])
    }
}
