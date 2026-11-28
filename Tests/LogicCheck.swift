import Foundation

let c = Config()
let cal: Calendar = { var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!; return utc }()

func tick(_ c: Config, _ r: inout Runtime, _ pct: Int, ac: Bool = true, temp: Double? = nil, at t: TimeInterval = 0) -> Action {
    decide(c, &r, Inputs(percent: pct, adapter: ac, temperature: temp, now: Date(timeIntervalSince1970: t)))
}

func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

func useLanguage(_ code: String) { UserDefaults.standard.register(defaults: [languageKey: code]) }

let calibrationDoneEntry = HistoryEntry(event: .calibrationDone, capacityBeforeMAh: 7100, capacityAfterMAh: 7180, healthBeforePercent: 82.76, healthAfterPercent: 83.69, cycles: 278)

let pw = SoCPower(cpuWatts: 1, gpuWatts: 0, aneWatts: 0)
let pwHistory = [100.0, 200, 300].map { SoCPowerPoint(date: at($0), averagePower: pw) }

func pastLimitEpisodeStarts(_ a: Action, _ pct: Int, _ st: ChargeState = .pause, settled: Bool = true, serviceInControl: Bool = true, ac: Bool = true,
                            mA: Int? = 900, at s: Double = 0, since: inout Date?) -> Bool {
    nil != pastLimitEpisode(a, state: st, settled: settled, inControl: serviceInControl, adapter: ac, limit: c.limit, percent: pct, amperage: mA, watts: 0,
                            since: &since, now: at(s))
}

func hp(_ s: String, _ m: Int = 4200, cycles: Int? = 100, calibration: Bool? = nil) -> HealthSample {
    HealthSample(date: d(s), fullChargeCapacityMAh: m, nominalCapacityMAh: m + 100, designCapacityMAh: 4800, cycleCount: cycles, fromCalibration: calibration)
}

func aboveLimitHoldsBelowLimitCharges() {
    var c = Config(); c.limit = 50
    var r = Runtime()
    assert(tick(c, &r, 80) == .hold(at: 80) && r.state == .pause)
    r = Runtime(); c.limit = 60
    assert(tick(c, &r, 17) == .charge(to: 60) && r.state == .charging)
    assert(tick(c, &r, 60) == .hold(at: 60))
}

func manualDischargeStopsAtLimit() {
    var r = Runtime(); r.discharge = true
    assert(tick(c, &r, 90) == .discharge && r.state == .discharging)
    assert(tick(c, &r, 80) == .hold(at: 80) && !r.discharge)
}

func drainAboveLimitOnAdapterDrainsThenHolds() {
    var c = Config(); c.drainAboveLimitOnAdapter = true
    var r = Runtime()
    assert(tick(c, &r, 90) == .discharge)
    assert(tick(c, &r, 80) == .hold(at: 80))
}

func idleRangeKeepsPauseUntilBelowRange() {
    var c = Config(); c.idle = true; c.idleRange = 10
    var r = Runtime()
    _ = tick(c, &r, 80)
    _ = tick(c, &r, 74, ac: false)
    assert(tick(c, &r, 74) == .hold(at: 74) && r.state == .idle)
    _ = tick(c, &r, 62, ac: false)
    assert(tick(c, &r, 62) == .charge(to: 80))
    assert(tick(c, &r, 75) == .charge(to: 80))
    assert(tick(c, &r, 80) == .hold(at: 80))
}

func topUpChargesTo100AndClearsOnUnplug() {
    var r = Runtime(); r.topUp = true
    assert(tick(c, &r, 85) == .charge(to: 100) && r.state == .topup)
    _ = tick(c, &r, 100, ac: false)
    assert(!r.topUp)
}

func heatProtectBlocksThenRechecksAfterHeatWindow() {
    var c = Config(); c.heatProtect = true; c.maxTemp = 35
    var r = Runtime()
    assert(tick(c, &r, 45, temp: 36, at: 0) == .hold(at: 45) && r.state == .heatProtect)
    assert(tick(c, &r, 45, temp: 30, at: heatProtectHysteresis - 200) == .hold(at: 45))
    assert(tick(c, &r, 45, temp: 30, at: heatProtectHysteresis) == .charge(to: 80))
    assert(tick(c, &r, 46, temp: 40, at: heatProtectHysteresis + 100) == .charge(to: 80), "charges at least one heat window")
    assert(tick(c, &r, 46, temp: 40, at: 2 * heatProtectHysteresis) == .hold(at: 46))
}

func calibrationRunsFullCycle() {
    var r = Runtime(); r.calibration = .chargeFull
    assert(tick(c, &r, 70) == .charge(to: 100))
    _ = tick(c, &r, 100, at: 0); assert(r.calibration == .dischargeTo10)
    assert(tick(c, &r, 50, at: 10) == .discharge)
    _ = tick(c, &r, 10, at: 20); assert(r.calibration == .rechargeFull)
    let holdStart: TimeInterval = 30
    _ = tick(c, &r, 100, at: holdStart); assert(r.calibration == .hold)
    assert(tick(c, &r, 100, at: holdStart + calibrationRestDuration - 1) == .hold(at: 100))
    _ = tick(c, &r, 100, at: holdStart + calibrationRestDuration); assert(r.calibration == .returnToLimit)
    assert(tick(c, &r, 95, at: 4000) == .discharge)
    assert(tick(c, &r, 80, at: 5000) == .hold(at: 80) && r.calibration == nil && r.state == .pause)
}

func calibrationFinishedOnlyWhenRestEnds() {
    var r = Runtime(); r.calibration = .rechargeFull
    var finished: [Bool] = []
    for (pct, t) in [(100, 0.0), (100, calibrationRestDuration - 1), (100, calibrationRestDuration), (95, 4000), (80, 5000)] as [(Int, TimeInterval)] {
        let from = r.calibration
        _ = tick(c, &r, pct, at: t)
        finished.append(calibrationFinished(from: from, to: r.calibration))
    }
    assert(finished == [false, false, true, false, false])
    assert(!calibrationFinished(from: .hold, to: nil) && !calibrationFinished(from: .returnToLimit, to: nil))
}

func calibrationNoticeSeedsThenNotifiesOncePerResult() {
    let t0 = at(1000), t1 = at(2000)
    assert(calibrationNotice(end: t0, handled: nil) == .rememberWithoutBanner(t0))
    assert(calibrationNotice(end: nil, handled: nil) == .rememberWithoutBanner(.distantPast))
    assert(calibrationNotice(end: t0, handled: .distantPast) == .notify)
    assert(calibrationNotice(end: t0, handled: t0) == .none && calibrationNotice(end: nil, handled: t0) == .none)
    assert(calibrationNotice(end: t1, handled: t0) == .notify)
}

func calibrationSummaryShowsBeforeAfterHealth() {
    let before = BatterySnapshot(date: Date(), fullChargeCapacityMAh: 7100, nominalCapacityMAh: 7344, designCapacityMAh: 8579, cycleCount: 277, percent: 60)
    var after = before; after.fullChargeCapacityMAh = 7180; after.cycleCount = 278
    assert(String(format: "%.1f", before.healthPercent!) == "82.8" && String(format: "%.1f", before.nominalHealthPercent!) == "85.6")
    assert(calibrationSummary(before: before, after: after) == "7100→7180 mAh, health 82.8→83.7 %, 278 cycles")
    assert(calibrationSummary(before: nil, after: after) == "7180 mAh, health 83.7 %, 278 cycles")
    after.designCapacityMAh = nil
    assert(after.healthPercent == nil && calibrationSummary(before: before, after: after) == "7100→7180 mAh, 278 cycles")
}

func heatNoticeOncePerEpisode() {
    var latch = NoticeLatch(previousLimit: 80)
    assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, limit: 80, latch: &latch) == [.heatProtect])
    assert(serviceNotices(from: .heatProtect, to: .heatProtect, adapter: true, limit: 80, latch: &latch) == [])
    assert(serviceNotices(from: .heatProtect, to: .charging, adapter: true, limit: 80, latch: &latch) == [])
    assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, limit: 80, latch: &latch) == [.heatProtect], "pause after cooling is a new episode")
    assert(serviceNotices(from: .heatProtect, to: .charging, adapter: true, limit: 80, latch: &latch) == [])
}

func heatNoticeStillSentAfterLimitNotice() {
    var latch = NoticeLatch(limitNoticeSent: true, previousLimit: 80)
    assert(serviceNotices(from: .charging, to: .heatProtect, adapter: true, limit: 80, latch: &latch) == [.heatProtect])
}

func limitNoticeOncePerChargingSession() {
    var latch = NoticeLatch(previousLimit: 80)
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: 80, latch: &latch) == [.limitReached])
    assert(serviceNotices(from: .pause, to: .charging, adapter: true, limit: 80, latch: &latch) == [])
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: 80, latch: &latch) == [])
    assert(serviceNotices(from: .calibration, to: .pause, adapter: true, limit: 80, latch: &latch) == [])
}

func unplugResetsLimitNotice() {
    var latch = NoticeLatch(limitNoticeSent: true, previousLimit: 80)
    assert(serviceNotices(from: .pause, to: .discharging, adapter: false, limit: 80, latch: &latch) == [] && !latch.limitNoticeSent)
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: 80, latch: &latch) == [.limitReached])
}

func limitChangeRearmsLimitNotice() {
    let seenLimit = 80, loweredLimit = 70, raisedLimit = 90
    var latch = NoticeLatch(previousLimit: seenLimit)
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: loweredLimit, latch: &latch) == [], "pause from a lowered limit")
    assert(serviceNotices(from: .pause, to: .charging, adapter: true, limit: raisedLimit, latch: &latch) == [])
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: raisedLimit, latch: &latch) == [.limitReached])
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: seenLimit, latch: &latch) == [])
}

func firstTickAfterRestartGivesNoLimitNotice() {
    var latch = NoticeLatch()
    assert(serviceNotices(from: .charging, to: .pause, adapter: true, limit: 80, latch: &latch) == [])
}

func historyEventsRenderInEnglish() {
    assert(historyText(calibrationDoneEntry) == "Calibration complete: 7100 → 7180 mAh, health 82.8 → 83.7 %, 278 cycles")
    assert(historyText(HistoryEntry(event: .calibrationDone)) == "Calibration complete")
    assert(historyText(HistoryEntry(event: .calibrationPhase, phase: .dischargeTo10)) == "Calibration: discharging to 10 %")
    assert(historyText(HistoryEntry(event: .taskRun, action: .setLimit, caughtUpOnWake: true, percent: 60)) == "Missed task run on wake: Set charge limit (60 %)")
    assert(historyText(HistoryEntry(event: .taskRun, action: .topUp, caughtUpOnWake: false)) == "Scheduled task: Charge to 100%")
    assert(historyText(HistoryEntry(event: .heatProtect, temperature: 36.24)) == "Heat protection: charging paused at 36.2 °C")
    assert(historyText(HistoryEntry(event: .chargedPastLimit, percent: 85)) == "macOS charged the battery above 85 %")
    assert(historyText(HistoryEntry(event: .limitChanged, percent: 75)) == "Charge limit set to 75 %")
}

func legacyHistoryTextMapsToEvents() {
    assert(historyText(HistoryEntry(text: "calibration done: 7100→7180 mAh, health 82.8→83.7 %, 278 cycles")) == historyText(calibrationDoneEntry))
    assert(historyText(HistoryEntry(text: "calibration done: 7180 mAh, 278 cycles")) == "Calibration complete: 7180 mAh, 278 cycles")
    assert(parsedLegacyHistory(HistoryEntry(text: "calibration: dischargeTo10")).phase == .dischargeTo10)
    assert(parsedLegacyHistory(HistoryEntry(text: "calibration: back to limit")).event == .calibrationEnded)
    assert(parsedLegacyHistory(HistoryEntry(text: "calibration started")).event == .calibrationStarted)
    let caught = parsedLegacyHistory(HistoryEntry(text: "task calibrate (caught up)"))
    assert(caught.event == .taskRun && caught.action == .calibrate && caught.caughtUpOnWake == true)
    assert(parsedLegacyHistory(HistoryEntry(text: "task skipped (missed): topUp")).event == .taskSkipped)
    assert(historyText(HistoryEntry(text: "Limit 80 %")) == "Limit 80 %", "unknown text stays as is")
}

func unknownHistoryEventFallsBackToText() {
    let decoded = try! JSONDecoder().decode([HistoryEntry].self, from: Data(#"[{"date":0,"text":"x","event":"future"},{"date":0,"text":"calibration stopped"}]"#.utf8))
    assert(decoded[0].event == nil && historyText(decoded[0]) == "x" && historyText(decoded[1]) == "Calibration stopped")
}

func olderAppsReadHistoryText() {
    struct OldEntry: Codable { var date: Date; var text: String }
    var stored = calibrationDoneEntry; stored.text = historyText(calibrationDoneEntry)
    assert(try! JSONDecoder().decode(OldEntry.self, from: JSONEncoder().encode(stored)).text == historyText(calibrationDoneEntry))
    assert(try! JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(stored)) == stored)
}

func historyRendersInFrench() {
    useLanguage("fr")
    defer { useLanguage("system") }
    assert(localizedHistory(calibrationDoneEntry) == "Calibration terminée : 7100 → 7180\u{00A0}mAh, santé 82,8 → 83,7\u{00A0}%, 278 cycles")
    assert(localizedHistory(HistoryEntry(event: .calibrationPhase, phase: .dischargeTo10)) == "Calibration : décharge jusqu'à 10\u{00A0}%")
}

func localeFollowsTextLanguageKeepsRegion() {
    assert(uiLocale(language: "en", preferred: "fr-FR").language.languageCode?.identifier == "en")
    assert(uiLocale(language: "fr", preferred: "fr-CA").region?.identifier == "CA")
    assert(uiLocale(language: "en", preferred: nil).identifier == "en")
    useLanguage("system")
    assert(appLocale.language.languageCode?.identifier == appLanguage)
}

func numbersDatesAndDurationsFollowFrench() {
    useLanguage("fr")
    defer { useLanguage("system") }
    assert(celsius(31.24) == "31,2 °C" && celsius(nil) == "--" && watts(13.4) == "13,4 W")
    var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
    let oct30 = paris.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 21, minute: 5))!
    assert(dateTime(oct30).contains("oct.") && dateTime(oct30).contains("2026") && !dateTime(oct30).contains("PM"), dateTime(oct30))
    assert(approxDuration(1500) == "~25 min" && approxDuration(3900) == "~1 h 05 min")
    assert(tr("%@ to %@ %%", approxDuration(1500), "80") == "~25 min jusqu'à 80 %")
}

func menuAndNotificationStringsAreTranslated() {
    useLanguage("fr")
    defer { useLanguage("system") }
    assert(tr("Plug in the adapter to continue calibration") != "Plug in the adapter to continue calibration")
    assert(tr("Calibration paused") == "Calibration en pause" && tr("Calibration needs the adapter") == "Calibration en attente de l'adaptateur")
    assert(tr("%@ min left", "35") == "encore 35 min" && tr("Step %d/%d", 2, 5) == "Étape 2/5")
    assert(tr("Before: %@", "4210 mAh") == "Avant : 4210 mAh" && tr("%@ %% reached", "80") == "80 % atteint")
    assert(localizedHistory(HistoryEntry(event: .chargedPastLimit, percent: 85)) == "macOS a chargé la batterie au-delà de 85\u{00A0}%")
    assert(localizedHistory(HistoryEntry(event: .chargedPastLimit)) == "macOS a chargé la batterie au-delà de la limite")
    assert(tr("Battery is above the limit while plugged in (macOS charged it). ChargeKeeper holds this level and does not discharge. Turn on Automatic discharge to return to the limit.")
           == "La batterie dépasse la limite sur secteur (chargée par macOS). ChargeKeeper maintient ce niveau sans décharger. Activez la décharge automatique pour revenir à la limite.")
    assert(tr("Battery is above the limit while plugged in (macOS charged it). ChargeKeeper discharges it back to the limit.") == "La batterie dépasse la limite sur secteur (chargée par macOS). ChargeKeeper la décharge jusqu'à la limite.")
    assert(tr("Apple's Charge Limit is set to %@ %% in System Settings. Set it to 100 %% to let ChargeKeeper manage charging.", "80")
           == "La limite de recharge d'Apple est réglée à 80 % dans Réglages Système. Réglez-la sur 100 % pour laisser ChargeKeeper gérer la recharge.")
    for k in ["macOS battery settings", "Open Battery Settings",
              "Turn off Optimized Battery Charging in System Settings > Battery: it can conflict with ChargeKeeper's limit."] { assert(tr(k) != k, k) }
}

func everyHistoryTemplateAndBannerHasFrench() {
    let samples = [calibrationDoneEntry, HistoryEntry(event: .calibrationNeedsAdapter, phase: .hold), HistoryEntry(event: .calibrationDone),
                   HistoryEntry(event: .calibrationStarted), HistoryEntry(event: .calibrationStopped),
                   HistoryEntry(event: .calibrationEnded), HistoryEntry(event: .limitChanged, percent: 80), HistoryEntry(event: .heatProtect),
                   HistoryEntry(event: .heatProtect, temperature: 36), HistoryEntry(event: .taskSkipped, action: .calibrate),
                   HistoryEntry(event: .chargedPastLimit), HistoryEntry(event: .chargedPastLimit, percent: 80),
                   HistoryEntry(event: .keepAwakeTimeUp), HistoryEntry(event: .keepAwakeLowBattery, percent: 19), HistoryEntry(event: .keepAwakeFailed)]
        + [CalibrationPhase.chargeFull, .dischargeTo10, .rechargeFull, .hold, .returnToLimit].map { HistoryEntry(event: .calibrationPhase, phase: $0) }
        + TaskAction.allCases.flatMap { a in [false, true].map { HistoryEntry(event: .taskRun, action: a, caughtUpOnWake: $0, percent: 60) } }
    var templates: Set<String> = []
    for e in samples { _ = historyText(e, { templates.insert($0); return englishTemplate($0, $1) }) }
    let bannerAndNotificationSettingsStrings = ["Heat protection", "Charge limit reached", "Calibration complete", "Heat protection paused charging", "Notifications",
                                                "Shown only while ChargeKeeper is running. Allow ChargeKeeper in System Settings > Notifications.",
                                                "Charging paused: battery at %@ °C (max %@ °C).", "Battery at %@ %%. Charging paused at the limit.",
                                                "Capacity: %@ → %@ mAh", "Health: %@ → %@ %%", "Finished %@"]
    templates.formUnion(bannerAndNotificationSettingsStrings)
    for k in templates { assert(french[k] != nil, "no French for \(k)") }
}

func timeToTargetFromCurrentAndCapacity() {
    let watts2000mAAt11_4V = 22.8
    assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: 2000, watts: 0) == 1800)
    assert(timeToTarget(percent: 90, target: 80, capacity: 5000, amperage: -1000, watts: 0) == 1800)
    assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: nil, watts: watts2000mAAt11_4V) == 1800)
}

func timeToTargetIsAtLeastOneMinute() {
    assert(timeToTarget(percent: 79, target: 80, capacity: 1000, amperage: 5000, watts: 0) == 60)
}

func timeToTargetIsNilWhenReachedIdleWrongWayOrNoCapacity() {
    assert(timeToTarget(percent: 80, target: 80, capacity: 5000, amperage: 2000, watts: 0) == nil)
    assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: 20, watts: 0) == nil)
    assert(timeToTarget(percent: 60, target: 80, capacity: 5000, amperage: -2000, watts: 0) == nil)
    assert(timeToTarget(percent: 60, target: 80, capacity: nil, amperage: 2000, watts: 0) == nil)
}

func timeToTargetIsNilOver24Hours() {
    assert(timeToTarget(percent: 10, target: 100, capacity: 5000, amperage: 60, watts: 0) == nil)
}

func calibrationProgressReportsStepAndTarget() {
    assert(calibrationStep(.chargeFull) == (1, 5) && calibrationStep(.dischargeTo10) == (2, 5) && calibrationStep(.returnToLimit) == (5, 5))
    assert(calibrationTargetPercent(.dischargeTo10, limit: 80) == 10 && calibrationTargetPercent(.returnToLimit, limit: 80) == 80 && calibrationTargetPercent(.hold, limit: 80) == nil)
}

func calibrationRestReportsTimeLeft() {
    assert(calibrationRestRemaining(phaseStart: at(0), now: at(1500)) == calibrationRestDuration - 1500)
    assert(calibrationRestRemaining(phaseStart: at(0), now: at(calibrationRestDuration + 1400)) == 0)
}

func calibrationNeedsAdapterInChargingAndRestPhasesOnly() {
    assert(calibrationNeedsAdapter(.hold) && !calibrationNeedsAdapter(.dischargeTo10) && !calibrationNeedsAdapter(nil))
}

func adapterNoticeOnFirstTickAfterRestart() {
    var an = AdapterNoticeState()
    assert(adapterNotice(phase: .hold, adapter: false, now: at(0), &an) == .first)
}

func adapterNoticeOncePerWaitAcrossRestAndRecharge() {
    var an = AdapterNoticeState()
    _ = adapterNotice(phase: .hold, adapter: false, now: at(0), &an)
    assert(adapterNotice(phase: .hold, adapter: false, now: at(5), &an) == .none)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(10), &an) == .none)
}

func adapterNoticeRateLimitedAcrossShortUnplugs() {
    var an = AdapterNoticeState()
    _ = adapterNotice(phase: .rechargeFull, adapter: false, now: at(0), &an)
    assert(adapterNotice(phase: .rechargeFull, adapter: true, now: at(60), &an) == .none)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(adapterNoticeGap - 1), &an) == .none)
    assert(adapterNotice(phase: .rechargeFull, adapter: true, now: at(adapterNoticeGap), &an) == .none)
    assert(adapterNotice(phase: .chargeFull, adapter: false, now: at(adapterNoticeGap + 1), &an) == .first)
}

func rateLimitedWaitStartsItsOwnReminderTimer() {
    var an = AdapterNoticeState()
    _ = adapterNotice(phase: .rechargeFull, adapter: false, now: at(0), &an)
    _ = adapterNotice(phase: .rechargeFull, adapter: true, now: at(60), &an)
    let secondUnplug: TimeInterval = 120
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(secondUnplug), &an) == .none)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(secondUnplug + adapterReminderAfter - 1), &an) == .none)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(secondUnplug + adapterReminderAfter), &an) == .reminder)
}

func adapterNoticeRemindsOnceAfterReminderDelay() {
    var an = AdapterNoticeState()
    _ = adapterNotice(phase: .rechargeFull, adapter: false, now: at(0), &an)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(adapterReminderAfter - 1), &an) == .none)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(adapterReminderAfter), &an) == .reminder)
    assert(adapterNotice(phase: .rechargeFull, adapter: false, now: at(3 * adapterReminderAfter), &an) == .none)
}

func adapterNoticeOnlyInPhasesNeedingAdapter() {
    var an = AdapterNoticeState()
    assert(adapterNotice(phase: .dischargeTo10, adapter: false, now: at(0), &an) == .none)
    assert(adapterNotice(phase: nil, adapter: false, now: at(0), &an) == .none)
}

func calibrationRestCountsOnlyOnAdapter() {
    var r = Runtime(); r.calibration = .hold; r.phaseStart = at(0)
    assert(tick(c, &r, 100, at: 1800) == .hold(at: 100))
    _ = tick(c, &r, 100, ac: false, at: 3000)
    _ = tick(c, &r, 100, ac: false, at: 4000); assert(r.calibration == .hold)
    assert(!calibrationFinished(from: .hold, to: r.calibration))
    let replug: TimeInterval = 7000
    _ = tick(c, &r, 100, at: replug); assert(r.calibration == .hold)
    _ = tick(c, &r, 100, at: replug + calibrationRestDuration - 100); assert(r.calibration == .hold)
    _ = tick(c, &r, 100, at: replug + calibrationRestDuration + 100); assert(r.calibration == .returnToLimit)
}

func unpluggedCalibrationRestLeavesRuntimeUnchanged() {
    var r = Runtime(); r.calibration = .hold; r.phaseStart = at(0)
    _ = tick(c, &r, 100, ac: false, at: 1000)
    let firstUnpluggedTick = r
    _ = tick(c, &r, 100, ac: false, at: 2000)
    assert(r == firstUnpluggedTick)
}

func calibrationRestBelow100RechargesFirst() {
    var r = Runtime(); r.calibration = .hold; r.phaseStart = at(0)
    assert(tick(c, &r, 99, ac: false, at: 3700) == .charge(to: 100) && r.calibration == .rechargeFull)
    assert(tick(c, &r, 99, at: 3800) == .charge(to: 100))
    let full: TimeInterval = 3900
    _ = tick(c, &r, 100, at: full); assert(r.calibration == .hold)
    _ = tick(c, &r, 100, at: full + calibrationRestDuration - 100); assert(r.calibration == .hold)
    _ = tick(c, &r, 100, at: full + calibrationRestDuration); assert(r.calibration == .returnToLimit)
}

func calibrationRestWithoutStartBeginsOnAdapter() {
    var r = Runtime(); r.calibration = .hold
    let start: TimeInterval = 1000
    _ = tick(c, &r, 100, at: start); assert(r.calibration == .hold && r.phaseStart == at(start))
    _ = tick(c, &r, 100, at: start + calibrationRestDuration - 100); assert(r.calibration == .hold)
    _ = tick(c, &r, 100, at: start + calibrationRestDuration + 100); assert(r.calibration == .returnToLimit)
}

func nativeLimitRoundingIsNotAnEpisode() {
    var since: Date? = nil
    assert(!pastLimitEpisodeStarts(.hold(at: 80), 80 + nativeChargeLimitStepPercent - 1, since: &since) && since == nil)
}

func aboveLimitWhileNotChargingIsNotAnEpisode() {
    var since: Date? = nil
    assert(!pastLimitEpisodeStarts(.hold(at: 80), 80 + nativeChargeLimitStepPercent, mA: 0, since: &since) && since == nil)
}

func pastLimitEpisodeStartsOnceAndEndsWhenLevelIsBack() {
    var since: Date? = nil
    assert(pastLimitEpisodeStarts(.hold(at: 80), 80 + nativeChargeLimitStepPercent, at: 10, since: &since) && since == at(10))
    assert(!pastLimitEpisodeStarts(.hold(at: 80), 99, at: 20, since: &since) && !pastLimitEpisodeStarts(.hold(at: 80), 100, mA: 0, at: 30, since: &since))
    assert(since == at(10))
    assert(!pastLimitEpisodeStarts(.hold(at: 80), 80, since: &since) && since == nil)
}

func pastLimitEpisodeReportsHeldLevel() {
    var since: Date? = nil
    assert(pastLimitEpisode(.hold(at: 90), state: .pause, settled: true, inControl: true, adapter: true, limit: 80, percent: 95, amperage: 900,
                            watts: 0, since: &since, now: Date()) == 90)
}

func unplugEndsPastLimitEpisode() {
    var since: Date? = nil
    assert(pastLimitEpisodeStarts(.hold(at: 80), 90, since: &since) && !pastLimitEpisodeStarts(.hold(at: 80), 92, ac: false, since: &since) && since == nil)
}

func modesThatChargeOnPurposeAreNotPastLimitEpisodes() {
    var since: Date? = nil
    assert(!pastLimitEpisodeStarts(.charge(to: 100), 95, .topup, since: &since) && !pastLimitEpisodeStarts(.hold(at: 100), 100, .calibration, since: &since))
    assert(!pastLimitEpisodeStarts(.hold(at: 60), 70, .heatProtect, since: &since) && since == nil)
}

func pastLimitEpisodeWhileDrainingUsesWattsWhenNoAmperage() {
    var since: Date? = nil
    assert(80 == pastLimitEpisode(.discharge, state: .discharging, settled: true, inControl: true, adapter: true, limit: 80, percent: 90, amperage: nil, watts: 10,
                                  since: &since, now: Date()))
    since = nil
    assert(nil == pastLimitEpisode(.discharge, state: .discharging, settled: true, inControl: true, adapter: true, limit: 80, percent: 90, amperage: nil, watts: -10,
                                   since: &since, now: Date()))
}

func failedOwnActionIsNotBlamedOnMacOS() {
    var since: Date? = nil
    assert(!pastLimitEpisodeStarts(.discharge, 90, .discharging, serviceInControl: false, since: &since))
    assert(!pastLimitEpisodeStarts(.hold(at: 70), 80, serviceInControl: false, since: &since) && since == nil)
}

func noPastLimitEpisodeOnTheTickThatChangesMode() {
    var since: Date? = nil
    var pc = Config(); pc.limit = 80; pc.drainAboveLimitOnAdapter = true
    var pr = Runtime()
    assert(tick(pc, &pr, 78) == .charge(to: 80) && pr.state == .charging)
    pc.limit = 70
    let pa = tick(pc, &pr, 78)
    assert(pa == .discharge && pr.state == .discharging)
    let amperageReadBeforeNewActionMA = 2000
    assert(nil == pastLimitEpisode(pa, state: pr.state, settled: false, inControl: true, adapter: true, limit: 70, percent: 78,
                                   amperage: amperageReadBeforeNewActionMA, watts: 0, since: &since, now: Date()))
    assert(nil == pastLimitEpisode(pa, state: pr.state, settled: true, inControl: true, adapter: true, limit: 70, percent: 78, amperage: -2000, watts: 0,
                                   since: &since, now: Date()), "discharge has taken over on the next tick")
    assert(since == nil)
}

func noPastLimitEpisodeOnModeChangeViaDischargeTo() {
    var since: Date? = nil
    var pc = Config(); pc.limit = 80
    var pr = Runtime()
    _ = tick(pc, &pr, 78)
    pc.limit = 70; pr.discharge = true
    assert(tick(pc, &pr, 78) == .discharge)
    assert(nil == pastLimitEpisode(.discharge, state: pr.state, settled: false, inControl: true, adapter: true, limit: 70, percent: 78, amperage: 2000, watts: 0,
                                   since: &since, now: Date()))
}

func systemSettingsChargeLimitCountsOnlyWhenEnabledIn50to99() {
    let failedRead = -1
    assert(userChargeLimit(enabled: 1, limit: 80) == 80 && userChargeLimit(enabled: 0, limit: 80) == nil)
    assert(userChargeLimit(enabled: 1, limit: 100) == nil && userChargeLimit(enabled: failedRead, limit: 80) == nil)
    assert(userChargeLimit(enabled: 1, limit: failedRead) == nil && userChargeLimit(enabled: 1, limit: 0) == nil && userChargeLimit(enabled: 1, limit: 49) == nil)
}

func ledShowsGreenAtLimitAndBlinksOrangeWhenDischarging() {
    var c = Config(); c.led = .indicate
    var r = Runtime(); r.state = .pause
    assert(ledColor(c, r, adapter: true, percent: 80) == .green)
    r.state = .discharging; c.ledBlinkDischarge = true
    assert(ledColor(c, r, adapter: true, percent: 90) == .orangeBlink)
}

func monthlyOn31stSkipsShortMonths() {
    let t = ScheduledTask(action: .calibrate, repeatRule: .monthly, start: d("2026-01-31T09:00:00Z"))
    assert(lastOccurrence(t, after: d("2026-04-01T00:00:00Z"), upTo: d("2026-04-30T23:00:00Z"), calendar: cal) == nil)
    assert(lastOccurrence(t, after: d("2026-05-01T00:00:00Z"), upTo: d("2026-05-31T10:00:00Z"), calendar: cal) == d("2026-05-31T09:00:00Z"))
}

func weekdaysSkipWeekends() {
    let friday = d("2026-10-23T09:00:00Z")
    let t = ScheduledTask(action: .calibrate, repeatRule: .weekdays, start: friday)
    assert(lastOccurrence(t, after: d("2026-10-23T10:00:00Z"), upTo: d("2026-10-25T23:00:00Z"), calendar: cal) == nil)
    assert(lastOccurrence(t, after: d("2026-10-23T10:00:00Z"), upTo: d("2026-10-26T09:30:00Z"), calendar: cal) == d("2026-10-26T09:00:00Z"))
}

func longRunningRepeatsGiveTheirLatestOccurrence() {
    let start = d("2020-01-31T09:00:00Z"), after = d("2026-05-01T00:00:00Z")
    func last(_ rule: Repeat, upTo: String) -> Date? {
        lastOccurrence(ScheduledTask(action: .calibrate, repeatRule: rule, start: start), after: after, upTo: d(upTo), calendar: cal)
    }
    assert(last(.daily, upTo: "2026-05-20T08:00:00Z") == d("2026-05-19T09:00:00Z"))
    assert(last(.weekly, upTo: "2026-05-20T08:00:00Z") == d("2026-05-15T09:00:00Z"))
    assert(last(.biweekly, upTo: "2026-05-20T08:00:00Z") == d("2026-05-15T09:00:00Z"))
    assert(last(.monthly, upTo: "2026-06-30T10:00:00Z") == d("2026-05-31T09:00:00Z"))
    assert(last(.yearly, upTo: "2026-06-30T10:00:00Z") == nil)
}

func oneOffTaskOccursAtItsStart() {
    let t = ScheduledTask(action: .calibrate, repeatRule: .never, start: d("2026-10-23T09:00:00Z"))
    assert(lastOccurrence(t, after: d("2026-10-01T00:00:00Z"), upTo: d("2026-10-24T00:00:00Z"), calendar: cal) == d("2026-10-23T09:00:00Z"))
}

func macWattsIsLoadMinusPortsUnlessPortsExceedLoad() {
    assert(macWattsExcludingPorts(system: 27, ports: [1, 13]) == 13)
    assert(macWattsExcludingPorts(system: 10, ports: [13]) == 10)
}

func powerHistoryDropsPointsOutsideWindow() {
    let older = [0.0, 100, 200].map { SoCPowerPoint(date: at($0), averagePower: pw) }
    assert(appendPowerPoint(older, SoCPowerPoint(date: at(300), averagePower: pw), window: 250) == pwHistory)
}

func powerHistoryDropsPointsDatedAfterTheNewOne() {
    let afterClockJump = [SoCPowerPoint(date: at(400), averagePower: pw)]
    assert(appendPowerPoint(afterClockJump, SoCPowerPoint(date: at(300), averagePower: pw), window: 250) == [SoCPowerPoint(date: at(300), averagePower: pw)])
}

func currentPowerIsNewestWhileFresh() {
    let maxGapWithoutInterval = socStaleAfterIntervals * assumedPowerSampleInterval
    assert(currentPower(pwHistory, now: at(300 + maxGapWithoutInterval)) == pw)
    assert(currentPower(pwHistory, now: at(300 + maxGapWithoutInterval + 1)) == nil && currentPower([], now: Date()) == nil)
}

func currentPowerLastsTwoOwnIntervals() {
    let interval: TimeInterval = 30
    let pw30 = [SoCPowerPoint(date: at(300), averagePower: pw, samplingInterval: interval)]
    assert(currentPower(pw30, now: at(300 + socStaleAfterIntervals * interval)) == pw)
    assert(currentPower(pw30, now: at(300 + socStaleAfterIntervals * interval + 1)) == nil)
}

func powerGapOverTwoIntervalsSplitsCurve() {
    let pwGaps = [0.0, 5, 10, 60, 65, 75].map { SoCPowerPoint(date: at($0), averagePower: pw) }
    assert(powerSegments(pwGaps) == [0, 0, 0, 1, 1, 1] && powerSegments([]).isEmpty)
}

func powerPoints(_ pts: [(TimeInterval, TimeInterval)]) -> [SoCPowerPoint] {
    pts.map { SoCPowerPoint(date: at($0.0), averagePower: pw, samplingInterval: $0.1) }
}

func segmentsAcrossIntervalChange(old: TimeInterval, new: TimeInterval, gap: TimeInterval) -> [Int] {
    powerSegments(powerPoints([(0, old), (old, old), (old + gap, new), (old + gap + new, new)]))
}

func intervalChangeRestartGapDoesNotSplit() {
    let oneToFiveRestartGap = 1 + 2 * 5 + socIntervalChangeSlack
    assert(segmentsAcrossIntervalChange(old: 1, new: 5, gap: 11.55) == [0, 0, 0, 0])
    assert(segmentsAcrossIntervalChange(old: 1, new: 5, gap: oneToFiveRestartGap) == [0, 0, 0, 0])
    assert(segmentsAcrossIntervalChange(old: 1, new: 5, gap: oneToFiveRestartGap + 0.01) == [0, 0, 1, 1])
    assert(segmentsAcrossIntervalChange(old: 5, new: 1, gap: 12) == [0, 0, 0, 0] && segmentsAcrossIntervalChange(old: 5, new: 1, gap: 12.01) == [0, 0, 1, 1])
    assert(segmentsAcrossIntervalChange(old: 1, new: 30, gap: 66) == [0, 0, 0, 0] && segmentsAcrossIntervalChange(old: 1, new: 30, gap: 66.01) == [0, 0, 1, 1])
    assert(segmentsAcrossIntervalChange(old: 30, new: 1, gap: 60) == [0, 0, 0, 0] && segmentsAcrossIntervalChange(old: 30, new: 1, gap: 60.01) == [0, 0, 1, 1])
}

func realGapAfterIntervalChangeStillSplits() {
    assert(powerSegments(powerPoints([(0, 30), (30, 30), (60, 30), (61.5, 1), (62.5, 1), (63.5, 1), (66, 1)])) == [0, 0, 0, 0, 0, 0, 1])
}

func appRefreshFollowsShortPowerIntervalElsePollInterval() {
    assert(PowerInterval.allCases.map(appRefreshInterval) == [appMaxRefreshInterval, 1, 2, 2, 2, 2])
}

func powermetricsArgumentsFixedExceptIntervalMs() {
    assert(powermetricsArguments(.off) == nil)
    assert(powermetricsArguments(.s1) == ["--samplers", "cpu_power,gpu_power", "-i", "1000", "-f", "plist"])
    let intervalMsIndex = 3
    for i in PowerInterval.allCases where i != .off {
        var a = powermetricsArguments(i)!
        assert(a[intervalMsIndex] == String(i.rawValue * 1000), "\(i)")
        a[intervalMsIndex] = "5000"
        assert(a == powermetricsArguments(.s5)!)
    }
}

func powerIntervalDefaultsToFiveSeconds() {
    var pwConfig = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
    assert(Config().powerInterval == .s5 && pwConfig["powerInterval"] as? Int == 5)
    pwConfig["powerInterval"] = nil
    assert(try! JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: pwConfig)).powerInterval == .s5, "config without it")
}

func powerIntervalDecodesListedValues() {
    var pwConfig = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
    pwConfig["powerInterval"] = 1
    assert(try! JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: pwConfig)).powerInterval == .s1)
    pwConfig["powerInterval"] = 0
    assert(try! JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: pwConfig)).powerInterval == .off)
    pwConfig["powerInterval"] = 2
    if case .setConfig(let c)? = try? JSONDecoder().decode(Command.self, from: JSONSerialization.data(withJSONObject: ["setConfig": ["_0": pwConfig]])) {
        assert(c.powerInterval == .s2)
    } else { assert(false) }
}

func powerIntervalOutsideListFailsDecode() {
    var pwConfig = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
    pwConfig["powerInterval"] = 3
    assert((try? JSONDecoder().decode(Command.self, from: JSONSerialization.data(withJSONObject: ["setConfig": ["_0": pwConfig]]))) == nil)
}

func replyOmitsStalePowerPoints() {
    assert(recentPowerPoints(pwHistory, now: at(420), window: 250).map(\.date.timeIntervalSince1970) == [200, 300])
    assert(recentPowerPoints(pwHistory, now: at(1000), window: 250).isEmpty)
}

func powermetricsStreamTakesNulTerminatedSamplesKeepsTail() {
    var pmBuffer = Data("a\0\0b\0par".utf8)
    let pmTaken = takePlistSamples(&pmBuffer, maxBytes: 10)
    assert(pmTaken.samples == [Data("a".utf8), Data("b".utf8)] && !pmTaken.dropped && pmBuffer == Data("par".utf8))
}

func oversizedPowermetricsTailIsDropped() {
    var pmBuffer = Data("partial sample".utf8)
    let pmOversized = takePlistSamples(&pmBuffer, maxBytes: 10)
    assert(pmOversized.samples.isEmpty && pmOversized.dropped && pmBuffer.isEmpty)
}

func pmSample(_ root: [String: Any]) -> Data { try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0) }

let trimmedM4ProPowermetricsSample = Data(#"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>elapsed_ns</key><integer>1016464625</integer>
	<key>gpu</key>
	<dict>
		<key>gpu_energy</key><integer>34</integer>
		<key>idle_ratio</key><real>0.895009</real>
	</dict>
	<key>hw_model</key><string>Mac16,7</string>
	<key>is_delta</key><true/>
	<key>processor</key>
	<dict>
		<key>ane_energy</key><integer>0</integer>
		<key>ane_power</key><real>0.0</real>
		<key>combined_power</key><real>244.967</real>
		<key>cpu_energy</key><integer>214</integer>
		<key>cpu_power</key><real>210.534</real>
		<key>gpu_energy</key><integer>35</integer>
		<key>gpu_power</key><real>34.4331</real>
	</dict>
	<key>timestamp</key><date>2026-11-07T21:40:04Z</date>
</dict>
</plist>
"""#.utf8)

func powermetricsSampleConvertsMillijoulesOverElapsedToWatts() {
    let pm = socPower(plist: trimmedM4ProPowermetricsSample)!
    let elapsedS = 1.016464625, cpuEnergyJ = 0.214, processorGpuEnergyJ = 0.035
    assert(abs(pm.cpuWatts - cpuEnergyJ / elapsedS) < 1e-12 && abs(pm.gpuWatts - processorGpuEnergyJ / elapsedS) < 1e-12 && pm.aneWatts == 0)
}

func powerFallsBackToDefaultIntervalWithoutElapsed() {
    assert(socPower(plist: pmSample(["processor": ["cpu_energy": 15000, "gpu_energy": 5000]])) == SoCPower(cpuWatts: 3, gpuWatts: 1, aneWatts: 0))
}

func malformedPowermetricsSampleIsRejected() {
    assert(socPower(plist: Data("garbage".utf8)) == nil && socPower(plist: pmSample(["processor": ["cpu_energy": 1]])) == nil)
    assert(socPower(plist: pmSample(["elapsed_ns": 1, "processor": ["cpu_energy": 3000, "gpu_energy": 1000]])) == nil, "absurd values")
}

func statusSocFlagIsOptionalBothWays() {
    assert(String(data: try! JSONEncoder().encode(Command.status()), encoding: .utf8) == #"{"status":{}}"#)
    if case .status(let soc) = try! JSONDecoder().decode(Command.self, from: Data(#"{"status":{"soc":true}}"#.utf8)) { assert(soc == true) } else { assert(false) }
}

func statusWithoutSocHistoryDecodesNil() {
    var socStatus = Status(config: Config(), runtime: Runtime(), percent: 80, hardwarePercent: nil, adapter: true, temperature: nil, adapterWatts: 0, adapterRatedWatts: nil, systemWatts: 0, batteryChargeWatts: 0, nativeLimit: true, sleepDisabled: false, history: [])
    socStatus.socHistory = [SoCPowerPoint(date: at(0), averagePower: SoCPower(cpuWatts: 1, gpuWatts: 2, aneWatts: 0))]
    assert(try! JSONDecoder().decode(Status.self, from: JSONEncoder().encode(socStatus)).socHistory == socStatus.socHistory)
    var olderService = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(socStatus)) as! [String: Any]
    olderService["socHistory"] = nil
    assert(try! JSONDecoder().decode(Status.self, from: JSONSerialization.data(withJSONObject: olderService)).socHistory == nil)
}

func powerFlowLabelsSpreadWithinHeight() {
    assert(spreadLabels([50, 51, 52], gap: 14, height: 200) == [50, 64, 78])
    assert(spreadLabels([100, 108], gap: 14, height: 110) == [89, 103])
}

func deviceIconMatchesAppleNamesElseGeneric() {
    assert(deviceIcon("iPhone") == "iphone" && deviceIcon("AirPods Charging Case") == "airpods" && deviceIcon(nil) == "cable.connector")
}

func healthSampleNeedsBothCapacities() {
    let snap = BatterySnapshot(date: d("2026-10-01T12:00:00Z"), fullChargeCapacityMAh: 4200, nominalCapacityMAh: 4300, designCapacityMAh: 4800, cycleCount: 100, temperature: nil, percent: 80)
    assert(healthSample(snap)?.healthPercent == 87.5 && healthSample(snap)?.fromCalibration == nil && healthSample(snap, calibration: true)?.fromCalibration == true)
    var noDesign = snap; noDesign.designCapacityMAh = 0
    assert(healthSample(noDesign) == nil)
}

func healthSampleDueOncePerCalendarDay() {
    assert(healthSampleDue([], now: d("2026-10-01T12:00:00Z"), calendar: cal))
    assert(!healthSampleDue([hp("2026-10-01T00:30:00Z")], now: d("2026-10-01T23:00:00Z"), calendar: cal))
    assert(healthSampleDue([hp("2026-10-01T23:00:00Z")], now: d("2026-10-02T00:10:00Z"), calendar: cal))
    assert(!healthSampleDue([hp("2026-09-01T12:00:00Z"), hp("2026-10-01T12:00:00Z")], now: d("2026-09-01T18:00:00Z"), calendar: cal), "clock moved back")
}

func healthSeriesThinsToWeeklyAfterDailyKeepDays() {
    let now = d("2026-10-01T12:00:00Z")
    var series: [HealthSample] = []
    var day = d("2025-01-01T12:00:00Z")
    while day <= now {
        series = addHealthSample(series, HealthSample(date: day, fullChargeCapacityMAh: 4200, nominalCapacityMAh: nil, designCapacityMAh: 4800, cycleCount: nil, fromCalibration: nil), now: day, calendar: cal)
        day = day.addingTimeInterval(secondsPerDay)
    }
    series = addHealthSample(series, hp("2025-03-05T18:00:00Z", calibration: true), now: now, calendar: cal)
    assert(zip(series, series.dropFirst()).allSatisfy { $0.date <= $1.date })
    let cutoff = now.addingTimeInterval(-Double(healthDailyRetentionDays) * secondsPerDay)
    assert(series.filter { $0.date >= cutoff }.count == healthDailyRetentionDays + 1)
    let old = series.filter { $0.date < cutoff && $0.fromCalibration != true }
    assert(Set(old.map { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) }).count == old.count && (65...67).contains(old.count))
    assert(series.contains { $0.fromCalibration == true })
}

func minutePoint(_ i: Int, calibration: Bool?) -> HealthSample {
    HealthSample(date: d("2026-01-01T00:00:00Z").addingTimeInterval(Double(i) * 60), fullChargeCapacityMAh: 4200, nominalCapacityMAh: nil, designCapacityMAh: 4800,
                 cycleCount: nil, fromCalibration: calibration)
}

func healthSeriesCapDropsDailyBeforeCalibration() {
    let capNow = d("2026-01-02T00:00:00Z"), pointCount = 600
    var series = (0..<pointCount).reduce([]) { s, i in addHealthSample(s, minutePoint(i, calibration: i % 2 == 0 ? true : nil), now: capNow, calendar: cal) }
    assert(series.count == healthMaxSamples && series.filter { $0.fromCalibration == true }.count == pointCount / 2)
    assert(series.last?.date == minutePoint(pointCount - 1, calibration: nil).date && series.first?.date == minutePoint(0, calibration: true).date)
    series = (0..<pointCount).reduce([]) { s, i in addHealthSample(s, minutePoint(i, calibration: true), now: capNow, calendar: cal) }
    assert(series.count == healthMaxSamples && series.first?.date == minutePoint(pointCount - healthMaxSamples, calibration: true).date, "oldest first")
}

func healthSeriesRefusesFutureDatedPoints() {
    let base = [hp("2026-10-01T12:00:00Z")]
    assert(addHealthSample(base, hp("2026-10-03T12:00:00Z"), now: d("2026-10-01T12:00:00Z"), calendar: cal) == base)
    assert(addHealthSample([hp("2026-10-01T12:00:00Z"), hp("2027-10-01T12:00:00Z")], hp("2026-10-02T12:00:00Z"), now: d("2026-10-02T12:00:00Z"), calendar: cal)
           == [hp("2026-10-01T12:00:00Z"), hp("2026-10-02T12:00:00Z")], "future points drop once the clock is back")
}

func thinningCutoffUsesNowNotInsertedPoint() {
    let now = d("2026-10-01T12:00:00Z")
    let daily = (0..<200).map { i in HealthSample(date: now.addingTimeInterval(-Double(i) * secondsPerDay), fullChargeCapacityMAh: 4200,
                                                  nominalCapacityMAh: nil, designCapacityMAh: 4800, cycleCount: nil, fromCalibration: nil) }.reversed()
    let thinned = addHealthSample(Array(daily), hp("2026-03-01T12:00:00Z", calibration: true), now: now, calendar: cal)
    let cutoff = now.addingTimeInterval(-Double(healthDailyRetentionDays) * secondsPerDay)
    assert(thinned.filter { $0.fromCalibration != true && $0.date < cutoff }.count <= 3)
}

func calibrationPointReplacesDailyPointOfSameTick() {
    let tickDaily = hp("2026-10-01T12:00:00Z"), tickCal = hp("2026-10-01T12:00:00Z", 4300, calibration: true)
    assert(addHealthSample([tickDaily], tickCal, now: tickDaily.date, calendar: cal) == [tickCal])
    assert(addHealthSample([tickCal], tickDaily, now: tickDaily.date, calendar: cal) == [tickCal])
    assert(addHealthSample([tickDaily], tickDaily, now: tickDaily.date, calendar: cal) == [tickDaily])
}

func healthHistoryRequestRoundTrips() {
    if case .healthHistory = try! JSONDecoder().decode(Command.self, from: JSONEncoder().encode(Command.healthHistory)) {} else { assert(false) }
}

func healthStatus() -> Status {
    Status(config: Config(), runtime: Runtime(), percent: 80, hardwarePercent: nil, adapter: true, temperature: nil, adapterWatts: 0,
           adapterRatedWatts: nil, systemWatts: 0, batteryChargeWatts: 0, batteryChargeMilliamps: nil, usbCOutputPorts: nil, nativeLimit: true, sleepDisabled: false,
           history: [], battery: nil, lastCalibration: nil, systemSettingsChargeLimit: nil)
}

func healthHistoryRidesOnlyInItsReply() {
    var wire = healthStatus()
    assert(!String(decoding: try! JSONEncoder().encode(wire), as: UTF8.self).contains("healthHistory"))
    let series = [hp("2026-10-01T12:00:00Z"), hp("2026-10-01T12:00:00Z", 4300, calibration: true)]
    wire.healthHistory = series
    assert(try! JSONDecoder().decode(Status.self, from: JSONEncoder().encode(wire)).healthHistory == series)
}

func olderHealthPayloadsDecode() {
    var wire = healthStatus()
    wire.healthHistory = [hp("2026-10-01T12:00:00Z")]
    var olderService = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as! [String: Any]
    olderService["healthHistory"] = nil
    assert(try! JSONDecoder().decode(Status.self, from: JSONSerialization.data(withJSONObject: olderService)).healthHistory == nil)
    let noFlag = #"{"date":0,"maxCapacity":4200,"designCapacity":4800}"#.data(using: .utf8)!
    assert(try! JSONDecoder().decode(HealthSample.self, from: noFlag) == HealthSample(date: Date(timeIntervalSinceReferenceDate: 0), fullChargeCapacityMAh: 4200,
                                                                                     nominalCapacityMAh: nil, designCapacityMAh: 4800, cycleCount: nil, fromCalibration: nil))
}

func healthRangeStartsThreeMonthsOrOneYearBack() {
    assert(healthRangeStart(.threeMonths, now: d("2026-10-30T12:00:00Z"), calendar: cal) == d("2026-07-30T12:00:00Z"))
    assert(healthRangeStart(.year, now: d("2026-10-30T12:00:00Z"), calendar: cal) == d("2025-10-30T12:00:00Z"))
}

func healthChangeNeedsTwoPointsAndBothCycleCounts() {
    let change = healthChange([hp("2026-07-01T12:00:00Z", 4260, cycles: 100), hp("2026-08-01T12:00:00Z"), hp("2026-10-01T12:00:00Z", 4200, cycles: 114)])!
    assert(abs(change.healthPercentagePoints - -1.25) < 1e-9 && change.cycles == 14 && change.days == 92)
    assert(healthChange([hp("2026-07-01T12:00:00Z", cycles: nil), hp("2026-10-01T12:00:00Z")])?.cycles == nil)
    assert(healthChange([hp("2026-07-01T12:00:00Z")]) == nil)
}

func healthSpanPicksDaysMonthsOrYears() {
    assert(healthSpan(days: 0) == (1, .days) && healthSpan(days: 59) == (59, .days) && healthSpan(days: 92) == (3, .months))
    assert(healthSpan(days: 365) == (1, .years) && healthSpan(days: 400) == (13, .months) && healthSpan(days: 800) == (2, .years))
}

func healthChartStringsAreTranslated() {
    useLanguage("fr")
    defer { useLanguage("system") }
    for k in ["3 months", "1 year", "All", "Health over time", "Not enough data yet: one point is recorded per day.", "Period",
              "%d days", "1 day", "%d months", "%d years", "%@ points in %@", "no new cycle", "+1 cycle", "+%d cycles",
              "Health history unavailable: the ChargeKeeper service did not answer (restart it after an update)."] { assert(tr(k) != k, k) }
    assert(tr("%@ points in %@", "−1,2", tr("%d months", 3)) == "−1,2 pt en 3 mois" && tr("+%d cycles", 14) == "14 cycles de plus")
}

func settingsSearchIgnoresAccentsCaseAndRequiresAllWords() {
    let ids = { (q: String) in searchSettings(q).map(\.id) }
    assert(ids("login") == ["openAtLogin"] && ids("connexion") == ["openAtLogin"])
    assert(ids("REVEIL") == ["catchUp"] && ids("réveil") == ids("reveil"))
    assert(ids("niveau veille") == ["sleepFreeze"] && ids("login quit").isEmpty && ids("  ").isEmpty)
}

func settingsIndexIdsAreUnique() {
    assert(Set(settingsIndex.map(\.id)).count == settingsIndex.count)
}

func settingsIndexIsTranslated() {
    for e in settingsIndex { for k in [e.label, e.description].compactMap({ $0 }) { assert(french[k] != nil, k) } }
}

func logFileNameRoundTripsPerUtcDay() {
    let logToday = logDay(d("2026-11-03T23:59:59Z"))
    assert(logToday == logDay(d("2026-11-03T00:00:00Z")) && logToday == logDay(d("2026-11-04T00:00:00Z")) - 1)
    assert(logFileName(day: logToday) == "chargekeeper-2026-11-03.log" && logFileDay("chargekeeper-2026-11-03.log") == logToday)
}

func foreignLogFileNamesAreRejected() {
    for n in ["chargekeeper-2026-02-31.log", "chargekeeper-2026-11-3.log", "chargekeeper-2026-11-03.log.tmp", "other-2026-11-03.log",
              "chargekeeper-2026-11-0３.log", "chargekeeper-+026-11-03.log"] { assert(logFileDay(n) == nil, n) }
}

func logFileExpiresAfterKeptWholeDays() {
    let logToday = logDay(d("2026-11-03T12:00:00Z"))
    assert(!logFileExpired(day: logToday, now: d("2026-11-04T23:59:59Z"), keepDays: 1))
    assert(logFileExpired(day: logToday, now: d("2026-11-05T00:00:00Z"), keepDays: 1))
    assert(!logFileExpired(day: logToday, now: d("2026-11-10T23:59:59Z"), keepDays: 7) && logFileExpired(day: logToday, now: d("2026-11-11T00:00:00Z"), keepDays: 7))
}

func logLineRoundTripsWithBreaksFlattened() {
    let logEntry = LogLine(date: d("2026-11-03T08:33:47Z"), level: .warn, message: "socket: invalid request\nnext")
    assert(logLineText(logEntry) == "2026-11-03T08:33:47Z warn socket: invalid request next\n")
    assert(parseLogLine(logLineText(logEntry).dropLast()) == LogLine(date: logEntry.date, level: .warn, message: "socket: invalid request next"))
}

func foreignLogLinesAreRejected() {
    assert(parseLogLine("2026-11-03T08:33:47Z 80%: Pause -> Discharging") == nil && parseLogLine("") == nil)
}

func logLevelsAreOrdered() {
    assert(LogLevel.info < .warn && .warn < .error)
}

func configWithoutLogSettingsDecodesDefaults() {
    var olderService = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Config(logEnabled: false, logDays: 30))) as! [String: Any]
    olderService["logEnabled"] = nil; olderService["logDays"] = nil
    assert(try! JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: olderService)) == Config())
    assert(try! JSONDecoder().decode(Config.self, from: JSONEncoder().encode(Config(logEnabled: false, logDays: 30))) == Config(logEnabled: false, logDays: 30))
}

let awakeNow = d("2026-11-20T14:30:00Z")

func keepAwakeEndIsAbsoluteOrNever() {
    assert(keepAwakeEnd(.m30, now: awakeNow) == d("2026-11-20T15:00:00Z") && keepAwakeEnd(.h4, now: awakeNow) == d("2026-11-20T18:30:00Z"))
    assert(keepAwakeEnd(.untilOff, now: awakeNow) == .distantFuture)
}

func keepAwakeExpiresAtItsEnd() {
    let awakeEnd = keepAwakeEnd(.h1, now: awakeNow)
    assert(keepAwakeUntil(awakeEnd, now: awakeEnd.addingTimeInterval(-1), adapter: true, percent: 50, minBattery: 20) == awakeEnd)
    assert(keepAwakeUntil(awakeEnd, now: awakeEnd, adapter: true, percent: 50, minBattery: 20) == nil, "a restart after the end finds it expired")
    assert(keepAwakeUntil(nil, now: awakeNow, adapter: true, percent: 50, minBattery: 20) == nil)
}

func keepAwakeStopsOnBatteryBelowThreshold() {
    assert(keepAwakeUntil(.distantFuture, now: awakeNow, adapter: false, percent: 20, minBattery: 20) == .distantFuture)
    assert(keepAwakeUntil(.distantFuture, now: awakeNow, adapter: false, percent: 19, minBattery: 20) == nil)
    assert(keepAwakeUntil(.distantFuture, now: awakeNow, adapter: true, percent: 5, minBattery: 20) == .distantFuture)
}

func lidClosedKeepAwakeAddsSleepDisabledReason() {
    var sc = Config()
    assert(!sleepDisabledWanted(sc, .hold(at: 80), state: .pause, adapter: true, keepAwake: true))
    sc.keepAwakeWithLidClosed = true
    assert(sleepDisabledWanted(sc, .hold(at: 80), state: .pause, adapter: false, keepAwake: true))
    assert(!sleepDisabledWanted(sc, .hold(at: 80), state: .pause, adapter: true, keepAwake: false))
    assert(sleepDisabledWanted(sc, .discharge, state: .discharging, adapter: true, keepAwake: false))
    assert(!sleepDisabledWanted(sc, .discharge, state: .discharging, adapter: false, keepAwake: false))
    sc.disableSleepUntilLimit = true
    assert(sleepDisabledWanted(sc, .charge(to: 80), state: .charging, adapter: true, keepAwake: false))
}

func keepAwakeHistoryTexts() {
    assert(historyText(HistoryEntry(event: .keepAwakeTimeUp)) == "Keep awake ended: time up")
    assert(historyText(HistoryEntry(event: .keepAwakeLowBattery, percent: 19)) == "Keep awake turned off: battery at 19 %")
    assert(historyText(HistoryEntry(event: .keepAwakeFailed)) == "Keep awake could not start: macOS refused to block sleep")
}

func keepAwakeBatteryThresholdIsClamped() {
    assert(clampedKeepAwakeMinBattery(0) == 5 && clampedKeepAwakeMinBattery(5) == 5 && clampedKeepAwakeMinBattery(20) == 20)
    assert(clampedKeepAwakeMinBattery(50) == 50 && clampedKeepAwakeMinBattery(51) == 50 && clampedKeepAwakeMinBattery(-3) == 5)
}

func keepAwakeSurvivesUpdateRestartOnly() {
    assert(keepAwakeAtStart(.distantFuture, updateRestart: true) == .distantFuture)
    assert(keepAwakeAtStart(.distantFuture, updateRestart: false) == nil && keepAwakeAtStart(nil, updateRestart: true) == nil)
}

func keepAwakeOffAndForeverSurviveEncoding() {
    if case .keepAwake(nil)? = try? JSONDecoder().decode(Command.self, from: JSONEncoder().encode(Command.stopKeepAwake)) {} else { assert(false) }
    var awakeRuntime = Runtime(); awakeRuntime.keepAwakeUntil = .distantFuture
    assert(try! JSONDecoder().decode(Runtime.self, from: JSONEncoder().encode(awakeRuntime)) == awakeRuntime)
    assert(try! JSONDecoder().decode(Runtime.self, from: JSONEncoder().encode(Runtime())).keepAwakeUntil == nil)
}

func strayDisableSleepIsWarned() {
    assert(unexplainedSleepDisabled(systemSleepDisabled: true, serviceSleepDisabled: nil) && unexplainedSleepDisabled(systemSleepDisabled: true, serviceSleepDisabled: false))
    assert(!unexplainedSleepDisabled(systemSleepDisabled: true, serviceSleepDisabled: true) && !unexplainedSleepDisabled(systemSleepDisabled: false, serviceSleepDisabled: nil))
    assert(!unexplainedSleepDisabled(systemSleepDisabled: nil, serviceSleepDisabled: false) && !unexplainedSleepDisabled(systemSleepDisabled: false, serviceSleepDisabled: false))
}

func reenableSleepCommandRoundTrips() {
    if case .reenableSleepIfNotWanted? = try? JSONDecoder().decode(Command.self, from: JSONEncoder().encode(Command.reenableSleepIfNotWanted)) {} else { assert(false) }
}

func straySleepWarningIsTranslated() {
    for k in ["Sleep is disabled for no reason (another tool or left over from a stop)", "Turn Sleep Back On", "Run in Terminal:", "Copy"] {
        assert(french[k] != nil, k)
    }
}

func configWithoutKeepAwakeSettingsDecodesDefaults() {
    var olderService = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
    olderService["keepAwakeLidClosed"] = nil; olderService["keepAwakeMinBattery"] = nil
    assert(try! JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: olderService)) == Config())
    assert(Config().keepAwakeMinBattery == 20 && !Config().keepAwakeWithLidClosed)
}

func keepAwakeDurationOutsideListFailsDecode() {
    assert((try? JSONDecoder().decode(Command.self, from: JSONSerialization.data(withJSONObject: ["keepAwake": ["_0": 45]]))) == nil)
    if case .keepAwake(.h2)? = try? JSONDecoder().decode(Command.self, from: JSONEncoder().encode(Command.keepAwake(.h2))) {} else { assert(false) }
}

func menuWindowIsCenteredAndClampedOnAnyDisplay() {
    let mainScreen = 0.0...1512, leftScreen = -1920.0...0, rightScreen = 1512.0...4072
    assert(centeredMenuX(width: 320, under: 1000...1030, in: mainScreen, margin: 8) == 855)
    assert(centeredMenuX(width: 320, under: 1480...1510, in: mainScreen, margin: 8) == 1184)
    assert(centeredMenuX(width: 320, under: 20...50, in: mainScreen, margin: 8) == 8)
    assert(centeredMenuX(width: 320, under: -900...(-870), in: leftScreen, margin: 8) == -1045)
    assert(centeredMenuX(width: 320, under: -1915...(-1885), in: leftScreen, margin: 8) == -1912)
    assert(centeredMenuX(width: 320, under: -40...(-10), in: leftScreen, margin: 8) == -328)
    assert(centeredMenuX(width: 320, under: 1520...1550, in: rightScreen, margin: 8) == 1520)
    assert(centeredMenuX(width: 320, under: 3000...3030, in: rightScreen, margin: 8) == 2855)
    assert(centeredMenuX(width: 2000, under: 1000...1030, in: mainScreen, margin: 8) == 8)
}

let olderServiceConfigJSON = #"""
{"limit":75,"autoDischarge":true,"idle":false,"idleRange":5,"heatProtect":false,"maxTemp":35,"led":"system","ledBlinkDischarge":false,\#
"stopChargingDuringSleep":false,"disableSleepUntilLimit":false,"keepLimitWhenStopped":true,"catchUpMissedTasks":false,"tasks":[]}
"""#

func wireKeys<T: Encodable>(_ v: T) -> Set<String> {
    Set((try! JSONSerialization.jsonObject(with: JSONEncoder().encode(v)) as! [String: Any]).keys)
}

func wireText(_ c: Command) -> String { String(decoding: try! JSONEncoder().encode(c), as: UTF8.self) }

func decodedCommand(_ json: String) -> Command? { try? JSONDecoder().decode(Command.self, from: Data(json.utf8)) }

func configFromOlderServiceUsesDefaults() {
    var expected = Config()
    expected.limit = 75
    expected.drainAboveLimitOnAdapter = true
    assert(try! JSONDecoder().decode(Config.self, from: Data(olderServiceConfigJSON.utf8)) == expected)
}

func statusFromOlderServiceDecodes() {
    let json = #"""
    {"config":\#(olderServiceConfigJSON),"runtime":{"discharge":false,"topUp":false,"heatBlocked":false,"idleRecharge":true,"state":"Pause",\#
    "calibrationBefore":{"date":0,"maxCapacity":4200,"designCapacity":4800,"percent":80},"pastLimitSince":0},"percent":80,"adapter":true,\#
    "adapterWatts":0,"systemWatts":5,"batteryWatts":-5,"nativeLimit":true,"sleepDisabled":false,\#
    "history":[{"date":0,"text":"task setLimit (caught up)","event":"taskRun","action":"setLimit","late":true,"value":80}]}
    """#
    let s = try! JSONDecoder().decode(Status.self, from: Data(json.utf8))
    assert(s.config.drainAboveLimitOnAdapter && s.runtime.isRefillingToLimit && s.runtime.macOSPastLimitSince == Date(timeIntervalSinceReferenceDate: 0))
    assert(s.runtime.calibrationStartSnapshot?.fullChargeCapacityMAh == 4200 && s.runtime.calibrationStartSnapshot?.healthPercent == 87.5)
    assert(s.batteryChargeWatts == -5 && s.batteryChargeMilliamps == nil && s.usbCOutputPorts == nil && s.battery == nil)
    assert(s.systemSettingsChargeLimit == nil && s.healthHistory == nil && s.socHistory == nil)
    assert(s.history[0].caughtUpOnWake == true && s.history[0].percent == 80)
}

func renamedFieldsKeepTheirWireKeys() {
    assert(wireKeys(Config()).isSuperset(of: ["autoDischarge", "keepAwakeLidClosed"]))
    var runtime = Runtime()
    runtime.calibrationStartSnapshot = BatterySnapshot(date: at(0), percent: 50)
    runtime.macOSPastLimitSince = at(0)
    assert(wireKeys(runtime).isSuperset(of: ["idleRecharge", "calibrationBefore", "pastLimitSince"]))
    let snapshot = BatterySnapshot(date: at(0), fullChargeCapacityMAh: 1, nominalCapacityMAh: 1, designCapacityMAh: 1, percent: 50)
    assert(wireKeys(snapshot).isSuperset(of: ["maxCapacity", "nominalCapacity", "designCapacity"]))
    assert(wireKeys(hp("2026-10-01T12:00:00Z", calibration: true)).isSuperset(of: ["maxCapacity", "nominalCapacity", "designCapacity", "calibration"]))
    let entry = HistoryEntry(caughtUpOnWake: true, percent: 1, capacityBeforeMAh: 1, capacityAfterMAh: 1, healthBeforePercent: 1, healthAfterPercent: 1)
    assert(wireKeys(entry).isSuperset(of: ["late", "value", "capacityBefore", "capacityAfter", "healthBefore", "healthAfter"]))
    assert(wireKeys(PortPower(deviceName: "iPhone", watts: 1, negotiatedWatts: 1)) == ["name", "watts", "maxWatts"])
    assert(wireKeys(SoCPowerPoint(date: at(0), averagePower: pw, samplingInterval: 1)) == ["date", "power", "interval"])
    var status = healthStatus()
    status.batteryChargeMilliamps = 1
    status.usbCOutputPorts = []
    status.systemSettingsChargeLimit = 80
    assert(wireKeys(status).isSuperset(of: ["batteryWatts", "batteryAmperage", "ports", "appleChargeLimit"]))
}

func commandsKeepTheirWireNames() {
    assert(wireText(.reenableSleepIfNotWanted) == #"{"resetSleep":{}}"#)
    assert(wireText(.status(includePowerHistory: true)) == #"{"status":{"soc":true}}"#)
    if case .reenableSleepIfNotWanted? = decodedCommand(#"{"resetSleep":{}}"#) {} else { assert(false) }
    if case .status(includePowerHistory: true)? = decodedCommand(#"{"status":{"soc":true}}"#) {} else { assert(false) }
}

func statusRequestFromOldAppDecodes() {
    if case .status(includePowerHistory: nil)? = decodedCommand(#"{"status":{}}"#) {} else { assert(false) }
}

func keepAwakeEndedFromOlderServiceSplitsOnBatteryLevel() {
    func event(_ json: String) -> HistoryEvent? { try! JSONDecoder().decode(HistoryEntry.self, from: Data(json.utf8)).event }
    assert(event(#"{"date":0,"text":"","event":"keepAwakeEnded"}"#) == .keepAwakeTimeUp)
    assert(event(#"{"date":0,"text":"","event":"keepAwakeEnded","value":19}"#) == .keepAwakeLowBattery)
    assert(String(decoding: try! JSONEncoder().encode(HistoryEntry(event: .keepAwakeTimeUp)), as: UTF8.self).contains(#""keepAwakeEnded""#))
}

func legacyInstallNamesUnchanged() {
    assert(socketPath == "/var/run/jauge.sock" && logDir == "/Library/Application Support/Jauge/Logs")
    assert(DarwinNotification.allCases.map(\.name) == ["com.vlor999.jauge.calibrationDone", "com.vlor999.jauge.heatProtect",
                                                        "com.vlor999.jauge.calibrationNeedsAdapter", "com.vlor999.jauge.limitReached"])
}

func taskMergeKeepsNewestLastRunPerTask() {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    let current = [
        ScheduledTask(id: a, lastRun: at(200)), ScheduledTask(id: b, lastRun: at(100)),
        ScheduledTask(id: c, lastRun: at(300)), ScheduledTask(id: d, lastRun: nil),
    ]
    let incoming = [
        ScheduledTask(id: a, value: 60, lastRun: at(100)), ScheduledTask(id: b, lastRun: at(200)),
        ScheduledTask(id: c, lastRun: nil), ScheduledTask(id: d, lastRun: at(50)), ScheduledTask(id: UUID(), lastRun: nil),
    ]
    let merged = tasksKeepingNewestLastRun(incoming, current: current)
    assert(merged.map(\.lastRun) == [at(200), at(200), at(300), at(50), nil])
    assert(merged.map(\.id) == incoming.map(\.id) && merged[0].value == 60)
}

func fileStat(_ type: mode_t, mode: mode_t, uid: uid_t = 0, links: nlink_t = 1) -> stat {
    var st = stat()
    st.st_mode = type | mode
    st.st_uid = uid
    st.st_nlink = links
    return st
}

func logFileMustBeRootOwnedRegularWithOneLink() {
    assert(isRootOwnedRegularFileWithoutHardLinks(fileStat(S_IFREG, mode: 0o644)))
    assert(!isRootOwnedRegularFileWithoutHardLinks(fileStat(S_IFREG, mode: 0o644, uid: 501)))
    assert(!isRootOwnedRegularFileWithoutHardLinks(fileStat(S_IFREG, mode: 0o644, links: 2)))
    assert(!isRootOwnedRegularFileWithoutHardLinks(fileStat(S_IFLNK, mode: 0o644)))
    assert(!isRootOwnedRegularFileWithoutHardLinks(fileStat(S_IFDIR, mode: 0o755)))
}

func logFolderMustBeRootOwnedWithoutGroupOrOtherWrite() {
    assert(isRootOwnedFolderWithoutGroupOrOtherWrite(fileStat(S_IFDIR, mode: 0o755)))
    assert(!isRootOwnedFolderWithoutGroupOrOtherWrite(fileStat(S_IFDIR, mode: 0o755, uid: 501)))
    assert(!isRootOwnedFolderWithoutGroupOrOtherWrite(fileStat(S_IFDIR, mode: 0o775)))
    assert(!isRootOwnedFolderWithoutGroupOrOtherWrite(fileStat(S_IFDIR, mode: 0o757)))
    assert(!isRootOwnedFolderWithoutGroupOrOtherWrite(fileStat(S_IFLNK, mode: 0o755)))
    assert(!isRootOwnedFolderWithoutGroupOrOtherWrite(fileStat(S_IFREG, mode: 0o755)))
}

let checks: [() -> Void] = [
    aboveLimitHoldsBelowLimitCharges,
    manualDischargeStopsAtLimit,
    drainAboveLimitOnAdapterDrainsThenHolds,
    idleRangeKeepsPauseUntilBelowRange,
    topUpChargesTo100AndClearsOnUnplug,
    heatProtectBlocksThenRechecksAfterHeatWindow,
    calibrationRunsFullCycle,
    calibrationFinishedOnlyWhenRestEnds,
    calibrationNoticeSeedsThenNotifiesOncePerResult,
    calibrationSummaryShowsBeforeAfterHealth,
    heatNoticeOncePerEpisode,
    heatNoticeStillSentAfterLimitNotice,
    limitNoticeOncePerChargingSession,
    unplugResetsLimitNotice,
    limitChangeRearmsLimitNotice,
    firstTickAfterRestartGivesNoLimitNotice,
    historyEventsRenderInEnglish,
    legacyHistoryTextMapsToEvents,
    unknownHistoryEventFallsBackToText,
    olderAppsReadHistoryText,
    historyRendersInFrench,
    localeFollowsTextLanguageKeepsRegion,
    numbersDatesAndDurationsFollowFrench,
    menuAndNotificationStringsAreTranslated,
    everyHistoryTemplateAndBannerHasFrench,
    timeToTargetFromCurrentAndCapacity,
    timeToTargetIsAtLeastOneMinute,
    timeToTargetIsNilWhenReachedIdleWrongWayOrNoCapacity,
    timeToTargetIsNilOver24Hours,
    calibrationProgressReportsStepAndTarget,
    calibrationRestReportsTimeLeft,
    calibrationNeedsAdapterInChargingAndRestPhasesOnly,
    adapterNoticeOnFirstTickAfterRestart,
    adapterNoticeOncePerWaitAcrossRestAndRecharge,
    adapterNoticeRateLimitedAcrossShortUnplugs,
    rateLimitedWaitStartsItsOwnReminderTimer,
    adapterNoticeRemindsOnceAfterReminderDelay,
    adapterNoticeOnlyInPhasesNeedingAdapter,
    calibrationRestCountsOnlyOnAdapter,
    unpluggedCalibrationRestLeavesRuntimeUnchanged,
    calibrationRestBelow100RechargesFirst,
    calibrationRestWithoutStartBeginsOnAdapter,
    nativeLimitRoundingIsNotAnEpisode,
    aboveLimitWhileNotChargingIsNotAnEpisode,
    pastLimitEpisodeStartsOnceAndEndsWhenLevelIsBack,
    pastLimitEpisodeReportsHeldLevel,
    unplugEndsPastLimitEpisode,
    modesThatChargeOnPurposeAreNotPastLimitEpisodes,
    pastLimitEpisodeWhileDrainingUsesWattsWhenNoAmperage,
    failedOwnActionIsNotBlamedOnMacOS,
    noPastLimitEpisodeOnTheTickThatChangesMode,
    noPastLimitEpisodeOnModeChangeViaDischargeTo,
    systemSettingsChargeLimitCountsOnlyWhenEnabledIn50to99,
    ledShowsGreenAtLimitAndBlinksOrangeWhenDischarging,
    monthlyOn31stSkipsShortMonths,
    weekdaysSkipWeekends,
    longRunningRepeatsGiveTheirLatestOccurrence,
    oneOffTaskOccursAtItsStart,
    macWattsIsLoadMinusPortsUnlessPortsExceedLoad,
    powerHistoryDropsPointsOutsideWindow,
    powerHistoryDropsPointsDatedAfterTheNewOne,
    currentPowerIsNewestWhileFresh,
    currentPowerLastsTwoOwnIntervals,
    powerGapOverTwoIntervalsSplitsCurve,
    intervalChangeRestartGapDoesNotSplit,
    realGapAfterIntervalChangeStillSplits,
    appRefreshFollowsShortPowerIntervalElsePollInterval,
    powermetricsArgumentsFixedExceptIntervalMs,
    powerIntervalDefaultsToFiveSeconds,
    powerIntervalDecodesListedValues,
    powerIntervalOutsideListFailsDecode,
    replyOmitsStalePowerPoints,
    powermetricsStreamTakesNulTerminatedSamplesKeepsTail,
    oversizedPowermetricsTailIsDropped,
    powermetricsSampleConvertsMillijoulesOverElapsedToWatts,
    powerFallsBackToDefaultIntervalWithoutElapsed,
    malformedPowermetricsSampleIsRejected,
    statusSocFlagIsOptionalBothWays,
    statusWithoutSocHistoryDecodesNil,
    powerFlowLabelsSpreadWithinHeight,
    deviceIconMatchesAppleNamesElseGeneric,
    healthSampleNeedsBothCapacities,
    healthSampleDueOncePerCalendarDay,
    healthSeriesThinsToWeeklyAfterDailyKeepDays,
    healthSeriesCapDropsDailyBeforeCalibration,
    healthSeriesRefusesFutureDatedPoints,
    thinningCutoffUsesNowNotInsertedPoint,
    calibrationPointReplacesDailyPointOfSameTick,
    healthHistoryRequestRoundTrips,
    healthHistoryRidesOnlyInItsReply,
    olderHealthPayloadsDecode,
    healthRangeStartsThreeMonthsOrOneYearBack,
    healthChangeNeedsTwoPointsAndBothCycleCounts,
    healthSpanPicksDaysMonthsOrYears,
    healthChartStringsAreTranslated,
    settingsSearchIgnoresAccentsCaseAndRequiresAllWords,
    settingsIndexIdsAreUnique,
    settingsIndexIsTranslated,
    logFileNameRoundTripsPerUtcDay,
    foreignLogFileNamesAreRejected,
    logFileExpiresAfterKeptWholeDays,
    logLineRoundTripsWithBreaksFlattened,
    foreignLogLinesAreRejected,
    logLevelsAreOrdered,
    configWithoutLogSettingsDecodesDefaults,
    keepAwakeEndIsAbsoluteOrNever,
    keepAwakeExpiresAtItsEnd,
    keepAwakeStopsOnBatteryBelowThreshold,
    lidClosedKeepAwakeAddsSleepDisabledReason,
    keepAwakeHistoryTexts,
    keepAwakeBatteryThresholdIsClamped,
    keepAwakeSurvivesUpdateRestartOnly,
    keepAwakeOffAndForeverSurviveEncoding,
    strayDisableSleepIsWarned,
    reenableSleepCommandRoundTrips,
    straySleepWarningIsTranslated,
    configWithoutKeepAwakeSettingsDecodesDefaults,
    keepAwakeDurationOutsideListFailsDecode,
    menuWindowIsCenteredAndClampedOnAnyDisplay,
    configFromOlderServiceUsesDefaults,
    statusFromOlderServiceDecodes,
    renamedFieldsKeepTheirWireKeys,
    commandsKeepTheirWireNames,
    statusRequestFromOldAppDecodes,
    keepAwakeEndedFromOlderServiceSplitsOnBatteryLevel,
    legacyInstallNamesUnchanged,
    taskMergeKeepsNewestLastRunPerTask,
    logFileMustBeRootOwnedRegularWithOneLink,
    logFolderMustBeRootOwnedWithoutGroupOrOtherWrite,
]
for check in checks { check() }
print("logic ok")
