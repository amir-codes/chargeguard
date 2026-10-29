import Foundation
import IOKit
import IOKit.pwr_mgt
import ChargeGuardCore

/// System sleep/wake notifications for the root daemon (IORegisterForSystemPower). The daemon cannot
/// use NSWorkspace (AppKit); this is the IOKit equivalent of willSleep/didWake.
public final class SystemPowerObserver {
    // iokit_common_msg values, spelled out because the macros may not import into Swift.
    static let canSystemSleep: UInt32 = 0xE000_0270
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemWillNotSleep: UInt32 = 0xE000_0290
    static let systemHasPoweredOn: UInt32 = 0xE000_0300
    static let systemWillPowerOn: UInt32 = 0xE000_0320

    /// Called before sleep. Call the argument when ready; sleep waits for it (up to 30 s).
    public var willSleep: ((@escaping () -> Void) -> Void)?
    public var willNotSleep: (() -> Void)?
    public var didWake: (() -> Void)?

    private var rootPort: io_connect_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    public init() {}

    @discardableResult
    public func start() -> Bool {
        guard rootPort == 0 else { return true }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceInterestCallback = { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let observer = Unmanaged<SystemPowerObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handle(messageType: messageType, argument: messageArgument)
        }
        rootPort = IORegisterForSystemPower(refcon, &notificationPort, callback, &notifier)
        guard rootPort != 0, let port = notificationPort else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        return true
    }

    public func stop() {
        guard rootPort != 0 else { return }
        IODeregisterForSystemPower(&notifier)
        if let port = notificationPort { IONotificationPortDestroy(port) }
        IOServiceClose(rootPort)
        rootPort = 0
        notificationPort = nil
    }

    private func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        let notificationID = Int(bitPattern: argument)
        switch messageType {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, notificationID)
        case Self.systemWillSleep:
            if let willSleep {
                let port = rootPort
                willSleep { _ = IOAllowPowerChange(port, notificationID) }
            } else {
                IOAllowPowerChange(rootPort, notificationID)
            }
        case Self.systemWillNotSleep:
            willNotSleep?()
        case Self.systemHasPoweredOn:
            didWake?()
        default:
            break
        }
    }

    deinit { stop() }
}

/// Holds IOPM assertions by name. Idempotent: only changes what differs.
public final class PowerAssertionManager: PowerAssertionControlling {
    // Assertion type strings (kIOPMAssertionType...), literal because CFSTR macros may not import.
    static let preventUserIdleSystemSleep = "PreventUserIdleSystemSleep"
    static let preventUserIdleDisplaySleep = "PreventUserIdleDisplaySleep"
    static let preventSystemSleep = "PreventSystemSleep"
    static let levelOn: IOPMAssertionLevel = 255

    private let lock = NSLock()
    private var held: [String: IOPMAssertionID] = [:]
    private let logger: CoreLogger?

    public init(logger: CoreLogger? = nil) {
        self.logger = logger
    }

    public func apply(_ assertions: AssertionSet) {
        lock.lock(); defer { lock.unlock() }
        update(Self.preventUserIdleSystemSleep, assertions.preventIdleSystemSleep, "ChargeGuard keeps the Mac awake")
        update(Self.preventUserIdleDisplaySleep, assertions.preventDisplaySleep, "ChargeGuard keeps the display on")
        update(Self.preventSystemSleep, assertions.preventSystemSleep, "ChargeGuard discharges in clamshell mode")
    }

    public func releaseAll() {
        apply(.none)
    }

    private func update(_ type: String, _ on: Bool, _ name: String) {
        if on, held[type] == nil {
            var id = IOPMAssertionID(0)
            let kr = IOPMAssertionCreateWithName(type as CFString, Self.levelOn, name as CFString, &id)
            if kr == KERN_SUCCESS {
                held[type] = id
                logger?.info(LogCategory.power, "assertion \(type) held")
            } else {
                logger?.error(LogCategory.power, "assertion \(type) failed: \(kr)")
            }
        } else if !on, let id = held[type] {
            IOPMAssertionRelease(id)
            held[type] = nil
            logger?.info(LogCategory.power, "assertion \(type) released")
        }
    }

    deinit {
        for id in held.values { IOPMAssertionRelease(id) }
    }
}

/// `/usr/bin/pmset` wrapper. Reads work for any user; writes need root (the daemon).
public final class PMSet: LowPowerModeControlling, SleepDisableControlling {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func settings() -> [String: String] {
        guard let result = try? runner.run("/usr/bin/pmset", ["-g"], timeout: 5), result.status == 0 else { return [:] }
        return PMSetParser.parse(result.stdout)
    }

    public func isLowPowerModeEnabled() -> Bool? {
        PMSetParser.flag(settings(), "lowpowermode")
    }

    public func setLowPowerMode(_ enabled: Bool) throws {
        try runner.check("/usr/bin/pmset", ["-a", "lowpowermode", enabled ? "1" : "0"])
    }

    public func isSleepDisabled() -> Bool? {
        PMSetParser.flag(settings(), "SleepDisabled") ?? false
    }

    public func setSleepDisabled(_ disabled: Bool) throws {
        try runner.check("/usr/bin/pmset", ["-a", "disablesleep", disabled ? "1" : "0"])
    }
}
