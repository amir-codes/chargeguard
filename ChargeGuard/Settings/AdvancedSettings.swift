import SwiftUI
import UniformTypeIdentifiers
import ChargeGuardCore

struct AdvancedSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var probing = false
    @State private var message: String?
    @State private var confirmUninstall = false
    @State private var busy = false

    var body: some View {
        let status = model.status
        let editable = model.isConnected || model.simulated
        Form {
            SettingsHelperNote()

            Section {
                Picker("Backend", selection: Binding(
                    get: { model.config.backendPreference },
                    set: { model.perform(.selectBackend($0)) }
                )) {
                    ForEach(BackendPreference.allCases, id: \.self) { preference in
                        Text(preference.settingsTitle).tag(preference)
                    }
                }
                .disabled(!editable)
                LabeledContent("In use", value: status?.backend.displayName ?? "—")
                if let caps = status?.backendCapabilities {
                    LabeledContent("Can block charging", value: yesNo(caps.canInhibitCharging))
                    LabeledContent("Can force discharge", value: yesNo(caps.canForceDischarge))
                    LabeledContent("Blocks by cutting the adapter", value: yesNo(caps.inhibitIsAdapterCutoff))
                    LabeledContent("Uses the firmware limit", value: yesNo(caps.usesFirmwareLimit))
                    LabeledContent("Controls the MagSafe LED", value: yesNo(caps.canControlLED))
                    LabeledContent("Enforces during sleep", value: yesNo(caps.enforcesDuringSleep))
                }
                if let error = status?.backendError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                ForEach(status?.backendLimitations ?? [], id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: model.settingsBinding(\.adapterCutoffMinBand), in: 1...20) {
                    LabeledContent("Adapter cutoff minimum band", value: "\(model.config.adapterCutoffMinBand) %")
                }
                .disabled(!editable)
                .accessibilityLabel("Adapter cutoff minimum band")
            } header: {
                Text("Charge control backend")
            } footer: {
                Text("Automatic picks a backend by probing which SMC keys exist, never by macOS version. If a write is refused (for example kIOReturnNotPrivileged on newer firmware), the helper switches to the next backend.")
            }

            Section {
                ScrollView(.horizontal) {
                    Text(status?.probe?.text ?? "Not probed yet")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
                HStack {
                    Button(probing ? "Probing…" : "Probe again") {
                        Task {
                            probing = true
                            _ = await model.probeKeys()
                            probing = false
                        }
                    }
                    .disabled(probing || !editable)
                    Button("Copy") { SettingsPanels.copy(status?.probe?.text ?? "") }
                        .disabled(status?.probe == nil)
                }
            } header: {
                Text("SMC key probe")
            } footer: {
                Text("Probing only reads keys. ChargeGuard never writes a key the probe did not find.")
            }

            Section("Control loop") {
                SettingsSlider(title: "Poll interval",
                               value: model.config.pollIntervalSeconds,
                               range: PolicyConfig.pollIntervalRange,
                               step: 1,
                               format: { "\(Int($0.rounded())) s" },
                               commit: { value in model.updateConfig { $0.pollIntervalSeconds = value } })
                    .disabled(!editable)
                LabeledContent("Helper version", value: status?.daemonVersion ?? "Not connected")
                LabeledContent("Protocol", value: "\(status?.protocolVersion ?? HelperProtocol.version)")
                LabeledContent("Firmware", value: status?.firmwareVersion ?? "—")
                LabeledContent("Keys modified by ChargeGuard", value: yesNo(status?.keysDirty ?? false))
                if model.simulated {
                    Label("Simulation (--simulate): no real keys are touched.", systemImage: "testtube.2")
                }
            }

            Section("Recent SMC writes") {
                let lines = model.recentWrites.suffix(30).reversed().map(\.line)
                if lines.isEmpty {
                    Text("No writes recorded").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                }
            }

            Section("Logs and settings") {
                HStack {
                    Button("Export logs…") { exportLogs() }
                    Button("Export settings…") { exportSettings() }
                        .disabled(!editable)
                    Button("Import settings…") { importSettings() }
                        .disabled(!editable)
                }
                .disabled(busy)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Status", value: model.installer.statusText)
                if case .versionMismatch(let helper) = model.connection {
                    Label("The installed helper speaks protocol \(helper); this app needs \(HelperProtocol.version). Reinstall the helper.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button(model.installer.isEnabled ? "Reinstall helper" : "Install helper") {
                        model.installer.register()
                        Task { await model.refreshStatus() }
                    }
                    Button("Uninstall helper…", role: .destructive) { confirmUninstall = true }
                    Button("Open Login Items") { model.installer.openLoginItems() }
                }
                if let error = model.installer.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                SettingsCommandRow(title: "Fallback install (Terminal)", command: HelperInstaller.installCommand)
                SettingsCommandRow(title: "Full uninstall (Terminal)", command: HelperInstaller.uninstallCommand)
            } header: {
                Text("Helper")
            } footer: {
                Text("The helper is installed with macOS Login Items and approved in System Settings > General > Login Items. If that fails, run the fallback command in Terminal. Use one method, not both. Uninstalling restores normal charging first.")
            }
        }
        .formStyle(.grouped)
        .task { await model.loadHistory() }
        .confirmationDialog("Uninstall the helper?", isPresented: $confirmUninstall) {
            Button("Restore charging and uninstall", role: .destructive) {
                Task { await uninstallHelper() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The helper restores normal charging, then it is removed. ChargeGuard can no longer enforce the limit until you install it again.")
        }
    }

    private func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }

    private func uninstallHelper() async {
        busy = true
        defer { busy = false }
        _ = await model.send(.prepareUninstall)
        await model.installer.unregister()
        await model.refreshStatus()
        message = model.installer.lastError ?? "Helper uninstalled. Normal charging was restored."
    }

    private func exportLogs() {
        let name = "ChargeGuard-log-\(Int(Date().timeIntervalSince1970)).txt"
        guard let url = SettingsPanels.save(name: name, type: .plainText) else { return }
        busy = true
        message = "Exporting logs…"
        Task {
            do {
                try await model.exportLogs(to: url)
                message = "Logs saved to \(url.path)"
            } catch {
                message = "Could not export logs: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func exportSettings() {
        guard let url = SettingsPanels.save(name: "ChargeGuard-settings.json", type: .json) else { return }
        Task {
            do {
                try await model.exportSettings(to: url)
                message = "Settings saved to \(url.path)"
            } catch {
                message = "Could not export settings: \(error.localizedDescription)"
            }
        }
    }

    private func importSettings() {
        guard let url = SettingsPanels.open(type: .json) else { return }
        Task {
            do {
                try await model.importSettings(from: url)
                message = "Settings imported. Charge control on/off was kept as it was."
            } catch {
                message = "Could not import settings: \(error.localizedDescription)"
            }
        }
    }
}

/// A selectable Terminal command with a Copy button.
struct SettingsCommandRow: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") { SettingsPanels.copy(command) }
                    .accessibilityLabel("Copy \(title) command")
            }
        }
    }
}
