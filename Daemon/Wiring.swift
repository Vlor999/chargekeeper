import Foundation
import IOKit.pwr_mgt

var daemon: Daemon!
var rootPort: io_connect_t = 0
var keep: [AnyObject] = []

func restrictSocketToAdmins(_ path: String) {
    chown(path, 0, getgrnam(adminGroupName)?.pointee.gr_gid ?? adminGroupFallbackGID)
    chmod(path, socketMode)
}

func limitClientStall(_ fd: Int32) {
    var tv = timeval(tv_sec: socketClientStallLimitSeconds, tv_usec: 0)
    for opt in [SO_RCVTIMEO, SO_SNDTIMEO] where setsockopt(fd, SOL_SOCKET, opt, &tv, socklen_t(MemoryLayout<timeval>.size)) != 0 {
        log("socket timeout \(opt) not set: errno \(errno)", .warn)
    }
}

func serve() {
    unlink(socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { p in socketPath.utf8CString.withUnsafeBytes { p.copyMemory(from: $0) } }
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, listen(fd, 8) == 0 else { log("cannot bind \(socketPath): errno \(errno)", .error); exit(1) }
    restrictSocketToAdmins(socketPath)

    let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    src.setEventHandler {
        let c = accept(fd, nil, nil)
        guard c >= 0 else { log("socket accept failed: errno \(errno)", .error); return }
        defer { close(c) }
        limitClientStall(c)
        guard let data = try? readLine(c) else { log("socket: no request read", .warn); return }
        guard let cmd = try? JSONDecoder().decode(Command.self, from: data) else { log("socket: invalid request (\(data.count) bytes)", .warn); return }
        guard let out = try? JSONEncoder().encode(daemon.handle(cmd)) else { return }
        if (try? writeLine(c, out)) == nil { log("socket: reply not sent", .warn) }
    }
    src.resume()
    keep.append(src)
}

func watchSleep() {
    var port: IONotificationPortRef?
    var notifier: io_object_t = 0
    rootPort = IORegisterForSystemPower(nil, &port, { _, _, msg, arg in
        switch SystemPowerMessage(rawValue: msg) {
        case .canSystemSleep: IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case .systemWillSleep: daemon.pauseChargingBeforeSleep(); IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case .systemHasPoweredOn: daemon.tick()
        case nil: break
        }
    }, &notifier)
    if let port { CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode) }
}

func runDaemon() -> Never {
    guard getuid() == 0 else { print("daemon must run as root"); exit(1) }
    guard smc_open() == 0 else { print("cannot open AppleSMC"); exit(1) }
    signal(SIGPIPE, SIG_IGN)
    daemon = Daemon()
    for sig in stopSignals {
        signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { daemon.stop() }
        s.resume()
        keep.append(s)
    }
    serve()
    watchSleep()
    daemon.tick()
    daemon.power.keepRunning()
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let built = { (try? FileManager.default.attributesOfItem(atPath: exe)[.modificationDate]) as? Date }
    let startedFrom = built()
    // ponytail: the battery is polled every serviceTickInterval; IOPSNotificationCreateRunLoopSource would cut latency and wakeups (https://github.com/Vlor999/chargekeeper/issues/62)
    keep.append(Timer.scheduledTimer(withTimeInterval: serviceTickInterval, repeats: true) { _ in
        if built() != startedFrom { daemon.exitForUpdate() }
        daemon.tick()
        daemon.power.keepRunning()
    })
    RunLoop.main.run()
    exit(0)
}
