// chargectl: debugging and emergency restore for ChargeGuard.
//
// Talks to the helper over XPC. With --direct it opens the SMC itself (reads work for any user;
// `restore --direct` needs sudo) so it works without the helper.

import Foundation
import ChargeGuardCore
import ChargeGuardSystem

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let usageText = """
usage: chargectl <command> [options]

  status [--json] [--direct]   battery, policy and key state
  probe [--direct]             report every section 5 key as present or absent, with its size
  read KEY [--direct]          read one SMC key
  restore [--direct]           write the deactivate value to every present charge and discharge key,
                               reset ACLC, and turn charge control off. --direct needs sudo and
                               works without the helper. A reboot also resets the keys.
  limit N                      set the charge limit (20-100)
  discharge on|off             force discharge to the limit / stop
  topup on|off                 charge to 100 % once / cancel
  calibrate start [--fast]|stop
  heat on|off                  Heat Protection
  sailing on|off               Sailing Mode
  lpm unmanaged|off|on|battery|adapter    Low Power Mode policy
  led system|state|off         MagSafe LED mode
  keepawake MINUTES|forever|off
  enable | disable             turn charge control on or off
  events                       recent helper events
  writes                       recent SMC writes (key, value, reason, battery)
  prepare-uninstall            restore charging and stop enforcing (used by uninstall.sh)
  version
"""

let arguments = Array(CommandLine.arguments.dropFirst())
let flags = Set(arguments.filter { $0.hasPrefix("--") })
let positional = arguments.filter { !$0.hasPrefix("--") }
let direct = flags.contains("--direct")
let wantsJSON = flags.contains("--json")

func printErr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

// MARK: - Helper access

let client = XPCHelperClient(timeout: 20)

func request(_ r: HelperRequest) throws -> HelperResponse {
    do {
        let response = try client.sendSync(r)
        if case .error(let message) = response { throw CLIError(message) }
        return response
    } catch let error as CLIError {
        throw error
    } catch {
        throw CLIError("could not reach the ChargeGuard helper (\(error)). Is it installed? Try --direct for read-only commands, or `sudo chargectl restore --direct`.")
    }
}

func command(_ c: HelperCommand) throws {
    let response = try request(.command(c))
    if case .status(let status) = response {
        printStatus(status)
    } else {
        print("ok")
    }
}

func helperIsRunning() -> Bool {
    let quick = XPCHelperClient(timeout: 3)
    defer { quick.invalidate() }
    guard let response = try? quick.sendSync(.hello(clientProtocolVersion: HelperProtocol.version, client: "chargectl")),
          case .hello = response else { return false }
    return true
}

// MARK: - Output

func onOff(_ value: Bool?) -> String {
    guard let value else { return "?" }
    return value ? "yes" : "no"
}

func describe(_ s: BatterySnapshot) -> String {
    var parts = ["\(s.percentage) % (hardware \(String(format: "%.1f", s.hardwarePercentage)) %)",
                 String(format: "%.1f °C", s.temperatureC),
                 String(format: "%.2f V", Double(s.voltageMV) / 1000),
                 "\(s.amperageMA) mA",
                 "charging \(onOff(s.isCharging))",
                 "external power \(onOff(s.externalConnected))",
                 "adapter present \(onOff(s.adapterPresent))"]
    if let adapter = s.adapter { parts.append("adapter \(adapter.watts.map { "\($0) W" } ?? "?") \(adapter.name ?? "")") }
    return parts.joined(separator: ", ")
}

func printStatus(_ status: DaemonStatus) {
    if wantsJSON {
        if let data = try? CoreJSON.encoder(pretty: true).encode(status) { print(String(decoding: data, as: UTF8.self)) }
        return
    }
    print("Helper:     \(status.daemonVersion) (protocol \(status.protocolVersion))\(status.simulated ? " SIMULATED" : "")")
    if let s = status.snapshot { print("Battery:    \(describe(s))") }
    print("State:      \(status.chargeStatus.title)")
    print("Control:    \(status.config.controlEnabled ? "on" : "off"), limit \(status.config.chargeLimit) %, effective \(status.effectiveLimit) %")
    print("Backend:    \(status.backend.displayName)")
    if let error = status.backendError { print("Error:      \(error)") }
    if let h = status.hardware {
        var keys: [String] = []
        if let v = h.chargingInhibited { keys.append("charging \(v ? "blocked" : "allowed")") }
        if let v = h.dischargeForced { keys.append("discharge \(v ? "forced" : "off")") }
        if let v = h.ledRaw { keys.append(String(format: "ACLC %02x", v)) }
        if let active = h.firmwareLimitActive { keys.append("firmware limit \(active ? "on \(h.firmwareLower ?? 0)-\(h.firmwareUpper ?? 0) %" : "off")") }
        print("Keys:       \(keys.joined(separator: ", "))")
    }
    print("Keys dirty: \(status.keysDirty ? "yes (ChargeGuard has changed keys)" : "no")")
    print("Conflicts:  \(status.conflicts.active.isEmpty ? "none" : status.conflicts.active.joined(separator: ", "))")
    for note in status.conflicts.installedOnly { print("            \(note)") }
    let c = status.control
    if let cal = c.calibration { print("Calibration: phase \(cal.phase.letter) \(cal.phase.title)\(cal.fast ? " (fast)" : "")") }
    if c.topUp != nil { print("Top up:     active") }
    if let ka = c.keepAwake { print("Keep awake: \(ka.until.map { "until \($0)" } ?? (ka.untilChargeLimit ? "until the limit" : "indefinitely"))") }
    if let lpm = status.lowPowerModeActive { print("Low Power:  \(lpm ? "on" : "off") (policy \(status.config.lowPowerMode.rawValue))") }
    if let next = status.nextScheduledRun { print("Next rule:  \(next.summary) at \(next.date)") }
    if let firmware = status.firmwareVersion { print("Firmware:   \(firmware)") }
}

func parseOnOff(_ value: String?) throws -> Bool {
    switch value {
    case "on", "true", "1", "start": return true
    case "off", "false", "0", "stop": return false
    default: throw CLIError("expected on or off")
    }
}

// MARK: - Direct (no helper)

func directSMC() throws -> AppleSMC {
    do { return try AppleSMC() } catch { throw CLIError("cannot open AppleSMC: \(error)") }
}

func directRead(_ key: String) throws {
    let smc = try directSMC()
    let info = try smc.keyInfo(key)
    let bytes = try smc.read(key)
    print("\(key)  size \(info.size)  type '\(info.type)'  value \(Hex.string(bytes))")
}

func directRestore() throws {
    guard getuid() == 0 else { throw CLIError("restore --direct writes SMC keys and needs root: sudo chargectl restore --direct") }
    let smc = try directSMC()
    let report = KeyProber.probe(smc)
    let writer = GuardedSMCWriter(io: smc, report: report)
    writer.snapshotSummary = (try? IORegistryBatteryReader(smc: smc).readSnapshot()).map(describe) ?? "battery unreadable"
    // The one explicit override of "never write while another tool runs": the user asked for it under sudo.
    let conflicts = ConflictScanner().scan().active
    if !conflicts.isEmpty {
        printErr("warning: another charging tool is running (\(conflicts.joined(separator: ", "))). Restoring anyway because you asked; that tool will probably rewrite the keys. Quit it for a lasting restore.")
    }
    let result = writer.restoreAll(reason: "chargectl restore --direct", bypassBlock: true)
    for record in result.records { print(record.line) }
    for error in result.errors { printErr("error: \(error)") }
    if result.records.isEmpty && result.errors.isEmpty { print("All present keys already hold their default values.") }
    if helperIsRunning() {
        printErr("note: the helper is running and may re-apply the limit on its next tick. Use `chargectl restore` (turns control off) or stop it: sudo launchctl bootout system/\(HelperProtocol.machServiceName)")
    }
    if !result.errors.isEmpty { throw CLIError("restore incomplete; a reboot resets every key") }
}

// MARK: - Commands

func run() throws {
    guard let name = positional.first else {
        print(usageText)
        exit(2)
    }
    let argument = positional.count > 1 ? positional[1] : nil

    switch name {
    case "status":
        if direct {
            let smc = try? AppleSMC()
            let snapshot = try IORegistryBatteryReader(smc: smc).readSnapshot()
            if wantsJSON {
                print(String(decoding: try CoreJSON.encoder(pretty: true).encode(snapshot), as: UTF8.self))
            } else {
                print("Battery: \(describe(snapshot))")
                if let smc { print(KeyProber.probe(smc).text) }
            }
        } else if case .status(let status) = try request(.getStatus) {
            printStatus(status)
        }
    case "probe":
        if direct {
            print(KeyProber.probe(try directSMC()).text)
        } else if case .probe(let report) = try request(.probeKeys) {
            print(report.text)
        }
    case "read":
        guard let key = argument else { throw CLIError("usage: chargectl read KEY") }
        if direct {
            try directRead(key)
        } else if case .keyValue(let result) = try request(.readKey(key)) {
            if let info = result.info, let bytes = result.bytes {
                print("\(key)  size \(info.size)  type '\(info.type)'  value \(Hex.string(bytes))")
            } else {
                print("\(key)  absent\(result.error.map { " (\($0))" } ?? "")")
            }
        }
    case "restore":
        if direct { try directRestore() } else { try command(.restoreNormalCharging) }
    case "limit":
        guard let value = argument.flatMap(Int.init), PolicyConfig.limitRange.contains(value) else {
            throw CLIError("usage: chargectl limit 20-100")
        }
        try command(.setChargeLimit(value))
    case "discharge":
        try command(try parseOnOff(argument) ? .startDischarge : .stopDischarge)
    case "topup":
        try command(try parseOnOff(argument) ? .startTopUp : .cancelTopUp)
    case "calibrate":
        switch argument {
        case "start": try command(.startCalibration(fast: flags.contains("--fast"), origin: "chargectl"))
        case "stop", "cancel": try command(.cancelCalibration)
        default: throw CLIError("usage: chargectl calibrate start [--fast] | stop")
        }
    case "heat":
        try command(.setHeatProtection(try parseOnOff(argument)))
    case "sailing":
        try command(.setSailing(try parseOnOff(argument)))
    case "lpm":
        let modes: [String: LowPowerModePolicy] = ["unmanaged": .unmanaged, "off": .alwaysOff, "on": .alwaysOn,
                                                   "battery": .onlyOnBattery, "adapter": .onlyOnAdapter]
        guard let mode = argument.flatMap({ modes[$0] }) else { throw CLIError("usage: chargectl lpm unmanaged|off|on|battery|adapter") }
        try command(.setLowPowerMode(mode))
    case "led":
        let modes: [String: MagSafeLEDMode] = ["system": .systemDefault, "state": .followState, "off": .alwaysOff]
        guard let mode = argument.flatMap({ modes[$0] }) else { throw CLIError("usage: chargectl led system|state|off") }
        try command(.setMagSafeLED(mode))
    case "keepawake":
        switch argument {
        case "off", "stop": try command(.cancelKeepAwake)
        case "forever": try command(.keepAwake(KeepAwakeRequest(durationSeconds: nil)))
        default:
            guard let minutes = argument.flatMap(Double.init), minutes > 0 else { throw CLIError("usage: chargectl keepawake MINUTES|forever|off") }
            try command(.keepAwake(KeepAwakeRequest(durationSeconds: minutes * 60, preventDisplaySleep: flags.contains("--display"))))
        }
    case "enable":
        try command(.setControlEnabled(true))
    case "disable":
        try command(.setControlEnabled(false))
    case "events":
        if case .events(let events) = try request(.recentEvents(limit: 50)) {
            for e in events { print("\(e.date)  \(e.event.summary)") }
        }
    case "writes":
        if case .writes(let writes) = try request(.recentWrites(limit: 50)) {
            for w in writes { print("\(w.date)  \(w.line)") }
        }
    case "prepare-uninstall":
        _ = try request(.command(.prepareUninstall))
        print("Normal charging restored; the helper stopped enforcing.")
    case "version":
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        print("chargectl \(version), protocol \(HelperProtocol.version)")
    case "help", "-h":
        print(usageText)
    default:
        printErr("unknown command: \(name)\n")
        print(usageText)
        exit(2)
    }
}

do {
    try run()
    client.invalidate()
    exit(0)
} catch {
    printErr("chargectl: \(error)")
    exit(1)
}
