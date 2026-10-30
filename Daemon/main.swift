import Foundation
import IOKit.pwr_mgt
import notify

let stateDir = "/Library/Application Support/Jauge"
let statePath = stateDir + "/state.json"

struct Saved: Codable {
    var config = Config()
    var runtime = Runtime()
    var history: [HistoryEntry] = []
    var lastCalibration: CalibrationResult?
}

func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

final class Daemon {
    var s: Saved
    let hw = Backend()
    var reading = Reading()
    var sleepDisabled = false
    var lastScheduleCheck = Date()
    var lastSaved: Data?
    var notices = NoticeLatch()  // in memory: a restart can only repeat a notice after a new state change
    var adapterNotices = AdapterNoticeState()
    var appleChargeLimit: Int?
    var lastAction: Action?  // in memory: the first tick after a restart counts as a mode change

    init() {
        s = Daemon.load()
        // A crash may have left sleep disabled: start from the system default.
        _ = setSleepDisabled(false)
        readAppleChargeLimit()
        log("start: inhibit=\(hw.inhibitKey ?? "-") discharge=\(hw.dischargeKey ?? "-") nativeMCL=\(hw.native)")
    }

    /// Saved JSON overlaid on defaults, so fields added in a newer build don't wipe the user's settings.
    static func load() -> Saved {
        func merge(_ a: Any, _ b: Any) -> Any {
            guard var a = a as? [String: Any], let b = b as? [String: Any] else { return b }
            for (k, v) in b { a[k] = a[k].map { merge($0, v) } ?? v }
            return a
        }
        guard let saved = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: statePath))),
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Saved())),
              let merged = try? JSONSerialization.data(withJSONObject: merge(defaults, saved)),
              let s = try? JSONDecoder().decode(Saved.self, from: merged) else { return Saved() }
        return s
    }

    func save() {
        guard let d = try? JSONEncoder().encode(s), d != lastSaved else { return }
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        if (try? d.write(to: URL(fileURLWithPath: statePath), options: .atomic)) != nil { lastSaved = d }
    }

    /// Stores the event with its English text, which older apps and the log show.
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
        if now.timeIntervalSince(lastScheduleCheck) >= 60 { runSchedule(now); readAppleChargeLimit() }

        let prev = s.runtime.state, prevPhase = s.runtime.calibration
        let a = decide(s.config, &s.runtime, Inputs(percent: rd.percent, adapter: rd.adapter, temperature: rd.temperature, now: now))
        hw.apply(a, percent: rd.percent)
        hw.setLED(ledColor(s.config, s.runtime, adapter: rd.adapter, percent: rd.percent))
        if prev != s.runtime.state { log("\(rd.percent)%: \(prev.rawValue) -> \(s.runtime.state.rawValue) (\(a))") }
        if prevPhase != s.runtime.calibration {
            record(s.runtime.calibration.map { HistoryEntry(event: .calibrationPhase, phase: $0) } ?? HistoryEntry(event: .calibrationEnded))
        }
        // The gauge has just relearned its capacity (full cycle, then 1 h rest at 100 %): the result is final here.
        if calibrationFinished(from: prevPhase, to: s.runtime.calibration) { finishCalibration(snapshot(rd, now)) }
        switch adapterNotice(phase: s.runtime.calibration, adapter: rd.adapter, now: now, &adapterNotices) {
        case .first: record(HistoryEntry(event: .calibrationNeedsAdapter, phase: s.runtime.calibration)); notify_post(calibrationNeedsAdapterNotification)
        case .reminder: notify_post(calibrationNeedsAdapterNotification)
        case .none: break
        }
        let settled = prev == s.runtime.state && lastAction == a
        lastAction = a
        if pastLimitEpisode(a, state: s.runtime.state, settled: settled, adapter: rd.adapter, limit: s.config.limit, percent: rd.percent,
                            amperage: rd.amperage, watts: rd.batteryWatts, since: &s.runtime.pastLimitSince, now: now) {
            record(HistoryEntry(event: .chargedPastLimit, value: s.config.limit))
        }
        for n in serviceNotices(from: prev, to: s.runtime.state, adapter: rd.adapter, latch: &notices) {
            switch n {
            case .heatProtect: record(HistoryEntry(event: .heatProtect, temperature: rd.temperature)); notify_post(heatProtectNotification)
            case .limitReached: notify_post(limitReachedNotification)
            }
        }

        let noSleep = rd.adapter && (a == .discharge || (s.config.disableSleepUntilLimit && s.runtime.state == .charging))
        if noSleep != sleepDisabled, setSleepDisabled(noSleep) { sleepDisabled = noSleep; log("sleep \(noSleep ? "disabled" : "enabled")") }
        save()
    }

    /// Read once a minute: two calls to powerd. Only where the service charges through the SMC: elsewhere the native
    /// limit is the service's own and a user value cannot be told apart from it.
    func readAppleChargeLimit() {
        guard hw.native, hw.inhibitKey != nil else { return }
        appleChargeLimit = userChargeLimit(enabled: mcl_enabled() != 0, limit: Int(mcl_limit()))
    }

    func snapshot(_ rd: Reading, _ date: Date = Date()) -> BatterySnapshot {
        BatterySnapshot(date: date, maxCapacity: rd.rawMaxCapacity, nominalCapacity: rd.nominalCapacity, designCapacity: rd.designCapacity,
                        cycleCount: rd.cycleCount, temperature: rd.temperature, percent: rd.percent)
    }

    func finishCalibration(_ after: BatterySnapshot) {
        let before = s.runtime.calibrationBefore
        s.runtime.calibrationBefore = nil
        record(HistoryEntry(event: .calibrationDone, capacityBefore: before?.maxCapacity, capacityAfter: after.maxCapacity,
                            healthBefore: before?.health, healthAfter: after.health, cycles: after.cycleCount))
        // Started by an older service: no starting point to compare with.
        guard let before else { return }
        s.lastCalibration = CalibrationResult(start: before.date, end: after.date, before: before, after: after)
        notify_post(calibrationDoneNotification)
    }

    func runSchedule(_ now: Date) {
        lastScheduleCheck = now
        for i in s.config.tasks.indices where s.config.tasks[i].enabled {
            let t = s.config.tasks[i]
            guard let o = lastOccurrence(t, after: max(t.lastRun ?? t.created, t.created), upTo: now) else { continue }
            s.config.tasks[i].lastRun = o
            let late = now.timeIntervalSince(o) > 600
            let value = t.action == .setLimit || t.action == .dischargeTo ? t.value : nil
            if late && !s.config.catchUpMissedTasks { record(HistoryEntry(event: .taskSkipped, action: t.action, value: value)); continue }
            record(HistoryEntry(event: .taskRun, action: t.action, late: late, value: value))
            switch t.action {
            case .setLimit: mutate(.setLimit(t.value))
            case .calibrate: mutate(.calibrate(true))
            case .topUp: mutate(.topUp(true))
            case .pause: mutate(.pause)
            case .dischargeTo: mutate(.dischargeTo(t.value))
            case .lowPowerOn: mutate(.lowPower(true))
            case .lowPowerOff: mutate(.lowPower(false))
            }
        }
    }

    func mutate(_ cmd: Command) {
        let limit = s.config.limit
        defer { if s.config.limit != limit { record(HistoryEntry(event: .limitChanged, value: s.config.limit)) } }
        switch cmd {
        case .status: break
        case .setConfig(var c):
            c.limit = clamp(c.limit, 20, 100)
            c.idleRange = clamp(c.idleRange, 1, 30)
            c.maxTemp = min(max(c.maxTemp, 25), 50)
            // Clients may hold a stale lastRun; never move it backwards or a task re-runs.
            let old = Dictionary(s.config.tasks.map { ($0.id, $0.lastRun) }, uniquingKeysWith: { a, _ in a })
            for i in c.tasks.indices { if let l = old[c.tasks[i].id] ?? nil, l > (c.tasks[i].lastRun ?? .distantPast) { c.tasks[i].lastRun = l } }
            s.config = c
        case .setLimit(let n): s.config.limit = clamp(n, 20, 100)
        case .discharge(let on): s.runtime.discharge = on
        case .dischargeTo(let n): s.config.limit = clamp(n, 20, 100); s.runtime.discharge = true
        case .topUp(let on): s.runtime.topUp = on
        case .calibrate(let on):
            // A restart while running keeps the original baseline, so the report covers the whole calibration.
            let running = s.runtime.calibration != nil ? s.runtime.calibrationBefore : nil
            s.runtime.calibration = on ? .chargeFull : nil
            s.runtime.phaseStart = Date()
            s.runtime.calibrationBefore = on ? running ?? snapshot(reading) : nil
            record(HistoryEntry(event: on ? .calibrationStarted : .calibrationStopped))
        case .pause: s.config.limit = clamp(reading.percent, 20, 100); s.runtime.discharge = false
        case .led(let c): s.runtime.ledOverride = c
        case .lowPower(let on): pmset(["-a", "lowpowermode", on ? "1" : "0"])
        case .highPower(let on): pmset(["-a", "powermode", on ? "2" : "0"])
        }
    }

    func handle(_ cmd: Command) -> Status {
        if case .status = cmd {} else { mutate(cmd); tick() }
        return Status(config: s.config, runtime: s.runtime, percent: reading.percent, hardwarePercent: reading.hardwarePercent,
                      adapter: reading.adapter, temperature: reading.temperature, adapterWatts: reading.adapterWatts, adapterRatedWatts: reading.adapterRatedWatts,
                      systemWatts: reading.systemWatts, batteryWatts: reading.batteryWatts, batteryAmperage: reading.amperage, ports: reading.ports, nativeLimit: hw.native,
                      sleepDisabled: sleepDisabled, history: Array(s.history.prefix(50)), battery: snapshot(reading),
                      lastCalibration: s.lastCalibration, appleChargeLimit: appleChargeLimit)
    }

    /// "Stop charging during sleep": freeze at current level before sleeping.
    func willSleep() {
        hw.setDischarge(false)
        guard s.config.stopChargingDuringSleep, reading.adapter, s.runtime.state == .charging else { return }
        if hw.inhibitKey != nil { hw.setInhibit(true) }
        else { hw.setMCL(clamp(reading.percent, 80, 100)) }  // ponytail: native limit can't go below 80
        log("sleep: charging paused at \(reading.percent)%")
    }

    /// An app update replaced our binary: exit without touching the limit, launchd (KeepAlive) starts the new one.
    func restartForUpdate() {
        hw.setDischarge(false)
        if sleepDisabled { _ = setSleepDisabled(false) }
        save()
        unlink(socketPath)
        log("binary updated, restarting")
        exit(0)
    }

    func stop() {
        hw.shutdown(keepLimit: s.config.keepLimitWhenStopped, limit: s.config.limit)
        if sleepDisabled { _ = setSleepDisabled(false) }
        s.runtime.state = .exit
        save()
        unlink(socketPath)
        log("stopped")
        exit(0)
    }
}

// MARK: - Daemon wiring

var daemon: Daemon!
var rootPort: io_connect_t = 0
var keep: [AnyObject] = []

func serve() {
    unlink(socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { p in socketPath.utf8CString.withUnsafeBytes { p.copyMemory(from: $0) } }
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, listen(fd, 8) == 0 else { log("cannot bind \(socketPath)"); exit(1) }
    // Only root and admins may drive the charger.
    chown(socketPath, 0, getgrnam("admin")?.pointee.gr_gid ?? 80)
    chmod(socketPath, 0o660)

    let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    src.setEventHandler {
        let c = accept(fd, nil, nil)
        guard c >= 0 else { return }
        defer { close(c) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard let data = try? readLine(c), let cmd = try? JSONDecoder().decode(Command.self, from: data),
              let out = try? JSONEncoder().encode(daemon.handle(cmd)) else { return }
        try? writeLine(c, out)
    }
    src.resume()
    keep.append(src)
}

func watchSleep() {
    var port: IONotificationPortRef?
    var notifier: io_object_t = 0
    rootPort = IORegisterForSystemPower(nil, &port, { _, _, msg, arg in
        switch msg {
        case 0xe000_0270: IOAllowPowerChange(rootPort, Int(bitPattern: arg))                    // kIOMessageCanSystemSleep
        case 0xe000_0280: daemon.willSleep(); IOAllowPowerChange(rootPort, Int(bitPattern: arg))  // kIOMessageSystemWillSleep
        case 0xe000_0300: daemon.tick()                                                          // kIOMessageSystemHasPoweredOn
        default: break
        }
    }, &notifier)
    if let port { CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode) }
}

func runDaemon() -> Never {
    guard getuid() == 0 else { print("daemon must run as root"); exit(1) }
    guard smc_open() == 0 else { print("cannot open AppleSMC"); exit(1) }
    signal(SIGPIPE, SIG_IGN)
    daemon = Daemon()
    for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { daemon.stop() }
        s.resume()
        keep.append(s)
    }
    serve()
    watchSleep()
    daemon.tick()
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let built = { (try? FileManager.default.attributesOfItem(atPath: exe)[.modificationDate]) as? Date }
    let startedFrom = built()
    // ponytail: 5s polling; IOPSNotificationCreateRunLoopSource would cut latency/wakeups
    keep.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
        if built() != startedFrom { daemon.restartForUpdate() }
        daemon.tick()
    })
    RunLoop.main.run()
    exit(0)
}

// MARK: - CLI

func printStatus(_ s: Status) {
    let r = s.runtime
    print("battery \(s.percent)% (hardware \(s.hardwarePercent.map { "\($0)%" } ?? "--")), \(s.adapter ? "adapter" : "battery"), \(s.temperature.map { String(format: "%.1f°C", $0) } ?? "--")")
    print("state \(r.state.rawValue), limit \(s.config.limit)%\(r.discharge ? ", discharge" : "")\(r.topUp ? ", top-up" : "")\(r.calibration.map { ", calibration \($0.rawValue)" } ?? "")")
    print(String(format: "power: adapter %.1fW, system %.1fW, battery %+.1fW", s.adapterWatts, s.systemWatts, s.batteryWatts))
    let ports = (s.ports ?? []).filter { $0.watts > 0.1 }
    if !ports.isEmpty {
        print("usb-c: " + ports.map { "\($0.name ?? "device") \(String(format: "%.1fW", $0.watts))\($0.maxWatts.map { String(format: "/%gW", $0) } ?? "")" }.joined(separator: ", "))
    }
    if let b = s.battery {
        print("health: \(calibrationSummary(before: nil, after: b))\(b.nominalHealth.map { String(format: " (nominal %.1f %%)", $0) } ?? ""), design \(b.designCapacity.map { "\($0) mAh" } ?? "--")")
    }
    if let c = s.lastCalibration {
        print("last calibration \(c.end.formatted(date: .abbreviated, time: .shortened)): \(calibrationSummary(before: c.before, after: c.after))")
    }
}

func cli(_ a: [String]) -> Int32 {
    let on = a.count > 1 && a[1] == "on"
    let n = a.count > 1 ? Int(a[1]) : nil
    let cmd: Command
    switch (a.first ?? "status", n) {
    case ("status", _): cmd = .status
    case ("limit", let n?): cmd = .setLimit(n)
    case ("discharge", let n?): cmd = .dischargeTo(n)
    case ("discharge", nil) where a.count > 1: cmd = .discharge(on)
    case ("full", _) where a.count > 1: cmd = .topUp(on)
    case ("calibrate", _) where a.count > 1: cmd = .calibrate(on)
    case ("pause", _): cmd = .pause
    case ("led", _) where a.count > 1:
        guard let c = a[1] == "auto" ? .some(nil) : LEDColor(rawValue: a[1]).map(Optional.some) else { return usage() }
        cmd = .led(c)
    case ("lowpower", _) where a.count > 1: cmd = .lowPower(on)
    case ("highpower", _) where a.count > 1: cmd = .highPower(on)
    default: return usage()
    }
    do { printStatus(try send(cmd)); return 0 } catch { print(error.localizedDescription); return 1 }
}

func usage() -> Int32 {
    print("""
    usage: chargekeeperctl daemon
           chargekeeperctl status | limit <20-100> | pause | discharge on|off|<n> | full on|off | calibrate on|off
           chargekeeperctl led auto|system|off|green|orange|orangeBlink | lowpower on|off | highpower on|off
    """)
    return 1
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "daemon" { runDaemon() }
exit(cli(args))
