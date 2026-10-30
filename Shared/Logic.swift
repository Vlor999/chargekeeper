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

/// The gauge has just relearned its capacity (full cycle, then 1 h rest at 100 %): the calibration result is final.
func calibrationFinished(from: CalibrationPhase?, to: CalibrationPhase?) -> Bool {
    from == .hold && to == .returnToLimit
}

/// What the app does with the service's last calibration, given the last result it handled.
enum CalibrationNotice: Equatable {
    case seed(Date)  // first run: remember the current result without a banner
    case notify
    case none
}

func calibrationNotice(end: Date?, handled: Date?) -> CalibrationNotice {
    guard let handled else { return .seed(end ?? .distantPast) }
    guard let end, end > handled else { return .none }
    return .notify
}

/// History line for a finished calibration: "7100→7180 mAh, health 82.8→83.7 %, 278 cycles".
func calibrationSummary(before b: BatterySnapshot?, after a: BatterySnapshot) -> String {
    func span(_ x: String?, _ y: String?) -> String? { y.map { y in x.map { "\($0)→\(y)" } ?? y } }
    func pct(_ h: Double?) -> String? { h.map { String(format: "%.1f", $0) } }
    return [span(b?.maxCapacity.map(String.init), a.maxCapacity.map(String.init)).map { "\($0) mAh" },
            span(pct(b?.health), pct(a.health)).map { "health \($0) %" },
            a.cycleCount.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: ", ")
}

/// Notification the service posts on a state change.
enum ServiceNotice: Equatable { case heatProtect, limitReached }

/// What has already been notified: heat until the episode ends, the limit until the charger is unplugged.
struct NoticeLatch: Equatable {
    var heat = false
    var limit = false
}

/// Notices for this tick: one heat notice per heat episode, one limit notice per charging session.
func serviceNotices(from prev: ChargeState, to now: ChargeState, adapter: Bool, latch l: inout NoticeLatch) -> [ServiceNotice] {
    guard adapter else { l = NoticeLatch(); return [] }
    var out: [ServiceNotice] = []
    if now == .heatProtect && prev != .heatProtect && !l.heat { l.heat = true; out.append(.heatProtect) }
    if now == .pause && prev == .charging {
        l.heat = false
        if !l.limit { l.limit = true; out.append(.limitReached) }
    }
    return out
}

// MARK: - History

/// Fills an English template (String(format:) placeholders, arguments already formatted). The app passes tr().
typealias Translate = (String, [CVarArg]) -> String
/// Formats a number with the given count of decimals. The app passes the UI locale.
typealias FormatNumber = (Double, Int) -> String

let englishTemplate: Translate = { $1.isEmpty ? $0 : String(format: $0, arguments: $1) }
let englishNumber: FormatNumber = { String(format: "%.\($1)f", $0) }

extension TaskAction {
    /// English label; the app translates it.
    var title: String {
        switch self {
        case .setLimit: "Set charge limit"
        case .calibrate: "Start Calibration"
        case .topUp: "Charge to 100%"
        case .pause: "Pause charging"
        case .dischargeTo: "Discharge to"
        case .lowPowerOn: "Turn on Low Power Mode"
        case .lowPowerOff: "Turn off Low Power Mode"
        }
    }
}

/// Text of a history entry in the language of `t` and `n` (English by default). Free text from an older service
/// is mapped to its event when known, shown as is otherwise.
func historyText(_ entry: HistoryEntry, _ t: Translate = englishTemplate, _ n: @escaping FormatNumber = englishNumber) -> String {
    let e = parsedHistory(entry)
    func int(_ v: Int) -> String { n(Double(v), 0) }
    func span<T>(_ a: T?, _ b: T?, _ f: (T) -> String) -> String? { b.map { b in a.map { t("%@ → %@", [f($0), f(b)]) } ?? f(b) } }
    switch e.event {
    case nil: return e.text
    case .calibrationStarted: return t("Calibration started", [])
    case .calibrationStopped: return t("Calibration stopped", [])
    case .calibrationEnded: return t("Calibration over: back at the limit", [])
    case .calibrationPhase:
        switch e.phase {
        case nil: return e.text
        case .chargeFull: return t("Calibration: charging to 100 %", [])
        case .dischargeTo10: return t("Calibration: discharging to 10 %", [])
        case .rechargeFull: return t("Calibration: recharging to 100 %", [])
        case .hold: return t("Calibration: resting 1 h at 100 %", [])
        case .returnToLimit: return t("Calibration: discharging back to the limit", [])
        }
    case .calibrationDone:
        let parts = [span(e.capacityBefore, e.capacityAfter, int).map { t("%@ mAh", [$0]) },
                     span(e.healthBefore, e.healthAfter) { n($0, 1) }.map { t("health %@ %%", [$0]) },
                     e.cycles.map { t("%@ cycles", [int($0)]) }].compactMap { $0 }
        return parts.isEmpty ? t("Calibration complete", []) : t("Calibration complete: %@", [parts.joined(separator: ", ")])
    case .taskRun, .taskSkipped:
        guard let a = e.action else { return e.text }
        var label = t(a.title, [])
        if let v = e.value, a == .setLimit || a == .dischargeTo { label = t("%@ (%@ %%)", [label, int(v)]) }
        if e.event == .taskSkipped { return t("Missed task skipped: %@", [label]) }
        return e.late == true ? t("Missed task run on wake: %@", [label]) : t("Scheduled task: %@", [label])
    case .limitChanged:
        guard let v = e.value else { return e.text }
        return t("Charge limit set to %@ %%", [int(v)])
    case .heatProtect:
        guard let c = e.temperature else { return t("Heat protection: charging paused", []) }
        return t("Heat protection: charging paused at %@ °C", [n(c, 1)])
    }
}

/// Maps the free text written by an older service ("calibration: dischargeTo10", "task calibrate (caught up)",
/// "calibration done: 7100→7180 mAh, health 82.8→83.7 %, 278 cycles") to its event. Unknown text is returned as is.
func parsedHistory(_ e: HistoryEntry) -> HistoryEntry {
    guard e.event == nil else { return e }
    var r = e
    let s = e.text
    func match(_ pattern: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }
    if s == "calibration started" { r.event = .calibrationStarted }
    else if s == "calibration stopped" { r.event = .calibrationStopped }
    else if s == "calibration: back to limit" { r.event = .calibrationEnded }
    else if s.hasPrefix("calibration: "), let p = CalibrationPhase(rawValue: String(s.dropFirst(13))) { r.event = .calibrationPhase; r.phase = p }
    else if s == "calibration done" || s.hasPrefix("calibration done: ") {
        r.event = .calibrationDone
        if let g = match(#"(\d+)(?:→(\d+))? mAh"#) { (r.capacityBefore, r.capacityAfter) = g[1] == nil ? (nil, g[0].flatMap { Int($0) }) : (g[0].flatMap { Int($0) }, g[1].flatMap { Int($0) }) }
        if let g = match(#"health ([\d.]+)(?:→([\d.]+))? %"#) { (r.healthBefore, r.healthAfter) = g[1] == nil ? (nil, g[0].flatMap { Double($0) }) : (g[0].flatMap { Double($0) }, g[1].flatMap { Double($0) }) }
        r.cycles = match(#"(\d+) cycles"#)?[0].flatMap { Int($0) }
    } else if let g = match(#"^task skipped \(missed\): (\w+)$"#), let a = g[0].flatMap(TaskAction.init(rawValue:)) {
        r.event = .taskSkipped; r.action = a
    } else if let g = match(#"^task (\w+)( \(caught up\))?$"#), let a = g[0].flatMap(TaskAction.init(rawValue:)) {
        r.event = .taskRun; r.action = a; r.late = g[1] != nil
    }
    return r
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
