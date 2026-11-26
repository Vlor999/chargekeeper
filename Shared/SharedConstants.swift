import Foundation

let legacyInstallName = "jauge"
let socketPath = "/var/run/\(legacyInstallName).sock"

enum DarwinNotification: String, CaseIterable {
    case calibrationDone, heatProtect, calibrationNeedsAdapter, limitReached

    var name: String { "com.vlor999.\(legacyInstallName).\(rawValue)" }
}

let secondsPerDay: TimeInterval = 86400
let healthDailyRetentionDays = 180
let healthWeeklySamplesKept = 340
let healthMaxSamples = healthDailyRetentionDays + healthWeeklySamplesKept
let logDir = "/Library/Application Support/\(legacyInstallName.capitalized)/Logs"
let logFilePrefix = "chargekeeper-"
let logFileExtension = ".log"
let logRetentionDaysRange = 1...90
let logRetentionDaysDefault = 7
let logMaxBytesPerDayFile = 5 * 1024 * 1024
let logFullNoticeReserveBytes = 1024
let powermetricsPath = "/usr/bin/powermetrics"
let assumedPowerSampleInterval: TimeInterval = 5
let appMaxRefreshInterval: TimeInterval = 2
let socHistoryRetention: TimeInterval = 5 * 60
let socStaleAfterIntervals: TimeInterval = 2
let socIntervalChangeSlack: TimeInterval = 5
let socRestartDelayAfterFailure: TimeInterval = 60
let socMaxPartialSampleBytes = 256 * 1024
let socSigkillDelayAfterSigterm: TimeInterval = 5
let socWarningLogInterval: TimeInterval = 10 * 60
let keepAwakeMinBatteryPercentRange = 5...50
let keepAwakeMinBatteryPercentDefault = 20
let socketLineTerminator: UInt8 = 0x0a
let socketReadBufferBytes = 65536
