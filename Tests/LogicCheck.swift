// Logic self-check. Run: make check
import Foundation

func tick(_ c: Config, _ r: inout Runtime, _ pct: Int, ac: Bool = true, temp: Double? = nil, at t: TimeInterval = 0) -> Action {
    decide(c, &r, Inputs(percent: pct, adapter: ac, temperature: temp, now: Date(timeIntervalSince1970: t)))
}

var c = Config()
var r = Runtime()

// Limit: above limit holds at current level, below charges.
c.limit = 50
assert(tick(c, &r, 80) == .hold(at: 80) && r.state == .pause)
r = Runtime(); c.limit = 60
assert(tick(c, &r, 17) == .charge(to: 60) && r.state == .charging)
assert(tick(c, &r, 60) == .hold(at: 60))

// Discharge: down to limit then auto-off.
r = Runtime(); c.limit = 80; r.discharge = true
assert(tick(c, &r, 90) == .discharge && r.state == .discharging)
assert(tick(c, &r, 80) == .hold(at: 80) && !r.discharge)

// Auto discharge: drains without the manual toggle, then holds.
r = Runtime(); c.autoDischarge = true
assert(tick(c, &r, 90) == .discharge)
assert(tick(c, &r, 80) == .hold(at: 80))
c.autoDischarge = false

// Idle range: range 10, replug at 74 stays paused, at 62 charges to 80.
r = Runtime(); c.idle = true; c.idleRange = 10
_ = tick(c, &r, 80)
_ = tick(c, &r, 74, ac: false)
assert(tick(c, &r, 74) == .hold(at: 74) && r.state == .idle)
_ = tick(c, &r, 62, ac: false)
assert(tick(c, &r, 62) == .charge(to: 80))
assert(tick(c, &r, 75) == .charge(to: 80))
assert(tick(c, &r, 80) == .hold(at: 80))
c.idle = false

// Top-up: to 100, cleared on unplug.
r = Runtime(); r.topUp = true
assert(tick(c, &r, 85) == .charge(to: 100) && r.state == .topup)
_ = tick(c, &r, 100, ac: false)
assert(!r.topUp)

// Heat protection: block immediately, re-check after 5 min, then charge at least 5 min.
r = Runtime(); c.heatProtect = true; c.maxTemp = 35
assert(tick(c, &r, 45, temp: 36, at: 0) == .hold(at: 45) && r.state == .heatProtect)
assert(tick(c, &r, 45, temp: 30, at: 100) == .hold(at: 45))
assert(tick(c, &r, 45, temp: 30, at: 300) == .charge(to: 80))
assert(tick(c, &r, 46, temp: 40, at: 400) == .charge(to: 80))
assert(tick(c, &r, 46, temp: 40, at: 600) == .hold(at: 46))
c.heatProtect = false

// Calibration: 100 -> 10 -> 100 -> hold 1h -> back to limit.
r = Runtime(); r.calibration = .chargeFull
assert(tick(c, &r, 70) == .charge(to: 100))
_ = tick(c, &r, 100, at: 0); assert(r.calibration == .dischargeTo10)
assert(tick(c, &r, 50, at: 10) == .discharge)
_ = tick(c, &r, 10, at: 20); assert(r.calibration == .rechargeFull)
_ = tick(c, &r, 100, at: 30); assert(r.calibration == .hold)
assert(tick(c, &r, 100, at: 30 + 3599) == .hold(at: 100))
_ = tick(c, &r, 100, at: 30 + 3600); assert(r.calibration == .returnToLimit)
assert(tick(c, &r, 95, at: 4000) == .discharge)
assert(tick(c, &r, 80, at: 5000) == .hold(at: 80) && r.calibration == nil && r.state == .pause)

// Calibration finished: only when the rest at 100 % ends, not on a stop or another phase change.
r = Runtime(); r.calibration = .rechargeFull
var finished: [Bool] = []
for (pct, t) in [(100, 0.0), (100, 3599), (100, 3600), (95, 4000), (80, 5000)] as [(Int, TimeInterval)] {
    let from = r.calibration
    _ = tick(c, &r, pct, at: t)
    finished.append(calibrationFinished(from: from, to: r.calibration))
}
assert(finished == [false, false, true, false, false])
assert(!calibrationFinished(from: .hold, to: nil) && !calibrationFinished(from: .returnToLimit, to: nil))

// Calibration notice: first run seeds without a banner, then one banner per new result.
let t0 = Date(timeIntervalSince1970: 1000), t1 = Date(timeIntervalSince1970: 2000)
assert(calibrationNotice(end: t0, handled: nil) == .seed(t0))
assert(calibrationNotice(end: nil, handled: nil) == .seed(.distantPast))
assert(calibrationNotice(end: t0, handled: .distantPast) == .notify)
assert(calibrationNotice(end: t0, handled: t0) == .none && calibrationNotice(end: nil, handled: t0) == .none)
assert(calibrationNotice(end: t1, handled: t0) == .notify)

// Calibration report: health is capacity over design, summary shows before→after.
let before = BatterySnapshot(date: Date(), maxCapacity: 7100, nominalCapacity: 7344, designCapacity: 8579, cycleCount: 277, percent: 60)
var after = before; after.maxCapacity = 7180; after.cycleCount = 278
assert(String(format: "%.1f", before.health!) == "82.8" && String(format: "%.1f", before.nominalHealth!) == "85.6")
assert(calibrationSummary(before: before, after: after) == "7100→7180 mAh, health 82.8→83.7 %, 278 cycles")
assert(calibrationSummary(before: nil, after: after) == "7180 mAh, health 83.7 %, 278 cycles")
after.designCapacity = nil
assert(after.health == nil && calibrationSummary(before: before, after: after) == "7100→7180 mAh, 278 cycles")

// Service notices: heat once per episode (a second pause after cooling is a new one), limit once per charging session, reset on unplug.
var latch = NoticeLatch()
assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, latch: &latch) == [.heatProtect])
assert(serviceNotices(from: .heatProtect, to: .heatProtect, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .heatProtect, to: .charging, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, latch: &latch) == [.heatProtect])
assert(serviceNotices(from: .heatProtect, to: .charging, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .charging, to: .pause, adapter: true, latch: &latch) == [.limitReached])
assert(serviceNotices(from: .pause, to: .charging, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .charging, to: .pause, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, latch: &latch) == [.heatProtect])
assert(serviceNotices(from: .calibration, to: .pause, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .pause, to: .discharging, adapter: false, latch: &latch) == [] && latch == NoticeLatch())
assert(serviceNotices(from: .charging, to: .pause, adapter: true, latch: &latch) == [.limitReached])

// History: events render in English with their parameters.
let done = HistoryEntry(event: .calibrationDone, capacityBefore: 7100, capacityAfter: 7180, healthBefore: 82.76, healthAfter: 83.69, cycles: 278)
assert(historyText(done) == "Calibration complete: 7100 → 7180 mAh, health 82.8 → 83.7 %, 278 cycles")
assert(historyText(HistoryEntry(event: .calibrationDone)) == "Calibration complete")
assert(historyText(HistoryEntry(event: .calibrationPhase, phase: .dischargeTo10)) == "Calibration: discharging to 10 %")
assert(historyText(HistoryEntry(event: .taskRun, action: .setLimit, late: true, value: 60)) == "Missed task run on wake: Set charge limit (60 %)")
assert(historyText(HistoryEntry(event: .taskRun, action: .topUp, late: false)) == "Scheduled task: Charge to 100%")
assert(historyText(HistoryEntry(event: .heatProtect, temperature: 36.24)) == "Heat protection: charging paused at 36.2 °C")
assert(historyText(HistoryEntry(event: .limitChanged, value: 75)) == "Charge limit set to 75 %")

// History: free text from an older service maps to its event, unknown text stays as is.
assert(historyText(HistoryEntry(text: "calibration done: 7100→7180 mAh, health 82.8→83.7 %, 278 cycles")) == historyText(done))
assert(historyText(HistoryEntry(text: "calibration done: 7180 mAh, 278 cycles")) == "Calibration complete: 7180 mAh, 278 cycles")
assert(parsedHistory(HistoryEntry(text: "calibration: dischargeTo10")).phase == .dischargeTo10)
assert(parsedHistory(HistoryEntry(text: "calibration: back to limit")).event == .calibrationEnded)
assert(parsedHistory(HistoryEntry(text: "calibration started")).event == .calibrationStarted)
let caught = parsedHistory(HistoryEntry(text: "task calibrate (caught up)"))
assert(caught.event == .taskRun && caught.action == .calibrate && caught.late == true)
assert(parsedHistory(HistoryEntry(text: "task skipped (missed): topUp")).event == .taskSkipped)
assert(historyText(HistoryEntry(text: "Limit 80 %")) == "Limit 80 %")

// History decoding: an event unknown to this build falls back to the text; older apps read the text only.
struct OldEntry: Codable { var date: Date; var text: String }
let decoded = try! JSONDecoder().decode([HistoryEntry].self, from: Data(#"[{"date":0,"text":"x","event":"future"},{"date":0,"text":"calibration stopped"}]"#.utf8))
assert(decoded[0].event == nil && historyText(decoded[0]) == "x" && historyText(decoded[1]) == "Calibration stopped")
var stored = done; stored.text = historyText(done)
assert(try! JSONDecoder().decode(OldEntry.self, from: JSONEncoder().encode(stored)).text == historyText(done))
assert(try! JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(stored)) == stored)

// History in French: locale numbers, and every event template has a translation.
UserDefaults.standard.register(defaults: [languageKey: "fr"])
assert(localizedHistory(done) == "Calibration terminée : 7100 → 7180\u{00A0}mAh, santé 82,8 → 83,7\u{00A0}%, 278 cycles")
assert(localizedHistory(HistoryEntry(event: .calibrationPhase, phase: .dischargeTo10)) == "Calibration : décharge jusqu'à 10\u{00A0}%")
let samples = [done, HistoryEntry(event: .calibrationDone), HistoryEntry(event: .calibrationStarted), HistoryEntry(event: .calibrationStopped),
               HistoryEntry(event: .calibrationEnded), HistoryEntry(event: .limitChanged, value: 80), HistoryEntry(event: .heatProtect),
               HistoryEntry(event: .heatProtect, temperature: 36), HistoryEntry(event: .taskSkipped, action: .calibrate)]
    + [CalibrationPhase.chargeFull, .dischargeTo10, .rechargeFull, .hold, .returnToLimit].map { HistoryEntry(event: .calibrationPhase, phase: $0) }
    + TaskAction.allCases.flatMap { a in [false, true].map { HistoryEntry(event: .taskRun, action: a, late: $0, value: 60) } }
for e in samples { assert(localizedHistory(e) != historyText(e), historyText(e)) }

// LED.
c.led = .indicate; r = Runtime(); r.state = .pause
assert(ledColor(c, r, adapter: true, percent: 80) == .green)
r.state = .discharging; c.ledBlinkDischarge = true
assert(ledColor(c, r, adapter: true, percent: 90) == .orangeBlink)

// Schedule: monthly on the 31st skips 30-day months; weekdays skip weekends.
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
var t = ScheduledTask(action: .calibrate, repeatRule: .monthly, start: d("2026-01-31T09:00:00Z"))
assert(lastOccurrence(t, after: d("2026-04-01T00:00:00Z"), upTo: d("2026-04-30T23:00:00Z"), calendar: cal) == nil)
assert(lastOccurrence(t, after: d("2026-05-01T00:00:00Z"), upTo: d("2026-05-31T10:00:00Z"), calendar: cal) == d("2026-05-31T09:00:00Z"))
t.repeatRule = .weekdays; t.start = d("2026-10-23T09:00:00Z")  // Friday
assert(lastOccurrence(t, after: d("2026-10-23T10:00:00Z"), upTo: d("2026-10-25T23:00:00Z"), calendar: cal) == nil)
assert(lastOccurrence(t, after: d("2026-10-23T10:00:00Z"), upTo: d("2026-10-26T09:30:00Z"), calendar: cal) == d("2026-10-26T09:00:00Z"))
t.repeatRule = .never
assert(lastOccurrence(t, after: d("2026-10-01T00:00:00Z"), upTo: d("2026-10-24T00:00:00Z"), calendar: cal) == d("2026-10-23T09:00:00Z"))

// Power flow: the MacBook gets the load minus the ports, unless the ports exceed the load.
assert(macWatts(system: 27, ports: [1, 13]) == 13)
assert(macWatts(system: 10, ports: [13]) == 10)

// Power flow labels: close centres are spread by gap and stay inside the height.
assert(spreadLabels([50, 51, 52], gap: 14, height: 200) == [50, 64, 78])
assert(spreadLabels([100, 108], gap: 14, height: 110) == [89, 103])

// Device icon: Apple devices by name, the rest generic.
assert(deviceIcon("iPhone") == "iphone" && deviceIcon("AirPods Charging Case") == "airpods" && deviceIcon(nil) == "cable.connector")

print("logic ok")
