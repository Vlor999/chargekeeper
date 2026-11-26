import Foundation

/// MacBook share of the system load once the USB-C ports are served.
// ponytail: SystemLoad includes port output on the one Mac checked; ports above the load mean it doesn't, so the load is kept whole.
func macWatts(system: Double, ports: [Double]) -> Double {
    let out = ports.reduce(0, +)
    return out <= system ? system - out : system
}

/// Component power history: appends the point and keeps the last `window` seconds before it.
func appendPowerPoint(_ history: [SoCPowerPoint], _ p: SoCPowerPoint, window: TimeInterval) -> [SoCPowerPoint] {
    (history + [p]).filter { p.date.timeIntervalSince($0.date) <= window && $0.date <= p.date }
}

/// powermetrics arguments for an interval, each a fixed string; nil when off (powermetrics not running).
func powermetricsArguments(_ i: PowerInterval) -> [String]? {
    let ms: String
    switch i {
    case .off: return nil
    case .s1: ms = "1000"
    case .s2: ms = "2000"
    case .s5: ms = "5000"
    case .s10: ms = "10000"
    case .s30: ms = "30000"
    }
    return ["--samplers", "cpu_power,gpu_power", "-i", ms, "-f", "plist"]
}

/// The app's refresh period while a window is open: `appMaxRefreshInterval`, or the power interval when shorter, so the graph
/// gets each point as it comes. Off: `appMaxRefreshInterval`.
func appRefreshInterval(_ i: PowerInterval) -> TimeInterval {
    i == .off ? appMaxRefreshInterval : min(appMaxRefreshInterval, TimeInterval(i.rawValue))
}

/// Longest normal wait for a point: `socStaleAfterIntervals` of its own sampling interval, so a point taken at 30 s stays
/// current as long as one taken at 1 s, relative to its interval.
func powerMaxGap(_ p: SoCPowerPoint) -> TimeInterval { socStaleAfterIntervals * p.effectiveSamplingInterval }

/// The newest power, unless it is older than its `powerMaxGap` at `now` (powermetrics stopped or the service is stuck).
func currentPower(_ history: [SoCPowerPoint], now: Date) -> SoCPower? {
    guard let p = history.last, now.timeIntervalSince(p.date) <= powerMaxGap(p) else { return nil }
    return p.averagePower
}

/// Longest gap from point `a` to the next point `b` that is still one curve. Same interval: `powerMaxGap`. Interval
/// change (powermetrics restarted): also the rest of the old interval, the new process's first sample and `socIntervalChangeSlack`.
func powerMaxGap(from a: SoCPowerPoint, to b: SoCPowerPoint) -> TimeInterval {
    let old = a.effectiveSamplingInterval, new = b.effectiveSamplingInterval
    let gap = max(powerMaxGap(a), powerMaxGap(b))
    return old == new ? gap : max(gap, old + 2 * new + socIntervalChangeSlack)
}

/// Curve segment of each point: a new segment starts after a gap longer than `powerMaxGap(from:to:)`, so missing data is
/// not drawn. Each point carries its own interval: after an interval change, the points sampled before keep their spacing.
func powerSegments(_ history: [SoCPowerPoint]) -> [Int] {
    var segment = 0
    return history.indices.map { i in
        if i > 0 && history[i].date.timeIntervalSince(history[i - 1].date) > powerMaxGap(from: history[i - 1], to: history[i]) { segment += 1 }
        return segment
    }
}

/// The points of the last `window` seconds before `now`: once powermetrics stops, its history ages out of the reply.
func recentPowerPoints(_ history: [SoCPowerPoint], now: Date, window: TimeInterval) -> [SoCPowerPoint] {
    history.filter { now.timeIntervalSince($0.date) <= window }
}

/// Takes the complete samples off a powermetrics plist stream, where each sample ends with a NUL byte. The partial
/// sample at the end stays in the buffer; one that grows past `maxBytes` is dropped (`dropped`).
func takePlistSamples(_ buffer: inout Data, maxBytes: Int) -> (samples: [Data], dropped: Bool) {
    var out: [Data] = []
    while let nul = buffer.firstIndex(of: 0) {
        let chunk = buffer[buffer.startIndex..<nul]
        if !chunk.isEmpty { out.append(Data(chunk)) }
        buffer = Data(buffer[buffer.index(after: nul)...])
    }
    guard buffer.count > maxBytes else { return (out, false) }
    buffer = Data()
    return (out, true)
}

/// One powermetrics plist sample (`cpu_power,gpu_power` samplers). Energies are in mJ over the sample's `elapsed_ns`.
/// nil when the sample is malformed.
func socPower(plist: Data) -> SoCPower? {
    func num(_ v: Any?) -> Double? { (v as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
    guard let root = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
          let p = root["processor"] as? [String: Any],
          let cpu = num(p["cpu_energy"]), let gpu = num(p["gpu_energy"]) else { return nil }
    let seconds = num(root["elapsed_ns"]).map { $0 / 1e9 } ?? assumedPowerSampleInterval
    guard seconds > 0 else { return nil }
    // A few hundred W at most on any Mac: anything else is a parsing error.
    func w(_ mJ: Double) -> Double? { let v = mJ / 1000 / seconds; return (0...1000).contains(v) ? v : nil }
    guard let cpuW = w(cpu), let gpuW = w(gpu), let aneW = w(num(p["ane_energy"]) ?? 0) else { return nil }
    return SoCPower(cpuWatts: cpuW, gpuWatts: gpuW, aneWatts: aneW)
}
