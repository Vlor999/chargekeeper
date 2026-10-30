import Charts
import SwiftUI

/// Battery health over time. The series comes from one request when the Battery pane opens, not from the periodic status.
struct HealthChartSection: View {
    let series: [HealthSample]
    @AppStorage("healthRange") private var range = HealthRange.year
    @State private var hovered: Date?

    private static let raw = Color.viz(light: 0x2a78d6, dark: 0x3987e5)
    private static let nominal = Color.viz(light: 0xeb6834, dark: 0xd95926)
    private static let surface = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        let shown = series.filter { $0.date >= healthRangeStart(range, now: Date()) }
        Section(tr("Health over time")) {
            if series.count >= 2 {
                Picker(tr("Period"), selection: $range) {
                    ForEach(HealthRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if shown.count < 2 {
                Text(tr("Not enough data yet: one point is recorded per day."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    legend(nominal: shown.contains { $0.nominalCapacity != nil }, calibrations: shown.contains { $0.calibration == true })
                    chart(shown)
                    if let c = healthChange(shown) {
                        Text(summary(c)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func chart(_ shown: [HealthSample]) -> some View {
        let focus = hovered.flatMap { h in shown.min { abs($0.date.timeIntervalSince(h)) < abs($1.date.timeIntervalSince(h)) } }
        return Chart {
            ForEach(shown, id: \.date) { s in
                LineMark(x: .value(tr("Date"), s.date), y: .value(tr("Health"), s.health), series: .value("", "raw"))
                    .foregroundStyle(Self.raw)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(day(s.date))
                    .accessibilityValue(tr("Health") + " " + percent(s.health))
                if let n = s.nominalHealth {
                    LineMark(x: .value(tr("Date"), s.date), y: .value(tr("Health (nominal)"), n), series: .value("", "nominal"))
                        .foregroundStyle(Self.nominal)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .accessibilityLabel(day(s.date))
                        .accessibilityValue(tr("Health (nominal)") + " " + percent(n))
                }
            }
            // Calibration results: a dot on the health line, ringed with the surface so it stays legible on the line.
            ForEach(shown.filter { $0.calibration == true }, id: \.date) { s in
                PointMark(x: .value(tr("Date"), s.date), y: .value(tr("Health"), s.health))
                    .symbolSize(160).foregroundStyle(Self.surface)
                    .accessibilityHidden(true)
                PointMark(x: .value(tr("Date"), s.date), y: .value(tr("Health"), s.health))
                    .symbolSize(64).foregroundStyle(Self.raw)
                    .accessibilityLabel(tr("Calibration") + ", " + day(s.date))
                    .accessibilityValue(percent(s.health))
            }
            if let f = focus {
                RuleMark(x: .value(tr("Date"), f.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { tooltip(f) }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { Text(number(y) + " %") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle(locale: appLocale).month(.abbreviated).year(.twoDigits))
            }
        }
        .chartXSelection(value: $hovered)
        .chartLegend(.hidden)
        .environment(\.locale, appLocale)
        .frame(height: 170)
    }

    func tooltip(_ s: HealthSample) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day(s.date)).font(.caption.weight(.semibold))
            key(Self.raw, tr("Health") + " " + percent(s.health))
            if let n = s.nominalHealth { key(Self.nominal, tr("Health (nominal)") + " " + percent(n)) }
            if let c = s.cycleCount { Text(tr("Cycle count") + " " + String(c)).font(.caption).foregroundStyle(.secondary) }
            if s.calibration == true { Text(tr("Calibration")).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    func legend(nominal: Bool, calibrations: Bool) -> some View {
        HStack(spacing: 14) {
            key(Self.raw, tr("Health"))
            if nominal { key(Self.nominal, tr("Health (nominal)")) }
            if calibrations {
                HStack(spacing: 5) {
                    Circle().fill(Self.raw).frame(width: 8, height: 8).padding(2).background(Circle().fill(Self.surface))
                    Text(tr("Calibration"))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Short line key beside text in text ink: identity comes from the mark, never from colored text.
    func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 2)
            Text(label).monospacedDigit()
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    /// "−1.2 points in 3 months, +14 cycles".
    func summary(_ c: HealthChange) -> String {
        let span = healthSpan(days: c.days)
        let period: String
        switch span.unit {
        case .days: period = span.value == 1 ? tr("1 day") : tr("%d days", span.value)
        case .months: period = tr("%d months", span.value)
        case .years: period = span.value == 1 ? tr("1 year") : tr("%d years", span.value)
        }
        let text = tr("%@ points in %@", signed(c.points), period)
        guard let n = c.cycles else { return text }
        return text + ", " + (n == 0 ? tr("no new cycle") : n == 1 ? tr("+1 cycle") : tr("+%d cycles", n))
    }

    func signed(_ v: Double) -> String {
        let s = number(abs(v), decimals: 1)
        guard s != number(0, decimals: 1) else { return s }
        return (v < 0 ? "\u{2212}" : "+") + s
    }

    func percent(_ v: Double) -> String { number(v, decimals: 1) + "\u{00A0}%" }
    func day(_ d: Date) -> String { d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(appLocale)) }
}

extension HealthRange {
    var label: String {
        switch self {
        case .threeMonths: return tr("3 months")
        case .year: return tr("1 year")
        case .all: return tr("All")
        }
    }
}

private extension Color {
    /// Chart color stepped separately for light and dark mode.
    static func viz(light: UInt32, dark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light) })
    }
}
