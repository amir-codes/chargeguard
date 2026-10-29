import SwiftUI
import ChargeGuardCore

struct AppearanceSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.preferences
        Form {
            Section("Menu bar icon") {
                Picker("Icon style", selection: $prefs.iconStyle) {
                    ForEach(IconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Colours", selection: $prefs.colorByState) {
                    Text("Coloured by state").tag(true)
                    Text("Monochrome").tag(false)
                }
                .pickerStyle(.radioGroup)
                Toggle("Show the percentage next to the icon", isOn: $prefs.showPercentage)
                    .disabled(prefs.iconStyle == .percentageOnly)
                Toggle("Show the charge limit in the menu bar", isOn: $prefs.showLimitInMenuBar)
            }

            Section("Pop-up") {
                Toggle("Show the hardware battery percentage", isOn: $prefs.showHardwarePercentage)
            }

            Section {
                List {
                    ForEach($prefs.widgets) { $entry in
                        HStack {
                            Toggle(entry.widget.title, isOn: $entry.visible)
                            Spacer()
                            Button {
                                move(entry.widget, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(prefs.widgets.first?.widget == entry.widget)
                            .accessibilityLabel("Move \(entry.widget.title) up")
                            Button {
                                move(entry.widget, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(prefs.widgets.last?.widget == entry.widget)
                            .accessibilityLabel("Move \(entry.widget.title) down")
                        }
                    }
                    .onMove { source, destination in
                        prefs.widgets.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .frame(height: 210)
                HStack {
                    Spacer()
                    Button("Reset layout") { prefs.resetLayout() }
                }
            } header: {
                Text("Pop-up layout")
            } footer: {
                Text("Choose which widgets appear in the pop-up and drag them (or use the arrows) to change their order. The percentage, the state line and the bottom bar are always shown.")
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ widget: PopupWidget, by offset: Int) {
        let prefs = model.preferences
        guard let index = prefs.widgets.firstIndex(where: { $0.widget == widget }) else { return }
        let target = index + offset
        guard prefs.widgets.indices.contains(target) else { return }
        prefs.widgets.swapAt(index, target)
    }
}
