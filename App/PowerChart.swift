import Charts
import SwiftUI

/// CPU, GPU and Neural Engine power over the service's last minutes (`socHistoryWindow`). Both views redraw only when
/// a refresh brings a new history: no timeline of their own. Either one counts as a chart on screen, which makes the
/// status refresh ask for the history.
private struct Component {
    let name: String
    let color: Color
    let value: (SoCPower) -> Double
    var dashed = false
    var short: String? = nil  // menu caption, where the full name does not fit

    // Neural Engine is dashed so the lines differ by more than color.
    static var all: [Component] {
        [Component(name: "CPU", color: .viz(light: 0x2a78d6, dark: 0x3987e5), value: \.cpuWatts),
         Component(name: "GPU", color: .viz(light: 0xeb6834, dark: 0xd95926), value: \.gpuWatts),
         Component(name: tr("Neural Engine"), color: .viz(light: 0x1f9e6a, dark: 0x2fb67e), value: \.aneWatts, dashed: true, short: "ANE")]
    }

    /// "CPU 0.9 W", or "CPU — W" before the first point.
    func caption(_ p: SoCPower?, short: Bool = false) -> String {
        "\(short ? self.short ?? name : name) " + (p.map { watts(value($0)) } ?? "\u{2014} W")
    }

    /// Short line key in the component's color, dashed like its curve.
    func key(width: CGFloat) -> some View {
        Path { $0.move(to: CGPoint(x: 1, y: 1)); $0.addLine(to: CGPoint(x: width - 1, y: 1)) }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
            .frame(width: width, height: 2)
    }
}

/// Reports going on or off screen once per change: window shown, hidden or closed, view removed. Visibility arrives
/// asynchronously: a report landing after the view was removed is ignored, so the app's chart count cannot stay above 0.
private struct OnScreen: ViewModifier {
    let report: (Bool) -> Void
    @State private var shown = false
    @State private var removed = false

    func body(content: Content) -> some View {
        content
            .background(WindowVisibility { v in
                guard !removed, v != shown else { return }
                shown = v
                report(v)
            })
            .onAppear { removed = false }
            .onDisappear {
                removed = true
                if shown { shown = false; report(false) }
            }
    }
}

/// The three curves on one W scale from 0 to the window's peak (at least 1 W, so idle stays flat), smoothed with
/// monotone interpolation: no overshoot below 0 or above a measured peak. A gap (sleep, powermetrics restart) splits each
/// curve. Before the first points: the empty frame over the last minutes.
private func powerCurves(_ history: [SoCPowerPoint], lineWidth: CGFloat) -> some ChartContent {
    let segments = powerSegments(history, maxGap: socMaxGap)
    return ForEach(Component.all, id: \.name) { c in
        ForEach(history.indices, id: \.self) { i in
            let p = history[i]
            LineMark(x: .value(tr("Time"), p.date), y: .value(tr("Power"), c.value(p.power)), series: .value("", "\(c.name) \(segments[i])"))
                .interpolationMethod(.monotone)
                .foregroundStyle(c.color)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: c.dashed ? [5, 4] : []))
        }
    }
}

/// The window ends at `now` (the history's arrival), so a stopped feed slides out instead of looking current.
private func powerScale(_ history: [SoCPowerPoint], now end: Date) -> (x: ClosedRange<Date>, y: ClosedRange<Double>) {
    let peak = history.map { max($0.power.cpuWatts, $0.power.gpuWatts, $0.power.aneWatts) }.max() ?? 0
    return (end.addingTimeInterval(-socHistoryWindow)...end, 0...max(peak, 1))
}

/// Menu: one compact card, the latest values above the three curves, no axes.
struct PowerGraph: View {
    let history: [SoCPowerPoint]
    var now = Date()
    var onScreen: (Bool) -> Void = { _ in }

    var body: some View {
        let latest = currentPower(history, now: now, maxAge: socMaxGap), scale = powerScale(history, now: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ForEach(Component.all, id: \.name) { c in
                    HStack(spacing: 4) {
                        c.key(width: 10)
                        Text(c.caption(latest, short: true)).monospacedDigit()
                    }
                }
            }
            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Chart { powerCurves(history, lineWidth: 1.5) }
                .chartXScale(domain: scale.x)
                .chartYScale(domain: scale.y)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 34)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Power by component"))
        .accessibilityValue(Component.all.map { $0.caption(latest) }.joined(separator: ", "))
        .modifier(OnScreen(report: onScreen))
    }
}

/// Dashboard: the three components on one axis in W, with the latest values in the legend.
struct PowerChart: View {
    let history: [SoCPowerPoint]
    var now = Date()
    var onScreen: (Bool) -> Void = { _ in }

    var body: some View {
        let latest = currentPower(history, now: now, maxAge: socMaxGap), scale = powerScale(history, now: now)
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Power by component")).font(.caption).foregroundStyle(.secondary)
            legend(latest)
            Chart { powerCurves(history, lineWidth: 2) }
                .chartXScale(domain: scale.x)
                .chartYScale(domain: scale.y)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine()
                        AxisValueLabel { if let y = v.as(Double.self) { Text(number(y, decimals: y != y.rounded() ? 1 : 0) + " W") } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: Date.FormatStyle(locale: appLocale).hour().minute())
                    }
                }
                .chartLegend(.hidden)
                .environment(\.locale, appLocale)
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("Power by component"))
                .accessibilityValue(Component.all.map { $0.caption(latest) }.joined(separator: ", "))
        }
        .modifier(OnScreen(report: onScreen))
    }

    /// Line key and latest value of each component, in text ink: identity comes from the mark, never from colored text.
    func legend(_ p: SoCPower?) -> some View {
        HStack(spacing: 14) {
            ForEach(Component.all, id: \.name) { c in
                HStack(spacing: 5) {
                    c.key(width: 16)
                    Text(c.caption(p)).monospacedDigit()
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
