import AppIntents

// Shortcuts actions. All go through the daemon socket.

struct GetBatteryPercentage: AppIntent {
    static var title: LocalizedStringResource = "Obtenir le pourcentage de la batterie"
    func perform() async throws -> some IntentResult & ReturnsValue<Int> { .result(value: try send(.status).percent) }
}

struct GetChargeLimit: AppIntent {
    static var title: LocalizedStringResource = "Obtenir la limite de recharge"
    func perform() async throws -> some IntentResult & ReturnsValue<Int> { .result(value: try send(.status).config.limit) }
}

struct GetState: AppIntent {
    static var title: LocalizedStringResource = "Obtenir l'état"
    func perform() async throws -> some IntentResult & ReturnsValue<String> { .result(value: try send(.status).runtime.state.rawValue) }
}

struct GetTemperature: AppIntent {
    static var title: LocalizedStringResource = "Obtenir la température"
    func perform() async throws -> some IntentResult & ReturnsValue<Double> { .result(value: try send(.status).temperature ?? 0) }
}

struct SetChargeLimit: AppIntent {
    static var title: LocalizedStringResource = "Définir la limite de recharge"
    @Parameter(title: "Limite", inclusiveRange: (20, 100)) var limit: Int
    func perform() async throws -> some IntentResult { _ = try send(.setLimit(limit)); return .result() }
}

struct PauseCharging: AppIntent {
    static var title: LocalizedStringResource = "Suspendre la charge"
    func perform() async throws -> some IntentResult { _ = try send(.pause); return .result() }
}

struct StartDischarge: AppIntent {
    static var title: LocalizedStringResource = "Démarrer la décharge"
    func perform() async throws -> some IntentResult { _ = try send(.discharge(true)); return .result() }
}

struct StartCalibration: AppIntent {
    static var title: LocalizedStringResource = "Démarrer la calibration"
    func perform() async throws -> some IntentResult { _ = try send(.calibrate(true)); return .result() }
}

struct TopUp: AppIntent {
    static var title: LocalizedStringResource = "Charger à 100 %"
    func perform() async throws -> some IntentResult { _ = try send(.topUp(true)); return .result() }
}

enum LEDOption: String, AppEnum {
    case green, orange, orangeBlink, off, auto
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "LED MagSafe"
    static var caseDisplayRepresentations: [LEDOption: DisplayRepresentation] = [
        .green: "Vert", .orange: "Orange", .orangeBlink: "Orange (clignotant)", .off: "Désactivé", .auto: "Automatique",
    ]
}

struct SetMagSafeLED: AppIntent {
    static var title: LocalizedStringResource = "Régler la LED MagSafe"
    @Parameter(title: "Couleur") var color: LEDOption
    func perform() async throws -> some IntentResult {
        _ = try send(.led(color == .auto ? nil : LEDColor(rawValue: color.rawValue)))
        return .result()
    }
}

struct SetLowPowerMode: AppIntent {
    static var title: LocalizedStringResource = "Mode économie d'énergie"
    @Parameter(title: "Activer") var enabled: Bool
    func perform() async throws -> some IntentResult { _ = try send(.lowPower(enabled)); return .result() }
}

struct SetHighPowerMode: AppIntent {
    static var title: LocalizedStringResource = "Mode Performance"
    @Parameter(title: "Activer") var enabled: Bool
    func perform() async throws -> some IntentResult { _ = try send(.highPower(enabled)); return .result() }
}
