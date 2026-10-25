import SwiftUI

/// Sankey-style power flow: sources (adapter, battery) on the left, consumers (MacBook, battery) on the right.
struct PowerFlow: View {
    let s: Status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Node { let name: String; let icon: String; let watts: Double; let color: Color }

    var sources: [Node] {
        var n: [Node] = []
        if s.adapter && s.adapterWatts > 0.1 { n.append(Node(name: "Adaptateur", icon: "bolt.fill", watts: s.adapterWatts, color: .yellow)) }
        if s.batteryWatts < -0.1 { n.append(Node(name: "Batterie", icon: "battery.50percent", watts: -s.batteryWatts, color: .orange)) }
        return n
    }

    var sinks: [Node] {
        var n = [Node(name: "MacBook", icon: "laptopcomputer", watts: max(s.systemWatts, 0.1), color: .blue)]
        if s.batteryWatts > 0.1 { n.append(Node(name: "Batterie", icon: "battery.100percent.bolt", watts: s.batteryWatts, color: .green)) }
        return n
    }

    /// Adapter connected but the battery still supplies power we didn't ask for.
    var underpowered: Bool {
        let ours = s.runtime.state == .discharging || s.runtime.calibration == .dischargeTo10 || s.runtime.calibration == .returnToLimit
        return s.adapter && s.batteryWatts < -0.5 && !ours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Flux de puissance").font(.caption).foregroundStyle(.secondary)
            TimelineView(.animation(paused: reduceMotion)) { tl in
                Canvas { ctx, size in draw(&ctx, size, phase: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate) }
            }
            if underpowered {
                Label("Adaptateur trop faible : la batterie complète \(String(format: "%.1f W", -s.batteryWatts))\(s.adapterRatedWatts.map { " (adaptateur \($0) W)" } ?? "")",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, phase: Double) {
        let src = sources, dst = sinks
        guard !src.isEmpty else { return }
        let label: CGFloat = 92, bar: CGFloat = 5, gap: CGFloat = 6
        let total = max(src.map(\.watts).reduce(0, +), dst.map(\.watts).reduce(0, +))
        let scale = (size.height - gap * CGFloat(max(src.count, dst.count) - 1)) / total
        let x0 = label, x1 = size.width - label

        func layout(_ nodes: [Node]) -> [CGFloat] {
            var y: CGFloat = 0
            return nodes.map { let top = y; y += CGFloat($0.watts) * scale + gap; return top }
        }
        let ys = layout(src), yd = layout(dst)
        var offS = ys, offD = yd

        // Greedy pairing of source watts into sink watts, stacked in order.
        var remS = src.map(\.watts), remD = dst.map(\.watts)
        var i = 0, j = 0
        while i < src.count && j < dst.count {
            let w = min(remS[i], remD[j])
            let h = CGFloat(w) * scale
            if h > 0.5 {
                let a = offS[i], b = offD[j]
                var band = Path()
                band.move(to: CGPoint(x: x0 + bar, y: a))
                band.addCurve(to: CGPoint(x: x1 - bar, y: b), control1: CGPoint(x: (x0 + x1) / 2, y: a), control2: CGPoint(x: (x0 + x1) / 2, y: b))
                band.addLine(to: CGPoint(x: x1 - bar, y: b + h))
                band.addCurve(to: CGPoint(x: x0 + bar, y: a + h), control1: CGPoint(x: (x0 + x1) / 2, y: b + h), control2: CGPoint(x: (x0 + x1) / 2, y: a + h))
                band.closeSubpath()
                ctx.fill(band, with: .linearGradient(Gradient(colors: [src[i].color.opacity(0.45), dst[j].color.opacity(0.45)]),
                                                     startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
                // Moving dashes along the band's centre line show the direction of flow.
                var mid = Path()
                mid.move(to: CGPoint(x: x0 + bar, y: a + h / 2))
                mid.addCurve(to: CGPoint(x: x1 - bar, y: b + h / 2), control1: CGPoint(x: (x0 + x1) / 2, y: a + h / 2), control2: CGPoint(x: (x0 + x1) / 2, y: b + h / 2))
                ctx.stroke(mid, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(1, h * 0.5), lineCap: .round, dash: [2, 12], dashPhase: -CGFloat(phase * 24)))
            }
            offS[i] += h; offD[j] += h
            remS[i] -= w; remD[j] -= w
            if remS[i] <= 0.01 { i += 1 }
            if remD[j] <= 0.01 { j += 1 }
        }

        func nodes(_ list: [Node], _ tops: [CGFloat], x: CGFloat, left: Bool) {
            for (n, top) in zip(list, tops) {
                let h = max(CGFloat(n.watts) * scale, 2)
                ctx.fill(Path(roundedRect: CGRect(x: left ? x : x - bar, y: top, width: bar, height: h), cornerRadius: 2), with: .color(n.color))
                let text = Text("\(Image(systemName: n.icon)) \(String(format: "%.1f W", n.watts))").font(.caption.monospacedDigit())
                ctx.draw(text, at: CGPoint(x: left ? x - 6 : x + 6, y: top + h / 2), anchor: left ? .trailing : .leading)
            }
        }
        nodes(src, ys, x: x0, left: true)
        nodes(dst, yd, x: x1, left: false)
    }
}

struct DashboardView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("flowInMenu") private var flowInMenu = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let s = m.status {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("\(s.percent) %").font(.system(size: 40, weight: .semibold))
                    VStack(alignment: .leading) {
                        Text(s.runtime.state.label).font(.headline)
                        Text("Matériel \(s.hardwarePercent.map { "\($0) %" } ?? "--") · \(s.temperature.map { String(format: "%.1f °C", $0) } ?? "--") · Limite \(s.config.limit) %")
                            .foregroundStyle(.secondary)
                    }
                }
                PowerFlow(s: s).frame(height: 220)
            } else {
                Text(m.error ?? "Connexion…").foregroundStyle(.secondary)
            }
            Toggle("Afficher dans le menu", isOn: $flowInMenu)
        }
        .padding(20)
        .frame(width: 560)
    }
}
