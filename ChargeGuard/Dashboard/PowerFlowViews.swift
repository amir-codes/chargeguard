import SwiftUI
import ChargeGuardCore

/// Live Sankey diagram of the power flow (feature 20), drawn with Canvas.
/// Adapter → System, Adapter → Battery while charging, Battery → System while discharging.
/// Ribbon widths are proportional to watts. Animatable, so wrapping it in
/// `.animation(_:value:)` interpolates the ribbons between 2-second samples.
struct PowerFlowSankey: View, Animatable {
    var adapterToSystem: Double
    var adapterToBattery: Double
    var batteryToSystem: Double
    var source: PowerFlow.AdapterPowerSource
    var compact: Bool

    init(flow: PowerFlow, compact: Bool = false) {
        adapterToSystem = flow.adapterToSystemW
        adapterToBattery = flow.adapterToBatteryW
        batteryToSystem = flow.batteryToSystemW
        source = flow.adapterSource
        self.compact = compact
    }

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(adapterToSystem, adapterToBattery), batteryToSystem) }
        set {
            adapterToSystem = newValue.first.first
            adapterToBattery = newValue.first.second
            batteryToSystem = newValue.second
        }
    }

    private var adapterW: Double { adapterToSystem + adapterToBattery }
    private var systemW: Double { adapterToSystem + batteryToSystem }
    private var adapterConnected: Bool { source != .none }

    var body: some View {
        // The Canvas closure only touches this plain value, never main-actor View state.
        let renderer = PowerFlowSankeyRenderer(adapterToSystem: adapterToSystem, adapterToBattery: adapterToBattery,
                                               batteryToSystem: batteryToSystem, adapterConnected: adapterConnected,
                                               compact: compact)
        Canvas { context, size in
            renderer.draw(in: &context, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Power flow")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if adapterConnected {
            parts.append("Adapter supplies \(Fmt.watts(adapterW))")
            parts.append("\(Fmt.watts(adapterToSystem)) to the system")
            if adapterToBattery > 0.05 { parts.append("\(Fmt.watts(adapterToBattery)) into the battery") }
        } else {
            parts.append("Adapter not connected")
        }
        if batteryToSystem > 0.05 { parts.append("battery supplies \(Fmt.watts(batteryToSystem)) to the system") }
        parts.append("system uses \(Fmt.watts(systemW))")
        return parts.joined(separator: ", ")
    }
}

/// Draws one frame of the Sankey diagram. A plain value type (not a View), so the Canvas renderer
/// closure can call it from any isolation context.
private struct PowerFlowSankeyRenderer {
    let adapterToSystem: Double
    let adapterToBattery: Double
    let batteryToSystem: Double
    let adapterConnected: Bool
    let compact: Bool

    static let adapterColor = Color.orange
    static let batteryColor = Color.green
    static let systemColor = Color.blue

    private var adapterW: Double { adapterToSystem + adapterToBattery }
    private var systemW: Double { adapterToSystem + batteryToSystem }
    private var batteryOnRight: Bool { adapterToBattery > 0.05 || batteryToSystem <= 0.05 }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let labelWidth: CGFloat = compact ? 58 : 112
        let nodeWidth: CGFloat = compact ? 5 : 12
        let gap: CGFloat = compact ? 22 : 36
        let verticalPadding: CGFloat = compact ? 6 : 14
        let floorWatts: Double = compact ? 15 : 25
        let minNode: CGFloat = 3

        let onRight = batteryOnRight
        let leftTotal = adapterW + (onRight ? 0 : batteryToSystem)
        let rightTotal = systemW + (onRight ? adapterToBattery : 0)
        let maxTotal = max(leftTotal, rightTotal, floorWatts)
        let usable = max(10, size.height - 2 * verticalPadding - gap)
        let scale = usable / CGFloat(maxTotal)
        func thickness(_ watts: Double) -> CGFloat {
            watts <= 0.05 ? 0 : max(CGFloat(watts) * scale, compact ? 1.5 : 2)
        }

        // Left column: adapter, then battery when it discharges.
        let adapterHeight = max(thickness(adapterW), minNode)
        let leftBatteryHeight = onRight ? 0 : max(thickness(batteryToSystem), minNode)
        let leftColumn = adapterHeight + (onRight ? 0 : gap + leftBatteryHeight)
        let leftTop = (size.height - leftColumn) / 2
        let leftX = labelWidth
        let adapterRect = CGRect(x: leftX, y: leftTop, width: nodeWidth, height: adapterHeight)
        let leftBatteryRect = CGRect(x: leftX, y: leftTop + adapterHeight + gap, width: nodeWidth, height: leftBatteryHeight)

        // Right column: system, then battery when it charges (or idles).
        let systemHeight = max(thickness(systemW), minNode)
        let rightBatteryHeight = onRight ? max(thickness(adapterToBattery), minNode) : 0
        let rightColumn = systemHeight + (onRight ? gap + rightBatteryHeight : 0)
        let rightTop = (size.height - rightColumn) / 2
        let rightX = size.width - labelWidth - nodeWidth
        let systemRect = CGRect(x: rightX, y: rightTop, width: nodeWidth, height: systemHeight)
        let rightBatteryRect = CGRect(x: rightX, y: rightTop + systemHeight + gap, width: nodeWidth, height: rightBatteryHeight)

        // Ribbons under the nodes.
        let a2s = thickness(adapterToSystem)
        if a2s > 0 {
            fillRibbon(&context, x0: adapterRect.maxX, top0: adapterRect.minY, x1: systemRect.minX, top1: systemRect.minY,
                       thickness: a2s, from: Self.adapterColor, to: Self.systemColor)
        }
        let a2b = thickness(adapterToBattery)
        if onRight, a2b > 0 {
            fillRibbon(&context, x0: adapterRect.maxX, top0: adapterRect.minY + a2s, x1: rightBatteryRect.minX,
                       top1: rightBatteryRect.minY, thickness: a2b, from: Self.adapterColor, to: Self.batteryColor)
        }
        let b2s = thickness(batteryToSystem)
        if !onRight, b2s > 0 {
            fillRibbon(&context, x0: leftBatteryRect.maxX, top0: leftBatteryRect.minY, x1: systemRect.minX,
                       top1: systemRect.minY + a2s, thickness: b2s, from: Self.batteryColor, to: Self.systemColor)
        }

        // Nodes.
        fillNode(&context, adapterRect, Self.adapterColor.opacity(adapterConnected ? 1 : 0.3))
        fillNode(&context, systemRect, Self.systemColor)
        let batteryRect = onRight ? rightBatteryRect : leftBatteryRect
        fillNode(&context, batteryRect, Self.batteryColor.opacity(adapterToBattery > 0.05 || batteryToSystem > 0.05 ? 1 : 0.4))

        // Labels: left column right-aligned before the nodes, right column after them.
        drawLabel(&context, title: "Adapter", value: adapterConnected ? Fmt.watts(adapterW) : "Unplugged",
                  x: adapterRect.minX - 6, midY: adapterRect.midY, anchorLeading: false)
        drawLabel(&context, title: "System", value: Fmt.watts(systemW),
                  x: systemRect.maxX + 6, midY: systemRect.midY, anchorLeading: true)
        drawLabel(&context, title: "Battery", value: batteryValue,
                  x: onRight ? batteryRect.maxX + 6 : batteryRect.minX - 6, midY: batteryRect.midY, anchorLeading: onRight)
    }

    private var batteryValue: String {
        if adapterToBattery > 0.05 { return String(format: "+%.1f W", adapterToBattery) }
        if batteryToSystem > 0.05 { return String(format: "−%.1f W", batteryToSystem) }
        return "Idle"
    }

    private func fillRibbon(_ context: inout GraphicsContext, x0: CGFloat, top0: CGFloat, x1: CGFloat, top1: CGFloat,
                            thickness: CGFloat, from: Color, to: Color) {
        var path = Path()
        let mid = (x0 + x1) / 2
        path.move(to: CGPoint(x: x0, y: top0))
        path.addCurve(to: CGPoint(x: x1, y: top1),
                      control1: CGPoint(x: mid, y: top0), control2: CGPoint(x: mid, y: top1))
        path.addLine(to: CGPoint(x: x1, y: top1 + thickness))
        path.addCurve(to: CGPoint(x: x0, y: top0 + thickness),
                      control1: CGPoint(x: mid, y: top1 + thickness), control2: CGPoint(x: mid, y: top0 + thickness))
        path.closeSubpath()
        context.fill(path, with: .linearGradient(Gradient(colors: [from.opacity(0.5), to.opacity(0.5)]),
                                                 startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
    }

    private func fillNode(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
        context.fill(Path(roundedRect: rect, cornerRadius: min(2, rect.width / 2)), with: .color(color))
    }

    private func drawLabel(_ context: inout GraphicsContext, title: String, value: String, x: CGFloat, midY: CGFloat,
                           anchorLeading: Bool) {
        let offset: CGFloat = compact ? 6 : 8
        let titleFont: Font = compact ? .caption2 : .caption
        let valueFont: Font = compact ? Font.caption2.weight(.semibold) : Font.callout.weight(.semibold)
        let titleText: Text = Text(title).font(titleFont).foregroundColor(.secondary)
        let valueText: Text = Text(value).font(valueFont).monospacedDigit().foregroundColor(.primary)
        let anchorTop: UnitPoint = anchorLeading ? .leading : .trailing
        context.draw(titleText, at: CGPoint(x: x, y: midY - offset), anchor: anchorTop)
        context.draw(valueText, at: CGPoint(x: x, y: midY + offset), anchor: anchorTop)
    }
}

extension PowerFlow.AdapterPowerSource {
    /// Caption explaining where the adapter number comes from.
    var caption: String {
        switch self {
        case .measured: return "Adapter input measured live"
        case .derived: return "Adapter input estimated from the system load"
        case .rated: return "Adapter rating shown: live input power is not readable on this Mac"
        case .none: return "Running on battery"
        }
    }

    var shortLabel: String {
        switch self {
        case .measured: return "measured"
        case .derived: return "estimated"
        case .rated: return "adapter rating"
        case .none: return "not connected"
        }
    }
}

/// Compact power flow for the menu bar pop-up (~300 x 90).
struct PowerFlowMiniView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let flow = currentFlow
        VStack(alignment: .leading, spacing: 4) {
            Text("Power Flow").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            PowerFlowSankey(flow: flow, compact: true)
                .frame(height: 90)
                .animation(.easeInOut(duration: 0.8), value: flow)
            Text(flow.adapterSource.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .onAppear { model.beginLiveRefresh() }
        .onDisappear { model.endLiveRefresh() }
    }

    private var currentFlow: PowerFlow {
        guard let snapshot = model.freshSnapshot else { return .zero }
        return PowerFlow.compute(from: snapshot)
    }
}

/// Full-size power flow with numeric cards, for the dashboard.
struct PowerFlowPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snapshot = model.freshSnapshot
        let flow = snapshot.map { PowerFlow.compute(from: $0) } ?? .zero
        VStack(alignment: .leading, spacing: 12) {
            PowerFlowSankey(flow: flow, compact: false)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.8), value: flow)
            PowerFlowCards(flow: flow, snapshot: snapshot)
            Text(flow.adapterSource.caption + ". Updates every 2 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Numeric cards next to the Sankey diagram.
struct PowerFlowCards: View {
    let flow: PowerFlow
    let snapshot: BatterySnapshot?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
            StatTile(title: "Adapter", value: flow.adapterSource == .none ? "Unplugged" : Fmt.watts(flow.adapterW),
                     systemImage: "powerplug", detail: flow.adapterSource.shortLabel)
            StatTile(title: "System", value: Fmt.watts(flow.systemW), systemImage: "desktopcomputer")
            StatTile(title: "Battery", value: batteryText, systemImage: "battery.75percent", detail: batteryDetail)
            StatTile(title: "Voltage", value: Fmt.millivolts(snapshot?.voltageMV), systemImage: "bolt")
            StatTile(title: "Amperage", value: Fmt.milliamps(snapshot?.amperageMA), systemImage: "waveform.path")
        }
    }

    private var batteryText: String {
        guard let snapshot else { return "—" }
        let watts = snapshot.batteryPowerW
        if abs(watts) < 0.05 { return "0 W" }
        return String(format: "%+.1f W", watts)
    }

    private var batteryDetail: String {
        guard let snapshot else { return "" }
        if snapshot.batteryPowerW > 0.05 { return "charging" }
        if snapshot.batteryPowerW < -0.05 { return "discharging" }
        return "idle"
    }
}
