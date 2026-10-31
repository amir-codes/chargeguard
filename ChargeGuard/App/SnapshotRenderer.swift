import AppKit
import SwiftUI
import ChargeGuardCore

/// Development tool: renders the app's windows offscreen into PNG files, so the UI can be checked
/// (and the README screenshots made) without Screen Recording permission or a person looking at
/// the screen. Only runs together with `--simulate`, so no helper is contacted and no key is written:
///
///     ChargeGuard.app/Contents/MacOS/ChargeGuard --simulate --render-snapshots /path/to/dir
///
/// Views are hosted in borderless, never-shown NSWindows and drawn with `cacheDisplay(in:to:)`,
/// which renders AppKit-backed controls (sliders, toggles, pickers) correctly, unlike ImageRenderer.
@MainActor
enum SnapshotRenderer {
    static let flag = "--render-snapshots"

    /// The output directory when the flag is present.
    static var requestedDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(model: AppModel, directory: URL) async {
        guard model.simulated else {
            FileHandle.standardError.write(Data("\(flag) needs --simulate\n".utf8))
            exit(2)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [String] = []

        // Let the simulated controller produce a few ticks first.
        try? await Task.sleep(for: .seconds(3))

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            written.append(render(PopupView().environment(model), size: CGSize(width: 340, height: 720),
                                  fitHeight: true, dark: dark, name: "popup-\(suffix)", in: directory))
            written.append(render(DashboardView().environment(model), size: CGSize(width: 900, height: 680),
                                  dark: dark, name: "dashboard-\(suffix)", in: directory))
        }
        written.append(render(OnboardingView().environment(model), size: CGSize(width: 560, height: 548),
                              dark: false, name: "onboarding", in: directory))
        written.append(render(UnsupportedMacView(), size: CGSize(width: 320, height: 200),
                              fitHeight: true, dark: false, name: "unsupported-mac", in: directory))

        let tabs: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsTab())),
            ("charging", AnyView(ChargingSettingsTab())),
            ("heat", AnyView(HeatSettingsTab())),
            ("sailing", AnyView(SailingSettingsTab())),
            ("calibration", AnyView(CalibrationSettingsTab())),
            ("schedule", AnyView(ScheduleSettingsTab())),
            ("sleep-power", AnyView(SleepPowerSettingsTab())),
            ("appearance", AnyView(AppearanceSettingsTab())),
            ("shortcuts", AnyView(ShortcutsSettingsTab())),
            ("advanced", AnyView(AdvancedSettingsTab())),
            ("about", AnyView(AboutSettingsTab())),
        ]
        for (name, view) in tabs {
            written.append(render(view.environment(model), size: CGSize(width: 760, height: 540),
                                  dark: false, name: "settings-\(name)", in: directory))
        }

        // A second popup after starting a discharge, to see a different state line and icon.
        model.setDischarge(true)
        try? await Task.sleep(for: .seconds(3))
        written.append(render(PopupView().environment(model), size: CGSize(width: 340, height: 720),
                              fitHeight: true, dark: false, name: "popup-discharging", in: directory))

        written.append(renderIconSheet(in: directory))
        print("rendered \(written.count) snapshots into \(directory.path)")
        for name in written { print("  \(name)") }
    }

    // MARK: Rendering

    @discardableResult
    private static func render<V: View>(_ view: V, size: CGSize, fitHeight: Bool = false, dark: Bool,
                                        name: String, in directory: URL) -> String {
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width)
            .frame(maxHeight: fitHeight ? nil : size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        var frame = NSRect(origin: .zero, size: size)
        if fitHeight {
            let fitting = hosting.fittingSize
            frame.size.height = max(80, min(size.height, fitting.height))
        }
        window.setContentSize(frame.size)
        hosting.frame = frame
        hosting.layoutSubtreeIfNeeded()
        // One run-loop turn so SwiftUI finishes the first layout pass and async image loads.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()
        return writePNG(of: hosting, name: name, in: directory)
    }

    private static func writePNG(of view: NSView, name: String, in directory: URL) -> String {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return "\(name): no bitmap" }
        view.cacheDisplay(in: bounds, to: rep)
        let url = directory.appendingPathComponent("\(name).png")
        guard let data = rep.representation(using: .png, properties: [:]) else { return "\(name): no png" }
        do {
            try data.write(to: url)
            return "\(name).png (\(Int(bounds.width))x\(Int(bounds.height)))"
        } catch {
            return "\(name): \(error.localizedDescription)"
        }
    }

    /// Every status kind in every icon style, monochrome and coloured, at 4x on a light and a dark strip.
    private static func renderIconSheet(in directory: URL) -> String {
        let kinds = StatusKind.allCases
        let styles = IconStyle.allCases.filter { $0 != .percentageOnly }
        let scale: CGFloat = 4
        let cell = NSSize(width: StatusIconRenderer.size.width * scale + 16, height: StatusIconRenderer.size.height * scale + 16)
        let labelWidth: CGFloat = 130
        let columns = styles.count * 2
        let sheetSize = NSSize(width: labelWidth + cell.width * CGFloat(columns), height: cell.height * CGFloat(kinds.count) * 2 + 24)
        let image = NSImage(size: sheetSize, flipped: true) { rect in
            for (band, dark) in [false, true].enumerated() {
                let bandTop = CGFloat(band) * (cell.height * CGFloat(kinds.count) + 12)
                (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
                NSRect(x: 0, y: bandTop, width: rect.width, height: cell.height * CGFloat(kinds.count) + 12).fill()
                let textColor: NSColor = dark ? .white : .black
                for (row, kind) in kinds.enumerated() {
                    let y = bandTop + 6 + CGFloat(row) * cell.height
                    NSAttributedString(string: kind.rawValue, attributes: [
                        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: textColor,
                    ]).draw(at: NSPoint(x: 8, y: y + cell.height / 2 - 8))
                    var column = 0
                    for style in styles {
                        for colored in [false, true] {
                            let letter = kind == .calibrating ? "B" : nil
                            if let icon = StatusIconRenderer.image(kind: kind, percentage: 62, style: style,
                                                                   colored: colored, calibrationLetter: letter) {
                                let target = NSRect(x: labelWidth + CGFloat(column) * cell.width + 8, y: y + 8,
                                                    width: StatusIconRenderer.size.width * scale,
                                                    height: StatusIconRenderer.size.height * scale)
                                let drawn = icon.isTemplate ? tinted(icon, with: textColor) : icon
                                drawn.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                                           respectFlipped: true, hints: nil)
                            }
                            column += 1
                        }
                    }
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return "icons: no png" }
        let url = directory.appendingPathComponent("icons.png")
        do {
            try data.write(to: url)
            return "icons.png (\(kinds.count) states x \(styles.count) styles x mono/colour)"
        } catch {
            return "icons: \(error.localizedDescription)"
        }
    }

    /// Template images are black; tint them the way the menu bar would.
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return copy
    }
}
