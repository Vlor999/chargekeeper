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

// Service notices: heat once per episode, limit once per charging session, both reset on unplug.
var latch = NoticeLatch()
assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, latch: &latch) == [.heatProtect])
assert(serviceNotices(from: .heatProtect, to: .charging, adapter: true, latch: &latch) == [])
assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, latch: &latch) == [])
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
assert(historyText(HistoryEntry(event: .chargedPastLimit, value: 85)) == "macOS charged the battery above 85 %")
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
// Decimals and dates follow the language of the text, in "system" mode too; the region is kept when the language matches.
assert(uiLocale(language: "en", preferred: "fr-FR").language.languageCode?.identifier == "en")
assert(uiLocale(language: "fr", preferred: "fr-CA").region?.identifier == "CA")
assert(uiLocale(language: "en", preferred: nil).identifier == "en")
UserDefaults.standard.register(defaults: [languageKey: "system"])
assert(appLocale.language.languageCode?.identifier == appLanguage)
UserDefaults.standard.register(defaults: [languageKey: "fr"])
assert(celsius(31.24) == "31,2 °C" && celsius(nil) == "--" && watts(13.4) == "13,4 W")
var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
let oct30 = paris.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 21, minute: 5))!
assert(dateTime(oct30).contains("oct.") && dateTime(oct30).contains("2026") && !dateTime(oct30).contains("PM"), dateTime(oct30))
assert(approxDuration(1500) == "~25 min" && approxDuration(3900) == "~1 h 05 min")
assert(tr("%@ to %@ %%", approxDuration(1500), "80") == "~25 min jusqu'à 80 %")
assert(tr("Plug in the adapter to continue calibration") != "Plug in the adapter to continue calibration")
// Menu and notification strings have their French text.
assert(tr("Calibration paused") == "Calibration en pause" && tr("Calibration needs the adapter") == "Calibration en attente de l'adaptateur")
assert(tr("%@ min left", "35") == "encore 35 min" && tr("Step %d/%d", 2, 5) == "Étape 2/5")
assert(tr("Before: %@", "4210 mAh") == "Avant : 4210 mAh" && tr("%@ %% reached", "80") == "80 % atteint")
assert(localizedHistory(HistoryEntry(event: .chargedPastLimit, value: 85)) == "macOS a chargé la batterie au-delà de 85\u{00A0}%")
assert(localizedHistory(HistoryEntry(event: .chargedPastLimit)) == "macOS a chargé la batterie au-delà de la limite")
assert(tr("Battery is above the limit while plugged in (macOS charged it). ChargeKeeper holds this level and does not discharge. Turn on Automatic discharge to return to the limit.")
       == "La batterie dépasse la limite sur secteur (chargée par macOS). ChargeKeeper maintient ce niveau sans décharger. Activez la décharge automatique pour revenir à la limite.")
assert(tr("Battery is above the limit while plugged in (macOS charged it). ChargeKeeper discharges it back to the limit.") == "La batterie dépasse la limite sur secteur (chargée par macOS). ChargeKeeper la décharge jusqu'à la limite.")
assert(tr("Apple's Charge Limit is set to %@ %% in System Settings. Set it to 100 %% to let ChargeKeeper manage charging.", "80")
       == "La limite de recharge d'Apple est réglée à 80 % dans Réglages Système. Réglez-la sur 100 % pour laisser ChargeKeeper gérer la recharge.")
for k in ["macOS battery settings", "Open Battery Settings",
          "Turn off Optimized Battery Charging in System Settings > Battery: it can conflict with ChargeKeeper's limit."] { assert(tr(k) != k, k) }
let samples = [done, HistoryEntry(event: .calibrationNeedsAdapter, phase: .hold), HistoryEntry(event: .calibrationDone), HistoryEntry(event: .calibrationStarted), HistoryEntry(event: .calibrationStopped),
               HistoryEntry(event: .calibrationEnded), HistoryEntry(event: .limitChanged, value: 80), HistoryEntry(event: .heatProtect),
               HistoryEntry(event: .heatProtect, temperature: 36), HistoryEntry(event: .taskSkipped, action: .calibrate),
               HistoryEntry(event: .chargedPastLimit), HistoryEntry(event: .chargedPastLimit, value: 80)]
    + [CalibrationPhase.chargeFull, .dischargeTo10, .rechargeFull, .hold, .returnToLimit].map { HistoryEntry(event: .calibrationPhase, phase: $0) }
    + TaskAction.allCases.flatMap { a in [false, true].map { HistoryEntry(event: .taskRun, action: a, late: $0, value: 60) } }
for e in samples { assert(localizedHistory(e) != historyText(e), historyText(e)) }

// Time to target: from the current and the capacity; nil when reached, idle, going the wrong way or over 24 h.
assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: 2000, watts: 0) == 1800)
assert(timeToTarget(percent: 90, target: 80, capacity: 5000, amperage: -1000, watts: 0) == 1800)
assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: nil, watts: 22.8) == 1800)  // 2000 mA at 11.4 V
assert(timeToTarget(percent: 80, target: 80, capacity: 5000, amperage: 2000, watts: 0) == nil)
assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: 20, watts: 0) == nil)
assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: -2000, watts: 0) == nil)
assert(timeToTarget(percent: 60, target: 80, capacity: nil, amperage: 2000, watts: 0) == nil)
assert(timeToTarget(percent: 10, target: 100, capacity: 5000, amperage: 60, watts: 0) == nil)
assert(timeToTarget(percent: 79, target: 80, capacity: 1000, amperage: 5000, watts: 0) == 60)

// Calibration progress: 5 steps in order, a target per phase except the timed rest, rest time left.
assert(calibrationStep(.chargeFull) == (1, 5) && calibrationStep(.dischargeTo10) == (2, 5) && calibrationStep(.returnToLimit) == (5, 5))
assert(calibrationTarget(.dischargeTo10, limit: 80) == 10 && calibrationTarget(.returnToLimit, limit: 80) == 80 && calibrationTarget(.hold, limit: 80) == nil)
assert(holdRemaining(phaseStart: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 1500)) == 2100)
assert(holdRemaining(phaseStart: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 5000)) == 0)

// Adapter needed: charging and rest phases only.
assert(calibrationNeedsAdapter(.hold) && !calibrationNeedsAdapter(.dischargeTo10) && !calibrationNeedsAdapter(nil))

// Adapter notice: once per wait, also on the first tick after a service restart; same wait across rest -> recharge;
// at most one per 10 min across short unplugs; one reminder after 1 h of waiting.
func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }
var an = AdapterNoticeState()
assert(adapterNotice(phase: .hold, adapter: false, now: at(0), &an) == .first)  // fresh state = restart while unplugged
assert(adapterNotice(phase: .hold, adapter: false, now: at(5), &an) == .none)
assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(10), &an) == .none)
assert(adapterNotice(phase: .rechargeFull, adapter: true, now: at(60), &an) == .none)
assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(120), &an) == .none)  // within 10 min
assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(3000), &an) == .none)
assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(3720), &an) == .reminder)
assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(9000), &an) == .none)
assert(adapterNotice(phase: .rechargeFull, adapter: true, now: at(9100), &an) == .none)
assert(adapterNotice(phase: .chargeFull, adapter: false, now: at(9200), &an) == .first)
assert(adapterNotice(phase: .dischargeTo10, adapter: false, now: at(20000), &an) == .none)
assert(adapterNotice(phase: nil, adapter: false, now: at(30000), &an) == .none)

// Calibration rest: only counts on the adapter. Unplugged at 100 % it restarts on replug; below 100 % it recharges first.
r = Runtime(); r.calibration = .hold; r.phaseStart = Date(timeIntervalSince1970: 0)
assert(tick(c, &r, 100, at: 1800) == .hold(at: 100))
_ = tick(c, &r, 100, ac: false, at: 3000)
_ = tick(c, &r, 100, ac: false, at: 4000); assert(r.calibration == .hold)
assert(!calibrationFinished(from: .hold, to: r.calibration))
_ = tick(c, &r, 100, at: 7000); assert(r.calibration == .hold)
_ = tick(c, &r, 100, at: 10500); assert(r.calibration == .hold)
_ = tick(c, &r, 100, at: 10700); assert(r.calibration == .returnToLimit)
r = Runtime(); r.calibration = .hold; r.phaseStart = Date(timeIntervalSince1970: 0)
assert(tick(c, &r, 99, ac: false, at: 3700) == .charge(to: 100) && r.calibration == .rechargeFull)
assert(tick(c, &r, 99, at: 3800) == .charge(to: 100))
_ = tick(c, &r, 100, at: 3900); assert(r.calibration == .hold)
_ = tick(c, &r, 100, at: 7400); assert(r.calibration == .hold)
_ = tick(c, &r, 100, at: 7500); assert(r.calibration == .returnToLimit)

// Calibration rest reloaded without a start (unplugged before a restart): the hour starts on the adapter.
r = Runtime(); r.calibration = .hold
_ = tick(c, &r, 100, at: 1000); assert(r.calibration == .hold && r.phaseStart == Date(timeIntervalSince1970: 1000))
_ = tick(c, &r, 100, at: 4500); assert(r.calibration == .hold)
_ = tick(c, &r, 100, at: 4700); assert(r.calibration == .returnToLimit)

// macOS charging past the limit: one episode from 5 points above the held level while the battery charges, kept until the
// level is back, ended by unplugging or a mode that charges on purpose.
var since: Date? = nil
func past(_ a: Action, _ pct: Int, _ st: ChargeState = .pause, settled: Bool = true, inControl: Bool = true, ac: Bool = true, mA: Int? = 900, at s: Double = 0) -> Bool {
    nil != pastLimitEpisode(a, state: st, settled: settled, inControl: inControl, adapter: ac, limit: 80, percent: pct, amperage: mA, watts: 0, since: &since,
                     now: Date(timeIntervalSince1970: s))
}
assert(!past(.hold(at: 80), 84) && since == nil)  // native limit rounding 81 → 85
assert(!past(.hold(at: 80), 85, mA: 0) && since == nil)  // above, not charging
assert(past(.hold(at: 80), 85, at: 10) && since == Date(timeIntervalSince1970: 10))
assert(!past(.hold(at: 80), 99, at: 20) && !past(.hold(at: 80), 100, mA: 0, at: 30) && since == Date(timeIntervalSince1970: 10))
assert(!past(.hold(at: 80), 80) && since == nil)
// The event carries the held level, above the limit when the hold started above it.
assert(pastLimitEpisode(.hold(at: 90), state: .pause, settled: true, inControl: true, adapter: true, limit: 80, percent: 95, amperage: 900,
                        watts: 0, since: &since, now: Date()) == 90)
since = nil
assert(past(.hold(at: 80), 90) && !past(.hold(at: 80), 92, ac: false) && since == nil)
assert(!past(.charge(to: 100), 95, .topup) && !past(.hold(at: 100), 100, .calibration) && since == nil)
assert(!past(.hold(at: 60), 70, .heatProtect) && since == nil)
// Draining toward the limit while macOS charges; the current comes from the watts when the service does not report it.
assert(80 == pastLimitEpisode(.discharge, state: .discharging, settled: true, inControl: true, adapter: true, limit: 80, percent: 90, amperage: nil, watts: 10,
                        since: &since, now: Date()))
since = nil
assert(nil == pastLimitEpisode(.discharge, state: .discharging, settled: true, inControl: true, adapter: true, limit: 80, percent: 90, amperage: nil, watts: -10,
                         since: &since, now: Date()))
// The service's own discharge or hold has no effect (no discharge key, failed SMC write): the charge is not blamed on macOS.
assert(!past(.discharge, 90, .discharging, inControl: false) && !past(.hold(at: 70), 80, inControl: false) && since == nil)
// Tick that changes mode: charging at 78 % (+2000 mA, read before the new action applies), limit lowered to 70 with automatic
// discharge. No episode on that tick; on the next one the discharge has taken over.
since = nil
var pc = Config(); pc.limit = 80; pc.autoDischarge = true
var pr = Runtime()
assert(tick(pc, &pr, 78) == .charge(to: 80) && pr.state == .charging)
pc.limit = 70
let pa = tick(pc, &pr, 78)
assert(pa == .discharge && pr.state == .discharging)
assert(nil == pastLimitEpisode(pa, state: pr.state, settled: false, inControl: true, adapter: true, limit: 70, percent: 78, amperage: 2000, watts: 0, since: &since, now: Date()))
assert(nil == pastLimitEpisode(pa, state: pr.state, settled: true, inControl: true, adapter: true, limit: 70, percent: 78, amperage: -2000, watts: 0, since: &since, now: Date()))
assert(since == nil)
// Same with dischargeTo(70): the service sets the limit and the discharge flag.
pc.autoDischarge = false; pc.limit = 80; pr = Runtime()
_ = tick(pc, &pr, 78)
pc.limit = 70; pr.discharge = true
assert(tick(pc, &pr, 78) == .discharge)
assert(nil == pastLimitEpisode(.discharge, state: pr.state, settled: false, inControl: true, adapter: true, limit: 70, percent: 78, amperage: 2000, watts: 0, since: &since, now: Date()))

// Apple Charge Limit from System Settings: only an enabled limit in 50...99 counts; a failed read (-1) or 100 is no cap.
assert(userChargeLimit(enabled: 1, limit: 80) == 80 && userChargeLimit(enabled: 0, limit: 80) == nil)
assert(userChargeLimit(enabled: 1, limit: 100) == nil && userChargeLimit(enabled: -1, limit: 80) == nil)
assert(userChargeLimit(enabled: 1, limit: -1) == nil && userChargeLimit(enabled: 1, limit: 0) == nil && userChargeLimit(enabled: 1, limit: 49) == nil)

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
