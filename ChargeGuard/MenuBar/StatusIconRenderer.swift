import AppKit
import ChargeGuardCore

/// Draws the menu bar icon for a state (feature 17) in a style (feature 18).
///
/// Monochrome icons are template images, so macOS tints them for light/dark menu bars.
/// Coloured icons use the state colour for the fill and the badge.
enum StatusIconRenderer {
    static let size = NSSize(width: 26, height: 16)

    static func image(kind: StatusKind, percentage: Int?, style: IconStyle, colored: Bool,
                      calibrationLetter: String? = nil) -> NSImage? {
        if style == .percentageOnly { return nil }
        let level = Double(min(100, max(0, percentage ?? 0))) / 100
        let tint = colored ? nsColor(for: kind) : NSColor.black
        let image = NSImage(size: size, flipped: false) { rect in
            switch style {
            case .bolt:
                drawSymbol(symbolName(for: kind, boltStyle: true), in: rect.insetBy(dx: 5, dy: 0), color: tint, pointSize: 13)
            case .outline, .filled:
                drawBattery(in: rect, level: level, filled: style == .filled, kind: kind, tint: tint,
                            colored: colored, calibrationLetter: calibrationLetter)
            case .percentageOnly:
                break
            }
            return true
        }
        image.isTemplate = !colored
        image.accessibilityDescription = "ChargeGuard: \(kind.accessibilityName)"
        return image
    }

    private static func drawBattery(in rect: NSRect, level: Double, filled: Bool, kind: StatusKind, tint: NSColor,
                                    colored: Bool, calibrationLetter: String?) {
        let body = NSRect(x: 1, y: 2.5, width: 21, height: 11)
        let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.2
        (colored ? NSColor.labelColor : NSColor.black).withAlphaComponent(colored ? 0.85 : 1).setStroke()
        outline.stroke()

        let tip = NSBezierPath(roundedRect: NSRect(x: 23, y: 6, width: 1.8, height: 4), xRadius: 0.9, yRadius: 0.9)
        (colored ? NSColor.labelColor : NSColor.black).withAlphaComponent(colored ? 0.85 : 1).setFill()
        tip.fill()

        let inner = body.insetBy(dx: 2, dy: 2)
        if filled {
            let width = max(1.5, inner.width * level)
            let fillRect = NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
            (colored ? tint : NSColor.black).withAlphaComponent(colored ? 0.9 : 0.55).setFill()
            fill.fill()
        }

        // State badge in the middle of the battery body.
        if let letter = calibrationLetter, kind == .calibrating {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                .foregroundColor: colored ? NSColor.labelColor : NSColor.black,
            ]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: body.midX - textSize.width / 2, y: body.midY - textSize.height / 2))
        } else if let symbol = badgeSymbol(for: kind) {
            let badgeColor: NSColor = colored ? (filled ? NSColor.labelColor : tint) : NSColor.black
            if filled && !colored {
                // Knock the badge out of the template fill so it stays readable. NSImage.draw(in:)
                // always uses .sourceOver, so the operation is passed to draw(in:from:operation:fraction:).
                drawSymbol(symbol, in: body.insetBy(dx: 4, dy: 1), color: .black, pointSize: 8, operation: .destinationOut)
            } else {
                drawSymbol(symbol, in: body.insetBy(dx: 4, dy: 1), color: badgeColor, pointSize: 8)
            }
        }
    }

    private static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat,
                                   operation: NSCompositingOperation = .sourceOver) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let symbolSize = symbol.size
        let origin = NSPoint(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: symbolSize), from: .zero, operation: operation, fraction: 1)
    }

    /// Small glyph inside the battery for each state.
    static func badgeSymbol(for kind: StatusKind) -> String? {
        switch kind {
        case .idle: return "pause.fill"
        case .onBattery: return nil
        case .charging: return "bolt.fill"
        case .limitReached: return "checkmark"
        case .sailing: return "wave.3.right"
        case .discharging: return "arrow.down"
        case .heatPaused: return "thermometer.medium"
        case .calibrating: return "gauge.with.dots.needle.33percent"
        case .topUp: return "arrow.up"
        case .helperMissing: return "questionmark"
        case .error: return "exclamationmark"
        case .conflict: return "xmark"
        }
    }

    static func symbolName(for kind: StatusKind, boltStyle: Bool) -> String {
        switch kind {
        case .charging, .topUp: return "bolt.fill"
        case .limitReached: return "checkmark.circle.fill"
        case .sailing: return "sailboat.fill"
        case .discharging: return "bolt.slash.fill"
        case .heatPaused: return "thermometer.high"
        case .calibrating: return "gauge.with.dots.needle.33percent"
        case .helperMissing: return "questionmark.circle"
        case .error, .conflict: return "exclamationmark.triangle.fill"
        case .idle, .onBattery: return "bolt"
        }
    }

    static func nsColor(for kind: StatusKind) -> NSColor {
        switch kind {
        case .idle, .helperMissing: return .systemGray
        case .onBattery: return .labelColor
        case .charging: return .systemOrange
        case .limitReached: return .systemGreen
        case .sailing: return .systemTeal
        case .discharging: return .systemBlue
        case .heatPaused, .error: return .systemRed
        case .calibrating: return .systemPurple
        case .topUp: return .systemYellow
        case .conflict: return .systemPink
        }
    }
}
