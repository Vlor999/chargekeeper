import Foundation

enum ClientError: Error, LocalizedError {
    case unavailable
    case closedWithoutReply
    var errorDescription: String? {
        switch self {
        case .unavailable: "ChargeKeeper service not running: open ChargeKeeper and enable it in System Settings > Login Items"
        case .closedWithoutReply: "ChargeKeeper service did not answer this request: it may be older than the app. Install the latest update, then restart the Mac."
        }
    }
}

func send(_ cmd: Command) throws -> Status {
    let fd = try connectToService()
    defer { close(fd) }
    try writeLine(fd, JSONEncoder().encode(cmd))
    return try JSONDecoder().decode(Status.self, from: readLine(fd))
}

private func connectToService() throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ClientError.unavailable }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { p in socketPath.utf8CString.withUnsafeBytes { p.copyMemory(from: $0) } }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0 else {
        close(fd)
        throw ClientError.unavailable
    }
    return fd
}

func writeLine(_ fd: Int32, _ data: Data) throws {
    let bytes = data + Data([socketLineTerminator])
    let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    if n != bytes.count { throw ClientError.unavailable }
}

func readLine(_ fd: Int32) throws -> Data {
    var out = Data(), buf = [UInt8](repeating: 0, count: socketReadBufferBytes)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        out.append(contentsOf: buf[0..<n])
        if buf[n - 1] == socketLineTerminator { break }
    }
    guard !out.isEmpty else { throw ClientError.closedWithoutReply }
    return out
}
