import Foundation

/// End date of a keep awake started at `now`.
func keepAwakeEnd(_ d: KeepAwakeDuration, now: Date) -> Date {
    d == .untilOff ? .distantFuture : now.addingTimeInterval(TimeInterval(d.rawValue * 60))
}

/// Keep awake end still in force at `now`: nil once the end has passed, or on battery below `minBattery`.
func keepAwakeUntil(_ until: Date?, now: Date, adapter: Bool, percent: Int, minBattery: Int) -> Date? {
    guard let until, until > now, adapter || percent >= minBattery else { return nil }
    return until
}

/// Battery threshold from a socket request, kept inside `keepAwakeMinBatteryPercentRange`.
func clampedKeepAwakeMinBattery(_ v: Int) -> Int {
    min(max(v, keepAwakeMinBatteryPercentRange.lowerBound), keepAwakeMinBatteryPercentRange.upperBound)
}

/// Keep awake at service start: kept only across a restart for an update. After a crash, a kill or a power loss it is
/// off, so crash recovery never leaves sleep disabled.
func keepAwakeAtStart(_ until: Date?, updateRestart: Bool) -> Date? { updateRestart ? until : nil }

/// System sleep disabled with no reason from the service: another tool, or left over from a stop. `system` nil: unknown;
/// `service` nil: the service is unreachable, otherwise its own sleep disabled state.
func unexplainedSleepDisabled(system: Bool?, service: Bool?) -> Bool { system == true && service != true }

/// System sleep disabled (a closed lid stays awake): discharging on the adapter, charging to the limit with that option
/// on, or keep awake with the lid closed option.
func sleepDisabledWanted(_ c: Config, _ a: Action, state: ChargeState, adapter: Bool, keepAwake: Bool) -> Bool {
    (adapter && (a == .discharge || (c.disableSleepUntilLimit && state == .charging))) || (keepAwake && c.keepAwakeWithLidClosed)
}
