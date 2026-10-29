import SwiftUI
import ChargeGuardCore

/// Formatting helpers shared by every view.
enum Fmt {
    static func percent(_ value: Int?) -> String {
        value.map { "\($0) %" } ?? "—"
    }

    static func percent(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f %%", value)
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: abs(value) < 10 ? "%.1f W" : "%.0f W", value)
    }

    static func celsius(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f °C", value)
    }

    static func millivolts(_ value: Int?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f V", Double(value) / 1000)
    }

    static func milliamps(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value) mA"
    }

    static func mAh(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(value) mAh"
    }

    static func minutes(_ value: Int?) -> String {
        TimeEstimates.format(minutes: value)
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

extension StatusKind {
    /// Colour used by the coloured icon set and status accents.
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .onBattery: return .primary
        case .charging: return .orange
        case .limitReached: return .green
        case .sailing: return .teal
        case .discharging: return .blue
        case .heatPaused: return .red
        case .calibrating: return .purple
        case .topUp: return .yellow
        case .helperMissing: return .gray
        case .error: return .red
        case .conflict: return .pink
        }
    }

    /// SF Symbol shown next to the state line and in the menu bar overlay.
    var symbol: String {
        switch self {
        case .idle: return "pause.circle"
        case .onBattery: return "battery.75percent"
        case .charging: return "bolt.fill"
        case .limitReached: return "checkmark.circle.fill"
        case .sailing: return "sailboat.fill"
        case .discharging: return "arrow.down.circle.fill"
        case .heatPaused: return "thermometer.high"
        case .calibrating: return "gauge.with.dots.needle.33percent"
        case .topUp: return "arrow.up.to.line.circle.fill"
        case .helperMissing: return "questionmark.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .conflict: return "exclamationmark.2"
        }
    }

    var accessibilityName: String {
        switch self {
        case .idle: return "Charge control off"
        case .onBattery: return "On battery"
        case .charging: return "Charging"
        case .limitReached: return "Limit reached"
        case .sailing: return "Sailing"
        case .discharging: return "Discharging"
        case .heatPaused: return "Heat paused"
        case .calibrating: return "Calibrating"
        case .topUp: return "Topping up"
        case .helperMissing: return "Helper missing"
        case .error: return "Error"
        case .conflict: return "Another charging tool is running"
        }
    }
}

/// A small value tile (pop-up stats, dashboard grid).
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Rounded section background used by cards.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Blocking banner shown while another charging tool runs (section 6).
struct ConflictBanner: View {
    let tools: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Another charging tool is running").font(.headline).foregroundStyle(.white)
                Text("\(tools.joined(separator: ", ")). ChargeGuard will not change any charging setting until it is quit, because two tools writing the same keys fight each other.")
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.gradient, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Banner for helper problems (missing, needs approval, version mismatch, backend error).
struct HelperBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if model.installer.needsApproval {
                            Button("Open Login Items") { model.installer.openLoginItems() }
                        } else if model.connection != .connected {
                            Button("Set up helper…") { WindowOpener(openWindow: openWindow).onboarding() }
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var message: String? {
        if model.simulated { return nil }
        switch model.connection {
        case .missing:
            return model.installer.needsApproval
                ? "Approve the ChargeGuard helper in System Settings > General > Login Items."
                : "The ChargeGuard helper is not running, so the limit is not enforced."
        case .versionMismatch(let helper):
            return "The helper speaks protocol \(helper), this app \(HelperProtocol.version). Reinstall the helper from Settings > Advanced."
        case .connecting:
            return nil
        case .connected:
            if let error = model.status?.backendError { return error }
            if model.status?.config.controlEnabled == false { return "Charge control is off. Turn it on in Settings > General." }
            return nil
        }
    }
}
