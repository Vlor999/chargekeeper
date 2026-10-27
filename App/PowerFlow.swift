import SwiftUI

/// Sankey-style power flow: sources (adapter, battery) on the left, consumers (MacBook, battery) on the right.
struct PowerFlow: View {
    let s: Status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    struct Node { let name: String; let icon: String; let watts: Double; let color: Color; var detail: String? = nil }

    var sources: [Node] {
        var n: [Node] = []
        if s.adapter && s.adapterWatts > 0.1 { n.append(Node(name: tr("Adapter"), icon: "bolt.fill", watts: s.adapterWatts, color: .yellow)) }
        if s.batteryWatts < -0.1 { n.append(Node(name: tr("Battery"), icon: "battery.50percent", watts: -s.batteryWatts, color: .orange)) }
        // Right after wake the gauge can report 0 W for a while: show the obvious source with the Mac's load.
        if n.isEmpty {
            n.append(s.adapter ? Node(name: tr("Adapter"), icon: "bolt.fill", watts: max(s.systemWatts, 0.1), color: .yellow)
                               : Node(name: tr("Battery"), icon: "battery.50percent", watts: max(s.systemWatts, 0.1), color: .orange))
        }
        return n
    }

    var sinks: [Node] {
        let ports = (s.ports ?? []).filter { $0.watts > 0.1 }
        var n = [Node(name: "MacBook", icon: "laptopcomputer", watts: max(macWatts(system: s.systemWatts, ports: ports.map(\.watts)), 0.1), color: .blue)]
        n += ports.map { Node(name: $0.name ?? "USB-C", icon: deviceIcon($0.name), watts: $0.watts, color: .purple, detail: $0.name) }
        if s.batteryWatts > 0.1 { n.append(Node(name: tr("Battery"), icon: "battery.100percent.bolt", watts: s.batteryWatts, color: .green)) }
        return n
    }

    static func spoken(_ n: Node) -> String { "\(n.name) \(String(format: "%.1f W", n.watts))" }

    /// Adapter connected but the battery still supplies power we didn't ask for.
    var underpowered: Bool {
        let ours = s.runtime.state == .discharging || s.runtime.calibration == .dischargeTo10 || s.runtime.calibration == .returnToLimit
        return s.adapter && s.batteryWatts < -0.5 && !ours
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Power flow")).font(.caption).foregroundStyle(.secondary)
            // 30 fps, and only while on screen: a hidden menu must not keep redrawing.
            // The timeline is created on appear rather than un-paused: SwiftUI doesn't restart a paused one.
            Group {
                if shown && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                        Canvas { ctx, size in draw(&ctx, size, phase: tl.date.timeIntervalSinceReferenceDate) }
                    }
                } else {
                    Canvas { ctx, size in draw(&ctx, size, phase: 0) }
                }
            }
            .background(WindowVisibility { shown = $0 })
            .accessibilityElement()
            .accessibilityLabel(sources.map(Self.spoken).joined(separator: ", ") + " → " + sinks.map(Self.spoken).joined(separator: ", "))
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
        // ponytail: device names only fit in the wide dashboard; the menu tells ports apart by icon only.
        let named = size.width > 400 && dst.contains { $0.detail != nil }
        let label: CGFloat = 92, bar: CGFloat = 5, gap: CGFloat = 6
        let x0 = label, x1 = size.width - (named ? 170 : label)
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
                // A soft bright crest travels from source to consumer every 1.4 s, clipped to the band.
                // Position from the clock modulo the period: no state, and no Float precision loss.
                let crest = CGFloat((phase / 1.4).truncatingRemainder(dividingBy: 1)) * 1.3 - 0.15
                let x = x0 + (x1 - x0) * crest, w = (x1 - x0) * 0.25
                var g = ctx
                g.clip(to: band)
                g.fill(Path(CGRect(x: x - w, y: 0, width: 2 * w, height: size.height)),
                       with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                              .init(color: .white.opacity(0.6), location: 0.5),
                                                              .init(color: .white.opacity(0), location: 1)]),
                                             startPoint: CGPoint(x: x - w, y: 0), endPoint: CGPoint(x: x + w, y: 0)))
            }
            offS[i] += ha; offD[j] += hb
            remS[i] -= w; remD[j] -= w
            if remS[i] <= 1e-6 { i += 1 }
            if remD[j] <= 1e-6 { j += 1 }
        }

        func nodes(_ list: [Node], _ f: [Double], _ tops: [CGFloat], _ side: CGFloat, x: CGFloat, left: Bool) {
            let hs = zip(f, tops).map { max(CGFloat($0.0) * side, 2) }
            // Thin bands sit closer than a caption line: spread the labels so they don't overlap.
            let ys = spreadLabels(zip(tops, hs).map { Double($0 + $1 / 2) }, gap: 14, height: Double(size.height))
            for (((n, top), h), y) in zip(zip(zip(list, tops), hs), ys) {
                ctx.fill(Path(roundedRect: CGRect(x: left ? x : x - bar, y: top, width: bar, height: h), cornerRadius: 2), with: .color(n.color))
                let watts = Text("\(Image(systemName: n.icon)) \(String(format: "%.1f W", n.watts))").font(.caption.monospacedDigit())
                // ponytail: character cap sized for the 170 pt reserve, not measured.
                let detail = (named ? n.detail : nil).map { Text("  \($0.count > 21 ? $0.prefix(20) + "…" : $0)").font(.caption).foregroundStyle(.secondary) }
                ctx.draw(detail.map { Text("\(watts)\($0)") } ?? watts, at: CGPoint(x: left ? x - 6 : x + 6, y: CGFloat(y)), anchor: left ? .trailing : .leading)
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
                HStack(alignment: .center, spacing: 16) {
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
        .onAppear { m.visible += 1 }
        .onDisappear { m.visible -= 1 }
    }
}

/// Reports whether the hosting window is actually on screen. onAppear/onDisappear aren't enough:
/// a closed menu bar window is only ordered out, and its views keep running.
struct WindowVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { Probe(onChange) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        let onChange: (Bool) -> Void
        private var token: NSObjectProtocol?
        private weak var observed: NSWindow?
        private var last: Bool?
        init(_ onChange: @escaping (Bool) -> Void) { self.onChange = onChange; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }

        // SwiftUI re-attaches this view often; only react when the window itself changes.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Detached for a moment while SwiftUI swaps views: keep the current window and state.
            guard let window, window !== observed else { return }
            if let token { NotificationCenter.default.removeObserver(token) }
            observed = window
            token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                self?.report()
            }
            report()
        }

        private func report() {
            let visible = observed?.occlusionState.contains(.visible) ?? false
            guard visible != last else { return }
            last = visible
            DispatchQueue.main.async { self.onChange(visible) }
        }
    }
}
