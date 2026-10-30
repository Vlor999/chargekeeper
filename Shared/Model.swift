import Foundation

// Internal names (socket, state dir, bundle ids, daemon label) keep the former name Jauge so existing installs keep working.
let socketPath = "/var/run/jauge.sock"
/// Darwin notification posted by the service when a calibration finishes.
let calibrationDoneNotification = "com.vlor999.jauge.calibrationDone"

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
    var calibrationBefore: BatterySnapshot?  // taken when the running calibration started
}

/// Battery wear at one point in time. Capacities in mAh.
struct BatterySnapshot: Codable, Equatable {
    var date: Date
    var maxCapacity: Int?  // full charge capacity learned by the gauge (AppleRawMaxCapacity)
    var nominalCapacity: Int?
    var designCapacity: Int?
    var cycleCount: Int?
    var temperature: Double?
    var percent: Int

    /// Full charge capacity over design capacity, in %.
    var health: Double? { ratio(maxCapacity) }
    /// Nominal capacity over design capacity, in %: close to the macOS "Maximum Capacity".
    var nominalHealth: Double? { ratio(nominalCapacity) }

    private func ratio(_ v: Int?) -> Double? {
        guard let v, let d = designCapacity, d > 0 else { return nil }
        return Double(v) * 100 / Double(d)
    }
}

struct CalibrationResult: Codable, Equatable {
    var start: Date
    var end: Date
    var before: BatterySnapshot
    var after: BatterySnapshot
}

struct PortPower: Codable {
    var name: String?  // USB device plugged straight into the port
    var watts: Double
    var maxWatts: Double?  // what the port agreed to supply (USB-PD contract, or 5 V current limit)
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
    var ports: [PortPower]?  // USB-C power out, included in systemWatts; nil from an older service
    var nativeLimit: Bool
    var sleepDisabled: Bool
    var history: [HistoryEntry]
    var battery: BatterySnapshot?  // nil from an older service
    var lastCalibration: CalibrationResult?
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
