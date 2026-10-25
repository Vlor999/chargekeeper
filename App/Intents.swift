import AppIntents

// Shortcuts actions. All go through the daemon socket.

struct GetBatteryPercentage: AppIntent {
    static var title: LocalizedStringResource = "Get Battery Percentage"
    func perform() async throws -> some IntentResult & ReturnsValue<Int> { .result(value: try send(.status).percent) }
}

struct GetChargeLimit: AppIntent {
    static var title: LocalizedStringResource = "Get Charge Limit"
    func perform() async throws -> some IntentResult & ReturnsValue<Int> { .result(value: try send(.status).config.limit) }
}

struct GetState: AppIntent {
    static var title: LocalizedStringResource = "Get State"
    func perform() async throws -> some IntentResult & ReturnsValue<String> { .result(value: try send(.status).runtime.state.rawValue) }
}

struct GetTemperature: AppIntent {
    static var title: LocalizedStringResource = "Get Temperature"
    func perform() async throws -> some IntentResult & ReturnsValue<Double> { .result(value: try send(.status).temperature ?? 0) }
}

struct SetChargeLimit: AppIntent {
    static var title: LocalizedStringResource = "Set Charge Limit"
    @Parameter(title: "Limit", inclusiveRange: (20, 100)) var limit: Int
    func perform() async throws -> some IntentResult { _ = try send(.setLimit(limit)); return .result() }
}

struct PauseCharging: AppIntent {
    static var title: LocalizedStringResource = "Pause Charging"
    func perform() async throws -> some IntentResult { _ = try send(.pause); return .result() }
}

struct StartDischarge: AppIntent {
    static var title: LocalizedStringResource = "Start Discharge"
    func perform() async throws -> some IntentResult { _ = try send(.discharge(true)); return .result() }
}

struct StartCalibration: AppIntent {
    static var title: LocalizedStringResource = "Start Calibration"
    func perform() async throws -> some IntentResult { _ = try send(.calibrate(true)); return .result() }
}

struct TopUp: AppIntent {
    static var title: LocalizedStringResource = "Charge to 100%"
    func perform() async throws -> some IntentResult { _ = try send(.topUp(true)); return .result() }
}

enum LEDOption: String, AppEnum {
    case green, orange, orangeBlink, off, auto
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "LED MagSafe"
    static var caseDisplayRepresentations: [LEDOption: DisplayRepresentation] = [
        .green: "Green", .orange: "Orange", .orangeBlink: "Orange (blinking)", .off: "Off", .auto: "Automatic",
    ]
}

struct SetMagSafeLED: AppIntent {
    static var title: LocalizedStringResource = "Set MagSafe LED"
    @Parameter(title: "Color") var color: LEDOption
    func perform() async throws -> some IntentResult {
        _ = try send(.led(color == .auto ? nil : LEDColor(rawValue: color.rawValue)))
        return .result()
    }
}

struct SetLowPowerMode: AppIntent {
    static var title: LocalizedStringResource = "Low Power Mode"
    @Parameter(title: "Enabled") var enabled: Bool
    func perform() async throws -> some IntentResult { _ = try send(.lowPower(enabled)); return .result() }
}

struct SetHighPowerMode: AppIntent {
    static var title: LocalizedStringResource = "Performance Mode"
    @Parameter(title: "Enabled") var enabled: Bool
    func perform() async throws -> some IntentResult { _ = try send(.highPower(enabled)); return .result() }
}
