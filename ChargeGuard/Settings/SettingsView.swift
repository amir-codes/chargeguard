import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ChargeGuardCore

/// The Settings window (section 7 "Also required"): General, Charging, Heat, Sailing, Calibration,
/// Schedule, Sleep and Power, Appearance, Shortcuts, Advanced, About.
struct SettingsView: View {
    var body: some View {
        TabView {
            // Two Groups keep each ViewBuilder block at 10 children or fewer (Group is transparent
            // to TabView, so this is still 11 tabs).
            Group {
                GeneralSettingsTab()
                    .tabItem { Label("General", systemImage: "gearshape") }
                ChargingSettingsTab()
                    .tabItem { Label("Charging", systemImage: "battery.75percent") }
                HeatSettingsTab()
                    .tabItem { Label("Heat", systemImage: "thermometer.high") }
                SailingSettingsTab()
                    .tabItem { Label("Sailing", systemImage: "sailboat") }
                CalibrationSettingsTab()
                    .tabItem { Label("Calibration", systemImage: "gauge.with.dots.needle.33percent") }
                ScheduleSettingsTab()
                    .tabItem { Label("Schedule", systemImage: "calendar.badge.clock") }
            }
            Group {
                SleepPowerSettingsTab()
                    .tabItem { Label("Sleep & Power", systemImage: "moon.zzz") }
                AppearanceSettingsTab()
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                ShortcutsSettingsTab()
                    .tabItem { Label("Shortcuts", systemImage: "square.2.layers.3d") }
                AdvancedSettingsTab()
                    .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                AboutSettingsTab()
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
        }
        // Eleven tabs need a little more width than 620 to fit the toolbar without overflow.
        .frame(width: 760, height: 540)
    }
}

// MARK: - Shared settings helpers

extension AppModel {
    /// A binding to one policy field. Reads the daemon's config, writes the whole config back.
    func settingsBinding<T>(_ keyPath: WritableKeyPath<PolicyConfig, T>) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { value in self.updateConfig { $0[keyPath: keyPath] = value } }
        )
    }

    /// The clock to compare daemon dates with: the daemon's own clock in simulation (it runs faster).
    func settingsNow(_ realNow: Date) -> Date {
        simulated ? (status?.date ?? realNow) : realNow
    }
}

/// A slider that shows its value and sends it to the daemon when the drag ends (or immediately for
/// keyboard and accessibility adjustments), instead of on every drag tick.
struct SettingsSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let commit: (Double) -> Void

    @State private var draft: Double?
    @State private var pending: Double?
    @State private var editing = false

    private var shown: Double { draft ?? pending ?? value }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(shown))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { shown },
                    set: { newValue in
                        draft = newValue
                        if !editing { send(newValue) }
                    }
                ),
                in: range,
                step: step,
                onEditingChanged: { isEditing in
                    editing = isEditing
                    if !isEditing, let draft { send(draft) }
                }
            )
            .accessibilityLabel(title)
            .accessibilityValue(format(shown))
        }
        .onChange(of: value) { _, _ in pending = nil }
        .task(id: pending) {
            // If the daemon never echoes the value (rejected, disconnected), show the real value again.
            guard pending != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            pending = nil
        }
    }

    private func send(_ newValue: Double) {
        draft = nil
        guard newValue != value else { return }
        pending = newValue
        commit(newValue)
    }
}

/// Text shown when a setting needs the helper.
struct SettingsHelperNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.isConnected && !model.simulated {
            Label("The helper is not connected. Changes are saved by the helper, so they are unavailable until it runs.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}

/// Save and open panels for log export and settings import/export.
@MainActor
enum SettingsPanels {
    static func save(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func open(type: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension AppClosedBehavior {
    var settingsTitle: String {
        switch self {
        case .keepEnforced: return "Keep the limit enforced by the helper"
        case .restoreOnQuit: return "Restore normal charging when ChargeGuard quits"
        }
    }
}

extension MagSafeLEDMode {
    var settingsTitle: String {
        switch self {
        case .systemDefault: return "System default (not controlled)"
        case .followState: return "Show ChargeGuard's state"
        case .alwaysOff: return "Off while plugged in"
        }
    }
}

extension BackendPreference {
    var settingsTitle: String {
        switch self {
        case .automatic: return "Automatic (chosen by key probing)"
        case .legacyKeys: return "Charge keys (CHTE / CH0B+CH0C)"
        case .firmwareLimit: return "Firmware charge limit (bfD0/bfE0)"
        case .adapterCutoff: return "Adapter cutoff (CHIE / CH0J / CH0I)"
        }
    }
}
