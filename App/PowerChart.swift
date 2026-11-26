import Charts
import SwiftUI

private struct PowerComponent {
    let name: String
    let color: Color
    let value: (SoCPower) -> Double
    var dashedBesidesColor = false
    var menuCaption: String? = nil

    static var all: [PowerComponent] {
        [PowerComponent(name: "CPU", color: .viz(light: 0x2a78d6, dark: 0x3987e5), value: \.cpuWatts),
         PowerComponent(name: "GPU", color: .viz(light: 0xeb6834, dark: 0xd95926), value: \.gpuWatts),
         PowerComponent(name: tr("Neural Engine"), color: .viz(light: 0x1f9e6a, dark: 0x2fb67e), value: \.aneWatts, dashedBesidesColor: true, menuCaption: "ANE")]
    }

    func caption(_ p: SoCPower?, inMenu: Bool = false) -> String {
        "\(inMenu ? menuCaption ?? name : name) " + (p.map { watts(value($0)) } ?? noPowerValueText)
    }

    func key(width: CGFloat) -> LineKey {
        LineKey(color: color, dash: dashedBesidesColor ? powerKeyDash : [], width: width)
    }
}

private func powerCurves(_ history: [SoCPowerPoint], lineWidth: CGFloat) -> some ChartContent {
    let segments = powerSegments(history)
    return ForEach(PowerComponent.all, id: \.name) { c in
        ForEach(history.indices, id: \.self) { i in
            let p = history[i]
            LineMark(x: .value(tr("Time"), p.date), y: .value(tr("Power"), c.value(p.averagePower)), series: .value("", "\(c.name) \(segments[i])"))
                .interpolationMethod(.monotone)
                .foregroundStyle(c.color)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: c.dashedBesidesColor ? chartCurveDash : []))
        }
    }
}

private func powerScale(_ history: [SoCPowerPoint], endingAtArrival arrival: Date) -> (x: ClosedRange<Date>, y: ClosedRange<Double>) {
    let peak = history.map { max($0.averagePower.cpuWatts, $0.averagePower.gpuWatts, $0.averagePower.aneWatts) }.max() ?? 0
    return (arrival.addingTimeInterval(-socHistoryRetention)...arrival, 0...max(peak, minimumPowerScalePeakWatts))
}

struct PowerGraph: View {
    let history: [SoCPowerPoint]
    var receivedAt = Date()

    var body: some View {
        let latest = currentPower(history, now: receivedAt), scale = powerScale(history, endingAtArrival: receivedAt)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ForEach(PowerComponent.all, id: \.name) { c in
                    HStack(spacing: 4) {
                        c.key(width: 10)
                        Text(c.caption(latest, inMenu: true)).monospacedDigit()
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
        .chartAsSingleAccessibilityElement(label: tr("Power by component"), value: PowerComponent.all.map { $0.caption(latest) }.joined(separator: ", "))
    }
}

struct PowerChart: View {
    let history: [SoCPowerPoint]
    var receivedAt = Date()

    var body: some View {
        let latest = currentPower(history, now: receivedAt), scale = powerScale(history, endingAtArrival: receivedAt)
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
                .chartAsSingleAccessibilityElement(label: tr("Power by component"), value: PowerComponent.all.map { $0.caption(latest) }.joined(separator: ", "))
        }
    }

    func legend(_ p: SoCPower?) -> some View {
        HStack(spacing: 14) {
            ForEach(PowerComponent.all, id: \.name) { c in
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
