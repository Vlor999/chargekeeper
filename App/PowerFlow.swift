import SwiftUI

/// Sankey-style power flow: sources (adapter, battery) on the left, consumers (MacBook, battery) on the right.
struct PowerFlow: View {
    let s: Status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Node { let name: String; let icon: String; let watts: Double; let color: Color }

    var sources: [Node] {
        var n: [Node] = []
        if s.adapter && s.adapterWatts > 0.1 { n.append(Node(name: "Adapter", icon: "bolt.fill", watts: s.adapterWatts, color: .yellow)) }
        if s.batteryWatts < -0.1 { n.append(Node(name: "Battery", icon: "battery.50percent", watts: -s.batteryWatts, color: .orange)) }
        return n
    }

    var sinks: [Node] {
        var n = [Node(name: "MacBook", icon: "laptopcomputer", watts: max(s.systemWatts, 0.1), color: .blue)]
        if s.batteryWatts > 0.1 { n.append(Node(name: "Battery", icon: "battery.100percent.bolt", watts: s.batteryWatts, color: .green)) }
        return n
    }

    /// Adapter connected but the battery still supplies power we didn't ask for.
    var underpowered: Bool {
        let ours = s.runtime.state == .discharging || s.runtime.calibration == .dischargeTo10 || s.runtime.calibration == .returnToLimit
        return s.adapter && s.batteryWatts < -0.5 && !ours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Power flow")).font(.caption).foregroundStyle(.secondary)
            TimelineView(.animation(paused: reduceMotion)) { tl in
                Canvas { ctx, size in draw(&ctx, size, phase: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate) }
            }
            if underpowered {
                Label(tr("Adapter too weak: the battery supplies %@", String(format: "%.1f W", -s.batteryWatts)) + (s.adapterRatedWatts.map { tr(" (adapter %d W)", $0) } ?? ""),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, phase: Double) {
        let src = sources, dst = sinks
        guard !src.isEmpty else { return }
        let label: CGFloat = 92, bar: CGFloat = 5, gap: CGFloat = 6
        let x0 = label, x1 = size.width - label
        // Each side fills the full height: sources and consumers are measured by different sensors
        // and rarely sum to the same watts, so bands are shares of their side, labels keep real watts.
        func shares(_ nodes: [Node]) -> [Double] { let t = nodes.map(\.watts).reduce(0, +); return nodes.map { $0.watts / t } }
        let fs = shares(src), fd = shares(dst)
        let hs = size.height - gap * CGFloat(src.count - 1), hd = size.height - gap * CGFloat(dst.count - 1)
        func layout(_ f: [Double], _ h: CGFloat) -> [CGFloat] {
            var y: CGFloat = 0
            return f.map { let top = y; y += CGFloat($0) * h + gap; return top }
        }
        let ys = layout(fs, hs), yd = layout(fd, hd)
        var offS = ys, offD = yd

        // Greedy pairing of source shares into consumer shares, stacked in order.
        var remS = fs, remD = fd
        var i = 0, j = 0
        while i < src.count && j < dst.count {
            let w = min(remS[i], remD[j])
            let ha = CGFloat(w) * hs, hb = CGFloat(w) * hd
            if ha > 0.5 {
                let a = offS[i], b = offD[j]
                var band = Path()
                band.move(to: CGPoint(x: x0 + bar, y: a))
                band.addCurve(to: CGPoint(x: x1 - bar, y: b), control1: CGPoint(x: (x0 + x1) / 2, y: a), control2: CGPoint(x: (x0 + x1) / 2, y: b))
                band.addLine(to: CGPoint(x: x1 - bar, y: b + hb))
                band.addCurve(to: CGPoint(x: x0 + bar, y: a + ha), control1: CGPoint(x: (x0 + x1) / 2, y: b + hb), control2: CGPoint(x: (x0 + x1) / 2, y: a + ha))
                band.closeSubpath()
                ctx.fill(band, with: .linearGradient(Gradient(colors: [src[i].color.opacity(0.45), dst[j].color.opacity(0.45)]),
                                                     startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
                // Thin moving dashes, one every ~10 pt across the band, show the direction of flow.
                let lines = max(1, Int(ha / 10))
                for k in 0..<lines {
                    let f = (CGFloat(k) + 0.5) / CGFloat(lines)
                    var p = Path()
                    p.move(to: CGPoint(x: x0 + bar, y: a + ha * f))
                    p.addCurve(to: CGPoint(x: x1 - bar, y: b + hb * f), control1: CGPoint(x: (x0 + x1) / 2, y: a + ha * f), control2: CGPoint(x: (x0 + x1) / 2, y: b + hb * f))
                    ctx.stroke(p, with: .color(.white.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .butt, dash: [8, 10], dashPhase: -CGFloat(phase * 24 + Double(k) * 6)))
                }
            }
            offS[i] += ha; offD[j] += hb
            remS[i] -= w; remD[j] -= w
            if remS[i] <= 1e-6 { i += 1 }
            if remD[j] <= 1e-6 { j += 1 }
        }

        func nodes(_ list: [Node], _ f: [Double], _ tops: [CGFloat], _ side: CGFloat, x: CGFloat, left: Bool) {
            for ((n, share), top) in zip(zip(list, f), tops) {
                let h = max(CGFloat(share) * side, 2)
                ctx.fill(Path(roundedRect: CGRect(x: left ? x : x - bar, y: top, width: bar, height: h), cornerRadius: 2), with: .color(n.color))
                let text = Text("\(Image(systemName: n.icon)) \(String(format: "%.1f W", n.watts))").font(.caption.monospacedDigit())
                ctx.draw(text, at: CGPoint(x: left ? x - 6 : x + 6, y: top + h / 2), anchor: left ? .trailing : .leading)
            }
        }
        nodes(src, fs, ys, hs, x: x0, left: true)
        nodes(dst, fd, yd, hd, x: x1, left: false)
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
                        Text(tr("Hardware %@ · %@ · Limit %d %%", s.hardwarePercent.map { "\($0) %" } ?? "--", s.temperature.map { String(format: "%.1f °C", $0) } ?? "--", s.config.limit))
                            .foregroundStyle(.secondary)
                    }
                }
                PowerFlow(s: s).frame(height: 220)
            } else {
                Text(m.error ?? tr("Connecting…")).foregroundStyle(.secondary)
            }
            Toggle(tr("Show in menu"), isOn: $flowInMenu)
        }
        .padding(20)
        .frame(width: 560)
    }
}
