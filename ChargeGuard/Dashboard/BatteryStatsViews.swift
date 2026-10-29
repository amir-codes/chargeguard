import SwiftUI
import ChargeGuardCore

/// Stats grid (feature 22) with the macOS and hardware percentages side by side (feature 19).
struct BatteryStatsGrid: View {
    let snapshot: BatterySnapshot?
    var minimumTileWidth: CGFloat = 150

    var body: some View {
        if let s = snapshot {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 8)], spacing: 8) {
                StatTile(title: "macOS percentage", value: Fmt.percent(s.percentage), systemImage: "battery.75percent")
                StatTile(title: "Hardware percentage", value: Fmt.percent(s.hardwarePercentage),
                         systemImage: "cpu", detail: "\(s.rawCurrentCapacityMAh) of \(s.rawMaxCapacityMAh) mAh")
                StatTile(title: "Cycle count", value: "\(s.cycleCount)", systemImage: "arrow.triangle.2.circlepath")
                StatTile(title: "Design capacity", value: Fmt.mAh(s.designCapacityMAh), systemImage: "ruler")
                StatTile(title: "Maximum capacity", value: Fmt.mAh(s.nominalChargeCapacityMAh ?? s.rawMaxCapacityMAh),
                         systemImage: "battery.100percent")
                StatTile(title: "Health", value: Fmt.percent(s.healthPercent, digits: 1), systemImage: "heart")
                StatTile(title: "Temperature", value: Fmt.celsius(s.temperatureC), systemImage: "thermometer.medium")
                StatTile(title: "Voltage", value: Fmt.millivolts(s.voltageMV), systemImage: "bolt")
                StatTile(title: "Amperage", value: Fmt.milliamps(s.amperageMA), systemImage: "waveform.path")
                StatTile(title: timeTitle(s), value: timeValue(s), systemImage: "clock")
                StatTile(title: "Adapter", value: s.adapter?.name ?? (s.adapterPresent ? "Connected" : "Not connected"),
                         systemImage: "powerplug", detail: s.adapter?.watts.map { "\($0) W rating" })
                StatTile(title: "Serial number", value: s.serial ?? "—", systemImage: "number")
            }
        } else {
            Text("No battery data yet.").foregroundStyle(.secondary)
        }
    }

    private func timeTitle(_ s: BatterySnapshot) -> String {
        if s.amperageMA > 0 { return "Time to full" }
        if s.amperageMA < 0 { return "Time to empty" }
        return "Time remaining"
    }

    private func timeValue(_ s: BatterySnapshot) -> String {
        if s.amperageMA > 0 { return Fmt.minutes(TimeEstimates.minutesToFull(s)) }
        if s.amperageMA < 0 { return Fmt.minutes(TimeEstimates.minutesToEmpty(s)) }
        return s.adapterPresent ? "Not charging" : "—"
    }
}

/// Past calibrations (calibration.jsonl from the helper).
struct CalibrationHistoryView: View {
    let records: [CalibrationRecord]

    var body: some View {
        if records.isEmpty {
            Text("No calibration has run yet.").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Started").bold()
                    Text("Result").bold()
                    Text("Mode").bold()
                    Text("Capacity before → after").bold()
                    Text("Duration").bold()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(records) { record in
                    GridRow {
                        Text(Fmt.dateTime(record.startedAt))
                        Text(outcome(record))
                            .foregroundStyle(record.outcome == .completed ? Color.green : Color.secondary)
                        Text(record.fast ? "Fast (test)" : "Full")
                        Text("\(Fmt.mAh(record.startMaxCapacityMAh)) → \(Fmt.mAh(record.endMaxCapacityMAh))")
                            .monospacedDigit()
                        Text(Fmt.duration(record.finishedAt.timeIntervalSince(record.startedAt)))
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func outcome(_ record: CalibrationRecord) -> String {
        switch record.outcome {
        case .completed: return "Completed"
        case .cancelled: return "Cancelled in phase \(record.lastPhase.letter)"
        }
    }
}

/// The helper's recent events (events.jsonl), newest first.
struct RecentEventsView: View {
    let events: [EventRecord]
    var limit: Int = 20

    var body: some View {
        if events.isEmpty {
            Text("No events yet.").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(events.suffix(limit).reversed())) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.dateTime(record.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(record.event.summary).font(.callout)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
