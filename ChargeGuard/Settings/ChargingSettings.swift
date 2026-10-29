import SwiftUI
import ChargeGuardCore

struct ChargingSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let config = model.config
        let editable = model.isConnected || model.simulated
        Form {
            SettingsHelperNote()

            Section {
                SettingsSlider(title: "Charge limit",
                               value: Double(config.chargeLimit),
                               range: Double(PolicyConfig.limitRange.lowerBound)...Double(PolicyConfig.limitRange.upperBound),
                               step: config.fineLimitSteps ? 1 : 5,
                               format: { "\(Int($0.rounded())) %" },
                               commit: { model.setLimit(Int($0.rounded())) })
                Toggle("1 % steps on the limit slider", isOn: model.settingsBinding(\.fineLimitSteps))
                Stepper(value: model.settingsBinding(\.resumeHysteresis), in: PolicyConfig.hysteresisRange) {
                    LabeledContent("Resume charging below the limit by", value: "\(config.resumeHysteresis) %")
                }
                .accessibilityLabel("Resume hysteresis")
                .accessibilityValue("\(config.resumeHysteresis) percent")
                Toggle("Use the hardware battery percentage", isOn: model.settingsBinding(\.useHardwarePercentage))
            } header: {
                Text("Charge Limiter")
            } footer: {
                Text(limitFooter(config))
            }
            .disabled(!editable)

            Section {
                Toggle("Automatic Discharge", isOn: model.settingsBinding(\.automaticDischarge))
                Text("When the battery is above the limit while plugged in (for example after you lower the limit), ChargeGuard runs the Mac from the battery until it reaches the limit.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Discharge in Clamshell Mode", isOn: model.settingsBinding(\.dischargeInClamshell))
                Text("Keeps discharging with the lid closed and an external display attached by holding a PreventSystemSleep assertion. Without it, discharge pauses while the lid is closed.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Force the Mac awake during clamshell discharge", isOn: model.settingsBinding(\.clamshellForceAwake))
                    .disabled(!config.dischargeInClamshell)
                Label("Advanced. Sets “pmset disablesleep 1” while discharging with an external display, for Macs that still sleep with the lid closed. The Mac then stays awake with the lid closed until discharge ends; do not put it in a bag. The previous value is restored afterwards.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(config.clamshellForceAwake ? Color.orange : Color.secondary)
            } header: {
                Text("Discharge")
            } footer: {
                Text("Discharge only happens while the Mac is awake. Before sleep it pauses, and it resumes on wake.")
            }
            .disabled(!editable)

            Section {
                Toggle("Stop Charging when Sleeping", isOn: model.settingsBinding(\.stopChargingWhenSleeping))
                Text("Nothing can enforce the limit during sleep: if the Mac goes to sleep while charging below the limit, it could charge far past it. With this on, ChargeGuard blocks charging right before sleep, so the level stays where it is, and re-evaluates on wake.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Sleep")
            }
            .disabled(!editable)

            Section {
                Picker("MagSafe LED", selection: model.settingsBinding(\.magSafeLED)) {
                    ForEach(MagSafeLEDMode.allCases, id: \.self) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }
                if model.status?.backendCapabilities.canControlLED == false {
                    Text("This Mac has no controllable MagSafe LED key (ACLC).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Control MagSafe LED")
            } footer: {
                Text("Green when the limit is reached or charging is blocked, orange while charging, off while discharging. Turning this off returns the LED to the system default.")
            }
            .disabled(!editable)

            if let limitations = model.status?.backendLimitations, !limitations.isEmpty {
                Section("About this Mac's charge control") {
                    ForEach(limitations, id: \.self) { note in
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func limitFooter(_ config: PolicyConfig) -> String {
        if config.chargeLimit >= 100 {
            return "At 100 % ChargeGuard does not limit charging."
        }
        let resume = config.sailing.enabled ? config.chargeLimit - config.sailing.range : config.chargeLimit - config.resumeHysteresis
        let how = config.sailing.enabled ? "Sailing is on" : "Resume hysteresis"
        return "Charging stops at \(config.chargeLimit) % while the adapter is connected and resumes at about \(max(0, resume)) % (\(how)). The limit takes effect within one control-loop tick."
    }
}

struct HeatSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let heat = model.config.heatProtection
        let editable = model.isConnected || model.simulated
        Form {
            SettingsHelperNote()

            Section {
                Toggle("Heat Protection", isOn: Binding(
                    get: { model.config.heatProtection.enabled },
                    set: { model.setHeatProtection($0) }
                ))
                SettingsSlider(title: "Max temperature",
                               value: heat.maxTemperatureC,
                               range: HeatProtectionConfig.temperatureRange,
                               step: 0.5,
                               format: { String(format: "%.1f °C", $0) },
                               commit: { value in model.updateConfig { $0.heatProtection.maxTemperatureC = value } })
                Stepper(value: model.settingsBinding(\.heatProtection.resumeDeltaC), in: 0.5...10, step: 0.5) {
                    LabeledContent("Resume when cooler by", value: String(format: "%.1f °C", heat.resumeDeltaC))
                }
                .accessibilityLabel("Resume temperature difference")
                .accessibilityValue(String(format: "%.1f degrees Celsius", heat.resumeDeltaC))
            } header: {
                Text("Heat Protection")
            } footer: {
                Text(String(format: "Charging pauses at or above %.1f °C and resumes at %.1f °C. Heat Protection overrides everything else, including calibration and Top Up.",
                            heat.maxTemperatureC, heat.maxTemperatureC - heat.resumeDeltaC))
            }
            .disabled(!editable)

            Section("Now") {
                LabeledContent("Battery temperature", value: Fmt.celsius(model.snapshot?.temperatureC))
                LabeledContent("State", value: model.control.heatPaused ? "Charging paused (too warm)" : "Normal")
            }
        }
        .formStyle(.grouped)
    }
}

struct SailingSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let config = model.config
        let editable = model.isConnected || model.simulated
        Form {
            SettingsHelperNote()

            Section {
                Toggle("Sailing Mode", isOn: Binding(
                    get: { model.config.sailing.enabled },
                    set: { model.setSailing($0) }
                ))
                Stepper(value: model.settingsBinding(\.sailing.range), in: SailingConfig.rangeLimits) {
                    LabeledContent("Sailing range", value: "\(config.sailing.range) %")
                }
                .accessibilityLabel("Sailing range")
                .accessibilityValue("\(config.sailing.range) percent")
            } header: {
                Text("Sailing Mode")
            } footer: {
                Text("After reaching the limit, ChargeGuard does not resume charging until the battery falls by the sailing range. The Mac runs from the adapter in the meantime, so the battery rests instead of topping up in small bursts. Sailing replaces the resume hysteresis while it is on.")
            }
            .disabled(!editable)

            Section("Example") {
                let limit = config.chargeLimit
                let resume = max(0, limit - config.sailing.range)
                Text(limit >= 100
                     ? "With the limit at 100 % there is nothing to sail from."
                     : "At your \(limit) % limit, charging resumes at \(resume) %.")
            }
        }
        .formStyle(.grouped)
    }
}
