import AppKit
import SwiftUI
import ChargeGuardCore

struct CalibrationSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var showTesting = false
    @State private var confirmCancel = false

    var body: some View {
        let config = model.config
        let editable = model.isConnected || model.simulated
        Form {
            SettingsHelperNote()

            Section {
                Text("""
                A. Charge to 100 % and hold for the hold time.
                B. Discharge to the floor while the Mac is kept awake.
                C. Charge to 100 % and hold again.
                D. Restore your charge limit (discharging to it when Automatic Discharge is on).
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                Text("Calibration keeps the Mac awake, needs the adapter for phases A and C, can be cancelled at any step and continues after a restart. Heat Protection still pauses charging while it runs.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Calibration Mode")
            }

            Section("Settings") {
                Stepper(value: model.settingsBinding(\.calibration.holdMinutes), in: CalibrationConfig.holdRange, step: 5) {
                    LabeledContent("Hold at 100 %", value: "\(config.calibration.holdMinutes) min")
                }
                .accessibilityLabel("Hold time at 100 percent")
                .accessibilityValue("\(config.calibration.holdMinutes) minutes")
                Stepper(value: model.settingsBinding(\.calibration.dischargeFloor), in: CalibrationConfig.floorRange) {
                    LabeledContent("Discharge down to", value: "\(config.calibration.dischargeFloor) %")
                }
                .accessibilityLabel("Calibration discharge floor")
                .accessibilityValue("\(config.calibration.dischargeFloor) percent")
                Text("The “After macOS Calibration” option needs macOS 26.4 or later and is not available in this version of ChargeGuard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!editable || model.control.calibration != nil)

            Section("Status") {
                if let cal = model.control.calibration {
                    SettingsCalibrationProgressRow(calibration: cal)
                    Button("Cancel calibration", role: .destructive) { confirmCancel = true }
                        .accessibilityHint("Stops calibration and restores your charge limit")
                } else {
                    Text("Not running").foregroundStyle(.secondary)
                    Button(config.calibration.fastMode ? "Start fast calibration (testing)" : "Start calibration") {
                        model.startCalibration(fast: config.calibration.fastMode)
                    }
                    .disabled(!editable || !config.controlEnabled)
                    if !config.controlEnabled {
                        Text("Turn charge control on first (General).").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if showTesting || config.calibration.fastMode {
                Section {
                    DisclosureGroup("Testing") {
                        Toggle("Fast calibration", isOn: model.settingsBinding(\.calibration.fastMode))
                        Text("Holds shortened to 2 minutes and the discharge target set to the current level minus 3 %, so the whole state machine can be checked on hardware in under 20 minutes. Not a real calibration.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!editable || model.control.calibration != nil)
                }
            }

            Section("History") {
                if model.calibrationHistory.isEmpty {
                    Text("No calibrations yet").foregroundStyle(.secondary)
                } else {
                    ForEach(model.calibrationHistory) { record in
                        SettingsCalibrationHistoryRow(record: record)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Hidden test setting: hold Option while opening this tab to reveal it.
            showTesting = NSEvent.modifierFlags.contains(.option)
        }
        .task { await model.loadHistory() }
        .confirmationDialog("Cancel calibration?", isPresented: $confirmCancel) {
            Button("Cancel calibration", role: .destructive) {
                model.cancelCalibration()
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await model.loadHistory()
                }
            }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("Your charge limit applies again right away.")
        }
    }
}

/// Current phase, step and hold countdown.
struct SettingsCalibrationProgressRow: View {
    @Environment(AppModel.self) private var model
    let calibration: CalibrationState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Phase \(calibration.phase.letter): \(calibration.phase.title)").font(.headline)
                Spacer()
                Text("Step \(calibration.phase.step) of \(CalibrationPhase.allCases.count)")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(calibration.phase.step - 1), total: Double(CalibrationPhase.allCases.count))
                .accessibilityLabel("Calibration progress")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let remaining = calibration.holdRemaining(now: model.settingsNow(context.date)) {
                    Text("Hold ends in \(Fmt.duration(remaining))").monospacedDigit()
                }
            }
            if calibration.phase == .dischargeToFloor, let target = calibration.dischargeTarget {
                Text("Discharging to \(target) %").foregroundStyle(.secondary)
            }
            if case .calibrating(_, let waiting)? = model.status?.chargeStatus, waiting {
                Label("Waiting for the power adapter", systemImage: "powerplug").foregroundStyle(.orange)
            }
            Text("Started \(Fmt.dateTime(calibration.startedAt))\(calibration.fast ? " · fast test mode" : "") · by \(calibration.origin)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsCalibrationHistoryRow: View {
    let record: CalibrationRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: record.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(record.outcome == .completed ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.dateTime(record.startedAt)) – \(Fmt.time(record.finishedAt))")
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [record.outcome == .completed ? "Completed" : "Cancelled in phase \(record.lastPhase.letter)"]
        if record.fast { parts.append("fast test") }
        if let start = record.startMaxCapacityMAh, let end = record.endMaxCapacityMAh {
            parts.append("capacity \(start) → \(end) mAh")
        }
        if let cycles = record.cycleCount { parts.append("\(cycles) cycles") }
        return parts.joined(separator: " · ")
    }
}
