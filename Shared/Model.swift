import Foundation

let socketPath = "/var/run/jauge.sock"

enum ChargeState: String, Codable {
    case charging = "Charging", pause = "Pause", idle = "Idle", discharging = "Discharging"
    case topup = "FullCharge", heatProtect = "HeatProtect", calibration = "Calibration", exit = "Exit"
}

enum CalibrationPhase: String, Codable {
    case chargeFull, dischargeTo10, rechargeFull, hold, returnToLimit
}

enum LEDColor: String, Codable, CaseIterable { case system, off, green, orange, orangeBlink }

enum LEDSetting: String, Codable, CaseIterable { case system, indicate, alwaysOff }

enum TaskAction: String, Codable, CaseIterable {
    case setLimit, calibrate, topUp, pause, dischargeTo, lowPowerOn, lowPowerOff
}

enum Repeat: String, Codable, CaseIterable { case never, daily, weekdays, weekly, biweekly, monthly, yearly }

struct ScheduledTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var enabled = true
    var action: TaskAction = .calibrate
    var value = 80
    var repeatRule: Repeat = .monthly
    var start = Date()
    var created = Date()
    var lastRun: Date?
}

struct HistoryEntry: Codable, Hashable {
    var date: Date
    var text: String
}

struct Config: Codable, Equatable {
    var limit = 80
    var autoDischarge = false  // drain to limit whenever above it, even plugged in
    var idle = false
    var idleRange = 5
    var heatProtect = false
    var maxTemp = 35.0
    var led: LEDSetting = .system
    var ledBlinkDischarge = false
    var stopChargingDuringSleep = false
    var disableSleepUntilLimit = false
    var keepLimitWhenStopped = true
    var catchUpMissedTasks = false
    var tasks: [ScheduledTask] = []
}

/// Daemon-owned state that survives restarts (calibration in progress, one-shot modes).
struct Runtime: Codable, Equatable {
    var discharge = false
    var topUp = false
    var calibration: CalibrationPhase?
    var phaseStart: Date?
    var ledOverride: LEDColor?
    var holdLevel: Int?
    var heatBlocked = false
    var idleRecharge = false  // dropped below idle range: charge back up to limit
    var heatSince: Date?
    var state: ChargeState = .charging
}

struct Status: Codable {
    var config: Config
    var runtime: Runtime
    var percent: Int
    var hardwarePercent: Int?
    var adapter: Bool
    var temperature: Double?
    var adapterWatts: Double
    var adapterRatedWatts: Int?
    var systemWatts: Double
    var batteryWatts: Double  // >0 charging, <0 discharging
    var nativeLimit: Bool
    var sleepDisabled: Bool
    var history: [HistoryEntry]
}

enum Command: Codable {
    case status
    case setConfig(Config)
    case setLimit(Int)
    case discharge(Bool)
    case dischargeTo(Int)
    case topUp(Bool)
    case calibrate(Bool)
    case pause
    case led(LEDColor?)
    case lowPower(Bool)
    case highPower(Bool)
}
