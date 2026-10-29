import SwiftUI
import ChargeGuardCore

/// The status item: state icon plus optional percentage and limit (features 1, 17, 18).
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let prefs = model.preferences
        let percentage = model.snapshot?.percentage
        HStack(spacing: 3) {
            if let image = StatusIconRenderer.image(kind: model.statusKind, percentage: percentage, style: prefs.iconStyle,
                                                    colored: prefs.colorByState,
                                                    calibrationLetter: model.control.calibration?.phase.letter) {
                Image(nsImage: image)
            }
            if prefs.showPercentage || prefs.iconStyle == .percentageOnly {
                Text(labelText(percentage: percentage, showLimit: prefs.showLimitInMenuBar))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(percentage: percentage))
        .onChange(of: model.showOnboarding) { _, show in
            if show {
                model.showOnboarding = false
                WindowOpener(openWindow: openWindow).onboarding()
            }
        }
    }

    private func labelText(percentage: Int?, showLimit: Bool) -> String {
        let pct = percentage.map { "\($0)%" } ?? "–"
        guard showLimit, model.isConnected, model.controlEnabled else { return pct }
        return "\(pct) · \(model.status?.effectiveLimit ?? model.config.chargeLimit)"
    }

    private func accessibilityText(percentage: Int?) -> String {
        var parts = ["ChargeGuard", model.statusKind.accessibilityName]
        if let percentage { parts.append("battery \(percentage) percent") }
        if model.isConnected { parts.append("limit \(model.config.chargeLimit) percent") }
        return parts.joined(separator: ", ")
    }
}

/// Shown instead of the pop-up on Intel Macs (non-goal: Apple silicon only).
struct UnsupportedMacView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This Mac is not supported", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("ChargeGuard needs a Mac with Apple silicon. Intel Macs use different charging keys, and ChargeGuard never writes keys it has not been built and tested for.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing has been changed on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Quit ChargeGuard") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
