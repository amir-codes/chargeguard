// ChargeGuardHelper: the root launchd daemon that enforces the charging policy.
//
// Runs the ChargeController (ChargeGuardCore) with the real IOKit dependencies (ChargeGuardSystem),
// serves the XPC Mach service com.amir.chargeguard.helper, follows system sleep/wake and power-source
// changes, and restores normal charging on SIGTERM.
//
// Arguments: --verbose (mirror logs to stderr), --simulate (in-memory SMC and battery, for testing the
// XPC path without touching hardware; still needs to be started by launchd or root).

import Foundation
import ChargeGuardCore
import ChargeGuardSystem

let arguments = CommandLine.arguments
let logger = OSLogger(echoToStderr: arguments.contains("--verbose"))
let simulate = arguments.contains("--simulate")
let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"

guard getuid() == 0 || simulate else {
    logger.error(LogCategory.controller, "ChargeGuardHelper must run as root (launchd). Exiting.")
    exit(1)
}

logger.notice(LogCategory.controller, "ChargeGuardHelper \(version) starting\(simulate ? " in simulation" : "")")

/// Used when AppleSMC cannot be opened: every key reads as absent, so the controller reports
/// "no supported keys" instead of crashing, and the app can show the error.
final class UnavailableSMC: SMCKeyIO {
    let reason: String
    init(reason: String) { self.reason = reason }
    func keyInfo(_ key: String) throws -> SMCKeyInfo { throw SMCError.driverUnavailable }
    func read(_ key: String) throws -> [UInt8] { throw SMCError.driverUnavailable }
    func write(_ key: String, bytes: [UInt8]) throws { throw SMCError.driverUnavailable }
}

let dependencies: ControllerDependencies
if simulate {
    let clock = ScaledTimeSource(scale: 60)
    let (simulated, _) = ControllerDependencies.makeSimulated(clock: clock, script: SimulatedBattery.demoScript(),
                                                              logger: logger)
    dependencies = simulated
} else {
    let smcIO: SMCKeyIO
    var appleSMC: AppleSMC?
    do {
        let opened = try AppleSMC()
        appleSMC = opened
        smcIO = opened
    } catch {
        logger.log(.fault, LogCategory.smc, "AppleSMC unavailable: \(error)")
        smcIO = UnavailableSMC(reason: "\(error)")
    }
    dependencies = ControllerDependencies(
        smc: smcIO,
        battery: IORegistryBatteryReader(smc: appleSMC),
        assertions: PowerAssertionManager(logger: logger),
        lowPowerMode: PMSet(),
        sleepDisable: PMSet(),
        store: FileStateStore(logger: logger),
        conflicts: ConflictScanner(),
        energy: PowermetricsSampler(),
        lid: ClamshellReader(),
        clock: SystemTimeSource(),
        calendar: Calendar.current,
        logger: logger,
        simulated: false,
        daemonVersion: version,
        firmwareVersion: MachineInfo.firmwareVersion()
    )
}

let controller = ChargeController(dependencies: dependencies)
let service = HelperService(controller: controller, logger: logger,
                            validator: ClientValidator(logger: logger, allowAnyClient: simulate && getuid() != 0))
controller.onStatus = { status in service.broadcast(status: status) }
controller.onEvents = { events in service.broadcast(events: events) }

let listener = NSXPCListener(machServiceName: HelperProtocol.machServiceName)
listener.delegate = service
listener.resume()

let systemPower = SystemPowerObserver()
systemPower.willSleep = { allow in controller.systemWillSleep(completion: allow) }
systemPower.willNotSleep = { controller.systemWillNotSleep() }
systemPower.didWake = { controller.systemDidWake() }
if !systemPower.start() {
    logger.error(LogCategory.power, "IORegisterForSystemPower failed: sleep hooks unavailable")
}

let powerSource = PowerSourceObserver { controller.powerSourceChanged() }
powerSource.start()

// Restore normal charging on SIGTERM (launchctl bootout, uninstall, shutdown) and SIGINT.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        logger.notice(LogCategory.controller, "signal \(sig): restoring normal charging and exiting")
        controller.shutdown(reason: sig == SIGTERM ? "SIGTERM" : "SIGINT") {
            exit(0)
        }
    }
    source.resume()
    signalSources.append(source)
}

controller.start()
RunLoop.main.run()
