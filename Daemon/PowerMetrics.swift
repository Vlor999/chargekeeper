import Foundation

/// CPU, GPU and Neural Engine power from powermetrics (root only), started with the service and kept running: the
/// last `socHistoryWindow` of samples stays in memory, so a chart opened later shows the last minutes at once.
/// If powermetrics ends on its own, the service starts it again after `socRetryDelay`.
final class PowerMetrics {
    private var pid: pid_t = 0
    private var reader: DispatchSourceRead?
    private var exitWatch: DispatchSourceProcess?
    private var buffer = Data()
    /// The service asked powermetrics to stop: its exit is not a failure.
    private var stopping = false
    /// When SIGTERM was sent, by the service or after powermetrics closed its output.
    private var termAt: Date?
    private var failedAt = Date.distantPast
    private var lastWarn = Date.distantPast
    private(set) var history: [SoCPowerPoint] = []

    /// Called at launch and by the service timer: starts powermetrics (again, after the retry delay), reaps it, and
    /// kills one that ignores SIGTERM.
    func keepRunning() {
        // Backstop for an exit the watch missed (child gone before the watch was armed).
        if pid != 0 { exited() }
        if pid == 0 {
            if !stopping && Date().timeIntervalSince(failedAt) >= socRetryDelay { start() }
            return
        }
        if let t = termAt, Date().timeIntervalSince(t) > socKillGrace { kill(pid, SIGKILL) }
    }

    /// Service exit or update: asks powermetrics to exit and not to start again. Reaped by launchd once the service is gone.
    func terminate() {
        stopping = true
        guard pid != 0 else { return }
        signalTerm()
    }

    private func signalTerm() {
        if termAt == nil { termAt = Date() }
        kill(pid, SIGTERM)
    }

    private func start() {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return failed("pipe failed: errno \(errno)") }
        var actions: posix_spawn_file_actions_t?
        var attr: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attr)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        // Only stdin/out/err reach the child (not the service socket). Signals the service ignores are reset: if the
        // service dies, powermetrics gets SIGPIPE on its next write and exits instead of running on.
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults); sigemptyset(&mask)
        for s in [SIGPIPE, SIGTERM, SIGINT] { sigaddset(&defaults, s) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &mask)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let argv = ([powermetricsPath] + powermetricsArguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var envp: [UnsafeMutablePointer<CChar>?] = [nil]
        var child: pid_t = 0
        let rc = posix_spawn(&child, powermetricsPath, &actions, &attr, argv, &envp)
        close(fds[1])
        guard rc == 0 else { close(fds[0]); return failed("spawn failed: \(rc)") }
        pid = child
        termAt = nil
        buffer = Data()
        _ = fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK)

        let fd = fds[0]
        let r = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        r.setEventHandler { [weak self] in self?.read(fd) }
        r.setCancelHandler { close(fd) }
        r.resume()
        reader = r
        let w = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .main)
        w.setEventHandler { [weak self] in self?.exited() }
        w.resume()
        exitWatch = w
    }

    private func read(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        var samples = 0, parsed = false, dropped = false
        while true {
            let n = Foundation.read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                let taken = takePlistSamples(&buffer, maxBytes: socMaxSampleBytes)
                samples += taken.samples.count
                dropped = dropped || taken.dropped
                // One sample per interval; a malformed one is skipped.
                if let p = taken.samples.reversed().lazy.compactMap(socPower).first {
                    history = appendPowerPoint(history, SoCPowerPoint(date: Date(), power: p), window: socHistoryWindow)
                    parsed = true
                }
                continue
            }
            // EOF: powermetrics closed its output. Not a stop the service asked for: its exit counts as a failure.
            if n == 0 { reader?.cancel(); reader = nil; signalTerm() }
            break
        }
        if dropped { warn("sample over \(socMaxSampleBytes) bytes dropped") }
        if samples > 0 && !parsed { warn("\(samples) unreadable sample(s)") }
    }

    /// Reaps powermetrics if it has exited.
    private func exited() {
        var status: Int32 = 0
        guard pid != 0, waitpid(pid, &status, WNOHANG) == pid else { return }
        if !stopping { failed("exited on its own (status \(status))") }
        reader?.cancel(); reader = nil
        exitWatch?.cancel(); exitWatch = nil
        pid = 0
        termAt = nil
        buffer = Data()
    }

    private func failed(_ why: String) {
        failedAt = Date()
        log("powermetrics: \(why), retry in \(Int(socRetryDelay)) s", .warn)
    }

    private func warn(_ why: String) {
        guard Date().timeIntervalSince(lastWarn) >= socWarnInterval else { return }
        lastWarn = Date()
        log("powermetrics: \(why)", .warn)
    }
}
