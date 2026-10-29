import Foundation
import Observation

/// Menu bar icon styles (feature 18).
enum IconStyle: String, CaseIterable, Codable, Identifiable {
    case outline
    case filled
    case bolt
    case percentageOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outline: return "Outline battery"
        case .filled: return "Filled battery"
        case .bolt: return "Bolt"
        case .percentageOnly: return "Percentage only"
        }
    }
}

/// Widgets of the menu bar pop-up, in user-chosen order (feature 18).
enum PopupWidget: String, CaseIterable, Codable, Identifiable {
    case limitSlider
    case toggles
    case calibrationCard
    case stats
    case powerFlowMini
    case energyApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .limitSlider: return "Charge limit slider"
        case .toggles: return "Toggles (Discharge, Heat, Sailing, Top Up)"
        case .calibrationCard: return "Calibration card"
        case .stats: return "Stat tiles"
        case .powerFlowMini: return "Power flow mini view"
        case .energyApps: return "Apps using significant energy"
        }
    }
}

struct PopupWidgetEntry: Codable, Equatable, Identifiable {
    var widget: PopupWidget
    var visible: Bool
    var id: String { widget.rawValue }
}

/// App-side preferences in UserDefaults (section 10). Policy settings live in the daemon.
///
/// The @Observable macro tracks the private `stored…` properties. The public properties are
/// computed wrappers that persist on set: this avoids `didSet` observers on macro-tracked stored
/// properties. Computed get/set properties still give `ReferenceWritableKeyPath`s, so
/// `@Bindable var prefs` / `$prefs.iconStyle` keep working.
@Observable
final class AppPreferences {
    private let defaults: UserDefaults

    private var storedIconStyle: IconStyle
    private var storedColorByState: Bool
    private var storedShowPercentage: Bool
    private var storedShowLimitInMenuBar: Bool
    private var storedShowHardwarePercentage: Bool
    private var storedWidgets: [PopupWidgetEntry]
    private var storedHasCompletedOnboarding: Bool
    private var storedNotificationsEnabled: Bool

    var iconStyle: IconStyle {
        get { storedIconStyle }
        set {
            storedIconStyle = newValue
            defaults.set(newValue.rawValue, forKey: Keys.iconStyle)
        }
    }

    var colorByState: Bool {
        get { storedColorByState }
        set {
            storedColorByState = newValue
            defaults.set(newValue, forKey: Keys.colorByState)
        }
    }

    var showPercentage: Bool {
        get { storedShowPercentage }
        set {
            storedShowPercentage = newValue
            defaults.set(newValue, forKey: Keys.showPercentage)
        }
    }

    var showLimitInMenuBar: Bool {
        get { storedShowLimitInMenuBar }
        set {
            storedShowLimitInMenuBar = newValue
            defaults.set(newValue, forKey: Keys.showLimitInMenuBar)
        }
    }

    var showHardwarePercentage: Bool {
        get { storedShowHardwarePercentage }
        set {
            storedShowHardwarePercentage = newValue
            defaults.set(newValue, forKey: Keys.showHardwarePercentage)
        }
    }

    var widgets: [PopupWidgetEntry] {
        get { storedWidgets }
        set {
            storedWidgets = newValue
            saveWidgets()
        }
    }

    var hasCompletedOnboarding: Bool {
        get { storedHasCompletedOnboarding }
        set {
            storedHasCompletedOnboarding = newValue
            defaults.set(newValue, forKey: Keys.onboarding)
        }
    }

    var notificationsEnabled: Bool {
        get { storedNotificationsEnabled }
        set {
            storedNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.notifications)
        }
    }

    enum Keys {
        static let iconStyle = "iconStyle"
        static let colorByState = "colorByState"
        static let showPercentage = "showPercentage"
        static let showLimitInMenuBar = "showLimitInMenuBar"
        static let showHardwarePercentage = "showHardwarePercentage"
        static let widgets = "popupWidgets"
        static let onboarding = "hasCompletedOnboarding"
        static let notifications = "notificationsEnabled"
    }

    static let defaultWidgets: [PopupWidgetEntry] = [
        PopupWidgetEntry(widget: .limitSlider, visible: true),
        PopupWidgetEntry(widget: .toggles, visible: true),
        PopupWidgetEntry(widget: .calibrationCard, visible: true),
        PopupWidgetEntry(widget: .stats, visible: true),
        PopupWidgetEntry(widget: .powerFlowMini, visible: true),
        PopupWidgetEntry(widget: .energyApps, visible: false),
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedIconStyle = IconStyle(rawValue: defaults.string(forKey: Keys.iconStyle) ?? "") ?? .filled
        storedColorByState = defaults.object(forKey: Keys.colorByState) as? Bool ?? true
        storedShowPercentage = defaults.object(forKey: Keys.showPercentage) as? Bool ?? true
        storedShowLimitInMenuBar = defaults.object(forKey: Keys.showLimitInMenuBar) as? Bool ?? false
        storedShowHardwarePercentage = defaults.object(forKey: Keys.showHardwarePercentage) as? Bool ?? true
        storedHasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        storedNotificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.widgets),
           let saved = try? JSONDecoder().decode([PopupWidgetEntry].self, from: data) {
            storedWidgets = Self.merged(saved)
        } else {
            storedWidgets = Self.defaultWidgets
        }
    }

    /// Keeps the saved order and adds widgets introduced by newer versions.
    static func merged(_ saved: [PopupWidgetEntry]) -> [PopupWidgetEntry] {
        var result = saved.filter { entry in PopupWidget.allCases.contains(entry.widget) }
        for entry in defaultWidgets where !result.contains(where: { $0.widget == entry.widget }) {
            result.append(entry)
        }
        return result
    }

    private func saveWidgets() {
        if let data = try? JSONEncoder().encode(widgets) { defaults.set(data, forKey: Keys.widgets) }
    }

    func resetLayout() {
        widgets = Self.defaultWidgets
    }

    // MARK: Export / import (bundled into SettingsExport.appPreferences)

    struct Snapshot: Codable {
        var iconStyle: IconStyle
        var colorByState: Bool
        var showPercentage: Bool
        var showLimitInMenuBar: Bool
        var showHardwarePercentage: Bool
        var widgets: [PopupWidgetEntry]
        var notificationsEnabled: Bool
    }

    func exportData() -> Data? {
        try? JSONEncoder().encode(Snapshot(iconStyle: iconStyle, colorByState: colorByState, showPercentage: showPercentage,
                                           showLimitInMenuBar: showLimitInMenuBar, showHardwarePercentage: showHardwarePercentage,
                                           widgets: widgets, notificationsEnabled: notificationsEnabled))
    }

    func importData(_ data: Data) {
        guard let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        iconStyle = s.iconStyle
        colorByState = s.colorByState
        showPercentage = s.showPercentage
        showLimitInMenuBar = s.showLimitInMenuBar
        showHardwarePercentage = s.showHardwarePercentage
        widgets = Self.merged(s.widgets)
        notificationsEnabled = s.notificationsEnabled
    }
}
