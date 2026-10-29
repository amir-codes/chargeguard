import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ChargeGuardCore

/// Dashboard window (section 9): Power Flow, Apps Using Energy, Stats, calibration history,
/// recent events and logs.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var logMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !model.conflicts.isEmpty { ConflictBanner(tools: model.conflicts) }
                HelperBanner()

                section("Power Flow", systemImage: "bolt.horizontal.fill") {
                    PowerFlowPanel()
                }
                section("Apps Using Significant Energy", systemImage: "flame") {
                    EnergyAppsList(limit: 10, compact: false)
                }
                section("Battery", systemImage: "battery.100percent") {
                    BatteryStatsGrid(snapshot: model.snapshot)
                }
                section("Calibration History", systemImage: "gauge.with.dots.needle.33percent") {
                    CalibrationHistoryView(records: model.calibrationHistory)
                }
                section("Recent Events", systemImage: "list.bullet.rectangle") {
                    RecentEventsView(events: model.recentEvents)
                }
                section("Logs", systemImage: "doc.text.magnifyingglass") {
                    logsPanel
                }
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { model.beginLiveRefresh() }
        .onDisappear { model.endLiveRefresh() }
        .task { await model.loadHistory() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: model.statusKind.symbol)
                .font(.system(size: 34))
                .foregroundStyle(model.statusKind.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.percent(model.snapshot?.percentage))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let hardware = model.snapshot?.hardwarePercentage {
                        Text("hardware \(Fmt.percent(hardware))")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(model.stateLine).font(.headline)
                if let status = model.status {
                    Text("Limit \(status.effectiveLimit) % · \(status.backend.displayName)\(status.simulated ? " · Simulation" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task {
                    await model.refreshStatus()
                    await model.loadHistory()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh the dashboard")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .card()
    }

    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ChargeGuard logs every SMC write with its key, value, reason and battery snapshot to the unified log (subsystem com.amir.chargeguard). The helper also keeps events.jsonl, writes.jsonl and calibration.jsonl in /Library/Application Support/ChargeGuard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Export Logs…") { exportLogs() }
                    .accessibilityLabel("Export logs to a text file")
                Button("Open Data Folder") { openDataFolder() }
                    .accessibilityLabel("Open the ChargeGuard data folder in Finder")
                Button("Open Console") { openConsole() }
                    .accessibilityLabel("Open the Console app")
            }
            if let logMessage {
                Text(logMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func exportLogs() {
        let panel = NSSavePanel()
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "ChargeGuard-log-\(stamp).txt"
        panel.allowedContentTypes = [.plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        logMessage = "Exporting…"
        Task {
            do {
                try await model.exportLogs(to: url)
                logMessage = "Saved to \(url.path)"
            } catch {
                logMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func openDataFolder() {
        let url = URL(fileURLWithPath: HelperProtocol.stateDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            logMessage = "The data folder does not exist yet (the helper has not run)."
        }
    }

    private func openConsole() {
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.openApplication(at: console, configuration: NSWorkspace.OpenConfiguration())
        logMessage = "In Console, search for subsystem:com.amir.chargeguard."
    }
}
