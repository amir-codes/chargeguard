import AppKit
import ChargeGuardSystem

/// NSWorkspace notifications for the app: sleep/wake (UI refresh) and fast user switching
/// (feature 23: the inactive session's app goes passive).
public final class WorkspaceObserver {
    public var onWillSleep: (() -> Void)?
    public var onDidWake: (() -> Void)?
    public var onSessionActiveChange: ((Bool) -> Void)?
    public var onScreensChange: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onWillSleep?()
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onDidWake?()
        })
        tokens.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onSessionActiveChange?(false)
        })
        tokens.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onSessionActiveChange?(true)
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            self?.onScreensChange?()
        })
    }

    public func stop() {
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }

    deinit { stop() }

    /// More than one screen, or the built-in display is not among them (clamshell with an external display).
    public static var externalDisplayConnected: Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0
        }
    }
}

/// Running apps for the energy list (icon, Quit button).
public enum RunningApps {
    public static func application(pid: pid_t) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }

    /// Asks the app to quit (NSRunningApplication.terminate). Returns false if it is not a GUI app.
    @discardableResult
    public static func quit(pid: pid_t) -> Bool {
        guard let app = application(pid: pid) else { return false }
        return app.terminate()
    }

    public static func isRunning(bundleIdentifierPrefix prefix: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.hasPrefix(prefix) == true }
    }
}
