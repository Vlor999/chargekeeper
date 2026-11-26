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
            // The rest only counts on the adapter: unplugged, it starts over on replug, or recharges first if the level fell.
            if !i.adapter {
                if pct < 100 { advance(&r, to: .rechargeFull, i.now); return .charge(to: 100) }
                r.phaseStart = nil  // not now: the saved state would change every tick
            } else {
                if r.phaseStart == nil { r.phaseStart = i.now }
                if i.now.timeIntervalSince(r.phaseStart!) >= calibrationHold { advance(&r, to: .returnToLimit, i.now) }
            }
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

    if pct > c.limit && (r.discharge || c.drainAboveLimitOnAdapter) {
        r.state = .discharging
        return .discharge
    }
    if pct >= c.limit {
        r.isRefillingToLimit = false
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

    if pct < c.limit - c.idleRange { r.isRefillingToLimit = true }
    if c.idle && !r.isRefillingToLimit {
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

/// Calibration phases that only progress on the adapter: unplugged, charging stalls and the rest is not a rest.
func calibrationNeedsAdapter(_ p: CalibrationPhase?) -> Bool {
    p == .chargeFull || p == .rechargeFull || p == .hold
}

let adapterNoticeGap: TimeInterval = 10 * 60
let adapterReminderAfter: TimeInterval = 60 * 60

/// Service memory of the "calibration needs the adapter" notices. In memory only: after a restart the first tick that finds
/// the adapter missing starts a new episode, since the adapter state before the restart is unknown.
struct AdapterNoticeState: Equatable {
    var waitingSince: Date?  // start of the current wait for the adapter
    var lastNotice: Date?
    var reminded = false
}

enum AdapterNotice: Equatable { case none, first, reminder }

/// One notice when a wait for the adapter starts (unplugged in a phase that needs it, or such a phase reached unplugged),
/// at most one per 10 min across short unplugs, and one reminder when the wait reaches 1 h.
/// Moving between two such phases while unplugged (rest back to recharge) is the same wait.
func adapterNotice(phase: CalibrationPhase?, adapter: Bool, now: Date, _ s: inout AdapterNoticeState) -> AdapterNotice {
    guard calibrationNeedsAdapter(phase) && !adapter else { s.waitingSince = nil; s.reminded = false; return .none }
    guard let since = s.waitingSince else {
        s.waitingSince = now
        if let last = s.lastNotice, now.timeIntervalSince(last) < adapterNoticeGap { return .none }
        s.lastNotice = now
        return .first
    }
    guard !s.reminded, now.timeIntervalSince(since) >= adapterReminderAfter else { return .none }
    s.reminded = true
    s.lastNotice = now
    return .reminder
}

/// Step of the phase in the calibration, from 1, and the step count.
func calibrationStep(_ p: CalibrationPhase) -> (step: Int, of: Int) {
    let all = CalibrationPhase.allCases
    return (all.firstIndex(of: p)! + 1, all.count)
}

/// Charge level the phase is heading to; nil for the timed rest.
func calibrationTarget(_ p: CalibrationPhase, limit: Int) -> Int? {
    switch p {
    case .chargeFull, .rechargeFull: 100
    case .dischargeTo10: 10
    case .hold: nil
    case .returnToLimit: limit
    }
}

/// Time left in the 1 h rest at 100 %.
func holdRemaining(phaseStart: Date?, now: Date) -> TimeInterval {
    max(0, calibrationHold - now.timeIntervalSince(phaseStart ?? now))
}

/// Pack voltage assumed when the service does not report the battery current (3-cell Li-ion, nominal).
let nominalPackVolts = 11.4

/// Time to go from `percent` to `target` at the present battery current, or nil when the estimate is not worth showing:
/// target reached, no capacity, current near zero or going the wrong way, or more than 24 h.
/// `amperage` in mA (>0 charging); without it the current comes from `watts` at the nominal pack voltage.
// ponytail: linear at the present current. Charging tapers above ~80 %, so the time to 100 % comes out short;
// the menu refreshes every 2 s while open, so the figure corrects itself as the current falls.
func timeToTarget(percent: Int, target: Int, capacity: Int?, amperage: Int?, watts: Double) -> TimeInterval? {
    guard let capacity, capacity > 0, target != percent else { return nil }
    let mA = amperage.map(Double.init) ?? watts * 1000 / nominalPackVolts
    let toGo = Double(target - percent) / 100 * Double(capacity)  // mAh, signed like the current
    guard abs(mA) >= 50, (toGo > 0) == (mA > 0) else { return nil }
    let t = toGo / mA * 3600
    return t <= 24 * 3600 ? max(t, 60) : nil
}

/// Points above the level the service holds before charging counts as macOS overriding the limit. Covers the native
/// Charge Limit rounding a held level up to its next step of 5 (81 → 85).
let pastLimitMargin = 5

/// Tracks macOS charging past the limit while the service holds or drains the battery: the gauge recalibration of
/// macOS 26.4+ ("Your Mac will occasionally charge to 100 %"), or any other system override. Detected from the effect,
/// since the cause is not readable without a private entitlement. Returns the held level when a new episode starts.
/// The episode lasts until the level is back to the held level, the adapter is unplugged or the service changes mode.
/// `inControl`: the service's own hold or discharge is in effect (keys present, writes succeeded); otherwise the charge
/// may come from the service's own limitation, not from macOS.
/// `settled`: same state and action as the previous tick. The reading is taken before the action is applied, so on the
/// tick that changes mode the current still reflects the previous mode (charging before a new discharge).
func pastLimitEpisode(_ a: Action, state: ChargeState, settled: Bool, inControl: Bool, adapter: Bool, limit: Int, percent: Int, amperage: Int?,
                      watts: Double, since: inout Date?, now: Date) -> Int? {
    let held: Int? = switch a {
    case .hold(let level) where state == .pause: level
    case .discharge where state == .discharging: limit
    default: nil
    }
    guard adapter, let held, percent > held else { since = nil; return nil }
    let mA = amperage.map(Double.init) ?? watts * 1000 / nominalPackVolts
    guard since == nil, settled, inControl, percent >= held + pastLimitMargin, mA >= 50 else { return nil }
    since = now
    return held
}

/// Charge Limit of System Settings when it caps charging. Read only on Macs where the service never sets it (it charges
/// through the SMC): there, an active limit below 100 % can only come from the user.
/// `enabled` is 1 or 0 and -1 when the read failed; a limit outside 50...99 is a failed read or no cap.
func userChargeLimit(enabled: Int, limit: Int) -> Int? {
    enabled == 1 && (50...99).contains(limit) ? limit : nil
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
    return [span(b?.fullChargeCapacityMAh.map(String.init), a.fullChargeCapacityMAh.map(String.init)).map { "\($0) mAh" },
            span(pct(b?.healthPercent), pct(a.healthPercent)).map { "health \($0) %" },
            a.cycleCount.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: ", ")
}

/// Notification the service posts on a state change.
enum ServiceNotice: Equatable { case heatProtect, limitReached }

/// The limit notice already sent this charging session (until the charger is unplugged or the limit changes).
struct NoticeLatch: Equatable {
    var limit = false
    var seenLimit: Int?  // charge limit at the previous tick
}

/// Notices for this tick: one heat notice each time heat protection pauses charging (an episode ends when the
/// state leaves heat protection), one limit notice per charging session when the battery level reaches the limit.
/// A pause caused by a limit change (Pause, a lower limit, a scheduled task) is not "limit reached".
func serviceNotices(from prev: ChargeState, to now: ChargeState, adapter: Bool, limit: Int, latch l: inout NoticeLatch) -> [ServiceNotice] {
    let changed = l.seenLimit != limit
    l.seenLimit = limit
    if changed || !adapter { l.limit = false }
    guard adapter else { return [] }
    var out: [ServiceNotice] = []
    if now == .heatProtect && prev != .heatProtect { out.append(.heatProtect) }
    if now == .pause && prev == .charging && !changed && !l.limit { l.limit = true; out.append(.limitReached) }
    return out
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
