import Foundation

enum ChargeState: String, Codable {
    case charging = "Charging", pause = "Pause", idle = "Idle", discharging = "Discharging"
    case topup = "FullCharge", heatProtect = "HeatProtect", calibration = "Calibration", exit = "Exit"
}

enum CalibrationPhase: String, Codable, CaseIterable {
    case chargeFull, dischargeTo10, rechargeFull, hold, returnToLimit
}

enum LogLevel: String, CaseIterable, Comparable {
    case info, warn, error

    var severity: Int {
        switch self {
        case .info: return 0
        case .warn: return 1
        case .error: return 2
        }
    }

    static func < (a: LogLevel, b: LogLevel) -> Bool { a.severity < b.severity }
}

/// powermetrics sampling interval chosen in Settings, in seconds; `off` stops powermetrics. A closed list: a socket
/// request with any other value fails to decode, so no free number reaches powermetrics' arguments.
enum PowerInterval: Int, Codable, CaseIterable { case off = 0, s1 = 1, s2 = 2, s5 = 5, s10 = 10, s30 = 30 }

/// Keep awake duration picked in the menu, in minutes; `untilOff` lasts until turned off. A closed list: a socket
/// request with any other value fails to decode.
enum KeepAwakeDuration: Int, Codable, CaseIterable { case m30 = 30, h1 = 60, h2 = 120, h4 = 240, untilOff = 0 }

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

enum HistoryEvent: String, Codable {
    case calibrationStarted, calibrationStopped, calibrationPhase, calibrationDone, calibrationEnded
    case taskRun, taskSkipped, limitChanged, heatProtect, calibrationNeedsAdapter, chargedPastLimit
    case keepAwakeEnded  // turned itself off: time up, or `value` = battery level under the threshold
    case keepAwakeFailed
}

/// One history line. The app renders `event` and its parameters in the UI language; `text` is the English
/// rendering, kept for older apps and for entries written by an older service (free text only).
struct HistoryEntry: Codable, Hashable {
    var date: Date
    var text: String
    var event: HistoryEvent?
    var phase: CalibrationPhase?
    var action: TaskAction?
    var late: Bool?  // task run after its time (caught up on wake)
    var value: Int?  // task value or new charge limit, in %
    var temperature: Double?
    var capacityBefore: Int?, capacityAfter: Int?  // mAh
    var healthBefore: Double?, healthAfter: Double?  // %
    var cycles: Int?

    init(date: Date = Date(), text: String = "", event: HistoryEvent? = nil, phase: CalibrationPhase? = nil, action: TaskAction? = nil,
         late: Bool? = nil, value: Int? = nil, temperature: Double? = nil, capacityBefore: Int? = nil, capacityAfter: Int? = nil,
         healthBefore: Double? = nil, healthAfter: Double? = nil, cycles: Int? = nil) {
        (self.date, self.text, self.event, self.phase, self.action, self.late, self.value, self.temperature) =
            (date, text, event, phase, action, late, value, temperature)
        (self.capacityBefore, self.capacityAfter, self.healthBefore, self.healthAfter, self.cycles) =
            (capacityBefore, capacityAfter, healthBefore, healthAfter, cycles)
    }

    private enum CodingKeys: String, CodingKey {
        case date, text, event, phase, action, late, value, temperature, capacityBefore, capacityAfter, healthBefore, healthAfter, cycles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        text = try c.decode(String.self, forKey: .text)
        event = c.decodeIfKnownToThisBuild(HistoryEvent.self, forKey: .event)
        phase = c.decodeIfKnownToThisBuild(CalibrationPhase.self, forKey: .phase)
        action = c.decodeIfKnownToThisBuild(TaskAction.self, forKey: .action)
        late = c.decodeIfKnownToThisBuild(Bool.self, forKey: .late)
        value = c.decodeIfKnownToThisBuild(Int.self, forKey: .value)
        temperature = c.decodeIfKnownToThisBuild(Double.self, forKey: .temperature)
        capacityBefore = c.decodeIfKnownToThisBuild(Int.self, forKey: .capacityBefore)
        capacityAfter = c.decodeIfKnownToThisBuild(Int.self, forKey: .capacityAfter)
        healthBefore = c.decodeIfKnownToThisBuild(Double.self, forKey: .healthBefore)
        healthAfter = c.decodeIfKnownToThisBuild(Double.self, forKey: .healthAfter)
        cycles = c.decodeIfKnownToThisBuild(Int.self, forKey: .cycles)
    }
}

private extension KeyedDecodingContainer {
    func decodeIfKnownToThisBuild<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
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
    var logEnabled = true
    var logDays = logRetentionDaysDefault
    var powerInterval = PowerInterval.s5
    var keepAwakeLidClosed = false  // keep awake also disables sleep, so a closed lid does not sleep
    var keepAwakeMinBattery = keepAwakeMinBatteryPercentDefault
}

extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallbackForOlderService = Config()
        limit = try c.decode(Int.self, forKey: .limit)
        autoDischarge = try c.decode(Bool.self, forKey: .autoDischarge)
        idle = try c.decode(Bool.self, forKey: .idle)
        idleRange = try c.decode(Int.self, forKey: .idleRange)
        heatProtect = try c.decode(Bool.self, forKey: .heatProtect)
        maxTemp = try c.decode(Double.self, forKey: .maxTemp)
        led = try c.decode(LEDSetting.self, forKey: .led)
        ledBlinkDischarge = try c.decode(Bool.self, forKey: .ledBlinkDischarge)
        stopChargingDuringSleep = try c.decode(Bool.self, forKey: .stopChargingDuringSleep)
        disableSleepUntilLimit = try c.decode(Bool.self, forKey: .disableSleepUntilLimit)
        keepLimitWhenStopped = try c.decode(Bool.self, forKey: .keepLimitWhenStopped)
        catchUpMissedTasks = try c.decode(Bool.self, forKey: .catchUpMissedTasks)
        tasks = try c.decode([ScheduledTask].self, forKey: .tasks)
        logEnabled = try c.decodeIfPresent(Bool.self, forKey: .logEnabled) ?? fallbackForOlderService.logEnabled
        logDays = try c.decodeIfPresent(Int.self, forKey: .logDays) ?? fallbackForOlderService.logDays
        powerInterval = try c.decodeIfPresent(PowerInterval.self, forKey: .powerInterval) ?? fallbackForOlderService.powerInterval
        keepAwakeLidClosed = try c.decodeIfPresent(Bool.self, forKey: .keepAwakeLidClosed) ?? fallbackForOlderService.keepAwakeLidClosed
        keepAwakeMinBattery = try c.decodeIfPresent(Int.self, forKey: .keepAwakeMinBattery) ?? fallbackForOlderService.keepAwakeMinBattery
    }
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
    var pastLimitSince: Date?  // macOS charging past the limit against the service (gauge recalibration or other override)
    var keepAwakeUntil: Date?  // keep awake on until this date; `.distantFuture` until turned off, nil when off
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

    var health: Double? { ratio(maxCapacity) }
    /// Nominal capacity over design capacity, in %: close to the macOS "Maximum Capacity".
    var nominalHealth: Double? { ratio(nominalCapacity) }

    private func ratio(_ v: Int?) -> Double? {
        guard let v, let d = designCapacity, d > 0 else { return nil }
        return percentOfDesignCapacity(v, designCapacity: d)
    }
}

/// One point of the battery health series: one per day, plus one per calibration result. Capacities in mAh.
struct HealthSample: Codable, Equatable {
    var date: Date
    var maxCapacity: Int
    var nominalCapacity: Int?
    var designCapacity: Int
    var cycleCount: Int?
    var calibration: Bool?  // taken when a calibration finished

    var health: Double { percentOfDesignCapacity(maxCapacity, designCapacity: max(designCapacity, 1)) }
    var nominalHealth: Double? { nominalCapacity.map { percentOfDesignCapacity($0, designCapacity: max(designCapacity, 1)) } }
}

private func percentOfDesignCapacity(_ capacity: Int, designCapacity: Int) -> Double {
    Double(capacity) * 100 / Double(designCapacity)
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

struct SoCPower: Codable, Equatable {
    var cpuWatts: Double
    var gpuWatts: Double
    var aneWatts: Double
}

/// One point of the component power history: the average power since the previous point.
struct SoCPowerPoint: Codable, Equatable {
    var date: Date
    var power: SoCPower
    var interval: TimeInterval?  // sampling interval in effect, in s; nil from an older service (5 s)
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
    var batteryAmperage: Int?  // mA, >0 charging; nil from an older service
    var ports: [PortPower]?  // USB-C power out, included in systemWatts; nil from an older service
    var nativeLimit: Bool
    var sleepDisabled: Bool
    var history: [HistoryEntry]
    var battery: BatterySnapshot?  // nil from an older service
    var lastCalibration: CalibrationResult?
    var appleChargeLimit: Int?  // Charge Limit set in System Settings below 100 %, on Macs where the service never sets it
    var healthHistory: [HealthSample]?  // only in the reply to .healthHistory, to keep the periodic status small
    var socHistory: [SoCPowerPoint]?  // only in the reply to .status(soc: true); nil from an older service
}

enum Command: Codable {
    /// `soc`: include the component power history (a chart is on screen). Encoded inside the case's object, which an
    /// older service ignores; a request from an older app decodes as nil.
    case status(soc: Bool? = nil)
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
    case healthHistory  // a service older than this command closes the connection without a reply
    case keepAwake(KeepAwakeDuration?)  // nil turns it off
    case resetSleep  // re-enable system sleep unless the service itself needs it disabled
}
