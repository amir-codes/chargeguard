import Foundation

/// Schedule state machine (feature 15). Pure: callers pass the calendar and the clock.
///
/// Each check looks for the latest occurrence of every enabled rule in (lowerBound, now], where
/// lowerBound is the later of the previous check, the rule's last run and its creation. An occurrence
/// less than `catchUpWindow` old runs (this covers wake and boot after a missed run); an older one is
/// reported as missed. A rule fires at most once per check.
public enum ScheduleEngine {
    public static let catchUpWindow: TimeInterval = 2 * 3600
    /// How far back occurrences are searched. A week covers every weekly rule.
    static let searchDays = 8

    public struct CheckResult: Equatable {
        public var due: [ScheduledOccurrence]
        public var missed: [ScheduledOccurrence]
        /// Rules with `lastRun` updated and once-rules disabled after firing.
        public var updatedRules: [ScheduleRule]
    }

    static func matches(_ rule: ScheduleRule, day: Date, calendar: Calendar) -> Bool {
        rule.weekdays.isEmpty || rule.weekdays.contains(calendar.component(.weekday, from: day))
    }

    static func occurrence(of rule: ScheduleRule, onDayOf day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: day)
    }

    /// Latest occurrence in (after, through], or nil.
    public static func latestOccurrence(of rule: ScheduleRule, after: Date, through: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: through)
        for offset in 0...searchDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            guard matches(rule, day: day, calendar: calendar),
                  let date = occurrence(of: rule, onDayOf: day, calendar: calendar) else { continue }
            if date <= through {
                return date > after ? date : nil
            }
        }
        return nil
    }

    /// Next occurrence strictly after `after`, or nil for a disabled rule.
    public static func nextRun(of rule: ScheduleRule, after: Date, calendar: Calendar) -> Date? {
        guard rule.enabled else { return nil }
        let lower = max(after, rule.lastRun ?? .distantPast)
        let today = calendar.startOfDay(for: lower)
        for offset in 0...searchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard matches(rule, day: day, calendar: calendar),
                  let date = occurrence(of: rule, onDayOf: day, calendar: calendar) else { continue }
            if date > lower { return date }
        }
        return nil
    }

    public static func check(rules: [ScheduleRule], lastCheck: Date?, now: Date, calendar: Calendar,
                             catchUpWindow: TimeInterval = ScheduleEngine.catchUpWindow) -> CheckResult {
        var due: [ScheduledOccurrence] = []
        var missed: [ScheduledOccurrence] = []
        var updated = rules
        for index in updated.indices {
            let rule = updated[index]
            guard rule.enabled else { continue }
            var lower = rule.createdAt
            if let lastRun = rule.lastRun { lower = max(lower, lastRun) }
            if let lastCheck { lower = max(lower, lastCheck) }
            // Never look further back than the catch-up window plus a day for the "missed" report.
            lower = max(lower, now.addingTimeInterval(-Double(searchDays) * 86_400))
            guard let date = latestOccurrence(of: rule, after: lower, through: now, calendar: calendar) else { continue }
            let occurrence = ScheduledOccurrence(ruleID: rule.id, scheduledAt: date, action: rule.action)
            if now.timeIntervalSince(date) <= catchUpWindow {
                due.append(occurrence)
            } else {
                missed.append(occurrence)
            }
            if rule.repeats == .once { updated[index].enabled = false }
            updated[index].lastRun = date
        }
        due.sort { $0.scheduledAt < $1.scheduledAt }
        return CheckResult(due: due, missed: missed, updatedRules: updated)
    }

    /// The soonest next run across all rules.
    public static func nextRun(rules: [ScheduleRule], after: Date, calendar: Calendar) -> (rule: ScheduleRule, date: Date)? {
        var best: (rule: ScheduleRule, date: Date)?
        for rule in rules {
            guard let date = nextRun(of: rule, after: after, calendar: calendar) else { continue }
            if best == nil || date < best!.date { best = (rule: rule, date: date) }
        }
        return best
    }
}
