import Foundation
import notify

struct Saved: Codable {
    var config = Config()
    var runtime = Runtime()
    var history: [HistoryEntry] = []
    var lastCalibration: CalibrationResult?
    var healthHistory: [HealthSample] = []
    var updateRestart = false
}

struct ResetOnRestart {
    var notices = NoticeLatch()
    var adapterNotices = AdapterNoticeState()
    var lastAction: Action?
}

enum CommandSource { case user, scheduledTask }

func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
func clamp(_ v: Int, to range: ClosedRange<Int>) -> Int { clamp(v, range.lowerBound, range.upperBound) }

func tasksKeepingNewestLastRun(_ incoming: [ScheduledTask], current: [ScheduledTask]) -> [ScheduledTask] {
    let currentLastRun = Dictionary(current.map { ($0.id, $0.lastRun) }, uniquingKeysWith: { a, _ in a })
    var tasks = incoming
    for i in tasks.indices { if let l = currentLastRun[tasks[i].id] ?? nil, l > (tasks[i].lastRun ?? .distantPast) { tasks[i].lastRun = l } }
    return tasks
}

final class Daemon {
    var s: Saved
    let hw = Backend()
    let power: PowerMetrics
    var reading = Reading()
    var sleepDisabled = false
    let awake = KeepAwakeAssertion()
    var lastScheduleCheck = Date()
    var lastAppleLimitRead = Date.distantPast
    var lastSaved: Data?
    var resetOnRestart = ResetOnRestart()
    var systemSettingsChargeLimit: Int?

    init() {
        let stateFileExistedAtStart = FileManager.default.fileExists(atPath: statePath)
        s = Daemon.loadOverlayingDefaults()
        power = PowerMetrics(interval: s.config.powerInterval)
        DiagnosticLog.configure(s.config)
        recoverFromPreviousRun()
        readAppleChargeLimit()
        log("start: inhibit=\(hw.inhibitKey ?? "-") discharge=\(hw.dischargeKey ?? "-") nativeMCL=\(hw.native)")
        let previousRunEndedWithoutStop = stateFileExistedAtStart && s.runtime.state != .exit
        if previousRunEndedWithoutStop {
            log("previous run ended without a stop (state \(s.runtime.state.rawValue)): sleep setting reset, keep awake \(s.runtime.keepAwakeUntil == nil ? "off" : "kept (update restart)")", .warn)
        }
    }

    private func recoverFromPreviousRun() {
        _ = setSystemSleepDisabled(false)
        s.runtime.keepAwakeUntil = keepAwakeAtStart(s.runtime.keepAwakeUntil, updateRestart: s.updateRestart)
        consumeUpdateRestartMarker()
    }

    private func consumeUpdateRestartMarker() {
        s.updateRestart = false
        save()
    }

    static func loadOverlayingDefaults() -> Saved {
        func overlay(_ defaults: Any, with saved: Any) -> Any {
            guard var defaults = defaults as? [String: Any], let saved = saved as? [String: Any] else { return saved }
            for (k, v) in saved { defaults[k] = defaults[k].map { overlay($0, with: v) } ?? v }
            return defaults
        }
        guard let saved = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: statePath))),
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Saved())),
              let merged = try? JSONSerialization.data(withJSONObject: overlay(defaults, with: saved)),
              let s = try? JSONDecoder().decode(Saved.self, from: merged) else { return Saved() }
        return s
    }

    func save() {
        guard let d = try? JSONEncoder().encode(s), d != lastSaved else { return }
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        if (try? d.write(to: URL(fileURLWithPath: statePath), options: .atomic)) != nil { lastSaved = d }
    }

    func record(_ entry: HistoryEntry) {
        var e = entry
        e.date = Date()
        e.text = historyText(e)
        log(e.text)
        s.history.insert(e, at: 0)
        if s.history.count > 200 { s.history.removeLast() }
    }

    func tick() {
        guard let rd = readBattery() else { return }
        reading = rd
        let now = Date()
        if now.timeIntervalSince(lastScheduleCheck) >= 60 { runSchedule(now) }
        if now.timeIntervalSince(lastAppleLimitRead) >= appleLimitReadInterval { readAppleChargeLimit() }
        if healthSampleDue(s.healthHistory, now: now), let p = healthSample(snapshot(rd, now)) { s.healthHistory = addHealthSample(s.healthHistory, p, now: now) }

        let prev = s.runtime.state, prevPhase = s.runtime.calibration
        let a = decide(s.config, &s.runtime, Inputs(percent: rd.percent, adapter: rd.adapter, temperature: rd.temperature, now: now))
        hw.apply(a, percent: rd.percent)
        hw.setLED(ledColor(s.config, s.runtime, adapter: rd.adapter, percent: rd.percent))
        if prev != s.runtime.state { log("\(rd.percent)%: \(prev.rawValue) -> \(s.runtime.state.rawValue) (\(a))") }
        if prevPhase != s.runtime.calibration {
            record(s.runtime.calibration.map { HistoryEntry(event: .calibrationPhase, phase: $0) } ?? HistoryEntry(event: .calibrationEnded))
        }
        if calibrationFinished(from: prevPhase, to: s.runtime.calibration) { finishCalibration(snapshot(rd, now)) }
        switch adapterNotice(phase: s.runtime.calibration, adapter: rd.adapter, now: now, &resetOnRestart.adapterNotices) {
        case .first: record(HistoryEntry(event: .calibrationNeedsAdapter, phase: s.runtime.calibration)); notify_post(DarwinNotification.calibrationNeedsAdapter.name)
        case .reminder: notify_post(DarwinNotification.calibrationNeedsAdapter.name)
        case .none: break
        }
        let settled = prev == s.runtime.state && resetOnRestart.lastAction == a
        resetOnRestart.lastAction = a
        if let held = pastLimitEpisode(a, state: s.runtime.state, settled: settled, inControl: hw.limitIsEnforced, adapter: rd.adapter, limit: s.config.limit, percent: rd.percent,
                            amperage: rd.batteryChargeMilliamps, watts: rd.batteryWatts, since: &s.runtime.macOSPastLimitSince, now: now) {
            record(HistoryEntry(event: .chargedPastLimit, percent: held))
        }
        for n in serviceNotices(from: prev, to: s.runtime.state, adapter: rd.adapter, limit: s.config.limit, latch: &resetOnRestart.notices) {
            switch n {
            case .heatProtect: record(HistoryEntry(event: .heatProtect, temperature: rd.temperature)); notify_post(DarwinNotification.heatProtect.name)
            case .limitReached: notify_post(DarwinNotification.limitReached.name)
            }
        }

        let until = keepAwakeUntil(s.runtime.keepAwakeUntil, now: now, adapter: rd.adapter, percent: rd.percent, minBattery: s.config.keepAwakeMinBattery)
        if let was = s.runtime.keepAwakeUntil, until == nil { record(was > now ? HistoryEntry(event: .keepAwakeLowBattery, percent: rd.percent) : HistoryEntry(event: .keepAwakeTimeUp)) }
        let heldUntil = heldKeepAwakeUntil(until)
        s.runtime.keepAwakeUntil = heldUntil
        let noSleep = sleepDisabledWanted(s.config, a, state: s.runtime.state, adapter: rd.adapter, keepAwake: heldUntil != nil)
        if noSleep != sleepDisabled, setSystemSleepDisabled(noSleep) { sleepDisabled = noSleep; log("sleep \(noSleep ? "disabled" : "enabled")") }
        save()
    }

    private func heldKeepAwakeUntil(_ until: Date?) -> Date? {
        guard awake.setHeld(until != nil) else { record(HistoryEntry(event: .keepAwakeFailed)); return nil }
        return until
    }

    func readAppleChargeLimit() {
        lastAppleLimitRead = Date()
        guard hw.nativeLimitBelongsToUser else { return }
        systemSettingsChargeLimit = userChargeLimit(enabled: Int(mcl_enabled()), limit: Int(mcl_limit()))
    }

    func snapshot(_ rd: Reading, _ date: Date = Date()) -> BatterySnapshot {
        BatterySnapshot(date: date, fullChargeCapacityMAh: rd.rawMaxCapacityMAh, nominalCapacityMAh: rd.nominalCapacityMAh, designCapacityMAh: rd.designCapacityMAh,
                        cycleCount: rd.cycleCount, temperature: rd.temperature, percent: rd.percent)
    }

    func finishCalibration(_ after: BatterySnapshot) {
        let before = s.runtime.calibrationStartSnapshot
        s.runtime.calibrationStartSnapshot = nil
        record(HistoryEntry(event: .calibrationDone, capacityBeforeMAh: before?.fullChargeCapacityMAh, capacityAfterMAh: after.fullChargeCapacityMAh,
                            healthBeforePercent: before?.healthPercent, healthAfterPercent: after.healthPercent, cycles: after.cycleCount))
        if let p = healthSample(after, calibration: true) { s.healthHistory = addHealthSample(s.healthHistory, p, now: after.date) }
        guard let before else { return }
        s.lastCalibration = CalibrationResult(start: before.date, end: after.date, before: before, after: after)
        notify_post(DarwinNotification.calibrationDone.name)
    }

    func runSchedule(_ now: Date) {
        lastScheduleCheck = now
        for i in s.config.tasks.indices where s.config.tasks[i].enabled {
            let t = s.config.tasks[i]
            guard let o = lastOccurrence(t, after: max(t.lastRun ?? t.created, t.created), upTo: now) else { continue }
            s.config.tasks[i].lastRun = o
            let late = now.timeIntervalSince(o) > 600
            let value = t.action == .setLimit || t.action == .dischargeTo ? t.value : nil
            if late && !s.config.catchUpMissedTasks { record(HistoryEntry(event: .taskSkipped, action: t.action, percent: value)); continue }
            record(HistoryEntry(event: .taskRun, action: t.action, caughtUpOnWake: late, percent: value))
            switch t.action {
            case .setLimit: mutate(.setLimit(t.value), from: .scheduledTask)
            case .calibrate: mutate(.calibrate(true), from: .scheduledTask)
            case .topUp: mutate(.topUp(true), from: .scheduledTask)
            case .pause: mutate(.pause, from: .scheduledTask)
            case .dischargeTo: mutate(.dischargeTo(t.value), from: .scheduledTask)
            case .lowPowerOn: mutate(.lowPower(true), from: .scheduledTask)
            case .lowPowerOff: mutate(.lowPower(false), from: .scheduledTask)
            }
        }
    }

    func mutate(_ cmd: Command, from source: CommandSource = .user) {
        let limit = s.config.limit
        defer { if source == .user && s.config.limit != limit { record(HistoryEntry(event: .limitChanged, percent: s.config.limit)) } }
        switch cmd {
        case .status, .healthHistory: break
        case .reenableSleepIfNotWanted: reenableSleepIfNotWanted()
        case .setConfig(var c):
            c.limit = clamp(c.limit, 20, 100)
            c.idleRange = clamp(c.idleRange, 1, 30)
            c.maxTemp = min(max(c.maxTemp, 25), 50)
            c.logDays = clamp(c.logDays, logRetentionDaysRange.lowerBound, logRetentionDaysRange.upperBound)
            c.keepAwakeMinBattery = clampedKeepAwakeMinBattery(c.keepAwakeMinBattery)
            c.tasks = tasksKeepingNewestLastRun(c.tasks, current: s.config.tasks)
            let logChanged = c.logEnabled != s.config.logEnabled || c.logDays != s.config.logDays
            s.config = c
            if logChanged { DiagnosticLog.configure(c) }
            power.applySetting(c.powerInterval)
        case .setLimit(let n): s.config.limit = clamp(n, 20, 100)
        case .discharge(let on): s.runtime.discharge = on
        case .dischargeTo(let n): s.config.limit = clamp(n, 20, 100); s.runtime.discharge = true
        case .topUp(let on): s.runtime.topUp = on
        case .calibrate(let on):
            let runningCalibrationBaseline = s.runtime.calibration != nil ? s.runtime.calibrationStartSnapshot : nil
            s.runtime.calibration = on ? .chargeFull : nil
            s.runtime.phaseStart = Date()
            s.runtime.calibrationStartSnapshot = on ? runningCalibrationBaseline ?? snapshot(reading) : nil
            record(HistoryEntry(event: on ? .calibrationStarted : .calibrationStopped))
        case .pause: s.config.limit = clamp(reading.percent, 20, 100); s.runtime.discharge = false
        case .led(let c): s.runtime.ledOverride = c
        case .lowPower(let on): pmset(["-a", "lowpowermode", on ? "1" : "0"])
        case .highPower(let on): pmset(["-a", "powermode", on ? "2" : "0"])
        case .keepAwake(let d): s.runtime.keepAwakeUntil = d.map { keepAwakeEnd($0, now: Date()) }
        }
    }

    private func reenableSleepIfNotWanted() {
        let wanted = sleepDisabledWanted(s.config, resetOnRestart.lastAction ?? .hold(at: reading.percent), state: s.runtime.state, adapter: reading.adapter,
                                         keepAwake: s.runtime.keepAwakeUntil != nil)
        guard !wanted else { return log("sleep reset refused: the service needs sleep disabled", .warn) }
        if setSystemSleepDisabled(false) { sleepDisabled = false; log("sleep enabled (reset from the app)") }
    }

    func handle(_ cmd: Command) -> Status {
        switch cmd {
        case .status, .healthHistory: break
        default: mutate(cmd); tick()
        }
        var out = Status(config: s.config, runtime: s.runtime, percent: reading.percent, hardwarePercent: reading.hardwarePercent,
                      adapter: reading.adapter, temperature: reading.temperature, adapterWatts: reading.adapterWatts, adapterRatedWatts: reading.adapterRatedWatts,
                      systemWatts: reading.systemWatts, batteryChargeWatts: reading.batteryWatts, batteryChargeMilliamps: reading.batteryChargeMilliamps, usbCOutputPorts: reading.ports, nativeLimit: hw.native,
                      sleepDisabled: sleepDisabled, history: Array(s.history.prefix(50)), battery: snapshot(reading),
                      lastCalibration: s.lastCalibration, systemSettingsChargeLimit: systemSettingsChargeLimit)
        if case .healthHistory = cmd { out.healthHistory = s.healthHistory }
        if case .status(includePowerHistory: true) = cmd { out.socHistory = recentPowerPoints(power.history, now: Date(), window: socHistoryRetention) }
        return out
    }

    func pauseChargingBeforeSleep() {
        hw.setDischarge(false)
        guard s.config.stopChargingDuringSleep, reading.adapter, s.runtime.state == .charging else { return }
        switch hw.limitStrategy {
        case .smcInhibit: hw.setInhibit(true)
        case .nativeLimit: hw.setMCL(clamp(reading.percent, to: nativeChargeLimitPercentRange))
        }
        log("sleep: charging paused at \(reading.percent)%")
    }

    private func releaseSleepHolds() {
        awake.setHeld(false)
        if sleepDisabled { _ = setSystemSleepDisabled(false) }
    }

    func exitForUpdate() {
        hw.setDischarge(false)
        power.stopForServiceExit()
        releaseSleepHolds()
        s.updateRestart = true
        save()
        unlink(socketPath)
        log("binary updated, restarting")
        exit(0)
    }

    func stop() {
        power.stopForServiceExit()
        hw.shutdown(keepLimit: s.config.keepLimitWhenStopped, limit: s.config.limit)
        releaseSleepHolds()
        s.runtime.keepAwakeUntil = nil
        s.runtime.state = .exit
        save()
        unlink(socketPath)
        log("stopped")
        exit(0)
    }
}
