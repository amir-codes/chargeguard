import AppKit
import SwiftUI
import ServiceManagement
import ChargeGuardCore
import ChargeGuardSystem

/// Window identifiers.
enum WindowID {
    static let dashboard = "dashboard"
    static let onboarding = "onboarding"
}

@main
struct ChargeGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            if MachineInfo.isAppleSilicon {
                PopupView()
                    .environment(model)
            } else {
                UnsupportedMacView()
            }
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("ChargeGuard Dashboard", id: WindowID.dashboard) {
            DashboardView()
                .environment(model)
        }
        .defaultSize(width: 900, height: 680)

        Window("Welcome to ChargeGuard", id: WindowID.onboarding) {
            OnboardingView()
                .environment(model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Explicitly main-actor isolated: NSApplicationDelegate callbacks arrive on the main thread and
/// AppModel is @MainActor.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        // Used by scripts/uninstall.sh: unregister the SMAppService daemon and exit.
        // Never block the main thread waiting for the completion handler (it may be delivered on the
        // main queue): exit from the handler, with a 10-second fallback.
        if arguments.contains("--unregister-helper") {
            let service = SMAppService.daemon(plistName: HelperProtocol.launchdPlistName)
            service.unregister { error in exit(error == nil ? 0 : 1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(0) }
            return
        }
        // Headless counterparts of the first-run window's "Install helper" button, for scripts and
        // tests: --register-helper registers the SMAppService daemon (and opens Login Items when
        // approval is needed), --helper-status only prints the status. Both exit at once.
        if arguments.contains("--register-helper") || arguments.contains("--helper-status") {
            let service = SMAppService.daemon(plistName: HelperProtocol.launchdPlistName)
            var exitCode: Int32 = 0
            if arguments.contains("--register-helper") {
                do {
                    try service.register()
                } catch {
                    FileHandle.standardError.write(Data("register failed: \(error.localizedDescription)\n".utf8))
                    exitCode = 1
                }
            }
            let status = service.status
            print("helper status: \(Self.describe(status))")
            if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            exit(exitCode)
        }
        guard MachineInfo.isAppleSilicon else { return }
        AppModel.shared.start()
        // Development tool (only with --simulate): draw every window offscreen into PNGs and exit.
        if let directory = SnapshotRenderer.requestedDirectory {
            Task { @MainActor in
                await SnapshotRenderer.run(model: AppModel.shared, directory: directory)
                exit(0)
            }
        }
    }

    /// True for the maintenance flags above: no AppModel runs, so nothing to prepare on quit.
    static var isHeadlessMaintenanceRun: Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("--unregister-helper") || arguments.contains("--register-helper")
            || arguments.contains("--helper-status")
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval (allow ChargeGuard in System Settings > General > Login Items)"
        case .notFound: return "notFound (helper or launchd plist missing from the bundle)"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isHeadlessMaintenanceRun else { return }
        AppModel.shared.prepareForQuit()
    }
}

/// Opens windows from views. LSUIElement apps must activate before showing a window.
@MainActor
struct WindowOpener {
    let openWindow: OpenWindowAction

    func dashboard() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.dashboard)
    }

    func onboarding() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.onboarding)
    }
}
