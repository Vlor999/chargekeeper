import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        TabView {
            general.tabItem { Label(tr("General"), systemImage: "gearshape") }
            charge.tabItem { Label(tr("Charge control"), systemImage: "bolt") }
            sleep.tabItem { Label(tr("Sleep"), systemImage: "moon") }
            led.tabItem { Label(tr("MagSafe LED"), systemImage: "lightbulb") }
            ScheduleView().tabItem { Label(tr("Schedule"), systemImage: "calendar") }
        }
        .frame(width: 560, height: 440)
        .onAppear { NSApp.activate(ignoringOtherApps: true); m.visible += 1 }
        .onDisappear { m.visible -= 1 }
    }

    @AppStorage(languageKey) private var language = "system"

    var general: some View {
        Form {
            Picker(tr("Language"), selection: $language) {
                Text(tr("System")).tag("system")
                Text("English").tag("en")
                Text("Français").tag("fr")
            }
            Toggle(tr("Open at login"), isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
            Section(tr("Updates")) {
                let u = m.updater.updater
                Toggle(tr("Install updates automatically"), isOn: Binding(
                    get: { u.automaticallyChecksForUpdates && u.automaticallyDownloadsUpdates },
                    set: { u.automaticallyChecksForUpdates = $0; u.automaticallyDownloadsUpdates = $0 }))
                HStack {
                    VStack(alignment: .leading) {
                        Text(tr("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                        Text(u.lastUpdateCheckDate.map { tr("Last check: %@", $0.formatted(date: .abbreviated, time: .shortened)) } ?? tr("Never checked"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("Check for Updates…")) { m.updater.checkForUpdates(nil) }
                }
            }
            Section(tr("About")) {
                Text(tr("Provided as is, without warranty (MIT License). ChargeKeeper uses undocumented macOS interfaces that may change: use it at your own risk. Independent project, not affiliated with or endorsed by Apple."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(tr("Quit ChargeKeeper")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .formStyle(.grouped)
    }

    var charge: some View {
        Form {
            Section(tr("Discharge")) {
                Toggle(tr("Automatic discharge"), isOn: m.config(\.autoDischarge))
                Text(tr("Above the limit, the battery drains down to the limit even when plugged in. Paused during calibration."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("Idle range")) {
                Toggle(tr("Recharge only below the idle range"), isOn: m.config(\.idle))
                Stepper(tr("Range: %d %%", m.config(\.idleRange).wrappedValue), value: m.config(\.idleRange), in: 1...30)
            }
            Section(tr("Heat protection")) {
                Toggle(tr("Stop charging when the battery is too hot"), isOn: m.config(\.heatProtect))
                Stepper(tr("Max temp: %.0f °C", m.config(\.maxTemp).wrappedValue), value: m.config(\.maxTemp), in: 25...50, step: 1)
            }
            Section(tr("Shutdown")) {
                Toggle(tr("Keep the limit when the service stops"), isOn: m.config(\.keepLimitWhenStopped))
                Text(tr("The system service applies the limit for every user account. This keeps it active if the service stops."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    var sleep: some View {
        Form {
            Toggle(tr("Freeze the charge level during sleep"), isOn: m.config(\.stopChargingDuringSleep))
            Toggle(tr("Prevent sleep until the limit is reached"), isOn: m.config(\.disableSleepUntilLimit))
            Text(tr("Sleep is also prevented while discharging on the adapter (clamshell mode)."))
                .font(.caption).foregroundStyle(.secondary)
            Section(tr("macOS energy mode")) {
                HStack {
                    Button(tr("Low Power Mode: on")) { m.run(.lowPower(true)) }
                    Button(tr("off")) { m.run(.lowPower(false)) }
                }
                HStack {
                    Button(tr("Performance mode: on")) { m.run(.highPower(true)) }
                    Button(tr("off")) { m.run(.highPower(false)) }
                }
            }
        }
        .formStyle(.grouped)
    }

    var led: some View {
        Form {
            Picker(tr("MagSafe LED"), selection: m.config(\.led)) {
                Text(tr("System control")).tag(LEDSetting.system)
                Text(tr("Color by charge state")).tag(LEDSetting.indicate)
                Text(tr("Always off")).tag(LEDSetting.alwaysOff)
            }
            Toggle(tr("Blinking orange while discharging"), isOn: m.config(\.ledBlinkDischarge))
            Text(tr("Green: limit reached · Orange: charging or discharging toward the limit."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

extension TaskAction {
    var label: String {
        switch self {
        case .setLimit: tr("Set charge limit")
        case .calibrate: tr("Start Calibration")
        case .topUp: tr("Charge to 100%")
        case .pause: tr("Pause charging")
        case .dischargeTo: tr("Discharge to")
        case .lowPowerOn: tr("Turn on Low Power Mode")
        case .lowPowerOff: tr("Turn off Low Power Mode")
        }
    }
}

extension Repeat {
    var label: String {
        switch self {
        case .never: tr("Never")
        case .daily: tr("Daily")
        case .weekdays: tr("Weekdays")
        case .weekly: tr("Weekly")
        case .biweekly: tr("Every 2 weeks")
        case .monthly: tr("Monthly")
        case .yearly: tr("Yearly")
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
                    Button(tr("+ Task")) { tasks.wrappedValue.append(ScheduledTask(action: .setLimit, repeatRule: .daily, start: nextNine())) }
                    Button(tr("Monthly calibration")) { m.requestNotifications(); tasks.wrappedValue.append(ScheduledTask(action: .calibrate, repeatRule: .monthly, start: nextNine())) }
                    Button(tr("Calibration every 2 weeks")) { m.requestNotifications(); tasks.wrappedValue.append(ScheduledTask(action: .calibrate, repeatRule: .biweekly, start: nextNine())) }
                }
                Toggle(tr("Run missed tasks on wake"), isOn: m.config(\.catchUpMissedTasks))
            }
            if let b = m.status?.battery {
                Section(tr("Battery health")) {
                    row(tr("Health"), percent(b.health))
                    row(tr("Health (nominal)"), percent(b.nominalHealth))
                    row(tr("Full charge capacity"), mAh(b.maxCapacity))
                    row(tr("Nominal capacity"), mAh(b.nominalCapacity))
                    row(tr("Design capacity"), mAh(b.designCapacity))
                    row(tr("Cycle count"), b.cycleCount.map(String.init) ?? "--")
                }
            }
            if let c = m.status?.lastCalibration {
                Section(tr("Last calibration")) {
                    row(tr("Date"), c.end.formatted(date: .abbreviated, time: .shortened))
                    row(tr("Duration"), duration(c.end.timeIntervalSince(c.start)))
                    row(tr("Capacity"), "\(mAh(c.before.maxCapacity)) → \(mAh(c.after.maxCapacity))")
                    row(tr("Health"), "\(percent(c.before.health)) → \(percent(c.after.health))")
                    row(tr("Health (nominal)"), "\(percent(c.before.nominalHealth)) → \(percent(c.after.nominalHealth))")
                    row(tr("Cycle count"), "\(c.before.cycleCount.map(String.init) ?? "--") → \(c.after.cycleCount.map(String.init) ?? "--")")
                    row(tr("Design capacity"), mAh(c.after.designCapacity))
                    row(tr("Temperature"), c.after.temperature.map { String(format: "%.1f °C", $0) } ?? "--")
                }
            }
            Section(tr("History")) {
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

    func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit() }
    }

    func mAh(_ v: Int?) -> String { v.map { "\($0) mAh" } ?? "--" }
    func percent(_ v: Double?) -> String { v.map { String(format: "%.1f %%", $0) } ?? "--" }
    func duration(_ s: TimeInterval) -> String { tr("%d h %02d min", Int(s) / 3600, Int(s) % 3600 / 60) }

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
                Picker(tr("Action"), selection: $task.action) { ForEach(TaskAction.allCases, id: \.self) { Text($0.label).tag($0) } }
                Toggle("", isOn: $task.enabled).toggleStyle(.switch)
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            HStack {
                Picker(tr("Repeat"), selection: $task.repeatRule) { ForEach(Repeat.allCases, id: \.self) { Text($0.label).tag($0) } }
                DatePicker("", selection: $task.start).labelsHidden()
            }
            if task.action == .setLimit || task.action == .dischargeTo {
                Stepper(tr("Value: %d %%", task.value), value: $task.value, in: 20...100)
            }
        }
    }
}
