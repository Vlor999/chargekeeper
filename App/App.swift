import ServiceManagement
import Sparkle
import SwiftUI
import UserNotifications
import notify

@main
struct ChargeKeeperApp: App {
    @StateObject var model = AppModel()
    // Changing it rebuilds every view (`.id`) so all tr() strings switch at once.
    @AppStorage(languageKey) var language = "system"

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model).localized(language)
        } label: {
            Image(nsImage: {
                let i = NSImage(named: "MenuIcon")!
                i.size = NSSize(width: 18, height: 18)
                i.isTemplate = true
                return i
            }())
        }
        .menuBarExtraStyle(.window)
        Window(tr("Dashboard"), id: "dashboard") { DashboardView().environmentObject(model).localized(language) }
            .windowResizability(.contentSize)
        Settings { SettingsView(model: model).environmentObject(model).localized(language) }
    }
}

final class AppModel: ObservableObject {
    @Published var status: Status?
    @Published var error: String?
    @Published var serviceStatus: SMAppService.Status = .notRegistered
    let service = SMAppService.daemon(plistName: "com.vlor999.jauge.daemon.plist")
    /// Downloaded update waiting for the app to quit; the menu offers to install it now.
    @Published var readyUpdate: (version: String, install: () -> Void)?
    let updater: SPUStandardUpdaterController
    private let watcher: UpdateWatcher  // Sparkle keeps its delegate weakly
    private let banner = BannerDelegate()  // UNUserNotificationCenter keeps its delegate weakly
    private var timer: Timer?
    private var calibrationToken: Int32 = 0, heatToken: Int32 = 0, limitToken: Int32 = 0, adapterToken: Int32 = 0
    /// Open windows showing live data; polling and animation only run while > 0.
    var visible = 0 { didSet { if visible > 0 { refresh() } } }

    init() {
        let w = UpdateWatcher()
        watcher = w
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: w, userDriverDelegate: nil)
        w.onReady = { [weak self] in self?.readyUpdate = ($0, $1) }
        // First launch: register the root service; macOS then asks for approval in Login Items.
        if service.status == .notRegistered { enableService() }
        UNUserNotificationCenter.current().delegate = banner
        // Posted by the service when a calibration finishes: event driven, nothing runs in between.
        notify_register_dispatch(calibrationDoneNotification, &calibrationToken, .main) { [weak self] _ in self?.run(.status) }
        notify_register_dispatch(heatProtectNotification, &heatToken, .main) { [weak self] _ in self?.notice(.heat) }
        notify_register_dispatch(limitReachedNotification, &limitToken, .main) { [weak self] _ in self?.notice(.limit) }
        notify_register_dispatch(calibrationNeedsAdapterNotification, &adapterToken, .main) { [weak self] _ in self?.notice(.adapter) }
        refresh()
        // ponytail: 2s polling of a local socket; push notifications if it ever matters
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            if let self, self.visible > 0 { self.refresh() }
        }
    }

    func refresh() {
        run(.status)
        serviceStatus = service.status
    }

    func enableService() {
        do { try service.register() } catch { self.error = error.localizedDescription }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        serviceStatus = service.status
    }

    func run(_ cmd: Command) {
        switch cmd {
        case .calibrate(true) where NoticeKind.calibration.enabled: requestNotifications()
        case .setConfig(let c) where NoticeKind.calibration.enabled && c.tasks.contains { $0.enabled && $0.action == .calibrate }: requestNotifications()
        default: break
        }
        do { status = try send(cmd); error = nil } catch { self.error = error.localizedDescription }
        if let s = status { notifyCalibration(s.lastCalibration) }
    }

    /// Asked when a calibration is started or scheduled, not at launch. No prompt once the user has answered.
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private let notifiedKey = "lastNotifiedCalibration"
    private var notifying = false

    /// Once per calibration: on the service's signal, or at the next status if the app was not running then.
    private func notifyCalibration(_ c: CalibrationResult?) {
        let handled = UserDefaults.standard.object(forKey: notifiedKey) as? Date
        switch calibrationNotice(end: c?.end, handled: handled) {
        case .seed(let d): UserDefaults.standard.set(d, forKey: notifiedKey)
        case .none: break
        case .notify:
            guard let c, !notifying else { return }
            guard NoticeKind.calibration.enabled else { return self.handled(c.end) }
            notifying = true
            deliver("calibration", content(c)) { if $0 { self.handled(c.end) } else { self.notifying = false } }
        }
    }

    /// Heat, limit and adapter banners follow the service's signal live: a signal sent while the app was not running is not replayed.
    private func notice(_ kind: NoticeKind) {
        guard kind.enabled else { return }
        run(.status)
        guard let s = status, error == nil else { return }
        let n = UNMutableNotificationContent()
        switch kind {
        case .heat:
            n.title = tr("Heat protection")
            n.body = tr("Charging paused: battery at %@ °C (max %@ °C).", s.temperature.map { number($0, decimals: 1) } ?? "--", number(s.config.maxTemp))
        case .limit:
            n.title = tr("Charge limit reached")
            n.body = tr("Battery at %@ %%. Charging paused at the limit.", number(Double(s.percent)))
        case .adapter:
            // Plugged back in before the signal was handled: nothing to ask.
            guard calibrationNeedsAdapter(s.runtime.calibration) && !s.adapter else { return }
            n.title = tr("Calibration paused")
            n.body = tr("Plug in the adapter to continue calibration.")
        case .calibration: return
        }
        deliver(kind.rawValue, n) { _ in }
    }

    /// Asks for permission first: events from Shortcuts, the CLI or the schedule never asked. `done(true)` once
    /// delivered or denied (denied counts as handled), `done(false)` on a delivery error.
    private func deliver(_ id: String, _ content: UNNotificationContent, done: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return DispatchQueue.main.async { done(true) } }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                DispatchQueue.main.async { done(error == nil) }
            }
        }
    }

    /// Denied counts as handled too: no retry on every status.
    private func handled(_ end: Date) {
        UserDefaults.standard.set(end, forKey: notifiedKey)
        notifying = false
    }

    private func content(_ c: CalibrationResult) -> UNNotificationContent {
        let n = UNMutableNotificationContent()
        n.title = tr("Calibration complete")
        let lines = [c.before.maxCapacity.flatMap { b in c.after.maxCapacity.map { tr("Capacity: %@ → %@ mAh", number(Double(b)), number(Double($0))) } },
                     c.before.health.flatMap { b in c.after.health.map { tr("Health: %@ → %@ %%", number(b, decimals: 1), number($0, decimals: 1)) } }]
            .compactMap { $0 }
        n.body = lines.isEmpty ? tr("Finished %@", dateTime(c.end)) : lines.joined(separator: "\n")
        return n
    }

    /// Binding into the daemon's config; every edit is pushed immediately.
    func config<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.status?.config[keyPath: kp] ?? Config()[keyPath: kp] },
                set: { v in guard var c = self.status?.config else { return }; c[keyPath: kp] = v; self.run(.setConfig(c)) })
    }
}

/// Banners the user can turn off in Settings > General.
enum NoticeKind: String, CaseIterable, Identifiable {
    case calibration, adapter, heat, limit

    var id: Self { self }
    var key: String { "notify." + rawValue }
    var defaultOn: Bool { self != .limit }
    var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultOn }

    var label: String {
        switch self {
        case .calibration: tr("Calibration complete")
        case .adapter: tr("Calibration needs the adapter")
        case .heat: tr("Heat protection paused charging")
        case .limit: tr("Charge limit reached")
        }
    }
}

/// Sparkle downloads updates silently and installs them when the app quits. A menu bar app rarely quits,
/// so the update would wait for days: keep Sparkle's install-now block for the menu instead.
final class UpdateWatcher: NSObject, SPUUpdaterDelegate {
    var onReady: ((String, @escaping () -> Void) -> Void)?

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        onReady?(item.displayVersionString, immediateInstallationBlock)
        return true
    }
}

/// Shows the banner even while the menu or a window has the app active.
final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

extension ChargeState {
    var label: String {
        switch self {
        case .charging: tr("Charging")
        case .pause: tr("Charging paused")
        case .idle: tr("Idle")
        case .discharging: tr("Discharging")
        case .topup: tr("Charge to 100%")
        case .heatProtect: tr("Heat protection")
        case .calibration: tr("Calibration")
        case .exit: tr("Stopped")
        }
    }
}

extension CalibrationPhase {
    func label(limit: Int) -> String {
        switch self {
        case .chargeFull: tr("Charge to %@ %%", number(100))
        case .dischargeTo10: tr("Discharge to %@ %%", number(10))
        case .rechargeFull: tr("Recharge to %@ %%", number(100))
        case .hold: tr("Rest 1 h at %@ %%", number(100))
        case .returnToLimit: tr("Back to %@ %%", number(Double(limit)))
        }
    }
}

extension Status {
    /// Time to reach `target` at the present battery current, as "~25 min".
    func eta(_ target: Int) -> String? {
        timeToTarget(percent: percent, target: target, capacity: battery?.maxCapacity, amperage: batteryAmperage, watts: batteryWatts)
            .map(approxDuration)
    }

    /// Menu status line: the state, then what it is heading to.
    var headline: (title: String, detail: String?) {
        let r = runtime
        let to = { (t: Int) in eta(t).map { tr("%@ to %@ %%", $0, number(Double(t))) } }
        switch r.state {
        case .pause: return (tr("Paused"), tr("%@ %% reached", number(Double(config.limit))))
        case .charging: return (r.state.label, to(config.limit))
        case .topup: return (r.state.label, to(100))
        case .discharging where adapter: return (r.state.label, to(config.limit))
        default: return (r.state.label, nil)
        }
    }

    /// "Step 2/5 · Discharge to 10 % · ~1 h 10 min" while calibrating.
    var calibrationLine: String? {
        guard let p = runtime.calibration else { return nil }
        let (n, of) = calibrationStep(p)
        var parts = [tr("Step %d/%d", n, of), p.label(limit: config.limit)]
        if !(calibrationNeedsAdapter(p) && !adapter) {
            if p == .hold {
                let left = holdRemaining(phaseStart: runtime.phaseStart, now: Date())
                parts.append(tr("%@ min left", number((left / 60).rounded(.up))))
            } else if let t = calibrationTarget(p, limit: config.limit), let e = eta(t) {
                parts.append(e)
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Capacity and health when the running calibration started.
    var calibrationBaseline: String? {
        guard runtime.calibration != nil, let b = runtime.calibrationBefore else { return nil }
        let parts = [b.maxCapacity.map { tr("%@ mAh", number(Double($0))) }, b.health.map { tr("health %@ %%", number($0, decimals: 1)) }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : tr("Before: %@", parts.joined(separator: " · "))
    }
}

struct MenuView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("flowInMenu") private var flowInMenu = true
    @State private var limit: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let u = m.readyUpdate { UpdateBanner(version: u.version, install: u.install); Divider() }
            if let s = m.status, m.error == nil { content(s) } else { serviceSetup }
            Divider()
            HStack {
                Button(tr("Dashboard")) { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                SettingsLink { Text(tr("Settings…")) }
                Spacer()
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { m.visible += 1 }
        .onDisappear { m.visible -= 1 }
    }

    /// The root service controls charging; without it the app is only a remote control.
    @ViewBuilder var serviceSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Charging service is off")).font(.headline)
            switch m.serviceStatus {
            case .requiresApproval:
                Text(tr("Allow “ChargeKeeper” in System Settings > General > Login Items > Allow in the Background."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(tr("Open System Settings")) { SMAppService.openSystemSettingsLoginItems() }
            case .enabled:
                Text(tr("Starting the service…")).font(.caption).foregroundStyle(.secondary)
            default:
                Text(tr("ChargeKeeper needs a system service to control charging.")).font(.caption).foregroundStyle(.secondary)
                Button(tr("Turn On Service")) { m.enableService() }
            }
        }
    }

    @ViewBuilder func content(_ s: Status) -> some View {
        let r = s.runtime
        HStack(alignment: .center) {
            Text("\(s.percent) %").font(.system(size: 34, weight: .semibold))
            VStack(alignment: .leading) {
                let h = s.headline
                Text("\(Text(h.title).font(.headline))\(Text(h.detail.map { " · " + $0 } ?? "").font(.subheadline).foregroundStyle(.secondary))")
                Text(tr("Hardware %@ · %@", s.hardwarePercent.map { "\($0) %" } ?? "--", celsius(s.temperature)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if let line = s.calibrationLine {
            VStack(alignment: .leading, spacing: 2) {
                Text(line).foregroundStyle(.orange)
                if let b = s.calibrationBaseline { Text(b).foregroundStyle(.secondary) }
                if calibrationNeedsAdapter(r.calibration) && !s.adapter {
                    Label(tr("Plug in the adapter to continue calibration"), systemImage: "powerplug.fill").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
        if r.pastLimitSince != nil && s.adapter {
            Label(tr("macOS charged past the limit (battery recalibration or system override). The limit applies again once the level falls back to it."),
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tr("Charge limit"))
                Spacer()
                TextField("", value: Binding(get: { s.config.limit }, set: { m.run(.setLimit($0)) }), format: .number)
                    .frame(width: 44).multilineTextAlignment(.trailing)
                Text("%")
            }
            Slider(value: Binding(get: { limit ?? Double(s.config.limit) }, set: { limit = $0 }), in: 20...100, step: 1) { editing in
                if !editing, let l = limit { m.run(.setLimit(Int(l))); limit = nil }
            }
            if s.config.idle {
                Text(tr("Idle: %d–%d %%", max(s.config.limit - s.config.idleRange, 0), s.config.limit))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        HStack {
            if !s.config.autoDischarge {
                Toggle(tr("Discharge"), isOn: Binding(get: { r.discharge }, set: { m.run(.discharge($0)) }))
                    .disabled(s.percent <= s.config.limit && !r.discharge)
            }
            Toggle(tr("Charge to 100%"), isOn: Binding(get: { r.topUp }, set: { m.run(.topUp($0)) }))
        }
        .toggleStyle(.button)
        HStack {
            Button(r.calibration == nil ? tr("Start Calibration") : tr("Stop Calibration")) { m.run(.calibrate(r.calibration == nil)) }
            Button(tr("Pause")) { m.run(.pause) }
        }

        if flowInMenu { PowerFlow(s: s).frame(height: 110) }
        if !s.nativeLimit { Text(tr("Native limit unavailable: SMC control only")).font(.caption2).foregroundStyle(.secondary) }
    }
}

struct UpdateBanner: View {
    let version: String
    let install: () -> Void

    var body: some View {
        HStack {
            Label(tr("ChargeKeeper %@ is ready", version), systemImage: "arrow.down.circle.fill")
                .font(.callout).foregroundStyle(.tint)
            Spacer()
            Button(tr("Install and Restart"), action: install).controlSize(.small)
        }
    }
}

extension View {
    /// Rebuilds the view tree when the language changes and formats dates in that language.
    func localized(_ language: String) -> some View {
        id(language).environment(\.locale, appLocale)
    }
}
