import Foundation

/// What the hardware layer should do this tick.
enum Action: Equatable {
    case charge(to: Int)  // allow charging up to target
    case hold(at: Int)    // keep battery at this level, run from adapter
    case discharge        // run from battery even if plugged
}

struct Inputs {
    var percent: Int
    var adapter: Bool
    var temperature: Double?
    var now: Date
}

let heatWindow: TimeInterval = 5 * 60
let calibrationHold: TimeInterval = 60 * 60

/// Pure charge policy. Mutates runtime (one-shot modes, latches) and returns the action.
func decide(_ c: Config, _ r: inout Runtime, _ i: Inputs) -> Action {
    let action = policy(c, &r, i)
    if case .hold = action {} else { r.holdLevel = nil }
    return action
}

private func hold(_ level: Int, _ r: inout Runtime) -> Action {
    if r.holdLevel == nil { r.holdLevel = level }
    return .hold(at: r.holdLevel!)
}

private func policy(_ c: Config, _ r: inout Runtime, _ i: Inputs) -> Action {
    let pct = i.percent
    if !i.adapter { r.topUp = false }
    if r.discharge && pct <= c.limit { r.discharge = false }

    if let phase = r.calibration {
        r.state = .calibration
        switch phase {
        case .chargeFull, .rechargeFull:
            if pct >= 100 { advance(&r, to: phase == .chargeFull ? .dischargeTo10 : .hold, i.now); return hold(100, &r) }
            return .charge(to: 100)
        case .dischargeTo10:
            if pct <= 10 { advance(&r, to: .rechargeFull, i.now); return .charge(to: 100) }
            return .discharge
        case .hold:
            if i.now.timeIntervalSince(r.phaseStart ?? i.now) >= calibrationHold { advance(&r, to: .returnToLimit, i.now) }
            return hold(100, &r)
        case .returnToLimit:
            if pct > c.limit { return .discharge }
            r.calibration = nil
            r.phaseStart = nil
        }
    }

    guard i.adapter else {
        r.state = .discharging
        return .charge(to: r.topUp ? 100 : c.limit)
    }

    if r.topUp {
        r.state = .topup
        return pct >= 100 ? hold(100, &r) : .charge(to: 100)
    }

    if pct > c.limit && (r.discharge || c.autoDischarge) {
        r.state = .discharging
        return .discharge
    }
    if pct >= c.limit {
        r.idleRecharge = false
        r.state = .pause
        return hold(pct, &r)
    }

    // Below limit: heat protection with 5 min hysteresis windows.
    if c.heatProtect, let t = i.temperature {
        let windowOver = r.heatSince.map { i.now.timeIntervalSince($0) >= heatWindow } ?? true
        if !r.heatBlocked && t > c.maxTemp && windowOver { r.heatBlocked = true; r.heatSince = i.now }
        else if r.heatBlocked && t <= c.maxTemp && windowOver { r.heatBlocked = false; r.heatSince = i.now }
        if r.heatBlocked { r.state = .heatProtect; return hold(pct, &r) }
    } else {
        r.heatBlocked = false
    }

    if pct < c.limit - c.idleRange { r.idleRecharge = true }
    if c.idle && !r.idleRecharge {
        r.state = .idle
        return hold(pct, &r)
    }
    r.state = .charging
    return .charge(to: c.limit)
}

private func advance(_ r: inout Runtime, to p: CalibrationPhase, _ now: Date) {
    r.calibration = p
    r.phaseStart = now
    r.holdLevel = nil
}

/// History line for a finished calibration: "7100→7180 mAh, health 82.8→83.7 %, 278 cycles".
func calibrationSummary(before b: BatterySnapshot?, after a: BatterySnapshot) -> String {
    func span(_ x: String?, _ y: String?) -> String? { y.map { y in x.map { "\($0)→\(y)" } ?? y } }
    func pct(_ h: Double?) -> String? { h.map { String(format: "%.1f", $0) } }
    return [span(b?.maxCapacity.map(String.init), a.maxCapacity.map(String.init)).map { "\($0) mAh" },
            span(pct(b?.health), pct(a.health)).map { "health \($0) %" },
            a.cycleCount.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: ", ")
}

func ledColor(_ c: Config, _ r: Runtime, adapter: Bool, percent: Int) -> LEDColor {
    if let o = r.ledOverride { return o }
    switch c.led {
    case .system: return .system
    case .alwaysOff: return .off
    case .indicate:
        guard adapter else { return .system }
        switch r.state {
        case .pause, .idle: return .green
        case .topup: return percent >= 100 ? .green : .orange
        case .discharging: return c.ledBlinkDischarge ? .orangeBlink : .orange
        case .calibration: return r.calibration == .dischargeTo10 || r.calibration == .returnToLimit
            ? (c.ledBlinkDischarge ? .orangeBlink : .orange) : .orange
        case .charging, .heatProtect, .exit: return .orange
        }
    }
}

// MARK: - Schedule

/// Most recent occurrence of the task in (after, upTo], or nil.
func lastOccurrence(_ t: ScheduledTask, after: Date, upTo: Date, calendar cal: Calendar = .current) -> Date? {
    let start = t.start
    if start > upTo { return nil }
    if t.repeatRule == .never { return start > after ? start : nil }

    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: start)
    var found: Date?
    // ponytail: linear walk from start; fine for years of daily tasks at a 60s check cadence
    for n in 0... {
        let d: Date?
        switch t.repeatRule {
        case .daily, .weekdays: d = cal.date(byAdding: .day, value: n, to: start)
        case .weekly: d = cal.date(byAdding: .day, value: 7 * n, to: start)
        case .biweekly: d = cal.date(byAdding: .day, value: 14 * n, to: start)
        case .monthly, .yearly:
            // Same day-of-month only; the 31st skips shorter months.
            var c = comps
            let m = (comps.month! - 1) + (t.repeatRule == .monthly ? n : 12 * n)
            c.year = comps.year! + m / 12
            c.month = m % 12 + 1
            d = cal.date(from: c).flatMap { cal.component(.day, from: $0) == comps.day ? $0 : Date.distantPast }
        case .never: d = nil
        }
        guard let date = d else { break }
        if date > upTo { break }
        if date == .distantPast { continue }
        if t.repeatRule == .weekdays, cal.isDateInWeekend(date) { continue }
        if date > after { found = date }
    }
    return found
}

/// MacBook share of the system load once the USB-C ports are served.
// ponytail: SystemLoad includes port output on the one Mac checked; ports above the load mean it doesn't, so the load is kept whole.
func macWatts(system: Double, ports: [Double]) -> Double {
    let out = ports.reduce(0, +)
    return out <= system ? system - out : system
}

/// Label centres pushed apart by at least gap, kept inside 0...height while they fit.
func spreadLabels(_ y: [Double], gap: Double, height: Double) -> [Double] {
    var y = y
    for i in y.indices.dropFirst() { y[i] = max(y[i], y[i - 1] + gap) }
    if let last = y.indices.last { y[last] = min(y[last], height - gap / 2) }
    for i in y.indices.dropLast().reversed() { y[i] = min(y[i], y[i + 1] - gap) }
    return y
}

/// SF Symbol for a USB device name.
// ponytail: substring match on Apple product names; anything else gets the generic connector.
func deviceIcon(_ name: String?) -> String {
    let d = name?.lowercased() ?? ""
    return d.contains("iphone") ? "iphone" : d.contains("ipad") ? "ipad" : d.contains("airpods") ? "airpods" : "cable.connector"
}
