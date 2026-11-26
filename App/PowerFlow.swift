import SwiftUI

struct PowerFlow: View {
    enum Presentation { case live, helpSample }

    let s: Status
    var presentation = Presentation.live
    @State private var help = false

    struct Node { let name: String; let icon: String; let watts: Double; let color: Color; var detail: String? = nil; var max: Double? = nil }

    var sources: [Node] {
        var n: [Node] = []
        if s.adapter && s.adapterWatts > 0.1 { n.append(Node(name: tr("Adapter"), icon: "bolt.fill", watts: s.adapterWatts, color: .yellow)) }
        if s.batteryWatts < -0.1 { n.append(Node(name: tr("Battery"), icon: "battery.50percent", watts: -s.batteryWatts, color: .orange)) }
        return n.isEmpty ? [sourceWhileGaugeReadsZero] : n
    }

    private var sourceWhileGaugeReadsZero: Node {
        s.adapter ? Node(name: tr("Adapter"), icon: "bolt.fill", watts: max(s.systemWatts, 0.1), color: .yellow)
                  : Node(name: tr("Battery"), icon: "battery.50percent", watts: max(s.systemWatts, 0.1), color: .orange)
    }

    var sinks: [Node] {
        let ports = (s.ports ?? []).filter { $0.watts > 0.1 }
        var n = [Node(name: "MacBook", icon: "laptopcomputer", watts: max(macWatts(system: s.systemWatts, ports: ports.map(\.watts)), 0.1), color: .blue)]
        n += ports.map { Node(name: $0.name ?? "USB-C", icon: deviceIcon($0.name), watts: $0.watts, color: .purple, detail: $0.name, max: $0.maxWatts) }
        if s.batteryWatts > 0.1 { n.append(Node(name: tr("Battery"), icon: "battery.100percent.bolt", watts: s.batteryWatts, color: .green)) }
        return n
    }

    static func spoken(_ n: Node) -> String { "\(n.name) \(watts(n.watts))" }

    var devicesChargingFromMacSuffix: String {
        let ports = (s.ports ?? []).filter { $0.watts > 0.5 }
        return ports.isEmpty ? "" : tr(" · charging from the Mac: %@", ports.map { "\($0.name ?? "USB-C") \(watts($0.watts))" }.joined(separator: ", "))
    }

    var batteryCoversAdapterShortfall: Bool {
        let dischargeRequested = s.runtime.state == .discharging || s.runtime.calibration == .dischargeTo10 || s.runtime.calibration == .returnToLimit
        return s.adapter && s.batteryWatts < -0.5 && !dischargeRequested
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if presentation == .live {
                HStack(spacing: 4) {
                    Text(tr("Power flow"))
                    Button { help.toggle() } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("How to read the power flow"))
                        .popover(isPresented: $help, arrowEdge: .bottom) { FlowHelp() }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            OnScreenAnimation { phase in
                Canvas { ctx, size in FlowCanvas(ctx: ctx, size: size, phase: phase, sources: sources, sinks: sinks).draw() }
            }
            .accessibilityElement()
            .accessibilityLabel(sources.map(Self.spoken).joined(separator: ", ") + " → " + sinks.map(Self.spoken).joined(separator: ", "))
            if batteryCoversAdapterShortfall {
                Label(tr("Adapter too weak: the battery supplies %@", watts(-s.batteryWatts)) + (s.adapterRatedWatts.map { tr(" (adapter %d W)", $0) } ?? "") + devicesChargingFromMacSuffix,
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct OnScreenAnimation<Content: View>: View {
    let content: (_ phaseSeconds: Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false

    var body: some View {
        Group {
            // exception: SwiftUI does not restart a paused TimelineView, so the timeline is created when the window comes on screen instead of un-paused (https://github.com/Vlor999/chargekeeper/commit/ff585d82fedc34fcd0d1ae6805f71261d6fd59f7)
            if onScreen && !reduceMotion {
                TimelineView(.animation(minimumInterval: animationFrameIntervalSeconds)) { tl in content(tl.date.timeIntervalSinceReferenceDate) }
            } else {
                content(0)
            }
        }
        .background(WindowVisibility { onScreen = $0 })
    }
}

private struct FlowSide {
    let nodes: [PowerFlow.Node]
    let sharesOfSide: [Double]
    let height: CGFloat
    let tops: [CGFloat]

    init(_ nodes: [PowerFlow.Node], totalHeight: CGFloat, gap: CGFloat) {
        self.nodes = nodes
        let total = nodes.map(\.watts).reduce(0, +)
        let shares = nodes.map { $0.watts / total }
        let sideHeight = totalHeight - gap * CGFloat(nodes.count - 1)
        var y: CGFloat = 0
        sharesOfSide = shares
        height = sideHeight
        tops = shares.map { let top = y; y += CGFloat($0) * sideHeight + gap; return top }
    }
}

private struct FlowCanvas {
    let ctx: GraphicsContext
    let size: CGSize
    let phase: Double
    let sources: [PowerFlow.Node]
    let sinks: [PowerFlow.Node]
    let showsDeviceNames: Bool
    let x0: CGFloat
    let x1: CGFloat
    let bar: CGFloat = 5
    let gap: CGFloat = 6

    init(ctx: GraphicsContext, size: CGSize, phase: Double, sources: [PowerFlow.Node], sinks: [PowerFlow.Node]) {
        self.ctx = ctx
        self.size = size
        self.phase = phase
        self.sources = sources
        self.sinks = sinks
        let labelColumn: CGFloat = 92
        showsDeviceNames = size.width > flowDeviceNamesMinWidthPoints && sinks.contains { $0.detail != nil }
        x0 = labelColumn
        x1 = size.width - (showsDeviceNames ? flowNamedSinkLabelColumnPoints : labelColumn)
    }

    var isAnimated: Bool { phase > 0 }

    func draw() {
        guard !sources.isEmpty else { return }
        let src = FlowSide(sources, totalHeight: size.height, gap: gap), dst = FlowSide(sinks, totalHeight: size.height, gap: gap)
        drawBandsPairedInOrder(from: src, to: dst)
        drawNodes(src, x: x0, left: true)
        drawNodes(dst, x: x1, left: false)
    }

    private func drawBandsPairedInOrder(from src: FlowSide, to dst: FlowSide) {
        var offS = src.tops, offD = dst.tops
        var remS = src.sharesOfSide, remD = dst.sharesOfSide
        var i = 0, j = 0
        while i < src.nodes.count && j < dst.nodes.count {
            let w = min(remS[i], remD[j])
            let ha = CGFloat(w) * src.height, hb = CGFloat(w) * dst.height
            if ha > 0.5 {
                let band = bandPath(fromTop: offS[i], fromHeight: ha, toTop: offD[j], toHeight: hb)
                ctx.fill(band, with: .linearGradient(Gradient(colors: [src.nodes[i].color.opacity(0.45), dst.nodes[j].color.opacity(0.45)]),
                                                     startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
                drawCrest(in: band)
            }
            offS[i] += ha; offD[j] += hb
            remS[i] -= w; remD[j] -= w
            if remS[i] <= 1e-6 { i += 1 }
            if remD[j] <= 1e-6 { j += 1 }
        }
    }

    private func bandPath(fromTop a: CGFloat, fromHeight ha: CGFloat, toTop b: CGFloat, toHeight hb: CGFloat) -> Path {
        var band = Path()
        band.move(to: CGPoint(x: x0 + bar, y: a))
        band.addCurve(to: CGPoint(x: x1 - bar, y: b), control1: CGPoint(x: (x0 + x1) / 2, y: a), control2: CGPoint(x: (x0 + x1) / 2, y: b))
        band.addLine(to: CGPoint(x: x1 - bar, y: b + hb))
        band.addCurve(to: CGPoint(x: x0 + bar, y: a + ha), control1: CGPoint(x: (x0 + x1) / 2, y: b + hb), control2: CGPoint(x: (x0 + x1) / 2, y: a + ha))
        band.closeSubpath()
        return band
    }

    private func drawCrest(in band: Path) {
        let cycleProgress = (phase / flowCrestPeriodSeconds).truncatingRemainder(dividingBy: 1)
        let crest = CGFloat(cycleProgress) * flowCrestTravelRatio + flowCrestStartRatio
        let x = x0 + (x1 - x0) * crest, w = (x1 - x0) * flowCrestHalfWidthRatio
        var g = ctx
        g.clip(to: band)
        g.fill(Path(CGRect(x: x - w, y: 0, width: 2 * w, height: size.height)),
               with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                      .init(color: .white.opacity(0.6), location: 0.5),
                                                      .init(color: .white.opacity(0), location: 1)]),
                                     startPoint: CGPoint(x: x - w, y: 0), endPoint: CGPoint(x: x + w, y: 0)))
    }

    private func drawNodes(_ side: FlowSide, x: CGFloat, left: Bool) {
        let heights = zip(side.sharesOfSide, side.tops).map { max(CGFloat($0.0) * side.height, 2) }
        let ys = spreadLabels(zip(side.tops, heights).map { Double($0 + $1 / 2) }, gap: flowCaptionLineHeightPoints, height: Double(size.height))
        for (((n, top), h), y) in zip(zip(zip(side.nodes, side.tops), heights), ys) {
            ctx.fill(Path(roundedRect: CGRect(x: left ? x : x - bar, y: top, width: bar, height: h), cornerRadius: 2), with: .color(n.color))
            let wattsText = Text("\(Image(systemName: n.icon)) \(number(n.watts, decimals: 1))\(portCeilingText(n)) W").font(.caption.monospacedDigit())
            let at = CGPoint(x: left ? x - 6 : x + 6, y: CGFloat(y))
            let resolved = ctx.resolve(wattsText)
            ctx.draw(resolved, at: at, anchor: left ? .trailing : .leading)
            if showsDeviceNames, let d = n.detail { drawDeviceName(d, x: at.x + resolved.measure(in: size).width + 8, y: at.y) }
        }
    }

    private func portCeilingText(_ n: PowerFlow.Node) -> String {
        guard showsDeviceNames, let ceiling = n.max else { return "" }
        return " / " + number(ceiling, decimals: ceiling == ceiling.rounded() ? 0 : 1)
    }

    private func captionText(_ s: String) -> GraphicsContext.ResolvedText {
        ctx.resolve(Text(s).font(.caption).foregroundStyle(.secondary))
    }

    private func drawDeviceName(_ s: String, x: CGFloat, y: CGFloat) {
        let name = captionText(s), room = size.width - x, w = name.measure(in: CGSize(width: .infinity, height: size.height)).width
        guard w > room else { return ctx.draw(name, at: CGPoint(x: x, y: y), anchor: .leading) }
        var g = ctx
        g.clip(to: Path(CGRect(x: x, y: 0, width: room, height: size.height)))
        if isAnimated {
            drawMarquee(name, width: w, in: g, x: x, y: y)
        } else {
            drawTruncated(s, room: room, in: g, x: x, y: y)
        }
    }

    private func drawTruncated(_ s: String, room: CGFloat, in g: GraphicsContext, x: CGFloat, y: CGFloat) {
        var n = s.count - 1, cut = captionText(s.prefix(n) + "…")
        while n > 1 && cut.measure(in: size).width > room { n -= 1; cut = captionText(s.prefix(n) + "…") }
        g.draw(cut, at: CGPoint(x: x, y: y), anchor: .leading)
    }

    private func drawMarquee(_ name: GraphicsContext.ResolvedText, width w: CGFloat, in g: GraphicsContext, x: CGFloat, y: CGFloat) {
        let cycle = flowMarqueePauseSeconds + Double(w + flowMarqueeSpacingPoints) / flowMarqueeSpeedPointsPerSecond
        let o = CGFloat(max(phase.truncatingRemainder(dividingBy: cycle) - flowMarqueePauseSeconds, 0) * flowMarqueeSpeedPointsPerSecond)
        g.draw(name, at: CGPoint(x: x - o, y: y), anchor: .leading)
        g.draw(name, at: CGPoint(x: x - o + w + flowMarqueeSpacingPoints, y: y), anchor: .leading)
    }
}

struct FlowHelp: View {
    static let landingPageSample = Status(config: Config(), runtime: Runtime(), percent: 50, hardwarePercent: nil, adapter: true, temperature: nil,
                               adapterWatts: 78, adapterRatedWatts: nil, systemWatts: 23, batteryWatts: 55,
                               ports: [PortPower(name: "iPhone", watts: 8, maxWatts: 15)], nativeLimit: true, sleepDisabled: false, history: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("How to read the power flow")).font(.headline)
            PowerFlow(s: Self.landingPageSample, presentation: .helpSample).frame(height: 90)
            Text(tr("Example: 78 W come in. 15 W run the Mac, 55 W charge the battery and 8 W charge an iPhone."))
                .font(.caption).foregroundStyle(.secondary)
            row("bolt.fill", tr("Left: where the power comes from. The adapter (or a display that charges the Mac), and the battery when it helps."))
            row("laptopcomputer", tr("Right: where it goes. The MacBook itself, the battery when it charges, and devices charging from the Mac's USB-C ports."))
            row("chart.bar.fill", tr("Each band is a share of its side. Each side has its own sensor, so the totals can differ by a few watts."))
            row("cable.connector", tr("13.3 / 15 W: what a device draws, out of the most its port can supply."))
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(width: 300)
    }

    func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).frame(width: 18)
            Text(text)
        }
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
                        Text(tr("Hardware %@ · %@ · Limit %d %%", s.hardwarePercent.map { "\($0) %" } ?? "--", celsius(s.temperature), s.config.limit))
                            .foregroundStyle(.secondary)
                    }
                }
                PowerFlow(s: s).frame(height: 220)
                if s.config.powerInterval != .off { PowerChart(history: m.lastKnownPowerHistory, receivedAt: m.powerHistoryReceivedAt) }
            } else {
                Text(m.error ?? tr("Connecting…")).foregroundStyle(.secondary)
            }
            Toggle(tr("Show in menu"), isOn: $flowInMenu)
        }
        .padding(20)
        .frame(width: 560)
        .countedWhileOnScreen(in: m)
    }
}

struct CountedWhileOnScreen: ViewModifier {
    final class Tally {
        var counted = false
        var disappeared = false
    }

    let model: AppModel
    @State private var tally = Tally()

    func body(content: Content) -> some View {
        content
            .background(WindowVisibility(onChange: count))
            .onAppear { tally.disappeared = false }
            .onDisappear {
                count(onScreen: false)
                tally.disappeared = true
            }
    }

    private func count(onScreen: Bool) {
        guard !tally.disappeared, onScreen != tally.counted else { return }
        tally.counted = onScreen
        model.openWindowCount += onScreen ? 1 : -1
    }
}

extension View {
    func countedWhileOnScreen(in model: AppModel) -> some View { modifier(CountedWhileOnScreen(model: model)) }
}

// exception: a closed MenuBarExtra window is only ordered out, so its views get no onDisappear and keep running; the window occlusion state tells whether it is on screen (https://github.com/Vlor999/chargekeeper/commit/ff585d82fedc34fcd0d1ae6805f71261d6fd59f7)
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
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
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
