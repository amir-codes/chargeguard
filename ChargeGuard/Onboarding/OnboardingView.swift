import SwiftUI
import ChargeGuardCore

/// First-run wizard (section 8): explains the helper, installs it, probes the keys, shows the result,
/// and asks for explicit confirmation before charge control is enabled. Nothing is written to the
/// SMC before the last step.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, install, probe, confirm, done
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step: Step = .welcome
    @State private var probe: KeyProbeReport?
    @State private var probing = false
    @State private var understood = false
    @State private var enabling = false
    @State private var confirmError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "battery.100percent.bolt")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Welcome to ChargeGuard").font(.title2.weight(.semibold))
                    Text("Step \(min(step.rawValue + 1, 4)) of 4").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Group {
                switch step {
                case .welcome: welcome
                case .install: install
                case .probe: probeStep
                case .confirm: confirm
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task {
            // Keep the helper state fresh while the user approves it in System Settings.
            while !Task.isCancelled {
                model.installer.refresh()
                if step == .install, model.isConnected == false { await model.refreshStatus() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChargeGuard keeps your battery at a charge limit you choose, which slows battery wear.")
            Text("To change charging, macOS requires a small helper that runs as root in the background. The helper:")
            VStack(alignment: .leading, spacing: 6) {
                Label("writes the charging keys of the System Management Controller (SMC)", systemImage: "cpu")
                Label("keeps enforcing the limit when the ChargeGuard window is closed", systemImage: "lock.shield")
                Label("restores normal charging when asked, on uninstall and when it is stopped", systemImage: "arrow.uturn.backward.circle")
                Label("never writes while another charging tool (AlDente, batt, battery) is running", systemImage: "hand.raised")
            }
            .padding(.leading, 6)
            Text("If anything goes wrong, \"Restore normal charging\" in the menu or a restart of the Mac puts every key back to the macOS default.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var install: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Install the helper. macOS asks you to allow it in System Settings > General > Login Items (\"Allow in the Background\").")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.installer.isEnabled ? "Reinstall helper" : "Install helper") { model.installer.register() }
                    .buttonStyle(.borderedProminent)
                if model.installer.needsApproval {
                    Button("Open Login Items") { model.installer.openLoginItems() }
                }
            }
            LabeledContent("Helper") { Text(model.installer.statusText) }
            LabeledContent("Connection") { Text(connectionText) }
            if let error = model.installer.lastError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            DisclosureGroup("Install from Terminal instead") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If the button does not work (for example with an unsigned development build), run this in Terminal. It asks for your password:")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(HelperInstaller.installCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(HelperInstaller.installCommand, forType: .string)
                        }
                    }
                }
            }
        }
    }

    private var probeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChargeGuard now checks which charging keys this Mac has. This only reads; nothing is changed.")
                .fixedSize(horizontal: false, vertical: true)
            Button(probing ? "Probing…" : (probe == nil ? "Probe keys" : "Probe again")) {
                probing = true
                Task {
                    probe = await model.probeKeys()
                    probing = false
                }
            }
            .disabled(probing || !model.isConnected)
            if let probe {
                ScrollView {
                    Text(probe.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            if let status = model.status {
                LabeledContent("Selected backend") { Text(status.backend.displayName) }
                ForEach(status.backendLimitations, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !status.conflicts.active.isEmpty {
                    ConflictBanner(tools: status.conflicts.active)
                }
                if status.backend == .none {
                    Text("No supported charging keys were found. ChargeGuard can show battery data but cannot control charging on this Mac.")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var confirm: some View {
        let config = model.config
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ready to enable charge control").font(.headline)
            Text("When you confirm, the helper starts enforcing a limit of \(config.chargeLimit) %. Above the limit, charging is paused while the Mac keeps running from the adapter. You can change the limit at any time from the menu bar.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Charging can only be controlled while the Mac is awake; see Settings > Charging for sleep options.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("I understand that ChargeGuard will change how this Mac charges, and that \"Restore normal charging\" or a restart undoes it.", isOn: $understood)
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: false, vertical: true)
            if let confirmError {
                Text(confirmError).foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Charge control is on", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("ChargeGuard lives in the menu bar. Click its icon to change the limit, discharge, top up or calibrate. Settings has every option, including Sleep Control, the schedule and the appearance of the icon.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Continue") { step = .install }.keyboardShortcut(.defaultAction)
            case .install:
                Button("Continue") { step = .probe }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isConnected)
            case .probe:
                Button("Continue") { step = .confirm }
                    .keyboardShortcut(.defaultAction)
                    .disabled(probe == nil || model.status?.backend == BackendKind.none)
            case .confirm:
                Button(enabling ? "Enabling…" : "Enable charge control") {
                    enabling = true
                    Task {
                        let ok = await model.confirmFirstRun()
                        enabling = false
                        if ok { step = .done } else { confirmError = model.lastError ?? "The helper did not accept the command." }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!understood || enabling || !model.conflicts.isEmpty)
            case .done:
                Button("Done") { dismissWindow(id: WindowID.onboarding) }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var connectionText: String {
        switch model.connection {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .missing: return "Not connected yet"
        case .versionMismatch(let v): return "Version mismatch (helper protocol \(v))"
        }
    }
}
