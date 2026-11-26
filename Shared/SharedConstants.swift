import Foundation

// Internal names (socket, state dir, bundle ids, daemon label) keep the former name Jauge so existing installs keep working.
let socketPath = "/var/run/jauge.sock"
let calibrationDoneNotification = "com.vlor999.jauge.calibrationDone"
let heatProtectNotification = "com.vlor999.jauge.heatProtect"
let calibrationNeedsAdapterNotification = "com.vlor999.jauge.calibrationNeedsAdapter"
let limitReachedNotification = "com.vlor999.jauge.limitReached"
/// Battery health series: one point per day for this many days, one per week before.
let healthDailyDays = 180
/// Battery health series cap: about 7 years at one point per week, ~100 bytes each in state.json (~52 KB).
let healthMaxSamples = 520
/// Diagnostic log: one file per UTC day, written by the service (root, 0644 in a root-owned 0755 folder), read by the app.
let logDir = "/Library/Application Support/Jauge/Logs"
let logFilePrefix = "chargekeeper-"
let logFileExtension = ".log"
/// Days kept, counted in whole UTC days; the user picks within this range.
let logDaysRange = 1...90
let logDaysDefault = 7
/// One day's file stops growing at this size: later entries of that day are dropped after one notice line.
let logMaxFileBytes = 5 * 1024 * 1024
/// Room left above the cap for the notice line.
let logFullReserveBytes = 1024
/// CPU, GPU and Neural Engine power: powermetrics runs as long as the service, at the interval set in Settings (5 s by
/// default, or off), even with no window open (deliberate exception: the CPU and Neural Engine energy counters only move
/// while powermetrics samples them). Its arguments come from `powermetricsArguments(_:)`, fixed per `PowerInterval`.
let powermetricsPath = "/usr/bin/powermetrics"
/// Sampling period of a point from a service older than `SoCPowerPoint.interval`, and of a sample lacking its own elapsed time.
let powermetricsInterval: TimeInterval = 5
/// The app's status refresh while a window is open, at most this long apart; shorter when the power interval is.
let appPollInterval: TimeInterval = 2
/// Power history kept by the service in memory, whatever the interval: 300 points at 1 s, 10 at 30 s.
let socHistoryWindow: TimeInterval = 5 * 60
/// Samples missed, as a multiple of the sampling interval: a newest point older than this is no longer the current
/// value, and a longer gap between two points (sleep, powermetrics restart) splits the curve (`powerMaxGap`).
let socMaxGapIntervals: TimeInterval = 2
/// Across an interval change, powermetrics restarts: its first sample came 11.5 s after the last 1 s point when switching
/// to 5 s (M4 Pro), about two new intervals. The gap there may reach the old interval, two new ones and this slack.
let socRestartSlack: TimeInterval = 5
/// After powermetrics fails or exits on its own, the service waits this long before starting it again.
let socRetryDelay: TimeInterval = 60
/// One sample is a few KB: a partial sample past this size is dropped.
let socMaxSampleBytes = 256 * 1024
/// powermetrics still running this long after SIGTERM gets SIGKILL.
let socKillGrace: TimeInterval = 5
/// Unreadable samples are logged at most once per this period.
let socWarnInterval: TimeInterval = 10 * 60
/// Keep awake turns itself off on battery below this level, in %: the user picks within this range.
let keepAwakeMinBatteryRange = 5...50
let keepAwakeMinBatteryDefault = 20
let socketLineTerminator: UInt8 = 0x0a
let socketReadBufferBytes = 65536
