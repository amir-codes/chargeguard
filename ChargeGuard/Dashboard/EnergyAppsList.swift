import AppKit
import SwiftUI
import ChargeGuardCore

/// Apps Using Significant Energy (feature 21). Preferred source is powermetrics run by the helper;
/// the fallback is proc_pid_rusage energy counters, then CPU percent. The method in use is labelled.
/// Refreshes every 10 seconds while visible.
struct EnergyAppsList: View {
    @Environment(AppModel.self) private var model
    var limit: Int = 8
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            header
            if let sample = model.energy {
                let rows = sample.top(limit).filter { $0.energy > 0 }
                if rows.isEmpty {
                    Text(sample.method == .unavailable ? "Energy data is not available." : "No app is using significant energy.")
                        .font(compact ? .caption : .callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { process in
                        EnergyRow(process: process, method: sample.method, compact: compact)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshEnergy()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            if compact {
                Text("Apps Using Significant Energy").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let sample = model.energy {
                Text(sample.method.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Measured with \(sample.method.label)")
            }
            if !compact {
                Button {
                    Task { await model.refreshEnergy() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .accessibilityLabel("Refresh the energy list")
            }
        }
    }
}

private struct EnergyRow: View {
    @Environment(AppModel.self) private var model
    let process: ProcessEnergy
    let method: EnergyMethod
    let compact: Bool

    var body: some View {
        let app = NSRunningApplication(processIdentifier: process.pid)
        HStack(spacing: 8) {
            icon(app)
                .frame(width: compact ? 16 : 22, height: compact ? 16 : 22)
            Text(app?.localizedName ?? process.name)
                .font(compact ? .caption : .body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(valueText)
                .font(compact ? Font.caption.monospacedDigit() : Font.body.monospacedDigit())
                .foregroundStyle(.secondary)
            if canQuit(app) {
                Button("Quit") { model.quitApp(pid: process.pid) }
                    .controlSize(.small)
                    .accessibilityLabel("Quit \(app?.localizedName ?? process.name)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func icon(_ app: NSRunningApplication?) -> some View {
        if let image = app?.icon {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
    }

    /// Only regular GUI apps with a bundle can be asked to quit, never ChargeGuard itself.
    private func canQuit(_ app: NSRunningApplication?) -> Bool {
        guard let app, app.bundleURL != nil, app.activationPolicy == .regular else { return false }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }
        if let id = app.bundleIdentifier, id == Bundle.main.bundleIdentifier { return false }
        return true
    }

    private var valueText: String {
        switch method {
        case .powermetrics: return String(format: "%.1f", process.energy)
        case .rusageEnergy: return String(format: "%.2f W", process.energy)
        case .cpuPercent: return String(format: "%.0f %% CPU", process.energy)
        case .unavailable: return "—"
        }
    }
}
