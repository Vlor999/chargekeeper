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
let groupOrOtherWriteBits: mode_t = 0o022
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
let heatProtectHysteresis: TimeInterval = 5 * 60
let calibrationRestDuration: TimeInterval = 60 * 60
let adapterNoticeGap: TimeInterval = 10 * 60
let adapterReminderAfter: TimeInterval = 60 * 60
let nominalThreeCellPackVolts = 11.4
let minEstimableCurrentMilliamps = 50.0
let minTimeEstimate: TimeInterval = 60
let maxTimeEstimate: TimeInterval = 24 * 60 * 60
let nativeChargeLimitStepPercent = 5
let systemSettingsChargeLimitPercentRange = 50...99
let healthMaxClockAhead: TimeInterval = secondsPerDay
let healthSpanDaysBeforeMonths = 60
let healthSpanDaysBeforeYears = 730
let averageDaysPerMonth = 30.44
let averageDaysPerYear = 365.25
let legacyCalibrationPhasePrefix = "calibration: "
let powermetricsSamplers = "cpu_power,gpu_power"
let plistSampleTerminator: UInt8 = 0
let maxPlausibleSoCWatts = 1000.0
let usbDeviceSymbolsByNameFragment = [(fragment: "iphone", symbol: "iphone"), (fragment: "ipad", symbol: "ipad"), (fragment: "airpods", symbol: "airpods")]
let genericUSBDeviceSymbol = "cable.connector"
let secondsPerHour: TimeInterval = 3600
