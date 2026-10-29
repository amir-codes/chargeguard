import SwiftUI
import ServiceManagement
import ChargeGuardCore

struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var restoreRequested = false

    var body: some View {
        @Bindable var prefs = model.preferences
        Form {
            Section {
                HelperBanner()
                Toggle("Charge control", isOn: Binding(
                    get: { model.config.controlEnabled },
                    set: { on in
                        if on && !model.preferences.hasCompletedOnboarding && !model.simulated {
                            // The first-run window probes the keys and asks for confirmation first.
                            WindowOpener(openWindow: openWindow).onboarding()
                        } else {
                            model.perform(.setControlEnabled(on))
                        }
                    }
                ))
                .disabled(!model.isConnected && !model.simulated)
                .accessibilityHint("Turns ChargeGuard's charge limit and all charging features on or off")
            } header: {
                Text("ChargeGuard")
            } footer: {
                Text("While charge control is off, ChargeGuard writes nothing and macOS charges normally.")
            }

            Section("Startup") {
                Toggle("Launch ChargeGuard at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Picker("When ChargeGuard quits", selection: Binding(
                    get: { model.config.appClosedBehavior },
                    set: { value in model.updateConfig { $0.appClosedBehavior = value } }
                )) {
                    ForEach(AppClosedBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.settingsTitle).tag(behavior)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.isConnected && !model.simulated)
            } header: {
                Text("Stop Charging when App Closed")
            } footer: {
                Text("The helper is a separate background process. By default it keeps enforcing the limit after you quit ChargeGuard. With the second option it restores normal charging when you quit, and enforces again when you open ChargeGuard. If ChargeGuard crashes, the helper always keeps enforcing.")
            }

            Section("Notifications") {
                Toggle("Show notifications", isOn: $prefs.notificationsEnabled)
                Text("Calibration phases, heat pauses, schedule runs and helper problems.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore normal charging") { restoreRequested = true }
                    .disabled(!model.isConnected && !model.simulated)
                    .accessibilityHint("Writes the macOS default to every charging key and turns charge control off")
            } header: {
                Text("Safety")
            } footer: {
                Text("Writes the default value to every charging, discharge and LED key and turns charge control off. Restarting the Mac also resets every key to the macOS default.")
            }

            if let error = model.lastError {
                Section {
                    Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore normal charging?", isPresented: $restoreRequested) {
            Button("Restore normal charging") { model.restoreNormalCharging() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ChargeGuard turns charge control off and macOS charges normally. Turn charge control on again to resume.")
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
