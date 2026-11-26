import Foundation

func logDay(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / secondsPerDay).rounded(.down)) }

private let utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func logFileName(day: Int) -> String {
    let c = utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) * secondsPerDay))
    return logFilePrefix + String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!) + logFileExtension
}

func logFileDay(_ name: String) -> Int? {
    guard name.hasPrefix(logFilePrefix), name.hasSuffix(logFileExtension) else { return nil }
    let date = name.dropFirst(logFilePrefix.count).dropLast(logFileExtension.count)
    let parts = date.split(separator: "-", omittingEmptySubsequences: false)
    guard date.count == 10, parts.map(\.count) == [4, 2, 2], parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
          let d = utcCalendar.date(from: DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))) else { return nil }
    let day = logDay(d)
    let isCanonicalName = logFileName(day: day) == name
    return isCanonicalName ? day : nil
}

func logFileExpired(day: Int, now: Date, keepDays: Int) -> Bool {
    let dayEnd = Double(day + 1) * secondsPerDay
    return dayEnd <= now.timeIntervalSince1970 - Double(keepDays) * secondsPerDay
}

struct LogLine: Equatable {
    var date: Date
    var level: LogLevel
    var message: String
}

func logLineText(_ l: LogLine) -> String {
    "\(ISO8601DateFormatter().string(from: l.date)) \(l.level.rawValue) \(singleLine(l.message))\n"
}

private func singleLine(_ s: String) -> String {
    s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
}

func parseLogLine<S: StringProtocol>(_ s: S) -> LogLine? {
    let f = s.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    guard f.count >= 2, let date = ISO8601DateFormatter().date(from: String(f[0])), let level = LogLevel(rawValue: String(f[1])) else { return nil }
    return LogLine(date: date, level: level, message: f.count == 3 ? String(f[2]) : "")
}
