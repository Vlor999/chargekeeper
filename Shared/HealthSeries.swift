import Foundation

func healthSample(_ b: BatterySnapshot, calibration: Bool = false) -> HealthSample? {
    guard let m = b.fullChargeCapacityMAh, m > 0, let d = b.designCapacityMAh, d > 0 else { return nil }
    return HealthSample(date: b.date, fullChargeCapacityMAh: m, nominalCapacityMAh: b.nominalCapacityMAh, designCapacityMAh: d,
                        cycleCount: b.cycleCount, fromCalibration: calibration)
}

func healthSampleDue(_ series: [HealthSample], now: Date, calendar: Calendar = .current) -> Bool {
    !series.contains { calendar.isDate($0.date, inSameDayAs: now) }
}

func addHealthSample(_ series: [HealthSample], _ p: HealthSample, now: Date, calendar cal: Calendar = .current) -> [HealthSample] {
    let latestAccepted = now.addingTimeInterval(healthMaxClockAhead)
    let current = series.filter { $0.date <= latestAccepted }
    guard p.date <= latestAccepted, let inserted = insertingInDateOrder(p, into: current) else { return current }
    let dailyCutoff = now.addingTimeInterval(-Double(healthDailyRetentionDays) * secondsPerDay)
    return cappedDroppingCalibrationLast(thinnedToWeekly(inserted, before: dailyCutoff, calendar: cal))
}

private func insertingInDateOrder(_ p: HealthSample, into series: [HealthSample]) -> [HealthSample]? {
    var all = series
    if let i = all.firstIndex(where: { $0.date == p.date }) {
        guard p.fromCalibration, !all[i].fromCalibration else { return nil }
        all.remove(at: i)
    }
    all.insert(p, at: all.firstIndex { $0.date > p.date } ?? all.count)
    return all
}

private func thinnedToWeekly(_ series: [HealthSample], before cutoff: Date, calendar cal: Calendar) -> [HealthSample] {
    var weeks = Set<DateComponents>()
    return series.filter { s in
        s.date >= cutoff || s.fromCalibration || weeks.insert(cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.date)).inserted
    }
}

private func cappedDroppingCalibrationLast(_ series: [HealthSample]) -> [HealthSample] {
    var kept = series
    var excess = kept.count - healthMaxSamples
    if excess > 0 {
        kept = kept.filter { s in
            guard excess > 0, !s.fromCalibration else { return true }
            excess -= 1
            return false
        }
    }
    return Array(kept.suffix(healthMaxSamples))
}

enum HealthRange: String, CaseIterable { case threeMonths, year, all }

func healthRangeStart(_ r: HealthRange, now: Date, calendar cal: Calendar = .current) -> Date {
    switch r {
    case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now) ?? now
    case .year: return cal.date(byAdding: .year, value: -1, to: now) ?? now
    case .all: return .distantPast
    }
}

struct HealthChange: Equatable {
    var healthPercentagePoints: Double
    var cycles: Int?
    var days: Int
}

func healthChange(_ series: [HealthSample]) -> HealthChange? {
    guard series.count >= 2, let a = series.first, let b = series.last else { return nil }
    let cycles = b.cycleCount.flatMap { y in a.cycleCount.map { y - $0 } }
    return HealthChange(healthPercentagePoints: b.healthPercent - a.healthPercent, cycles: cycles,
                        days: Int((b.date.timeIntervalSince(a.date) / secondsPerDay).rounded()))
}

enum SpanUnit: Equatable { case days, months, years }

func healthSpan(days: Int) -> (value: Int, unit: SpanUnit) {
    if days < healthSpanDaysBeforeMonths { return (max(days, 1), .days) }
    let months = Int((Double(days) / averageDaysPerMonth).rounded())
    if months == 12 { return (1, .years) }
    if days < healthSpanDaysBeforeYears { return (months, .months) }
    return (Int((Double(days) / averageDaysPerYear).rounded()), .years)
}
