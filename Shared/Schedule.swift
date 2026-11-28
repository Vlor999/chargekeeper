import Foundation

func lastOccurrence(_ t: ScheduledTask, after: Date, upTo: Date, calendar cal: Calendar = .current) -> Date? {
    if t.start > upTo { return nil }
    if t.repeatRule == .never { return t.start > after ? t.start : nil }
    for n in stride(from: occurrenceIndexBound(t, upTo: upTo, calendar: cal), through: 0, by: -1) {
        guard let date = occurrence(n, of: t, calendar: cal), date <= upTo else { continue }
        if date <= after { return nil }
        if t.repeatRule == .weekdays && cal.isDateInWeekend(date) { continue }
        return date
    }
    return nil
}

private func occurrenceIndexBound(_ t: ScheduledTask, upTo: Date, calendar cal: Calendar) -> Int {
    let elapsed = cal.dateComponents([.day, .month, .year], from: t.start, to: upTo)
    let days = cal.dateComponents([.day], from: t.start, to: upTo).day ?? 0
    let bound: Int = switch t.repeatRule {
    case .daily, .weekdays: days
    case .weekly: days / 7
    case .biweekly: days / 14
    case .monthly: (elapsed.year ?? 0) * 12 + (elapsed.month ?? 0)
    case .yearly: elapsed.year ?? 0
    case .never: 0
    }
    return bound + 1
}

private func occurrence(_ n: Int, of t: ScheduledTask, calendar cal: Calendar) -> Date? {
    switch t.repeatRule {
    case .daily, .weekdays: return cal.date(byAdding: .day, value: n, to: t.start)
    case .weekly: return cal.date(byAdding: .day, value: 7 * n, to: t.start)
    case .biweekly: return cal.date(byAdding: .day, value: 14 * n, to: t.start)
    case .monthly: return sameDayOfMonth(monthsAfterStart: n, of: t.start, calendar: cal)
    case .yearly: return sameDayOfMonth(monthsAfterStart: 12 * n, of: t.start, calendar: cal)
    case .never: return n == 0 ? t.start : nil
    }
}

private func sameDayOfMonth(monthsAfterStart months: Int, of start: Date, calendar cal: Calendar) -> Date? {
    let startComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: start)
    var c = startComponents
    let monthIndex = (startComponents.month! - 1) + months
    c.year = startComponents.year! + monthIndex / 12
    c.month = monthIndex % 12 + 1
    return cal.date(from: c).flatMap { cal.component(.day, from: $0) == startComponents.day ? $0 : nil }
}

func tasksKeepingNewestLastRun(_ incoming: [ScheduledTask], current: [ScheduledTask]) -> [ScheduledTask] {
    let currentLastRun = Dictionary(current.map { ($0.id, $0.lastRun) }, uniquingKeysWith: { a, _ in a })
    var tasks = incoming
    for i in tasks.indices { if let l = currentLastRun[tasks[i].id] ?? nil, l > (tasks[i].lastRun ?? .distantPast) { tasks[i].lastRun = l } }
    return tasks
}
