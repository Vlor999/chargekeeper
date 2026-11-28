import Foundation

enum DiagnosticLog {
    static var enabled = true
    static var keepDays = logRetentionDaysDefault
    private static var purgedDay: Int?
    private static var dayFullNoticeWritten: Int?

    static func configure(_ c: Config) {
        enabled = c.logEnabled
        keepDays = c.logDays
        purgeExpiredFiles(Date())
    }

    static func write(_ level: LogLevel, _ message: String) {
        let now = Date(), day = logDay(now)
        if purgedDay != day { purgeExpiredFiles(now) }
        guard enabled else { return }
        guard ensureRootOwnedFolders() else { return }
        let fd = open(logDir + "/" + logFileName(day: day), O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, logFileMode)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, isRootOwnedRegularFileWithoutHardLinks(st) else { return }
        if st.st_mode & permissionBitsMask != logFileMode { fchmod(fd, logFileMode) }
        var line = logLineText(LogLine(date: now, level: level, message: message))
        if Int(st.st_size) + line.utf8.count > logMaxBytesPerDayFile {
            guard dayFullNoticeWritten != day else { return }
            dayFullNoticeWritten = day
            line = logLineText(LogLine(date: now, level: .warn, message: "log file full: entries dropped until midnight UTC"))
            guard Int(st.st_size) + line.utf8.count <= logMaxBytesPerDayFile + logFullNoticeReserveBytes else { return }
        }
        _ = line.utf8CString.withUnsafeBufferPointer { Foundation.write(fd, $0.baseAddress, $0.count - 1) }
    }

    static func purgeExpiredFiles(_ now: Date) {
        purgedDay = logDay(now)
        guard isRootOnlyWritableFolder(logDir), let names = try? FileManager.default.contentsOfDirectory(atPath: logDir) else { return }
        for n in names {
            if let d = logFileDay(n), logFileExpired(day: d, now: now, keepDays: keepDays) { unlink(logDir + "/" + n) }
        }
    }

    private static func ensureRootOwnedFolders() -> Bool {
        let parent = (logDir as NSString).deletingLastPathComponent
        for dir in [parent, logDir] where !isRootOnlyWritableFolder(dir) {
            guard makeFolderIgnoringUmask(dir), isRootOnlyWritableFolder(dir) else { return false }
        }
        return true
    }

    private static func makeFolderIgnoringUmask(_ dir: String) -> Bool {
        guard mkdir(dir, logFolderMode) == 0 else { return errno == EEXIST }
        chmod(dir, logFolderMode)
        return true
    }

    private static func isRootOnlyWritableFolder(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && isRootOwnedFolderWithoutGroupOrOtherWrite(st)
    }
}

func log(_ s: String, _ level: LogLevel = .info) { DiagnosticLog.write(level, s) }
