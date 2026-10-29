import SwiftUI
import ChargeGuardCore

/// Text for schedule rules.
enum SettingsScheduleFormat {
    /// Monday-first display order of Calendar weekdays (1 = Sunday ... 7 = Saturday).
    static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    static func weekdaySymbol(_ day: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard day >= 1, day <= symbols.count else { return "?" }
        return symbols[day - 1]
    }

    static func days(_ weekdays: Set<Int>) -> String {
        if weekdays.isEmpty || weekdays.count == 7 { return "Every day" }
        if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        return displayOrder.filter { weekdays.contains($0) }.map(weekdaySymbol).joined(separator: ", ")
    }

    static func time(_ rule: ScheduleRule) -> String {
        String(format: "%02ld:%02ld", rule.hour, rule.minute)
    }

    static func nextRun(_ rule: ScheduleRule, now: Date) -> String {
        guard let date = ScheduleEngine.nextRun(of: rule, after: now, calendar: Calendar.current) else {
            return rule.enabled ? "—" : "Off"
        }
        return Fmt.dateTime(date)
    }
}

/// What the editor offers; maps to ScheduleAction.
enum ScheduleEditorActionKind: String, CaseIterable, Identifiable {
    case startCalibration, topUp, setLimit, enableDischarge, disableDischarge, setLowPowerMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startCalibration: return "Start calibration"
        case .topUp: return "Top up to 100 %"
        case .setLimit: return "Set charge limit"
        case .enableDischarge: return "Start discharge"
        case .disableDischarge: return "Stop discharge"
        case .setLowPowerMode: return "Set Low Power Mode"
        }
    }

    init(_ action: ScheduleAction) {
        switch action {
        case .startCalibration: self = .startCalibration
        case .topUp: self = .topUp
        case .setLimit: self = .setLimit
        case .enableDischarge: self = .enableDischarge
        case .disableDischarge: self = .disableDischarge
        case .setLowPowerMode: self = .setLowPowerMode
        }
    }

    func action(limit: Int, lowPowerMode: LowPowerModePolicy) -> ScheduleAction {
        switch self {
        case .startCalibration: return .startCalibration
        case .topUp: return .topUp
        case .setLimit: return .setLimit(limit)
        case .enableDischarge: return .enableDischarge
        case .disableDischarge: return .disableDischarge
        case .setLowPowerMode: return .setLowPowerMode(lowPowerMode)
        }
    }
}

struct ScheduleEditTarget: Identifiable {
    let id = UUID()
    var rule: ScheduleRule
    var isNew: Bool
}

struct ScheduleSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var selection: ScheduleRule.ID?
    @State private var editing: ScheduleEditTarget?

    private var rules: [ScheduleRule] { model.status?.schedule ?? [] }

    var body: some View {
        let editable = model.isConnected || model.simulated
        VStack(alignment: .leading, spacing: 10) {
            SettingsHelperNote()
            Text("Rules run in the helper, even while ChargeGuard is closed. A run missed by less than 2 hours (Mac asleep or off) runs on wake or at boot.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                scheduleTable(now: context.date)
            }

            HStack {
                Button {
                    editing = ScheduleEditTarget(rule: Self.newRule(), isNew: true)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityLabel("Add schedule rule")
                Button {
                    if let rule = selectedRule { editing = ScheduleEditTarget(rule: rule, isNew: false) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selectedRule == nil)
                .accessibilityLabel("Edit selected rule")
                Button(role: .destructive) {
                    if let id = selection { delete([id]) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedRule == nil)
                .accessibilityLabel("Delete selected rule")
                Spacer()
                if let next = model.status?.nextScheduledRun {
                    Text("Next: \(next.summary), \(Fmt.dateTime(next.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!editable)
        }
        .padding(20)
        .sheet(item: $editing) { target in
            ScheduleRuleEditor(rule: target.rule, isNew: target.isNew) { saved in
                save(saved)
            }
        }
    }

    private func scheduleTable(now: Date) -> some View {
        Table(rules, selection: $selection) {
            TableColumn("On") { rule in
                Toggle("Enabled", isOn: Binding(
                    get: { rule.enabled },
                    set: { setEnabled(rule.id, $0) }
                ))
                .labelsHidden()
                .disabled(!(model.isConnected || model.simulated))
                .accessibilityLabel("Rule enabled")
            }
            .width(34)
            TableColumn("Days") { rule in
                Text(SettingsScheduleFormat.days(rule.weekdays))
            }
            TableColumn("Time") { rule in
                Text(SettingsScheduleFormat.time(rule)).monospacedDigit()
            }
            .width(52)
            TableColumn("Action") { rule in
                Text(rule.action.summary)
            }
            TableColumn("Repeat") { rule in
                Text(rule.repeats == .weekly ? "Weekly" : "Once")
            }
            .width(60)
            TableColumn("Next run") { rule in
                Text(SettingsScheduleFormat.nextRun(rule, now: now))
            }
        }
        .contextMenu(forSelectionType: ScheduleRule.ID.self) { ids in
            if let id = ids.first, let rule = rules.first(where: { $0.id == id }) {
                Button("Edit…") { editing = ScheduleEditTarget(rule: rule, isNew: false) }
            }
            if !ids.isEmpty {
                Button("Delete", role: .destructive) { delete(ids) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let rule = rules.first(where: { $0.id == id }) {
                editing = ScheduleEditTarget(rule: rule, isNew: false)
            }
        }
        // Keyboard: the Delete key removes the selected rule, like the Delete button.
        .onDeleteCommand {
            guard model.isConnected || model.simulated, let id = selection else { return }
            delete([id])
        }
        .frame(minHeight: 240)
        .accessibilityLabel("Schedule rules")
    }

    private var selectedRule: ScheduleRule? {
        guard let selection else { return nil }
        return rules.first { $0.id == selection }
    }

    static func newRule() -> ScheduleRule {
        ScheduleRule(weekdays: [], hour: 7, minute: 0, action: .topUp, repeats: .weekly, createdAt: Date())
    }

    private func save(_ rule: ScheduleRule) {
        var updated = rules
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        model.setSchedule(updated)
    }

    private func setEnabled(_ id: ScheduleRule.ID, _ enabled: Bool) {
        var updated = rules
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].enabled = enabled
        model.setSchedule(updated)
    }

    private func delete(_ ids: Set<ScheduleRule.ID>) {
        model.setSchedule(rules.filter { !ids.contains($0.id) })
        if let selection, ids.contains(selection) { self.selection = nil }
    }
}

/// Add/edit sheet for one rule.
struct ScheduleRuleEditor: View {
    let original: ScheduleRule
    let isNew: Bool
    let onSave: (ScheduleRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var weekdays: Set<Int>
    @State private var time: Date
    @State private var kind: ScheduleEditorActionKind
    @State private var limit: Int
    @State private var lowPowerMode: LowPowerModePolicy
    @State private var repeats: ScheduleRepeat

    init(rule: ScheduleRule, isNew: Bool, onSave: @escaping (ScheduleRule) -> Void) {
        self.original = rule
        self.isNew = isNew
        self.onSave = onSave
        _enabled = State(initialValue: rule.enabled)
        _weekdays = State(initialValue: rule.weekdays)
        _time = State(initialValue: Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date())
        _kind = State(initialValue: ScheduleEditorActionKind(rule.action))
        if case .setLimit(let value) = rule.action {
            _limit = State(initialValue: value)
        } else {
            _limit = State(initialValue: 80)
        }
        if case .setLowPowerMode(let mode) = rule.action {
            _lowPowerMode = State(initialValue: mode)
        } else {
            _lowPowerMode = State(initialValue: .onlyOnBattery)
        }
        _repeats = State(initialValue: rule.repeats)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Toggle("Enabled", isOn: $enabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Days")
                        HStack(spacing: 4) {
                            ForEach(SettingsScheduleFormat.displayOrder, id: \.self) { day in
                                Toggle(SettingsScheduleFormat.weekdaySymbol(day), isOn: Binding(
                                    get: { weekdays.contains(day) },
                                    set: { on in
                                        if on { weekdays.insert(day) } else { weekdays.remove(day) }
                                    }
                                ))
                                .toggleStyle(.button)
                                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                            }
                        }
                        Text(weekdays.isEmpty ? "No day selected: runs every day." : SettingsScheduleFormat.days(weekdays))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Repeat", selection: $repeats) {
                        Text("Weekly").tag(ScheduleRepeat.weekly)
                        Text("Once").tag(ScheduleRepeat.once)
                    }
                }
                Section("Action") {
                    Picker("Action", selection: $kind) {
                        ForEach(ScheduleEditorActionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if kind == .setLimit {
                        Stepper(value: $limit, in: PolicyConfig.limitRange) {
                            LabeledContent("Limit", value: "\(limit) %")
                        }
                        .accessibilityLabel("Charge limit for this rule")
                    }
                    if kind == .setLowPowerMode {
                        Picker("Low Power Mode", selection: $lowPowerMode) {
                            ForEach(LowPowerModePolicy.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    onSave(makeRule())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 500)
    }

    private func makeRule() -> ScheduleRule {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var rule = original
        rule.enabled = enabled
        rule.weekdays = weekdays
        rule.hour = components.hour ?? original.hour
        rule.minute = components.minute ?? original.minute
        rule.action = kind.action(limit: limit, lowPowerMode: lowPowerMode)
        rule.repeats = repeats
        if isNew { rule.createdAt = Date() }
        // Re-enabling a once rule that already ran makes it run again at its next time.
        if rule.repeats == .once && rule.enabled && !original.enabled { rule.lastRun = Date() }
        return rule
    }
}
