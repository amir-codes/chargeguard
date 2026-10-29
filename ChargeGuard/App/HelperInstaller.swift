import Foundation
import Observation
import ServiceManagement
import ChargeGuardCore

/// Installs the root helper with SMAppService (primary path). The user approves it in
/// System Settings > General > Login Items. The fallback is scripts/install-helper.sh (sudo).
@MainActor
@Observable
final class HelperInstaller {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?
    private let service = SMAppService.daemon(plistName: HelperProtocol.launchdPlistName)

    init() {
        refresh()
    }

    func refresh() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    var statusText: String {
        switch status {
        case .notRegistered: return "Not installed"
        case .enabled: return "Installed and running"
        case .requiresApproval: return "Waiting for approval in System Settings > General > Login Items"
        case .notFound: return "Helper not found in the app bundle (rebuild the app)"
        @unknown default: return "Unknown"
        }
    }

    func register() {
        lastError = nil
        do {
            try service.register()
        } catch {
            lastError = "Could not register the helper: \(error.localizedDescription). " +
                "You can install it from Terminal instead: sudo \"\(Self.bundledScript("install-helper.sh"))\""
        }
        refresh()
        if status == .requiresApproval { openLoginItems() }
    }

    func unregister() async {
        lastError = nil
        do {
            try await service.unregister()
        } catch {
            lastError = "Could not unregister the helper: \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Path of a script bundled in Contents/Resources (install-helper.sh, uninstall.sh).
    static func bundledScript(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: nil)?.path ?? "scripts/\(name)"
    }

    static var installCommand: String {
        "sudo \"\(bundledScript("install-helper.sh"))\" \"\(Bundle.main.bundlePath)\""
    }

    static var uninstallCommand: String {
        "sudo \"\(bundledScript("uninstall.sh"))\" \"\(Bundle.main.bundlePath)\""
    }
}
