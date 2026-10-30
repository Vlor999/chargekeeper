import ServiceManagement
import Sparkle
import SwiftUI
import UserNotifications

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, charge, sleep, led, schedule, battery

    var id: Self { self }

    var title: String {
        switch self {
        case .general: tr("General")
        case .charge: tr("Charge")
        case .sleep: tr("Sleep")
        case .led: tr("MagSafe LED")
        case .schedule: tr("Schedule")
        case .battery: tr("Battery")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .charge: "bolt.fill"
        case .sleep: "moon.fill"
        case .led: "lightbulb.fill"
        case .schedule: "calendar"
        case .battery: "battery.100percent"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .charge: .orange
        case .sleep: .indigo
        case .led: .teal
        case .schedule: .red
        case .battery: .green
        }
    }
}

/// Sidebar navigation like System Settings. Does not observe the model: the status refresh while the
/// window is open re-renders the selected pane only, never the navigation.
struct SettingsView: View {
    let model: AppModel
    @AppStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: Binding(get: { pane }, set: { if let p = $0 { pane = p } })) {
                ForEach(SettingsPane.allCases) { p in
                    Label {
                        Text(p.title)
                    } icon: {
                        Image(systemName: p.icon)
                            .resizable().scaledToFit()
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 13, height: 13)
                            .frame(width: 20, height: 20)
                            .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .tag(p)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsPaneView(pane: pane).navigationTitle(pane.title)
        }
        .frame(width: 720, height: 480)
        .onAppear { NSApp.activate(ignoringOtherApps: true); model.visible += 1 }
        .onDisappear { model.visible -= 1 }
    }
}

struct SettingsPaneView: View {
    @EnvironmentObject var m: AppModel
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .general: general
        case .charge: charge
        case .sleep: sleep
        case .led: led
        case .schedule: ScheduleView()
        case .battery: BatteryView()
        }
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
            Section {
                ForEach(NoticeKind.allCases) { NoticeToggle(kind: $0) }
            } header: {
                Text(tr("Notifications"))
            } footer: {
                Text(tr("Shown only while ChargeKeeper is running. Allow ChargeKeeper in System Settings > Notifications."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("Updates")) {
                let u = m.updater.updater
                Toggle(tr("Install updates automatically"), isOn: Binding(
                    get: { u.automaticallyChecksForUpdates && u.automaticallyDownloadsUpdates },
                    set: { u.automaticallyChecksForUpdates = $0; u.automaticallyDownloadsUpdates = $0 }))
                HStack {
                    VStack(alignment: .leading) {
                        Text(tr("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                        Text(u.lastUpdateCheckDate.map { tr("Last check: %@", dateTime($0)) } ?? tr("Never checked"))
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

struct NoticeToggle: View {
    let kind: NoticeKind
    @AppStorage private var on: Bool

    init(kind: NoticeKind) {
        self.kind = kind
        _on = AppStorage(wrappedValue: kind.defaultOn, kind.key)
    }

    var body: some View {
        Toggle(kind.label, isOn: $on)
            .onChange(of: on) { _, v in
                if v { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
            }
    }
}

extension TaskAction {
    var label: String { tr(title) }
}

extension HistoryEntry {
    /// SF Symbol and tint of the entry; free text from an older service gets a neutral clock.
    var symbol: (name: String, color: Color) {
        let e = parsedHistory(self)
        switch e.event {
        case nil: return ("clock", .secondary)
        case .calibrationStarted: return ("play.circle.fill", .orange)
        case .calibrationStopped: return ("stop.circle.fill", .secondary)
        case .calibrationEnded: return ("checkmark.circle.fill", .orange)
        case .calibrationDone: return ("checkmark.seal.fill", .green)
        case .calibrationPhase:
            switch e.phase {
            case .chargeFull?, .rechargeFull?: return ("battery.100percent.bolt", .orange)
            case .dischargeTo10?: return ("battery.25percent", .orange)
            case .hold?: return ("hourglass", .orange)
            case .returnToLimit?, nil: return ("arrow.down.to.line", .orange)
            }
        case .taskRun: return ("calendar", .red)
        case .taskSkipped: return ("calendar.badge.exclamationmark", .secondary)
        case .limitChanged: return ("slider.horizontal.3", .blue)
        case .heatProtect: return ("thermometer.high", .red)
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
                    Button(tr("Monthly calibration")) { tasks.wrappedValue.append(ScheduledTask(action: .calibrate, repeatRule: .monthly, start: nextNine())) }
                    Button(tr("Calibration every 2 weeks")) { tasks.wrappedValue.append(ScheduledTask(action: .calibrate, repeatRule: .biweekly, start: nextNine())) }
                }
                Toggle(tr("Run missed tasks on wake"), isOn: m.config(\.catchUpMissedTasks))
            }
            Section(tr("History")) {
                ForEach(m.status?.history ?? [], id: \.self) { h in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: h.symbol.name).foregroundStyle(h.symbol.color).frame(width: 18)
                        Text(localizedHistory(h))
                        Spacer()
                        Text(h.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    func nextNine() -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) ?? Date()
    }
}

struct BatteryView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        Form {
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
                    row(tr("Date"), dateTime(c.end))
                    row(tr("Duration"), duration(c.end.timeIntervalSince(c.start)))
                    row(tr("Capacity"), "\(mAh(c.before.maxCapacity)) → \(mAh(c.after.maxCapacity))")
                    row(tr("Health"), "\(percent(c.before.health)) → \(percent(c.after.health))")
                    row(tr("Health (nominal)"), "\(percent(c.before.nominalHealth)) → \(percent(c.after.nominalHealth))")
                    row(tr("Cycle count"), "\(c.before.cycleCount.map(String.init) ?? "--") → \(c.after.cycleCount.map(String.init) ?? "--")")
                    row(tr("Design capacity"), mAh(c.after.designCapacity))
                    row(tr("Temperature"), celsius(c.after.temperature))
                }
            }
            if m.status?.battery == nil && m.status?.lastCalibration == nil {
                Text(tr("Battery data unavailable."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit() }
    }

    func mAh(_ v: Int?) -> String { v.map { "\($0) mAh" } ?? "--" }
    func percent(_ v: Double?) -> String { v.map { number($0, decimals: 1) + " %" } ?? "--" }
    func duration(_ s: TimeInterval) -> String { tr("%d h %02d min", Int(s) / 3600, Int(s) % 3600 / 60) }
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
