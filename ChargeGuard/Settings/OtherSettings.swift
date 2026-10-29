import AppKit
import SwiftUI
import ChargeGuardCore

struct ShortcutsSettingsTab: View {
    private struct IntentInfo: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    private let intents: [IntentInfo] = [
        IntentInfo(name: "Get Battery Status", detail: "Percentage, hardware percentage, temperature, state and limit."),
        IntentInfo(name: "Set Charge Limit", detail: "Sets the limit (20–100 %)."),
        IntentInfo(name: "Enable or Disable Discharge", detail: "Runs the Mac from the battery down to the limit, or stops."),
        IntentInfo(name: "Toggle Heat Protection", detail: "Turns Heat Protection on or off."),
        IntentInfo(name: "Toggle Sailing", detail: "Turns Sailing Mode on or off."),
        IntentInfo(name: "Top Up", detail: "Charges to 100 % once."),
        IntentInfo(name: "Start or Stop Calibration", detail: "Starts or cancels Calibration Mode."),
        IntentInfo(name: "Set Low Power Mode", detail: "Always off, always on, only on battery, only on adapter."),
        IntentInfo(name: "Keep Awake", detail: "Keeps the Mac awake for a duration."),
        IntentInfo(name: "Set MagSafe LED", detail: "Follow ChargeGuard's state, system default or off."),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(intents) { intent in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(intent.name)
                        Text(intent.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Apple Shortcuts actions")
            } footer: {
                Text("Find these actions under ChargeGuard in the Shortcuts app, or ask Siri, for example “Top up with ChargeGuard”. Actions that change charging need the helper.")
            }

            Section {
                // ShortcutsLink (AppIntents) is not available on macOS, so a plain button opens the app.
                HStack {
                    Spacer()
                    Button("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
                    }
                    .accessibilityHint("Opens the Shortcuts app, where ChargeGuard's actions are listed")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsTab: View {
    @Environment(AppModel.self) private var model

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("ChargeGuard").font(.title.bold())
            Text(version).foregroundStyle(.secondary)
            if let helper = model.status?.daemonVersion {
                Text("Helper \(helper)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Battery care for Apple silicon MacBooks: charge limit, discharge, heat protection, sailing, top up, calibration, schedules and Shortcuts.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Divider().frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 6) {
                Text("Released under the MIT License.")
                Text("Credits").font(.headline).padding(.top, 4)
                Link("SMCKit by beltex (MIT): SMC access", destination: URL(string: "https://github.com/beltex/SMCKit")!)
                Link("battery by actuallymentor (MIT): SMC key values", destination: URL(string: "https://github.com/actuallymentor/battery")!)
                Link("batt by charlie0129 (GPL-2.0): read as a reference only, no code used", destination: URL(string: "https://github.com/charlie0129/batt")!)
                Text("ChargeGuard is an independent, clean-room app. It is not affiliated with or endorsed by AlDente or AppHouseKitchen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 480, alignment: .leading)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
