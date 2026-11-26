import Foundation

final class PowerMetrics {
    private enum Child {
        case notRunning
        case running(pid_t)
        case closedItsOutput(pid_t, sigtermSentAt: Date)
        case stopRequested(pid_t, sigtermSentAt: Date)
    }

    private var configuredInterval: PowerInterval
    private var runningInterval = PowerInterval.off
    private var child = Child.notRunning
    private var serviceIsExiting = false
    private var reader: DispatchSourceRead?
    private var exitWatch: DispatchSourceProcess?
    private var buffer = Data()
    private var failedAt = Date.distantPast
    private var lastWarn = Date.distantPast, lastFailureLog = Date.distantPast
    private(set) var history: [SoCPowerPoint] = []

    init(interval: PowerInterval) { configuredInterval = interval }

    private var pid: pid_t? {
        switch child {
        case .notRunning: nil
        case .running(let pid), .closedItsOutput(let pid, _), .stopRequested(let pid, _): pid
        }
    }

    private var sigtermSentAt: Date? {
        switch child {
        case .notRunning, .running: nil
        case .closedItsOutput(_, let at), .stopRequested(_, let at): at
        }
    }

    private var stopRequested: Bool {
        if case .stopRequested = child { return true }
        return false
    }

    func applySetting(_ i: PowerInterval) {
        guard i != configuredInterval else { return }
        configuredInterval = i
        log("powermetrics: " + (i == .off ? "off" : "every \(i.rawValue) s"))
        if i == .off { history = [] }
        failedAt = .distantPast
        if pid != nil { requestStop() } else { keepRunning() }
    }

    func keepRunning() {
        reapIfExited()
        if pid == nil { startIfDue() } else { killIfIgnoringSigterm() }
    }

    func stopForServiceExit() {
        serviceIsExiting = true
        requestStop()
    }

    private func startIfDue() {
        if !serviceIsExiting && configuredInterval != .off && Date().timeIntervalSince(failedAt) >= socRestartDelayAfterFailure { start() }
    }

    private func killIfIgnoringSigterm() {
        guard let pid, let at = sigtermSentAt, Date().timeIntervalSince(at) > socSigkillDelayAfterSigterm else { return }
        kill(pid, SIGKILL)
    }

    private func requestStop() {
        guard let pid else { return }
        child = .stopRequested(pid, sigtermSentAt: sigtermSentAt ?? Date())
        kill(pid, SIGTERM)
    }

    private func handleOutputClosed() {
        reader?.cancel(); reader = nil
        guard let pid else { return }
        if case .running = child { child = .closedItsOutput(pid, sigtermSentAt: Date()) }
        kill(pid, SIGTERM)
    }

    private func makeSpawnFileActions(stdout: Int32) -> posix_spawn_file_actions_t? {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        return actions
    }

    private func makeSpawnAttributesClosingInheritedFDsAndResettingSignals() -> posix_spawnattr_t? {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults); sigemptyset(&mask)
        for s in signalsIgnoredByService { sigaddset(&defaults, s) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &mask)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        return attr
    }

    private func start() {
        guard let args = powermetricsArguments(configuredInterval) else { return }
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return failed("pipe failed: errno \(errno)") }
        var actions = makeSpawnFileActions(stdout: fds[1])
        var attr = makeSpawnAttributesClosingInheritedFDsAndResettingSignals()
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }

        let argv = ([powermetricsPath] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var envp: [UnsafeMutablePointer<CChar>?] = [nil]
        var spawned: pid_t = 0
        let rc = posix_spawn(&spawned, powermetricsPath, &actions, &attr, argv, &envp)
        close(fds[1])
        guard rc == 0 else { close(fds[0]); return failed("spawn failed: \(rc)") }
        child = .running(spawned)
        runningInterval = configuredInterval
        buffer = Data()
        _ = fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK)

        let fd = fds[0]
        let r = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        r.setEventHandler { [weak self] in self?.read(fd) }
        r.setCancelHandler { close(fd) }
        r.resume()
        reader = r
        let w = DispatchSource.makeProcessSource(identifier: spawned, eventMask: .exit, queue: .main)
        w.setEventHandler { [weak self] in self?.reapOnExitEvent() }
        w.resume()
        exitWatch = w
    }

    private func latestPower(in samples: [Data]) -> SoCPower? { samples.reversed().lazy.compactMap(socPower).first }

    private func read(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        var samples = 0, parsed = false, dropped = false
        while true {
            let n = Foundation.read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                let taken = takePlistSamples(&buffer, maxBytes: socMaxPartialSampleBytes)
                samples += taken.samples.count
                dropped = dropped || taken.dropped
                if configuredInterval != .off, let p = latestPower(in: taken.samples) {
                    let point = SoCPowerPoint(date: Date(), averagePower: p, samplingInterval: TimeInterval(runningInterval.rawValue))
                    history = appendPowerPoint(history, point, window: socHistoryRetention)
                    parsed = true
                }
                continue
            }
            if n == 0 { handleOutputClosed() }
            break
        }
        if dropped { warn("sample over \(socMaxPartialSampleBytes) bytes dropped") }
        if samples > 0 && !parsed { warn("\(samples) unreadable sample(s)") }
    }

    private func reapIfExited() { reap(waitOptions: WNOHANG) }

    private func reapOnExitEvent() { reap(waitOptions: 0) }

    private func reap(waitOptions: Int32) {
        var status: Int32 = 0
        guard let pid, waitpid(pid, &status, waitOptions) == pid else { return }
        if !stopRequested { failed("exited on its own (status \(status))") }
        let restartWithNewInterval = stopRequested && !serviceIsExiting
        reader?.cancel(); reader = nil
        exitWatch?.cancel(); exitWatch = nil
        child = .notRunning
        buffer = Data()
        if restartWithNewInterval { keepRunning() }
    }

    private func failed(_ why: String) {
        failedAt = Date()
        rateLimited(&lastFailureLog, "\(why), retry every \(Int(socRestartDelayAfterFailure)) s")
    }

    private func warn(_ why: String) { rateLimited(&lastWarn, why) }

    private func rateLimited(_ last: inout Date, _ why: String) {
        guard Date().timeIntervalSince(last) >= socWarningLogInterval else { return }
        last = Date()
        log("powermetrics: \(why)", .warn)
    }
}
