import AppIntents
import Foundation
import ChargeGuardCore

// Apple Shortcuts integration (feature 16). Intents run in the app process (openAppWhenRun = false)
// and talk to the helper through AppModel.shared, exactly like the menu bar UI.

/// Error shown by Shortcuts when the helper refuses or cannot be reached.
struct ChargeGuardIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        "\(message)"
    }
}

@MainActor
enum IntentSupport {
    /// Starts the model if the app was launched by Shortcuts and makes sure a status is available.
    static func readyModel() async -> AppModel {
        let model = AppModel.shared
        model.start()
        if model.status == nil {
            await model.refreshStatus()
        }
        return model
    }

    static func send(_ command: HelperCommand) async throws {
        let model = await readyModel()
        let ok = await model.send(command)
        guard ok else {
            throw ChargeGuardIntentError(message: model.lastError ?? "The ChargeGuard helper did not accept the command. Is it installed and running?")
        }
    }
}

// MARK: - Battery status entity

struct BatteryStatusEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Battery Status"
    static let defaultQuery = BatteryStatusQuery()

    let id: String

    @Property(title: "Percentage")
    var percentage: Int

    @Property(title: "Hardware Percentage")
    var hardwarePercentage: Double

    @Property(title: "Temperature (°C)")
    var temperature: Double

    @Property(title: "State")
    var state: String

    @Property(title: "Charge Limit")
    var limit: Int

    @Property(title: "Plugged In")
    var pluggedIn: Bool

    init(percentage: Int, hardwarePercentage: Double, temperature: Double, state: String, limit: Int, pluggedIn: Bool) {
        self.id = "current"
        self.percentage = percentage
        self.hardwarePercentage = hardwarePercentage
        self.temperature = temperature
        self.state = state
        self.limit = limit
        self.pluggedIn = pluggedIn
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(percentage) percent", subtitle: "\(state)")
    }

    var summary: String {
        String(format: "Battery %ld %% (hardware %.1f %%), %.1f °C. ", percentage, hardwarePercentage, temperature)
            + "\(state). Charge limit \(limit) %."
    }

    @MainActor
    static func current() async -> BatteryStatusEntity {
        let model = await IntentSupport.readyModel()
        let snapshot = model.snapshot
        return BatteryStatusEntity(percentage: snapshot?.percentage ?? 0,
                                   hardwarePercentage: ((snapshot?.hardwarePercentage ?? 0) * 10).rounded() / 10,
                                   temperature: snapshot?.temperatureC ?? 0,
                                   state: model.stateLine,
                                   limit: model.status?.effectiveLimit ?? model.config.chargeLimit,
                                   pluggedIn: snapshot?.adapterPresent ?? false)
    }
}

struct BatteryStatusQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BatteryStatusEntity] {
        [await BatteryStatusEntity.current()]
    }

    func suggestedEntities() async throws -> [BatteryStatusEntity] {
        [await BatteryStatusEntity.current()]
    }
}

// MARK: - App enums

enum LowPowerModeOption: String, AppEnum {
    case unmanaged
    case alwaysOff
    case alwaysOn
    case onlyOnBattery
    case onlyOnAdapter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Low Power Mode"
    static let caseDisplayRepresentations: [LowPowerModeOption: DisplayRepresentation] = [
        .unmanaged: "Not managed by ChargeGuard",
        .alwaysOff: "Always off",
        .alwaysOn: "Always on",
        .onlyOnBattery: "Only on battery",
        .onlyOnAdapter: "Only on adapter",
    ]

    var policy: LowPowerModePolicy {
        LowPowerModePolicy(rawValue: rawValue) ?? .unmanaged
    }
}

enum MagSafeLEDOption: String, AppEnum {
    case systemDefault
    case followState
    case alwaysOff

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "MagSafe LED"
    static let caseDisplayRepresentations: [MagSafeLEDOption: DisplayRepresentation] = [
        .systemDefault: "System default",
        .followState: "Show ChargeGuard's state",
        .alwaysOff: "Off",
    ]

    var mode: MagSafeLEDMode {
        MagSafeLEDMode(rawValue: rawValue) ?? .systemDefault
    }
}

// MARK: - Intents

struct GetBatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Status"
    static let description: IntentDescription? = IntentDescription("Returns the battery percentage, the hardware percentage, the temperature, the charging state and the charge limit.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BatteryStatusEntity> & ProvidesDialog {
        let entity = await BatteryStatusEntity.current()
        return .result(value: entity, dialog: IntentDialog("\(entity.summary)"))
    }
}

struct SetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Charge Limit"
    static let description: IntentDescription? = IntentDescription("Sets the charge limit (20 to 100 percent). Charging stops at the limit.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Limit", description: "Charge limit in percent, from 20 to 100.", default: 80, inclusiveRange: (20, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set the charge limit to \(\.$limit) percent")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let value = min(100, max(20, limit))
        try await IntentSupport.send(.setChargeLimit(value))
        return .result(dialog: IntentDialog("Charge limit set to \(value) percent."))
    }
}

struct SetDischargeIntent: AppIntent {
    static let title: LocalizedStringResource = "Enable or Disable Discharge"
    static let description: IntentDescription? = IntentDescription("Runs the Mac from the battery while plugged in until the charge limit is reached. Works only while the Mac is awake.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Discharge", default: true)
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set discharge to \(\.$enabled)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.send(enabled ? .startDischarge : .stopDischarge)
        return .result(dialog: IntentDialog(enabled ? "Discharging to the charge limit." : "Discharge stopped."))
    }
}

struct ToggleHeatProtectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Heat Protection"
    static let description: IntentDescription? = IntentDescription("Turns Heat Protection on or off. Leave the value empty to toggle it.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Enabled")
    var enabled: Bool?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = await IntentSupport.readyModel()
        let target = enabled ?? !model.config.heatProtection.enabled
        try await IntentSupport.send(.setHeatProtection(target))
        return .result(dialog: IntentDialog(target ? "Heat Protection is on." : "Heat Protection is off."))
    }
}

struct ToggleSailingIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Sailing Mode"
    static let description: IntentDescription? = IntentDescription("Turns Sailing Mode on or off. Leave the value empty to toggle it.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Enabled")
    var enabled: Bool?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = await IntentSupport.readyModel()
        let target = enabled ?? !model.config.sailing.enabled
        try await IntentSupport.send(.setSailing(target))
        return .result(dialog: IntentDialog(target ? "Sailing Mode is on." : "Sailing Mode is off."))
    }
}

struct TopUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Top Up"
    static let description: IntentDescription? = IntentDescription("Charges to 100 percent once, then returns to the charge limit when fully charged or unplugged.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.send(.startTopUp)
        return .result(dialog: "Topping up to 100 percent.")
    }
}

struct StartCalibrationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Calibration"
    static let description: IntentDescription? = IntentDescription("Starts battery calibration: charge to 100 percent and hold, discharge, charge to 100 percent and hold, then restore the limit.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.send(.startCalibration(fast: false, origin: "shortcut"))
        return .result(dialog: "Calibration started.")
    }
}

struct StopCalibrationIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Calibration"
    static let description: IntentDescription? = IntentDescription("Cancels a running calibration and restores the charge limit.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.send(.cancelCalibration)
        return .result(dialog: "Calibration stopped.")
    }
}

struct SetLowPowerModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Low Power Mode"
    static let description: IntentDescription? = IntentDescription("Chooses when ChargeGuard turns Low Power Mode on.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Low Power Mode", default: .onlyOnBattery)
    var option: LowPowerModeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Set Low Power Mode to \(\.$option)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.send(.setLowPowerMode(option.policy))
        return .result(dialog: IntentDialog("Low Power Mode: \(option.policy.title)."))
    }
}

struct KeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Awake"
    static let description: IntentDescription? = IntentDescription("Keeps the Mac awake for a number of minutes. 0 keeps it awake until you turn it off.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Minutes", description: "0 keeps the Mac awake until you turn it off.", default: 60, inclusiveRange: (0, 1440))
    var minutes: Int

    @Parameter(title: "Keep Display On", default: false)
    var keepDisplayOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Keep the Mac awake for \(\.$minutes) minutes") {
            \.$keepDisplayOn
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let duration: TimeInterval? = minutes <= 0 ? nil : TimeInterval(minutes * 60)
        try await IntentSupport.send(.keepAwake(KeepAwakeRequest(durationSeconds: duration, untilChargeLimit: false,
                                                                  preventDisplaySleep: keepDisplayOn)))
        let text = minutes <= 0 ? "The Mac stays awake until you turn it off." : "The Mac stays awake for \(minutes) minutes."
        return .result(dialog: IntentDialog("\(text)"))
    }
}

struct SetMagSafeLEDIntent: AppIntent {
    static let title: LocalizedStringResource = "Set MagSafe LED"
    static let description: IntentDescription? = IntentDescription("Chooses what the MagSafe LED shows.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "LED", default: .followState)
    var option: MagSafeLEDOption

    static var parameterSummary: some ParameterSummary {
        Summary("Set the MagSafe LED to \(\.$option)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.send(.setMagSafeLED(option.mode))
        return .result(dialog: "MagSafe LED updated.")
    }
}
