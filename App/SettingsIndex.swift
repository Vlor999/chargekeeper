import Foundation

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, charge, sleep, led, schedule, battery, diagnostic

    var id: Self { self }
}

enum SettingsRowID {
    case language, openAtLogin, notifications, autoUpdate, version, support,
         feedback, links, about, quit, macOSBattery, autoDischarge,
         idle, heat, keepLimit, sleepFreeze, sleepPrevent, keepAwakeLid,
         keepAwakeBattery, energyMode, led, ledBlink, tasks, catchUp,
         history, health, lastCalibration, powerInterval, logEnabled, logDays,
         logFolder, logViewer
}

struct SettingsEntry: Identifiable {
    let id: SettingsRowID
    let pane: SettingsPane
    let label: String
    var description: String?
    var hiddenKeywords = ""

    var haystack: String {
        let texts = [label, description].compactMap { $0 }.flatMap { [$0, french[$0] ?? ""] }
        return foldCaseAndAccents((texts + [hiddenKeywords]).joined(separator: " "))
    }
}

let settingsIndex: [SettingsEntry] = [
    SettingsEntry(id: .language, pane: .general, label: "Language", hiddenKeywords: "english français french anglais"),
    SettingsEntry(id: .openAtLogin, pane: .general, label: "Open at login",
                  hiddenKeywords: "startup launch boot démarrage lancer ouverture session"),
    SettingsEntry(id: .notifications, pane: .general, label: "Notifications",
                  description: "Shown only while ChargeKeeper is running. Allow ChargeKeeper in System Settings > Notifications.",
                  hiddenKeywords: "alert banner alerte bannière calibration adapter adaptateur heat chaleur limit limite"),
    SettingsEntry(id: .autoUpdate, pane: .general, label: "Install updates automatically",
                  hiddenKeywords: "sparkle mise à jour automatique"),
    SettingsEntry(id: .version, pane: .general, label: "Check for Updates…",
                  hiddenKeywords: "version update mise à jour sparkle"),
    SettingsEntry(id: .support, pane: .general, label: "Support ChargeKeeper",
                  description: "Free and ad-free. A coffee helps keep it going.",
                  hiddenKeywords: "buy me a coffee café don donate sponsor soutien"),
    SettingsEntry(id: .feedback, pane: .general, label: "Send feedback",
                  description: "An idea, a question, a bug? Opens a prefilled GitHub discussion, to write and post in your browser.",
                  hiddenKeywords: "avis idea idée discussion github"),
    SettingsEntry(id: .links, pane: .general, label: "Links",
                  hiddenKeywords: "liens source code download téléchargement report issue signaler problème bug privacy confidentialité licenses licences"),
    SettingsEntry(id: .about, pane: .general, label: "About",
                  description: "Provided as is, without warranty (MIT License). ChargeKeeper uses undocumented macOS interfaces that may change: use it at your own risk. Independent project, not affiliated with or endorsed by Apple.",
                  hiddenKeywords: "license licence"),
    SettingsEntry(id: .quit, pane: .general, label: "Quit ChargeKeeper", hiddenKeywords: "exit close fermer sortir"),

    SettingsEntry(id: .macOSBattery, pane: .charge, label: "macOS battery settings",
                  description: "Turn off Optimized Battery Charging in System Settings > Battery: it can conflict with ChargeKeeper's limit.",
                  hiddenKeywords: "apple charge limit optimized optimisée recharge"),
    SettingsEntry(id: .autoDischarge, pane: .charge, label: "Automatic discharge",
                  description: "Above the limit, the battery drains down to the limit even when plugged in. Paused during calibration.",
                  hiddenKeywords: "drain vider"),
    SettingsEntry(id: .idle, pane: .charge, label: "Idle range", description: "Recharge only below the idle range",
                  hiddenKeywords: "hysteresis hystérésis sailing"),
    SettingsEntry(id: .heat, pane: .charge, label: "Heat protection",
                  description: "Stop charging when the battery is too hot",
                  hiddenKeywords: "temperature température hot chaud thermal max"),
    SettingsEntry(id: .keepLimit, pane: .charge, label: "Keep the limit when the service stops",
                  description: "The system service applies the limit for every user account. This keeps it active if the service stops.",
                  hiddenKeywords: "shutdown arrêt daemon"),

    SettingsEntry(id: .sleepFreeze, pane: .sleep, label: "Freeze the charge level during sleep",
                  hiddenKeywords: "veille sleep"),
    SettingsEntry(id: .sleepPrevent, pane: .sleep, label: "Prevent sleep until the limit is reached",
                  description: "Sleep is also prevented while discharging on the adapter (clamshell mode).",
                  hiddenKeywords: "veille awake éveillé"),
    SettingsEntry(id: .keepAwakeLid, pane: .sleep, label: "Even with the lid closed",
                  description: "Keep awake is turned on from the menu. It prevents idle sleep; the display can still turn off.",
                  hiddenKeywords: "keep awake caffeinate clamshell lid capot fermé éveillé veille"),
    SettingsEntry(id: .keepAwakeBattery, pane: .sleep, label: "Turn off on battery below",
                  hiddenKeywords: "keep awake caffeinate battery batterie threshold seuil éveillé"),
    SettingsEntry(id: .energyMode, pane: .sleep, label: "macOS energy mode",
                  hiddenKeywords: "low power mode performance high basse consommation énergie économie"),

    SettingsEntry(id: .led, pane: .led, label: "MagSafe LED",
                  description: "Green: limit reached · Orange: charging or discharging toward the limit.",
                  hiddenKeywords: "light lumière voyant color couleur off éteinte"),
    SettingsEntry(id: .ledBlink, pane: .led, label: "Blinking orange while discharging", hiddenKeywords: "blink clignoter"),

    SettingsEntry(id: .tasks, pane: .schedule, label: "Scheduled tasks",
                  hiddenKeywords: "task tâche calibration calibrate calibrer planning schedule planifier limit limite"),
    SettingsEntry(id: .catchUp, pane: .schedule, label: "Run missed tasks on wake",
                  hiddenKeywords: "catch up rattraper réveil wake"),
    SettingsEntry(id: .history, pane: .schedule, label: "History", hiddenKeywords: "log journal events événements"),

    SettingsEntry(id: .health, pane: .battery, label: "Battery health",
                  hiddenKeywords: "capacity capacité cycle count mAh chart graphique courbe usure wear"),
    SettingsEntry(id: .lastCalibration, pane: .battery, label: "Last calibration",
                  hiddenKeywords: "calibration calibrer"),
    SettingsEntry(id: .powerInterval, pane: .diagnostic, label: "Sampling interval",
                  description: "CPU, GPU and Neural Engine power, measured by the service with powermetrics even when no window is open. Shorter is finer but costs more: about 3 % CPU at 1 s, 0.7 % at 5 s. Off hides the graphs.",
                  hiddenKeywords: "power consommation puissance graph graphique cpu gpu ane powermetrics intervalle échantillonnage off désactiver"),
    SettingsEntry(id: .logEnabled, pane: .diagnostic, label: "Keep a diagnostic log",
                  description: "Written by the ChargeKeeper service on this Mac only: service start and stop, charge decisions, errors. Nothing is sent. Whole days older than the retention are deleted.",
                  hiddenKeywords: "log logs journal diagnostic"),
    SettingsEntry(id: .logDays, pane: .diagnostic, label: "Retention",
                  hiddenKeywords: "keep days conserver jours log journal"),
    SettingsEntry(id: .logFolder, pane: .diagnostic, label: "Folder",
                  hiddenKeywords: "open folder ouvrir dossier finder log journal"),
    SettingsEntry(id: .logViewer, pane: .diagnostic, label: "Level",
                  hiddenKeywords: "viewer visionneuse entries entrées warnings avertissements errors erreurs reload recharger copy copier log journal"),
]

func foldCaseAndAccents(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

func searchSettings(_ query: String) -> [SettingsEntry] {
    let words = foldCaseAndAccents(query).split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return [] }
    return settingsIndex.filter { e in let h = e.haystack; return words.allSatisfy { h.contains($0) } }
}
