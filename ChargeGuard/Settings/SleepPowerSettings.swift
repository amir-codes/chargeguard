import SwiftUI
import ChargeGuardCore

struct SleepPowerSettingsTab: View {
    @Environment(AppModel.self) private var model
    @AppStorage("keepAwakePreventDisplaySleep") private var keepDisplayOn = false

    var body: some View {
        let editable = model.isConnected || model.simulated
        Form {
            SettingsHelperNote()

            Section {
                Toggle("Disable Sleep until Charge Limit", isOn: model.settingsBinding(\.disableSleepUntilLimit))
            } footer: {
                Text("While plugged in and charging below the limit, the Mac does not go to sleep on its own, so the limit can be enforced. Released when the limit is reached.")
            }
            .disabled(!editable)

            Section {
                if let keepAwake = model.control.keepAwake {
                    SettingsKeepAwakeStatusRow(keepAwake: keepAwake)
                    Button("Stop keeping awake") { model.perform(.cancelKeepAwake) }
                        .accessibilityHint("Lets the Mac sleep normally again")
                } else {
                    Text("Not active").foregroundStyle(.secondary)
                }
                Toggle("Also keep the display on", isOn: $keepDisplayOn)
                HStack {
                    ForEach(KeepAwakeRequest.presets) { preset in
                        Button(preset.title) {
                            model.keepAwake(seconds: preset.seconds, display: keepDisplayOn)
                        }
                        .accessibilityLabel("Keep awake for \(preset.title)")
                    }
                }
                HStack {
                    Button("Indefinitely") {
                        model.keepAwake(seconds: nil, display: keepDisplayOn)
                    }
                    .accessibilityLabel("Keep awake indefinitely")
                    Button("Until the charge limit") {
                        model.keepAwake(seconds: nil, untilLimit: true, display: keepDisplayOn)
                    }
                    .accessibilityLabel("Keep awake until the charge limit is reached")
                }
            } header: {
                Text("Sleep Control")
            } footer: {
                Text("Keep-awake runs in the helper and survives closing ChargeGuard.")
            }
            .disabled(!editable)

            Section {
                Picker("Low Power Mode", selection: Binding(
                    get: { model.config.lowPowerMode },
                    set: { model.perform(.setLowPowerMode($0)) }
                )) {
                    ForEach(LowPowerModePolicy.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                LabeledContent("Current state (pmset)", value: onOff(model.status?.lowPowerModeActive))
                LabeledContent("Current state (this Mac)", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
            } header: {
                Text("Low Power Mode")
            } footer: {
                Text("The helper applies this with pmset on every power-source change. “Not managed” leaves Low Power Mode to you and macOS.")
            }
            .disabled(!editable)
        }
        .formStyle(.grouped)
    }

    private func onOff(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "On" : "Off"
    }
}

struct SettingsKeepAwakeStatusRow: View {
    @Environment(AppModel.self) private var model
    let keepAwake: KeepAwakeState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(title(now: model.settingsNow(context.date)))
                    .monospacedDigit()
                if keepAwake.preventDisplaySleep {
                    Text("Display kept on").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func title(now: Date) -> String {
        if let remaining = keepAwake.remaining(now: now) {
            return "Keeping the Mac awake for \(Fmt.duration(remaining))"
        }
        if keepAwake.untilChargeLimit {
            return "Keeping the Mac awake until the charge limit"
        }
        return "Keeping the Mac awake indefinitely"
    }
}
