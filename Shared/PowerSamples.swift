import Foundation

func macWattsExcludingPorts(system: Double, ports: [Double]) -> Double {
    let portsWatts = ports.reduce(0, +)
    return systemLoadIncludesPorts(systemWatts: system, portsWatts: portsWatts) ? system - portsWatts : system
}

func systemLoadIncludesPorts(systemWatts: Double, portsWatts: Double) -> Bool { portsWatts <= systemWatts }

extension SoCPowerPoint {
    func isWithin(_ window: TimeInterval, before end: Date) -> Bool { end.timeIntervalSince(date) <= window }
}

func appendPowerPoint(_ history: [SoCPowerPoint], _ p: SoCPowerPoint, window: TimeInterval) -> [SoCPowerPoint] {
    (history + [p]).filter { $0.isWithin(window, before: p.date) && $0.date <= p.date }
}

func powermetricsArguments(_ i: PowerInterval) -> [String]? {
    guard i != .off else { return nil }
    return ["--samplers", powermetricsSamplers, "-i", String(i.rawValue * 1000), "-f", "plist"]
}

func appRefreshInterval(_ i: PowerInterval) -> TimeInterval {
    i == .off ? appMaxRefreshInterval : min(appMaxRefreshInterval, TimeInterval(i.rawValue))
}

func powerPointStaleAfter(_ p: SoCPowerPoint) -> TimeInterval { socStaleAfterIntervals * p.effectiveSamplingInterval }

func currentPower(_ history: [SoCPowerPoint], now: Date) -> SoCPower? {
    guard let p = history.last, now.timeIntervalSince(p.date) <= powerPointStaleAfter(p) else { return nil }
    return p.averagePower
}

func maxCurveGap(from a: SoCPowerPoint, to b: SoCPowerPoint) -> TimeInterval {
    let old = a.effectiveSamplingInterval, new = b.effectiveSamplingInterval
    let gap = max(powerPointStaleAfter(a), powerPointStaleAfter(b))
    return old == new ? gap : max(gap, powermetricsRestartGap(oldInterval: old, newInterval: new))
}

private func powermetricsRestartGap(oldInterval: TimeInterval, newInterval: TimeInterval) -> TimeInterval {
    oldInterval + 2 * newInterval + socIntervalChangeSlack
}

func powerSegments(_ history: [SoCPowerPoint]) -> [Int] {
    var segment = 0
    return history.indices.map { i in
        if i > 0 && history[i].date.timeIntervalSince(history[i - 1].date) > maxCurveGap(from: history[i - 1], to: history[i]) { segment += 1 }
        return segment
    }
}

func recentPowerPoints(_ history: [SoCPowerPoint], now: Date, window: TimeInterval) -> [SoCPowerPoint] {
    history.filter { $0.isWithin(window, before: now) }
}

func takePlistSamples(_ buffer: inout Data, maxBytes: Int) -> (samples: [Data], dropped: Bool) {
    var out: [Data] = []
    while let end = buffer.firstIndex(of: plistSampleTerminator) {
        let chunk = buffer[buffer.startIndex..<end]
        if !chunk.isEmpty { out.append(Data(chunk)) }
        buffer = Data(buffer[buffer.index(after: end)...])
    }
    guard buffer.count > maxBytes else { return (out, false) }
    buffer = Data()
    return (out, true)
}

func socPower(plist: Data) -> SoCPower? {
    func num(_ v: Any?) -> Double? { (v as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
    guard let root = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
          let p = root["processor"] as? [String: Any],
          let cpu = num(p["cpu_energy"]), let gpu = num(p["gpu_energy"]) else { return nil }
    let seconds = num(root["elapsed_ns"]).map { $0 / 1e9 } ?? assumedPowerSampleInterval
    guard seconds > 0 else { return nil }
    func watts(fromMillijoules mJ: Double) -> Double? {
        let w = mJ / 1000 / seconds
        return (0...maxPlausibleSoCWatts).contains(w) ? w : nil
    }
    guard let cpuW = watts(fromMillijoules: cpu), let gpuW = watts(fromMillijoules: gpu),
          let aneW = watts(fromMillijoules: num(p["ane_energy"]) ?? 0) else { return nil }
    return SoCPower(cpuWatts: cpuW, gpuWatts: gpuW, aneWatts: aneW)
}
