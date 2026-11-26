import Foundation

func keepAwakeEnd(_ d: KeepAwakeDuration, now: Date) -> Date {
    d == .untilOff ? .distantFuture : now.addingTimeInterval(TimeInterval(d.rawValue * 60))
}

func keepAwakeUntil(_ until: Date?, now: Date, adapter: Bool, percent: Int, minBattery: Int) -> Date? {
    guard let until, until > now, adapter || percent >= minBattery else { return nil }
    return until
}

func clampedKeepAwakeMinBattery(_ v: Int) -> Int {
    min(max(v, keepAwakeMinBatteryPercentRange.lowerBound), keepAwakeMinBatteryPercentRange.upperBound)
}

func keepAwakeAtStart(_ until: Date?, updateRestart: Bool) -> Date? { updateRestart ? until : nil }

func unexplainedSleepDisabled(systemSleepDisabled: Bool?, serviceSleepDisabled: Bool?) -> Bool {
    systemSleepDisabled == true && serviceSleepDisabled != true
}

func sleepDisabledWanted(_ c: Config, _ a: Action, state: ChargeState, adapter: Bool, keepAwake: Bool) -> Bool {
    let dischargingOnAdapter = adapter && a == .discharge
    let chargingToLimitAwake = adapter && c.disableSleepUntilLimit && state == .charging
    let keepAwakeWithLidClosed = keepAwake && c.keepAwakeWithLidClosed
    return dischargingOnAdapter || chargingToLimitAwake || keepAwakeWithLidClosed
}
