import Foundation

/// UI language: "system", "en" or "fr", stored in the app's defaults (Settings > General).
let languageKey = "language"

var appLanguage: String {
    let pref = UserDefaults.standard.string(forKey: languageKey) ?? "system"
    if pref != "system" { return pref }
    return Locale.preferredLanguages.first?.hasPrefix("fr") == true ? "fr" : "en"
}

/// English is the source text; French comes from the table below. Placeholders follow String(format:).
func tr(_ en: String, _ args: CVarArg...) -> String { tr(en, args) }

func tr(_ en: String, _ args: [CVarArg]) -> String {
    let s = appLanguage == "fr" ? (french[en] ?? en) : en
    return args.isEmpty ? s : String(format: s, arguments: args)
}

/// Number in the UI language ("82.8" in English, "82,8" in French), without grouping like the mAh values elsewhere.
func number(_ v: Double, decimals: Int = 0) -> String {
    v.formatted(.number.precision(.fractionLength(decimals)).grouping(.never).locale(Locale(identifier: appLanguage)))
}

/// History entry in the UI language. Units stay on the line of their number.
func localizedHistory(_ e: HistoryEntry) -> String {
    historyText(e, { tr($0, $1) }, { number($0, decimals: $1) })
        .replacingOccurrences(of: #" (%|mAh|°C)"#, with: "\u{00A0}$1", options: .regularExpression)
}

private let french: [String: String] = [
    // Menu
    "Dashboard": "Tableau de bord",
    "Settings…": "Réglages…",
    "Check for Updates…": "Rechercher des mises à jour…",
    "ChargeKeeper %@ is ready": "ChargeKeeper %@ est prête",
    "Install and Restart": "Installer et redémarrer",
    "Quit ChargeKeeper": "Quitter ChargeKeeper",
    "Charging service is off": "Service de charge inactif",
    "Allow “ChargeKeeper” in System Settings > General > Login Items > Allow in the Background.":
        "Autorisez « ChargeKeeper » dans Réglages Système > Général > Ouverture > Autoriser en arrière-plan.",
    "Open System Settings": "Ouvrir Réglages Système",
    "Starting the service…": "Démarrage du service…",
    "ChargeKeeper needs a system service to control charging.": "ChargeKeeper a besoin d'un service système pour piloter la charge.",
    "Turn On Service": "Activer le service",
    "Hardware %@ · %@": "Matériel %@ · %@",
    "Hardware %@ · %@ · Limit %d %%": "Matériel %@ · %@ · Limite %d %%",
    "Charge limit": "Limite de recharge",
    "Idle: %d–%d %%": "Repos : %d–%d %%",
    "Discharge": "Décharge",
    "Charge to 100%": "Charger à 100 %",
    "Start Calibration": "Démarrer la calibration",
    "Stop Calibration": "Arrêter la calibration",
    "Pause": "Suspendre",
    "Native limit unavailable: SMC control only": "Limite native indisponible : contrôle SMC uniquement",
    "Connecting…": "Connexion…",
    // States
    "Charging": "En charge",
    "Charging paused": "Charge suspendue",
    "Idle": "Au repos",
    "Discharging": "Décharge",
    "Heat protection": "Protection thermique",
    "Calibration": "Calibration",
    "Stopped": "Arrêté",
    "1/5 Charging to 100%": "1/5 Charge à 100 %",
    "2/5 Discharging to 10%": "2/5 Décharge à 10 %",
    "3/5 Recharging to 100%": "3/5 Recharge à 100 %",
    "4/5 Resting 1 h at 100%": "4/5 Pause 1 h à 100 %",
    "5/5 Back to the limit": "5/5 Retour à la limite",
    // Power flow
    "Power flow": "Flux de puissance",
    "How to read the power flow": "Comment lire le flux de puissance",
    "Left: where the power comes from. The adapter (or a display that charges the Mac), and the battery when it helps.":
        "À gauche : d'où vient la puissance. L'adaptateur (ou un écran qui recharge le Mac), et la batterie quand elle complète.",
    "Right: where it goes. The MacBook itself, the battery when it charges, and devices charging from the Mac's USB-C ports.":
        "À droite : où elle va. Le MacBook lui-même, la batterie quand elle se recharge, et les appareils rechargés par les ports USB-C du Mac.",
    "Example: 78 W come in. 15 W run the Mac, 55 W charge the battery and 8 W charge an iPhone.":
        "Exemple : 78 W arrivent. 15 W font tourner le Mac, 55 W rechargent la batterie et 8 W rechargent un iPhone.",
    "Each band is a share of its side. Each side has its own sensor, so the totals can differ by a few watts.":
        "Chaque bande est une part de son côté. Chaque côté a son propre capteur : les totaux peuvent différer de quelques watts.",
    "13.3 / 15 W: what a device draws, out of the most its port can supply.":
        "13.3 / 15 W : ce que consomme un appareil, sur le maximum que son port peut fournir.",
    "Adapter": "Adaptateur",
    "Battery": "Batterie",
    "Adapter too weak: the battery supplies %@": "Adaptateur trop faible : la batterie complète %@",
    " (adapter %d W)": " (adaptateur %d W)",
    " · charging from the Mac: %@": " · rechargé par le Mac : %@",
    "Show in menu": "Afficher dans le menu",
    // Settings
    "Sleep": "Suspension",
    "Charge": "Charge",
    "MagSafe LED": "LED MagSafe",
    "Schedule": "Planification",
    "General": "Général",
    "Language": "Langue",
    "Updates": "Mises à jour",
    "Install updates automatically": "Installer les mises à jour automatiquement",
    "Version %@": "Version %@",
    "Last check: %@": "Dernière vérification : %@",
    "Never checked": "Jamais vérifié",
    "About": "À propos",
    "Provided as is, without warranty (MIT License). ChargeKeeper uses undocumented macOS interfaces that may change: use it at your own risk. Independent project, not affiliated with or endorsed by Apple.":
        "Fourni tel quel, sans garantie (licence MIT). ChargeKeeper utilise des interfaces de macOS non documentées, susceptibles de changer : utilisation à vos risques. Projet indépendant, ni affilié à Apple ni approuvé par Apple.",
    "System": "Système",
    "Automatic discharge": "Décharge automatique",
    "Above the limit, the battery drains down to the limit even when plugged in. Paused during calibration.":
        "Au-dessus de la limite, la batterie se décharge jusqu'à la limite même branchée. En pause pendant la calibration.",
    "Idle range": "Plage de repos",
    "Recharge only below the idle range": "Ne recharger que sous la plage de repos",
    "Range: %d %%": "Plage : %d %%",
    "Stop charging when the battery is too hot": "Arrêter la charge si la batterie est trop chaude",
    "Max temp: %.0f °C": "Temp. max : %.0f °C",
    "Startup": "Démarrage",
    "Open at login": "Ouvrir à la connexion",
    "Shutdown": "Arrêt",
    "Keep the limit when the service stops": "Garder la limite quand le service s'arrête",
    "The system service applies the limit for every user account. This keeps it active if the service stops.":
        "Le service système applique la limite pour tous les comptes. Cette option la garde active s'il s'arrête.",
    "Freeze the charge level during sleep": "Figer le niveau de charge pendant la veille",
    "Prevent sleep until the limit is reached": "Empêcher la veille tant que la limite n'est pas atteinte",
    "Sleep is also prevented while discharging on the adapter (clamshell mode).":
        "La suspension est aussi désactivée pendant la décharge sur secteur (mode clamshell).",
    "macOS energy mode": "Mode d'énergie macOS",
    "Low Power Mode: on": "Économie d'énergie : activer",
    "Performance mode: on": "Mode Performance : activer",
    "off": "désactiver",
    "System control": "Contrôle système",
    "Color by charge state": "Couleur selon la charge",
    "Always off": "Toujours éteinte",
    "Blinking orange while discharging": "Orange clignotant pendant la décharge",
    "Green: limit reached · Orange: charging or discharging toward the limit.":
        "Vert : limite atteinte · Orange : charge ou décharge vers la limite.",
    // Schedule
    "Set charge limit": "Définir la limite de recharge",
    "Pause charging": "Suspendre la charge",
    "Discharge to": "Décharger jusqu'à",
    "Turn on Low Power Mode": "Activer l'Économie d'énergie",
    "Turn off Low Power Mode": "Désactiver l'Économie d'énergie",
    "Never": "Ne pas répéter",
    "Daily": "Quotidienne",
    "Weekdays": "En semaine",
    "Weekly": "Hebdomadaire",
    "Every 2 weeks": "Toutes les 2 semaines",
    "Monthly": "Mensuelle",
    "Yearly": "Annuelle",
    "+ Task": "+ Tâche",
    "Monthly calibration": "Calibration mensuelle",
    "Calibration every 2 weeks": "Calibration toutes les 2 semaines",
    "Run missed tasks on wake": "Exécuter au réveil les tâches manquées",
    "History": "Historique",
    "Battery health": "Santé de la batterie",
    "Battery data unavailable.": "Données de la batterie indisponibles.",
    "Health": "Santé",
    "Health (nominal)": "Santé (nominale)",
    "Full charge capacity": "Capacité de charge complète",
    "Nominal capacity": "Capacité nominale",
    "Design capacity": "Capacité d'origine",
    "Cycle count": "Nombre de cycles",
    "Last calibration": "Dernière calibration",
    "Date": "Date",
    "Duration": "Durée",
    "Capacity": "Capacité",
    "Temperature": "Température",
    "%d h %02d min": "%d h %02d min",
    "Calibration complete": "Calibration terminée",
    "Finished %@": "Terminée le %@",
    "Action": "Action",
    "Repeat": "Répétition",
    "Value: %d %%": "Valeur : %d %%",
    // History
    "Calibration started": "Calibration démarrée",
    "Calibration stopped": "Calibration arrêtée",
    "Calibration over: back at the limit": "Fin de la calibration : retour à la limite",
    "Calibration: charging to 100 %": "Calibration : charge jusqu'à 100 %",
    "Calibration: discharging to 10 %": "Calibration : décharge jusqu'à 10 %",
    "Calibration: recharging to 100 %": "Calibration : recharge jusqu'à 100 %",
    "Calibration: resting 1 h at 100 %": "Calibration : pause d'1 h à 100 %",
    "Calibration: discharging back to the limit": "Calibration : décharge jusqu'à la limite",
    "Calibration complete: %@": "Calibration terminée : %@",
    "%@ → %@": "%@ → %@",
    "%@ mAh": "%@ mAh",
    "health %@ %%": "santé %@ %%",
    "%@ cycles": "%@ cycles",
    "%@ (%@ %%)": "%@ (%@ %%)",
    "Scheduled task: %@": "Tâche planifiée : %@",
    "Missed task run on wake: %@": "Tâche manquée exécutée au réveil : %@",
    "Missed task skipped: %@": "Tâche manquée ignorée : %@",
    "Charge limit set to %@ %%": "Limite de recharge réglée à %@ %%",
    "Heat protection: charging paused": "Protection thermique : charge suspendue",
    "Heat protection: charging paused at %@ °C": "Protection thermique : charge suspendue à %@ °C",
    // Notifications
    "Notifications": "Notifications",
    "Heat protection paused charging": "Charge suspendue par la protection thermique",
    "Charge limit reached": "Limite de recharge atteinte",
    "Shown only while ChargeKeeper is running. Allow ChargeKeeper in System Settings > Notifications.":
        "Affichées seulement quand ChargeKeeper est ouvert. Autorisez ChargeKeeper dans Réglages Système > Notifications.",
    "Charging paused: battery at %@ °C (max %@ °C).": "Charge suspendue : batterie à %@ °C (max %@ °C).",
    "Battery at %@ %%. Charging paused at the limit.": "Batterie à %@ %%. Charge suspendue à la limite.",
    "Capacity: %@ → %@ mAh": "Capacité : %@ → %@ mAh",
    "Health: %@ → %@ %%": "Santé : %@ → %@ %%",
]
