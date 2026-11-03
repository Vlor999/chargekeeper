import SwiftUI

/// A settings row the search can find. `label` and `description` are the English source of `tr(...)`: the search
/// matches them in English and French whatever the UI language. `keywords` are extra search words, EN and FR, never shown.
/// To index a new row: add an entry here and tag the row in its pane with `.settingsRow(id)`.
struct SettingsEntry: Identifiable {
    let id: String
    let pane: SettingsPane
    let label: String
    var description: String?
    var keywords = ""

    var haystack: String {
        let texts = [label, description].compactMap { $0 }.flatMap { [$0, french[$0] ?? ""] }
        return fold((texts + [keywords]).joined(separator: " "))
    }
}

/// In display order: pane by pane, rows top to bottom.
let settingsIndex: [SettingsEntry] = [
    SettingsEntry(id: "language", pane: .general, label: "Language", keywords: "english français french anglais"),
    SettingsEntry(id: "openAtLogin", pane: .general, label: "Open at login",
                  keywords: "startup launch boot démarrage lancer ouverture session"),
    SettingsEntry(id: "notifications", pane: .general, label: "Notifications",
                  description: "Shown only while ChargeKeeper is running. Allow ChargeKeeper in System Settings > Notifications.",
                  keywords: "alert banner alerte bannière calibration adapter adaptateur heat chaleur limit limite"),
    SettingsEntry(id: "autoUpdate", pane: .general, label: "Install updates automatically",
                  keywords: "sparkle mise à jour automatique"),
    SettingsEntry(id: "version", pane: .general, label: "Check for Updates…",
                  keywords: "version update mise à jour sparkle"),
    SettingsEntry(id: "about", pane: .general, label: "About",
                  description: "Provided as is, without warranty (MIT License). ChargeKeeper uses undocumented macOS interfaces that may change: use it at your own risk. Independent project, not affiliated with or endorsed by Apple.",
                  keywords: "license licence"),
    SettingsEntry(id: "quit", pane: .general, label: "Quit ChargeKeeper", keywords: "exit close fermer sortir"),

    SettingsEntry(id: "macOSBattery", pane: .charge, label: "macOS battery settings",
                  description: "Turn off Optimized Battery Charging in System Settings > Battery: it can conflict with ChargeKeeper's limit.",
                  keywords: "apple charge limit optimized optimisée recharge"),
    SettingsEntry(id: "autoDischarge", pane: .charge, label: "Automatic discharge",
                  description: "Above the limit, the battery drains down to the limit even when plugged in. Paused during calibration.",
                  keywords: "drain vider"),
    SettingsEntry(id: "idle", pane: .charge, label: "Idle range", description: "Recharge only below the idle range",
                  keywords: "hysteresis hystérésis sailing"),
    SettingsEntry(id: "heat", pane: .charge, label: "Heat protection",
                  description: "Stop charging when the battery is too hot",
                  keywords: "temperature température hot chaud thermal max"),
    SettingsEntry(id: "keepLimit", pane: .charge, label: "Keep the limit when the service stops",
                  description: "The system service applies the limit for every user account. This keeps it active if the service stops.",
                  keywords: "shutdown arrêt daemon"),

    SettingsEntry(id: "sleepFreeze", pane: .sleep, label: "Freeze the charge level during sleep",
                  keywords: "veille sleep"),
    SettingsEntry(id: "sleepPrevent", pane: .sleep, label: "Prevent sleep until the limit is reached",
                  description: "Sleep is also prevented while discharging on the adapter (clamshell mode).",
                  keywords: "veille awake éveillé"),
    SettingsEntry(id: "energyMode", pane: .sleep, label: "macOS energy mode",
                  keywords: "low power mode performance high basse consommation énergie économie"),

    SettingsEntry(id: "led", pane: .led, label: "MagSafe LED",
                  description: "Green: limit reached · Orange: charging or discharging toward the limit.",
                  keywords: "light lumière voyant color couleur off éteinte"),
    SettingsEntry(id: "ledBlink", pane: .led, label: "Blinking orange while discharging", keywords: "blink clignoter"),

    SettingsEntry(id: "tasks", pane: .schedule, label: "Scheduled tasks",
                  keywords: "task tâche calibration calibrate calibrer planning schedule planifier limit limite"),
    SettingsEntry(id: "catchUp", pane: .schedule, label: "Run missed tasks on wake",
                  keywords: "catch up rattraper réveil wake"),
    SettingsEntry(id: "history", pane: .schedule, label: "History", keywords: "log journal events événements"),

    SettingsEntry(id: "health", pane: .battery, label: "Battery health",
                  keywords: "capacity capacité cycle count mAh chart graphique courbe usure wear"),
    SettingsEntry(id: "lastCalibration", pane: .battery, label: "Last calibration",
                  keywords: "calibration calibrer"),
]

/// Lowercased, accents removed: "Réveil" and "reveil" match.
func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

/// Entries containing every word of the query, in index order.
func searchSettings(_ query: String) -> [SettingsEntry] {
    let words = fold(query).split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return [] }
    return settingsIndex.filter { e in let h = e.haystack; return words.allSatisfy { h.contains($0) } }
}

private struct SettingsTargetKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Id of the search result picked in the sidebar.
    var settingsTarget: String? {
        get { self[SettingsTargetKey.self] }
        set { self[SettingsTargetKey.self] = newValue }
    }
}

private struct SettingsRow: ViewModifier {
    let id: String
    @Environment(\.settingsTarget) private var target

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(id == target ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4).inset(by: -4))
    }
}

extension View {
    /// Scroll anchor and highlight of the settings row with this `SettingsEntry` id.
    func settingsRow(_ id: String) -> some View { modifier(SettingsRow(id: id)) }
}
