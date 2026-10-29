import AppKit
import SwiftUI
import ChargeGuardCore

/// The MenuBarExtra window (section 9): percentages, state line, banners, the user's widgets in
/// their chosen order, and the bottom bar.
struct PopupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopupHeader()
            if !model.conflicts.isEmpty {
                ConflictBanner(tools: model.conflicts)
            }
            HelperBanner()
            ForEach(model.preferences.widgets.filter(\.visible)) { entry in
                widget(entry.widget)
            }
            KeepAwakeRow()
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { model.lastError = nil }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Dismisses the error")
            }
            Divider()
            PopupBottomBar()
        }
        .padding(14)
        .frame(width: 340)
        .disabled(model.isPassive)
        .overlay(alignment: .top) {
            if model.isPassive {
                Text("Passive: ChargeGuard is active in another user session")
                    .font(.caption)
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func widget(_ widget: PopupWidget) -> some View {
        switch widget {
        case .limitSlider:
            LimitSliderView()
        case .toggles:
            ToggleRow()
        case .calibrationCard:
            if model.control.calibration != nil { CalibrationCard() }
        case .stats:
            StatTilesRow()
        case .powerFlowMini:
            PowerFlowMiniView()
        case .energyApps:
            EnergyAppsList(limit: 5, compact: true)
        }
    }
}

// MARK: - Header

struct PopupHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snapshot = model.snapshot
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.percent(snapshot?.percentage))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel(percentAccessibilityLabel)
                if model.preferences.showHardwarePercentage, let snapshot {
                    Text("Hardware \(Fmt.percent(snapshot.hardwarePercentage))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(format: "Hardware percentage %.1f", snapshot.hardwarePercentage))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let adapter = snapshot?.adapter, snapshot?.adapterPresent == true {
                    Label(adapterTitle(adapter), systemImage: "powerplug.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(adapter.name ?? "Power adapter")
                }
                if model.simulated {
                    Text("SIMULATION")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.2), in: Capsule())
                }
            }
        }
        HStack(spacing: 6) {
            Image(systemName: model.statusKind.symbol)
                .foregroundStyle(model.statusKind.color)
            Text(model.stateLine)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func adapterTitle(_ adapter: AdapterInfo) -> String {
        guard let watts = adapter.watts else { return "Adapter" }
        return "\(watts) W"
    }

    private var percentAccessibilityLabel: String {
        guard let snapshot = model.snapshot else { return "Battery percentage unavailable" }
        return "Battery \(snapshot.percentage) percent"
    }
}

// MARK: - Limit slider (feature 1)

struct LimitSliderView: View {
    @Environment(AppModel.self) private var model
    @State private var value: Double = 80
    @State private var editing = false

    var body: some View {
        let step: Double = model.config.fineLimitSteps ? 1 : 5
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Charge limit")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value)) %")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 20...100, step: step, onEditingChanged: { isEditing in
                editing = isEditing
                if !isEditing { model.setLimit(Int(value)) }
            })
            .accessibilityLabel("Charge limit")
            .accessibilityValue("\(Int(value)) percent")
            if Int(value) >= 100 {
                Text("100 % turns the limit off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!model.isConnected)
        .onAppear { value = Double(model.config.chargeLimit) }
        .onChange(of: model.config.chargeLimit) { _, newValue in
            if !editing { value = Double(newValue) }
        }
    }
}

// MARK: - Toggle row (features 2, 5, 6, 7)

struct ToggleRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let control = model.control
        let config = model.config
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                pill("Discharge", systemImage: "arrow.down.circle", isOn: control.manualDischarge || control.dischargeActive,
                     enabled: model.canDischarge && config.chargeLimit < 100 && control.calibration == nil,
                     help: "Run from the battery until it reaches the limit, then hold there") { model.setDischarge($0) }
                pill("Heat", systemImage: "thermometer.medium", isOn: config.heatProtection.enabled, enabled: model.isConnected,
                     help: "Pause charging at \(Int(config.heatProtection.maxTemperatureC)) °C") { model.setHeatProtection($0) }
                pill("Sailing", systemImage: "sailboat", isOn: config.sailing.enabled, enabled: model.isConnected,
                     help: "Resume charging only below \(config.chargeLimit - config.sailing.range) %") { model.setSailing($0) }
                pill("Top Up", systemImage: "arrow.up.to.line", isOn: control.topUp != nil,
                     enabled: model.isConnected && control.calibration == nil,
                     help: "Charge to 100 % once, then return to the limit") { model.setTopUp($0) }
            }
            if control.manualDischarge || control.dischargeActive {
                Text("Discharge only happens while the Mac is awake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if control.topUp != nil, let minutes = model.status?.topUpMinutesRemaining {
                Text("Full in about \(Fmt.minutes(minutes)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pill(_ title: String, systemImage: String, isOn: Bool, enabled: Bool, help: String,
                      action: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { action($0) })) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Calibration card (feature 8)

struct CalibrationCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let calibration = model.control.calibration {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Calibration", systemImage: "gauge.with.dots.needle.33percent")
                            .font(.subheadline.weight(.semibold))
                        if calibration.fast {
                            Text("FAST TEST").font(.caption2.weight(.bold)).foregroundStyle(.purple)
                        }
                        Spacer()
                        Button("Cancel", role: .destructive) { model.cancelCalibration() }
                            .controlSize(.small)
                            .accessibilityLabel("Cancel calibration")
                    }
                    Text("Phase \(calibration.phase.letter): \(calibration.phase.title)")
                        .font(.callout)
                    ProgressView(value: Double(calibration.phase.step), total: Double(CalibrationPhase.allCases.count))
                        .accessibilityLabel("Calibration step \(calibration.phase.step) of \(CalibrationPhase.allCases.count)")
                    if let remaining = calibration.holdRemaining(now: context.date) {
                        Text("Holding: \(Fmt.duration(remaining)) left").font(.caption).foregroundStyle(.secondary)
                    } else if calibration.phase == .dischargeToFloor, let target = calibration.dischargeTarget {
                        Text("Discharging to \(target) %; the Mac is kept awake.").font(.caption).foregroundStyle(.secondary)
                    }
                    if case .calibrating(_, true) = model.status?.chargeStatus {
                        Text("Plug in the adapter to continue.").font(.caption).foregroundStyle(.orange)
                    }
                }
                .card()
            }
        }
    }
}

// MARK: - Stat tiles (features 19, 22)

struct StatTilesRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.snapshot
        HStack(spacing: 6) {
            StatTile(title: "Health", value: Fmt.percent(s?.healthPercent, digits: 0), systemImage: "heart",
                     detail: s.map { "\($0.cycleCount) cycles" })
            StatTile(title: "Temp", value: Fmt.celsius(s?.temperatureC), systemImage: "thermometer.medium")
            if let s, s.amperageMA < 0 {
                StatTile(title: "To empty", value: Fmt.minutes(TimeEstimates.minutesToEmpty(s)), systemImage: "hourglass")
            } else {
                StatTile(title: "To full", value: Fmt.minutes(s.flatMap(TimeEstimates.minutesToFull)), systemImage: "hourglass")
            }
        }
    }
}

// MARK: - Keep awake (feature 11)

struct KeepAwakeRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let keepAwake = model.control.keepAwake {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(.brown)
                    if let remaining = keepAwake.remaining(now: context.date) {
                        Text("Keeping awake: \(Fmt.duration(remaining)) left")
                    } else if keepAwake.untilChargeLimit {
                        Text("Keeping awake until the charge limit")
                    } else {
                        Text("Keeping awake indefinitely")
                    }
                    Spacer()
                    Button("Stop") { model.perform(.cancelKeepAwake) }
                        .controlSize(.small)
                        .accessibilityLabel("Stop keeping the Mac awake")
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Bottom bar

struct PopupBottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 8) {
            Button {
                WindowOpener(openWindow: openWindow).dashboard()
            } label: {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
            }
            .keyboardShortcut("d")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            .keyboardShortcut(",")

            Spacer()

            Menu {
                Section("Keep awake") {
                    ForEach(KeepAwakeRequest.presets, id: \.seconds) { preset in
                        Button(preset.title) { model.keepAwake(seconds: preset.seconds) }
                    }
                    Button("Indefinitely") { model.keepAwake(seconds: nil) }
                    Button("Until the charge limit") { model.keepAwake(seconds: nil, untilLimit: true) }
                    Divider()
                    ForEach(KeepAwakeRequest.presets, id: \.seconds) { preset in
                        Button("\(preset.title), display on too") { model.keepAwake(seconds: preset.seconds, display: true) }
                    }
                    if model.control.keepAwake != nil {
                        Button("Stop keeping awake") { model.perform(.cancelKeepAwake) }
                    }
                }
                Section {
                    Button("Restore normal charging") { model.restoreNormalCharging() }
                    if !model.controlEnabled && model.isConnected && model.preferences.hasCompletedOnboarding {
                        Button("Turn charge control on") { model.perform(.setControlEnabled(true)) }
                    }
                }
                Section {
                    Button("Quit ChargeGuard") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More: keep awake, restore normal charging, quit")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit ChargeGuard")
            .accessibilityLabel("Quit ChargeGuard")
        }
        .controlSize(.small)
    }
}
