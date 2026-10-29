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
        guard MachineInfo.isAppleSilicon else { return }
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--unregister-helper") else { return }
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
