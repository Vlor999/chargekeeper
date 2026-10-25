import Foundation

/// UI language: "system", "en" or "fr", stored in the app's defaults (Settings > General).
let languageKey = "language"

var appLanguage: String {
    let pref = UserDefaults.standard.string(forKey: languageKey) ?? "system"
    if pref != "system" { return pref }
    return Locale.preferredLanguages.first?.hasPrefix("fr") == true ? "fr" : "en"
}

/// English is the source text; French comes from the table below. Placeholders follow String(format:).
func tr(_ en: String, _ args: CVarArg...) -> String {
    let s = appLanguage == "fr" ? (french[en] ?? en) : en
    return args.isEmpty ? s : String(format: s, arguments: args)
}

private let french: [String: String] = [
    // Menu
    "Dashboard": "Tableau de bord",
    "Settings…": "Réglages…",
    "Check for Updates…": "Rechercher des mises à jour…",
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
    "Adapter too weak: the battery supplies %@": "Adaptateur trop faible : la batterie complète %@",
    " (adapter %d W)": " (adaptateur %d W)",
    "Show in menu": "Afficher dans le menu",
    // Settings
    "Charge control": "Contrôle de la charge",
    "Sleep": "Suspension",
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
    "Action": "Action",
    "Repeat": "Répétition",
    "Value: %d %%": "Valeur : %d %%",
]
