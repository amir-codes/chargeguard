import AppIntents

/// App Shortcuts with spoken phrases (feature 16). At most 10 are allowed per app; Set MagSafe LED
/// is available in the Shortcuts app as a regular action.
struct ChargeGuardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetBatteryStatusIntent(),
                    phrases: ["Get battery status in \(.applicationName)",
                              "How is my battery in \(.applicationName)"],
                    shortTitle: "Battery Status",
                    systemImageName: "battery.75percent")
        AppShortcut(intent: SetChargeLimitIntent(),
                    phrases: ["Set the charge limit in \(.applicationName)",
                              "Change the \(.applicationName) charge limit"],
                    shortTitle: "Set Charge Limit",
                    systemImageName: "slider.horizontal.3")
        AppShortcut(intent: SetDischargeIntent(),
                    phrases: ["Discharge with \(.applicationName)",
                              "Toggle discharge in \(.applicationName)"],
                    shortTitle: "Discharge",
                    systemImageName: "arrow.down.circle")
        AppShortcut(intent: ToggleHeatProtectionIntent(),
                    phrases: ["Toggle heat protection in \(.applicationName)"],
                    shortTitle: "Heat Protection",
                    systemImageName: "thermometer.high")
        AppShortcut(intent: ToggleSailingIntent(),
                    phrases: ["Toggle sailing mode in \(.applicationName)"],
                    shortTitle: "Sailing Mode",
                    systemImageName: "sailboat")
        AppShortcut(intent: TopUpIntent(),
                    phrases: ["Top up with \(.applicationName)",
                              "Charge to full with \(.applicationName)"],
                    shortTitle: "Top Up",
                    systemImageName: "arrow.up.to.line")
        AppShortcut(intent: StartCalibrationIntent(),
                    phrases: ["Start calibration in \(.applicationName)"],
                    shortTitle: "Start Calibration",
                    systemImageName: "gauge.with.dots.needle.33percent")
        AppShortcut(intent: StopCalibrationIntent(),
                    phrases: ["Stop calibration in \(.applicationName)"],
                    shortTitle: "Stop Calibration",
                    systemImageName: "stop.circle")
        AppShortcut(intent: SetLowPowerModeIntent(),
                    phrases: ["Set Low Power Mode in \(.applicationName)"],
                    shortTitle: "Low Power Mode",
                    systemImageName: "leaf")
        AppShortcut(intent: KeepAwakeIntent(),
                    phrases: ["Keep my Mac awake with \(.applicationName)"],
                    shortTitle: "Keep Awake",
                    systemImageName: "cup.and.saucer")
    }
}
