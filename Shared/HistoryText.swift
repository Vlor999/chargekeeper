import Foundation

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
        let parts = [span(e.capacityBeforeMAh, e.capacityAfterMAh, int).map { t("%@ mAh", [$0]) },
                     span(e.healthBeforePercent, e.healthAfterPercent) { n($0, 1) }.map { t("health %@ %%", [$0]) },
                     e.cycles.map { t("%@ cycles", [int($0)]) }].compactMap { $0 }
        return parts.isEmpty ? t("Calibration complete", []) : t("Calibration complete: %@", [parts.joined(separator: ", ")])
    case .taskRun, .taskSkipped:
        guard let a = e.action else { return e.text }
        var label = t(a.title, [])
        if let v = e.percent, a == .setLimit || a == .dischargeTo { label = t("%@ (%@ %%)", [label, int(v)]) }
        if e.event == .taskSkipped { return t("Missed task skipped: %@", [label]) }
        return e.caughtUpOnWake == true ? t("Missed task run on wake: %@", [label]) : t("Scheduled task: %@", [label])
    case .limitChanged:
        guard let v = e.percent else { return e.text }
        return t("Charge limit set to %@ %%", [int(v)])
    case .calibrationNeedsAdapter: return t("Calibration: adapter unplugged, plug it in to continue", [])
    case .chargedPastLimit:
        guard let v = e.percent else { return t("macOS charged the battery above the limit", []) }
        return t("macOS charged the battery above %@ %%", [int(v)])
    case .heatProtect:
        guard let c = e.temperature else { return t("Heat protection: charging paused", []) }
        return t("Heat protection: charging paused at %@ °C", [n(c, 1)])
    case .keepAwakeTimeUp: return t("Keep awake ended: time up", [])
    case .keepAwakeLowBattery:
        guard let v = e.percent else { return e.text }
        return t("Keep awake turned off: battery at %@ %%", [int(v)])
    case .keepAwakeFailed: return t("Keep awake could not start: macOS refused to block sleep", [])
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
        if let g = match(#"(\d+)(?:→(\d+))? mAh"#) { (r.capacityBeforeMAh, r.capacityAfterMAh) = g[1] == nil ? (nil, g[0].flatMap { Int($0) }) : (g[0].flatMap { Int($0) }, g[1].flatMap { Int($0) }) }
        if let g = match(#"health ([\d.]+)(?:→([\d.]+))? %"#) { (r.healthBeforePercent, r.healthAfterPercent) = g[1] == nil ? (nil, g[0].flatMap { Double($0) }) : (g[0].flatMap { Double($0) }, g[1].flatMap { Double($0) }) }
        r.cycles = match(#"(\d+) cycles"#)?[0].flatMap { Int($0) }
    } else if let g = match(#"^task skipped \(missed\): (\w+)$"#), let a = g[0].flatMap(TaskAction.init(rawValue:)) {
        r.event = .taskSkipped; r.action = a
    } else if let g = match(#"^task (\w+)( \(caught up\))?$"#), let a = g[0].flatMap(TaskAction.init(rawValue:)) {
        r.event = .taskRun; r.action = a; r.caughtUpOnWake = g[1] != nil
    }
    return r
}
