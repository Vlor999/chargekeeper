import Foundation

/// Diagnostic log of the service: one file per UTC day in `logDir`, root-owned and world-readable so the app can show it.
/// Written on events only (start, stop, state changes, errors), so each line opens and closes its file.
enum DiagnosticLog {
    static var enabled = true
    static var keepDays = logDaysDefault
    private static var purgedDay: Int?
    /// Day whose file reached `logMaxFileBytes` and already got its notice line (in memory: a restart may add one more).
    private static var fullDay: Int?

    static func configure(_ c: Config) {
        enabled = c.logEnabled
        keepDays = c.logDays
        purge(Date())
    }

    static func write(_ level: LogLevel, _ message: String) {
        let now = Date(), day = logDay(now)
        if purgedDay != day { purge(now) }
        guard enabled else { return }
        guard folderReady() else { return }
        let fd = open(logDir + "/" + logFileName(day: day), O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var st = stat()
        // A hard link planted in the folder would make us append to another file.
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == 0, st.st_nlink == 1 else { return }
        if st.st_mode & 0o7777 != 0o644 { fchmod(fd, 0o644) }
        var line = logLineText(LogLine(date: now, level: level, message: message))
        if Int(st.st_size) + line.utf8.count > logMaxFileBytes {
            guard fullDay != day else { return }
            fullDay = day
            line = logLineText(LogLine(date: now, level: .warn, message: "log file full: entries dropped until midnight UTC"))
            guard Int(st.st_size) + line.utf8.count <= logMaxFileBytes + logFullReserveBytes else { return }
        }
        _ = line.utf8CString.withUnsafeBufferPointer { Foundation.write(fd, $0.baseAddress, $0.count - 1) }
    }

    /// Deletes the files older than `keepDays`, by whole day. `unlink` removes a link itself, never its target.
    static func purge(_ now: Date) {
        purgedDay = logDay(now)
        guard isRootFolder(logDir), let names = try? FileManager.default.contentsOfDirectory(atPath: logDir) else { return }
        for n in names {
            if let d = logFileDay(n), logFileExpired(day: d, now: now, keepDays: keepDays) { unlink(logDir + "/" + n) }
        }
    }

    /// Creates the state folder and the log folder if missing (0755), then checks both are real root-owned folders.
    private static func folderReady() -> Bool {
        let parent = (logDir as NSString).deletingLastPathComponent
        for dir in [parent, logDir] {
            if !isRootFolder(dir) {
                // mkdir applies the umask: the mode is set again so the app can list the folder.
                if mkdir(dir, 0o755) == 0 { chmod(dir, 0o755) } else if errno != EEXIST { return false }
                guard isRootFolder(dir) else { return false }
            }
        }
        return true
    }

    /// A folder (not a link to one) owned by root and writable by root only.
    private static func isRootFolder(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR && st.st_uid == 0 && st.st_mode & 0o022 == 0
    }
}

func log(_ s: String, _ level: LogLevel = .info) { DiagnosticLog.write(level, s) }
