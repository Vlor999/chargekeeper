import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        TabView {
            charge.tabItem { Label("Contrôle de la charge", systemImage: "bolt") }
            sleep.tabItem { Label("Suspension", systemImage: "moon") }
            led.tabItem { Label("LED MagSafe", systemImage: "lightbulb") }
            ScheduleView().tabItem { Label("Planification", systemImage: "calendar") }
        }
        .frame(width: 560, height: 440)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    var charge: some View {
        Form {
            Section("Décharge") {
                Toggle("Décharge automatique", isOn: m.config(\.autoDischarge))
                Text("Au-dessus de la limite, la batterie se décharge jusqu'à la limite même branchée. En pause pendant la calibration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Plage de repos") {
                Toggle("Ne recharger que sous la plage de repos", isOn: m.config(\.idle))
                Stepper("Plage : \(m.config(\.idleRange).wrappedValue) %", value: m.config(\.idleRange), in: 1...30)
            }
            Section("Protection thermique") {
                Toggle("Arrêter la charge si la batterie est trop chaude", isOn: m.config(\.heatProtect))
                Stepper(String(format: "Temp. max : %.0f °C", m.config(\.maxTemp).wrappedValue), value: m.config(\.maxTemp), in: 25...50, step: 1)
            }
            Section("Démarrage") {
                Toggle("Ouvrir à la connexion", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
            }
            Section("Arrêt") {
                Toggle("Garder la limite quand le service s'arrête", isOn: m.config(\.keepLimitWhenStopped))
                Text("Le service système applique la limite pour tous les comptes. Cette option la garde active s'il s'arrête.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    var sleep: some View {
        Form {
            Toggle("Figer le niveau de charge pendant la veille", isOn: m.config(\.stopChargingDuringSleep))
            Toggle("Empêcher la veille tant que la limite n'est pas atteinte", isOn: m.config(\.disableSleepUntilLimit))
            Text("La suspension est aussi désactivée pendant la Décharge sur secteur (mode clamshell).")
                .font(.caption).foregroundStyle(.secondary)
            Section("Mode d'énergie macOS") {
                HStack {
                    Button("Économie d'énergie : activer") { m.run(.lowPower(true)) }
                    Button("désactiver") { m.run(.lowPower(false)) }
                }
                HStack {
                    Button("Mode Performance : activer") { m.run(.highPower(true)) }
                    Button("désactiver") { m.run(.highPower(false)) }
                }
            }
        }
        .formStyle(.grouped)
    }

    var led: some View {
        Form {
            Picker("LED MagSafe", selection: m.config(\.led)) {
                Text("Contrôle système").tag(LEDSetting.system)
                Text("Couleur selon la charge").tag(LEDSetting.indicate)
                Text("Toujours éteinte").tag(LEDSetting.alwaysOff)
            }
            Toggle("Orange clignotant pendant la décharge", isOn: m.config(\.ledBlinkDischarge))
            Text("Vert : limite atteinte · Orange : charge ou décharge vers la limite.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

extension TaskAction {
    var label: String {
        switch self {
        case .setLimit: "Définir la limite de recharge"
        case .calibrate: "Démarrer la calibration"
        case .topUp: "Charger à 100 %"
        case .pause: "Suspendre la charge"
        case .dischargeTo: "Décharger jusqu'à"
        case .lowPowerOn: "Activer l'Économie d'énergie"
        case .lowPowerOff: "Désactiver l'Économie d'énergie"
        }
    }
}

extension Repeat {
    var label: String {
        switch self {
        case .never: "Ne pas répéter"
        case .daily: "Quotidienne"
        case .weekdays: "En semaine"
        case .weekly: "Hebdomadaire"
        case .biweekly: "Toutes les 2 semaines"
        case .monthly: "Mensuelle"
        case .yearly: "Annuelle"
        }
    }
}

struct ScheduleView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        let tasks = m.config(\.tasks)
        Form {
            Section {
                ForEach(tasks.wrappedValue) { t in
                    if let i = tasks.wrappedValue.firstIndex(of: t) { TaskRow(task: tasks[i]) { tasks.wrappedValue.remove(at: i) } }
                }
                HStack {
                    Button("+ Tâche") { tasks.wrappedValue.append(ScheduledTask(action: .setLimit, repeatRule: .daily, start: nextNine())) }
                    Button("Calibration mensuelle") { tasks.wrappedValue.append(ScheduledTask(action: .calibrate, repeatRule: .monthly, start: nextNine())) }
                    Button("Calibration toutes les 2 semaines") { tasks.wrappedValue.append(ScheduledTask(action: .calibrate, repeatRule: .biweekly, start: nextNine())) }
                }
                Toggle("Exécuter au réveil les tâches manquées", isOn: m.config(\.catchUpMissedTasks))
            }
            Section("Historique") {
                ForEach(m.status?.history ?? [], id: \.self) { h in
                    HStack {
                        Text(h.date, style: .date); Text(h.date, style: .time)
                        Text(h.text).foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    func nextNine() -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) ?? Date()
    }
}

struct TaskRow: View {
    @Binding var task: ScheduledTask
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Action", selection: $task.action) { ForEach(TaskAction.allCases, id: \.self) { Text($0.label).tag($0) } }
                Toggle("", isOn: $task.enabled).toggleStyle(.switch)
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            HStack {
                Picker("Répétition", selection: $task.repeatRule) { ForEach(Repeat.allCases, id: \.self) { Text($0.label).tag($0) } }
                DatePicker("", selection: $task.start).labelsHidden()
            }
            if task.action == .setLimit || task.action == .dischargeTo {
                Stepper("Valeur : \(task.value) %", value: $task.value, in: 20...100)
            }
        }
    }
}
