import Foundation

enum Action: Equatable {
    case charge(to: Int)
    case hold(at: Int)
    case discharge
}

struct Inputs {
    var percent: Int
    var adapter: Bool
    var temperature: Double?
    var now: Date
}

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

    if let phase = r.calibration, let action = calibrationAction(phase, c, &r, i) { return action }

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

    updateHeatBlock(c, &r, i)
    if r.heatBlocked { r.state = .heatProtect; return hold(pct, &r) }

    if pct < c.limit - c.idleRange { r.isRefillingToLimit = true }
    if c.idle && !r.isRefillingToLimit {
        r.state = .idle
        return hold(pct, &r)
    }
    r.state = .charging
    return .charge(to: c.limit)
}

private func calibrationAction(_ phase: CalibrationPhase, _ c: Config, _ r: inout Runtime, _ i: Inputs) -> Action? {
    let pct = i.percent
    r.state = .calibration
    switch phase {
    case .chargeFull, .rechargeFull:
        if pct >= 100 { advance(&r, to: phase == .chargeFull ? .dischargeTo10 : .hold, i.now); return hold(100, &r) }
        return .charge(to: 100)
    case .dischargeTo10:
        if pct <= 10 { advance(&r, to: .rechargeFull, i.now); return .charge(to: 100) }
        return .discharge
    case .hold:
        return calibrationRestAction(&r, i)
    case .returnToLimit:
        if pct > c.limit { return .discharge }
        r.calibration = nil
        r.phaseStart = nil
        return nil
    }
}

private func calibrationRestAction(_ r: inout Runtime, _ i: Inputs) -> Action {
    if i.adapter {
        if r.phaseStart == nil { r.phaseStart = i.now }
        if i.now.timeIntervalSince(r.phaseStart!) >= calibrationRestDuration { advance(&r, to: .returnToLimit, i.now) }
    } else if i.percent < 100 {
        advance(&r, to: .rechargeFull, i.now)
        return .charge(to: 100)
    } else {
        restartRestOnReplug(&r)
    }
    return hold(100, &r)
}

private func restartRestOnReplug(_ r: inout Runtime) { r.phaseStart = nil }

private func updateHeatBlock(_ c: Config, _ r: inout Runtime, _ i: Inputs) {
    guard c.heatProtect, let t = i.temperature else { r.heatBlocked = false; return }
    let hysteresisOver = r.heatSince.map { i.now.timeIntervalSince($0) >= heatProtectHysteresis } ?? true
    if !r.heatBlocked && t > c.maxTemp && hysteresisOver { r.heatBlocked = true; r.heatSince = i.now }
    else if r.heatBlocked && t <= c.maxTemp && hysteresisOver { r.heatBlocked = false; r.heatSince = i.now }
}

private func advance(_ r: inout Runtime, to p: CalibrationPhase, _ now: Date) {
    r.calibration = p
    r.phaseStart = now
    r.holdLevel = nil
}

func calibrationFinished(from: CalibrationPhase?, to: CalibrationPhase?) -> Bool {
    from == .hold && to == .returnToLimit
}

func calibrationNeedsAdapter(_ p: CalibrationPhase?) -> Bool {
    p == .chargeFull || p == .rechargeFull || p == .hold
}

struct AdapterNoticeState: Equatable {
    var waitingSince: Date?
    var lastNotice: Date?
    var reminded = false
}

enum AdapterNotice: Equatable { case none, first, reminder }

func adapterNotice(phase: CalibrationPhase?, adapter: Bool, now: Date, _ s: inout AdapterNoticeState) -> AdapterNotice {
    guard calibrationNeedsAdapter(phase) && !adapter else { s.waitingSince = nil; s.reminded = false; return .none }
    guard let since = s.waitingSince else {
        s.waitingSince = now
        if noticeGapRunning(since: s.lastNotice, now: now) { return .none }
        s.lastNotice = now
        return .first
    }
    guard reminderDue(waitingSince: since, reminded: s.reminded, now: now) else { return .none }
    s.reminded = true
    s.lastNotice = now
    return .reminder
}

private func noticeGapRunning(since lastNotice: Date?, now: Date) -> Bool {
    lastNotice.map { now.timeIntervalSince($0) < adapterNoticeGap } ?? false
}

private func reminderDue(waitingSince: Date, reminded: Bool, now: Date) -> Bool {
    !reminded && now.timeIntervalSince(waitingSince) >= adapterReminderAfter
}

func calibrationStep(_ p: CalibrationPhase) -> (step: Int, of: Int) {
    let all = CalibrationPhase.allCases
    return (all.firstIndex(of: p)! + 1, all.count)
}

func calibrationTargetPercent(_ p: CalibrationPhase, limit: Int) -> Int? {
    switch p {
    case .chargeFull, .rechargeFull: 100
    case .dischargeTo10: 10
    case .hold: nil
    case .returnToLimit: limit
    }
}

func calibrationRestRemaining(phaseStart: Date?, now: Date) -> TimeInterval {
    max(0, calibrationRestDuration - now.timeIntervalSince(phaseStart ?? now))
}

private func milliamps(amperage: Int?, watts: Double) -> Double {
    amperage.map(Double.init) ?? watts * 1000 / nominalThreeCellPackVolts
}

func timeToTarget(percent: Int, target: Int, capacity: Int?, amperage: Int?, watts: Double) -> TimeInterval? {
    guard let capacity, capacity > 0, target != percent else { return nil }
    let mA = milliamps(amperage: amperage, watts: watts)
    let charging = target > percent
    guard abs(mA) >= minEstimableCurrentMilliamps, charging == (mA > 0) else { return nil }
    let mAhPerPercent = Double(capacity) / 100
    let hours = charging ? chargeHours(from: percent, to: target, mAhPerPercent: mAhPerPercent, milliamps: mA)
                         : Double(target - percent) * mAhPerPercent / mA
    let t = hours * secondsPerHour
    return t <= maxTimeEstimate ? max(t, minTimeEstimate) : nil
}

private func chargeHours(from percent: Int, to target: Int, mAhPerPercent: Double, milliamps mA: Double) -> Double {
    let taperStartMA = mA / taperCurrentShare(atPercent: percent)
    let fullCurrentHours = Double(max(0, min(target, chargeTaperStartPercent) - percent)) * mAhPerPercent / mA
    guard target > chargeTaperStartPercent else { return fullCurrentHours }
    let taperSpanMAh = Double(100 - chargeTaperStartPercent) * mAhPerPercent
    let taperHours = taperSpanMAh / ((1 - chargeTaperEndCurrentFraction) * taperStartMA)
        * log(taperCurrentShare(atPercent: percent) / taperCurrentShare(atPercent: target))
    return fullCurrentHours + taperHours
}

private func taperCurrentShare(atPercent p: Int) -> Double {
    let intoTaper = Double(max(0, p - chargeTaperStartPercent)) / Double(100 - chargeTaperStartPercent)
    return 1 - (1 - chargeTaperEndCurrentFraction) * intoTaper
}

// exception: macOS 26.4+ now and then charges to 100 % to recalibrate the gauge, a cause readable only with a private entitlement, so the episode is detected from its effect (https://github.com/Vlor999/chargekeeper/commit/baf88803900433fb05626892d550d114dee14677)
// ponytail: 11 parameters, with the `settled` and `inControl` flags; a reading type would name them but changes the Daemon call (https://github.com/Vlor999/chargekeeper/issues/68)
func pastLimitEpisode(_ a: Action, state: ChargeState, settled currentReflectsThisMode: Bool, inControl: Bool, adapter: Bool, limit: Int, percent: Int, amperage: Int?,
                      watts: Double, since: inout Date?, now: Date) -> Int? {
    guard adapter, let held = serviceHeldLevel(a, state: state, limit: limit), percent > held else { since = nil; return nil }
    let charging = milliamps(amperage: amperage, watts: watts) >= minEstimableCurrentMilliamps
    guard since == nil, currentReflectsThisMode, inControl, percent >= held + nativeChargeLimitStepPercent, charging else { return nil }
    since = now
    return held
}

private func serviceHeldLevel(_ a: Action, state: ChargeState, limit: Int) -> Int? {
    switch a {
    case .hold(let level) where state == .pause: level
    case .discharge where state == .discharging: limit
    default: nil
    }
}

func userChargeLimit(enabled: Int, limit: Int) -> Int? {
    enabled == 1 && systemSettingsChargeLimitPercentRange.contains(limit) ? limit : nil
}

enum CalibrationNotice: Equatable {
    case rememberWithoutBanner(Date)
    case notify
    case none
}

func calibrationNotice(end: Date?, handled: Date?) -> CalibrationNotice {
    guard let handled else { return .rememberWithoutBanner(end ?? .distantPast) }
    guard let end, end > handled else { return .none }
    return .notify
}

func calibrationSummary(before b: BatterySnapshot?, after a: BatterySnapshot) -> String {
    func span(_ x: String?, _ y: String?) -> String? { y.map { y in x.map { "\($0)→\(y)" } ?? y } }
    func pct(_ h: Double?) -> String? { h.map { String(format: "%.1f", $0) } }
    return [span(b?.fullChargeCapacityMAh.map(String.init), a.fullChargeCapacityMAh.map(String.init)).map { "\($0) mAh" },
            span(pct(b?.healthPercent), pct(a.healthPercent)).map { "health \($0) %" },
            a.cycleCount.map { "\($0) cycles" }].compactMap { $0 }.joined(separator: ", ")
}

enum ServiceNotice: Equatable { case heatProtect, limitReached }

struct NoticeLatch: Equatable {
    var limitNoticeSent = false
    var previousLimit: Int?
}

func serviceNotices(from prev: ChargeState, to now: ChargeState, adapter: Bool, limit: Int, latch l: inout NoticeLatch) -> [ServiceNotice] {
    let limitChanged = l.previousLimit != limit
    l.previousLimit = limit
    if limitChanged || !adapter { l.limitNoticeSent = false }
    guard adapter else { return [] }
    var out: [ServiceNotice] = []
    if heatProtectStarted(from: prev, to: now) { out.append(.heatProtect) }
    if limitReached(from: prev, to: now, limitChanged: limitChanged) && !l.limitNoticeSent {
        l.limitNoticeSent = true
        out.append(.limitReached)
    }
    return out
}

private func heatProtectStarted(from prev: ChargeState, to now: ChargeState) -> Bool {
    now == .heatProtect && prev != .heatProtect
}

private func limitReached(from prev: ChargeState, to now: ChargeState, limitChanged: Bool) -> Bool {
    now == .pause && prev == .charging && !limitChanged
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
