import Foundation

/// Days since 1970-01-01 in UTC: the log rolls to a new file at midnight UTC.
func logDay(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / secondsPerDay).rounded(.down)) }

private let utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// "chargekeeper-2026-11-03.log".
func logFileName(day: Int) -> String {
    let c = utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) * secondsPerDay))
    return logFilePrefix + String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!) + logFileExtension
}

/// Day of a log file name, nil for any other file (including impossible dates such as 2026-02-31).
func logFileDay(_ name: String) -> Int? {
    guard name.hasPrefix(logFilePrefix), name.hasSuffix(logFileExtension) else { return nil }
    let date = name.dropFirst(logFilePrefix.count).dropLast(logFileExtension.count)
    let parts = date.split(separator: "-", omittingEmptySubsequences: false)
    guard date.count == 10, parts.map(\.count) == [4, 2, 2], parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
          let d = utcCalendar.date(from: DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))) else { return nil }
    let day = logDay(d)
    return logFileName(day: day) == name ? day : nil
}

/// Whole days only: a file goes once its last second is more than `keepDays` days old.
func logFileExpired(day: Int, now: Date, keepDays: Int) -> Bool {
    Double(day + 1) * secondsPerDay <= now.timeIntervalSince1970 - Double(keepDays) * secondsPerDay
}

struct LogLine: Equatable {
    var date: Date
    var level: LogLevel
    var message: String
}

/// "2026-11-03T08:33:47Z warn message\n": one line per entry, line breaks in the message replaced by spaces.
func logLineText(_ l: LogLine) -> String {
    let msg = l.message.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    return "\(ISO8601DateFormatter().string(from: l.date)) \(l.level.rawValue) \(msg)\n"
}

/// Inverse of `logLineText` (without the line break); nil for a line in any other format.
func parseLogLine<S: StringProtocol>(_ s: S) -> LogLine? {
    let f = s.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    guard f.count >= 2, let date = ISO8601DateFormatter().date(from: String(f[0])), let level = LogLevel(rawValue: String(f[1])) else { return nil }
    return LogLine(date: date, level: level, message: f.count == 3 ? String(f[2]) : "")
}
