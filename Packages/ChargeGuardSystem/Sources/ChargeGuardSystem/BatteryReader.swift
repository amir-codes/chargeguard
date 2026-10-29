import Foundation
import IOKit
import IOKit.ps
import ChargeGuardCore

public enum BatteryReaderError: Error, CustomStringConvertible {
    case propertiesUnavailable(kern_return_t)

    public var description: String {
        switch self {
        case .propertiesUnavailable(let kr): return "AppleSmartBattery properties unavailable (kern_return \(kr))"
        }
    }
}

/// Reads AppleSmartBattery from the IORegistry (no root needed), plus read-only SMC telemetry keys
/// (AC-W adapter presence, PDTR input power, PPBR battery power) when an SMC connection is given.
public final class IORegistryBatteryReader: BatteryReading {
    private let smc: AppleSMC?

    public init(smc: AppleSMC? = nil) {
        self.smc = smc
    }

    /// The raw property dictionary, for `chargectl status --raw` and diagnostics.
    public static func properties() throws -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else {
            throw BatteryReaderError.propertiesUnavailable(kr)
        }
        return dictionary
    }

    public func readSnapshot() throws -> BatterySnapshot {
        guard let properties = try Self.properties() else {
            return BatterySnapshot(timestamp: Date(), batteryInstalled: false, percentage: 0)
        }
        var acPower: Bool?
        if let value = smc?.number(SMCKey.acPower) { acPower = value > 0 }
        let dcIn = smc?.number(SMCKey.dcInPower)
        let batteryPower = smc?.number(SMCKey.batteryPower)
        return BatteryRegistryParser.parse(properties, now: Date(), acPowerFromSMC: acPower,
                                           dcInPowerFromSMC: dcIn, batteryPowerFromSMC: batteryPower)
    }
}

/// Calls `handler` on the main run loop whenever the power source changes
/// (IOPSNotificationCreateRunLoopSource). Callers also poll as a backstop.
public final class PowerSourceObserver {
    private var source: CFRunLoopSource?
    private let handler: () -> Void

    public init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    public func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue().handler()
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        source = created
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    deinit { stop() }
}

/// Lid state from IOPMrootDomain's AppleClamshellState.
public final class ClamshellReader: LidStateReading {
    public init() {}

    public func isLidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        if let flag = value as? Bool { return flag }
        return (value as? NSNumber)?.boolValue
    }
}
