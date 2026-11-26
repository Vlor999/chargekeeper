import Foundation

/// Series point from a reading; nil while the gauge reports no capacity.
func healthSample(_ b: BatterySnapshot, calibration: Bool = false) -> HealthSample? {
    guard let m = b.fullChargeCapacityMAh, m > 0, let d = b.designCapacityMAh, d > 0 else { return nil }
    return HealthSample(date: b.date, fullChargeCapacityMAh: m, nominalCapacityMAh: b.nominalCapacityMAh, designCapacityMAh: d,
                        cycleCount: b.cycleCount, fromCalibration: calibration ? true : nil)
}

/// The daily point is due when no point falls on the same calendar day.
func healthSampleDue(_ series: [HealthSample], now: Date, calendar: Calendar = .current) -> Bool {
    series.last { calendar.isDate($0.date, inSameDayAs: now) } == nil
}

/// Inserts the point in date order, then thins the series: daily for the `healthDailyRetentionDays` days before `now`, the first
/// point of each week before that, calibration points kept. Over `healthMaxSamples` points, the oldest daily or weekly
/// points go first, then the oldest calibration points.
/// Points dated more than a day after `now` (a clock that was set ahead) are refused, and dropped from the series.
/// One point per date: the calibration point wins over the daily point of the same tick.
func addHealthSample(_ series: [HealthSample], _ p: HealthSample, now: Date, calendar cal: Calendar = .current) -> [HealthSample] {
    let latest = now.addingTimeInterval(secondsPerDay)
    var all = series.filter { $0.date <= latest }
    guard p.date <= latest else { return all }
    if let i = all.firstIndex(where: { $0.date == p.date }) {
        guard p.fromCalibration == true, all[i].fromCalibration != true else { return all }
        all.remove(at: i)
    }
    all.insert(p, at: all.firstIndex { $0.date > p.date } ?? all.count)
    let cutoff = now.addingTimeInterval(-Double(healthDailyRetentionDays) * secondsPerDay)
    var weeks = Set<DateComponents>()
    var kept = all.filter { s in
        s.date >= cutoff || s.fromCalibration == true || weeks.insert(cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.date)).inserted
    }
    var excess = kept.count - healthMaxSamples
    if excess > 0 {
        kept = kept.filter { s in
            guard excess > 0, s.fromCalibration != true else { return true }
            excess -= 1
            return false
        }
    }
    return Array(kept.suffix(healthMaxSamples))
}

enum HealthRange: String, CaseIterable { case threeMonths, year, all }

/// First date shown by the range.
func healthRangeStart(_ r: HealthRange, now: Date, calendar cal: Calendar = .current) -> Date {
    switch r {
    case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now) ?? now
    case .year: return cal.date(byAdding: .year, value: -1, to: now) ?? now
    case .all: return .distantPast
    }
}

/// Change between the first and last points of the period. Health in percentage points.
struct HealthChange: Equatable {
    var points: Double
    var cycles: Int?
    var days: Int
}

func healthChange(_ series: [HealthSample]) -> HealthChange? {
    guard series.count >= 2, let a = series.first, let b = series.last else { return nil }
    let cycles = b.cycleCount.flatMap { y in a.cycleCount.map { y - $0 } }
    return HealthChange(points: b.healthPercent - a.healthPercent, cycles: cycles,
                        days: Int((b.date.timeIntervalSince(a.date) / secondsPerDay).rounded()))
}

enum SpanUnit: Equatable { case days, months, years }

/// Period length as shown: days under 60 days, months under 2 years (12 months reads 1 year), whole years beyond. At least 1.
func healthSpan(days: Int) -> (value: Int, unit: SpanUnit) {
    if days < 60 { return (max(days, 1), .days) }
    let months = Int((Double(days) / 30.44).rounded())
    if months == 12 { return (1, .years) }
    if days < 730 { return (months, .months) }
    return (Int((Double(days) / 365.25).rounded()), .years)
}
