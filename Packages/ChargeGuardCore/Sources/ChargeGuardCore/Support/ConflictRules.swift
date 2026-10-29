import Foundation

/// Raw facts gathered by the platform scanner (ChargeGuardSystem.ConflictScanner).
public struct ConflictScanInput: Equatable, Sendable {
    /// Executable names of running processes.
    public var processNames: [String]
    /// Full command lines (argv joined) of running processes, when readable.
    public var processCommandLines: [String]
    /// Labels loaded in launchd (system domain and the console user's GUI domain).
    public var launchdLabels: [String]
    public var existingPaths: Set<String>

    public init(processNames: [String] = [], processCommandLines: [String] = [], launchdLabels: [String] = [],
                existingPaths: Set<String> = []) {
        self.processNames = processNames
        self.processCommandLines = processCommandLines
        self.launchdLabels = launchdLabels
        self.existingPaths = existingPaths
    }
}

public struct ConflictReport: Codable, Equatable, Sendable {
    /// Tools that are enforcing right now. While non-empty, ChargeGuard never writes SMC keys.
    public var active: [String]
    /// Tools that are installed but not running (informational only).
    public var installedOnly: [String]

    public init(active: [String] = [], installedOnly: [String] = []) {
        self.active = active
        self.installedOnly = installedOnly
    }

    public static let none = ConflictReport()
}

/// Section 6. AlDente's helper stays registered after the app quits but only writes keys while the
/// AlDente app runs, so AlDente is detected by its app process. batt and the battery CLI enforce on
/// their own, so their daemons, launchd labels and processes are detected.
public enum ConflictRules {
    public static let alDenteProcessNames: Set<String> = ["AlDente"]
    public static let battProcessNames: Set<String> = ["batt"]
    public static let battLabelFragments = ["chlc.batt", "homebrew.mxcl.batt"]
    /// "co.palokaj.battery" from the brief; "com.battery.app" is the LaunchAgent label battery.sh installs.
    public static let batteryCLILabelFragments = ["co.palokaj.battery", "com.battery.app"]
    public static let batteryCLICommandFragments = ["/usr/local/co.palokaj.battery/", "/usr/local/bin/battery maintain"]
    public static let batteryCLIFolder = "/usr/local/co.palokaj.battery"

    public static func evaluate(_ input: ConflictScanInput) -> ConflictReport {
        var active: [String] = []
        var installed: [String] = []

        if input.processNames.contains(where: { alDenteProcessNames.contains($0) }) {
            active.append("AlDente (app running)")
        }

        let battRunning = input.processNames.contains { battProcessNames.contains($0) }
        let battLabel = input.launchdLabels.first { label in battLabelFragments.contains { label.contains($0) } }
        if battRunning || battLabel != nil {
            active.append(battLabel.map { "batt (\($0))" } ?? "batt (process running)")
        }

        let batteryLabel = input.launchdLabels.first { label in batteryCLILabelFragments.contains { label.contains($0) } }
        let batteryProcess = input.processCommandLines.contains { line in batteryCLICommandFragments.contains { line.contains($0) } }
        if batteryLabel != nil || batteryProcess {
            active.append(batteryLabel.map { "battery CLI (\($0))" } ?? "battery CLI (process running)")
        } else if input.existingPaths.contains(batteryCLIFolder) {
            installed.append("battery CLI installed at \(batteryCLIFolder) (not running)")
        }
        return ConflictReport(active: active, installedOnly: installed)
    }
}
