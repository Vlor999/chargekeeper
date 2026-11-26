import ServiceManagement
import Sparkle
import SwiftUI
import UserNotifications
import notify
import os

@main
struct ChargeKeeperApp: App {
    @StateObject var model = AppModel()
    @AppStorage(languageKey) var language = "system"

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model).localized(language).background(MenuCenteredUnderStatusItem())
        } label: {
            MenuIconLabel(battery: model.battery)
        }
        .menuBarExtraStyle(.window)
        Window(tr("Dashboard"), id: "dashboard") { DashboardView().environmentObject(model).localized(language) }
            .windowResizability(.contentSize)
        Settings { SettingsView(unobservedModel: model).environmentObject(model).localized(language) }
    }
}

final class AppModel: ObservableObject {
    @Published var status: Status? { didSet { scheduleRefresh() } }
    @Published var error: String?
    @Published var serviceStatus: SMAppService.Status = .notRegistered
    let battery = BatteryLevel()
    let service = SMAppService.daemon(plistName: "com.vlor999.jauge.daemon.plist")
    @Published var updateWaitingForQuit: UpdateWaitingForQuit?
    let updater: SPUStandardUpdaterController
    private let retainedUpdaterDelegate: InstallNowUpdateWatcher
    private let retainedNotificationDelegate = ForegroundBannerDelegate()
    private var timer: Timer?
    private var refreshEvery: TimeInterval = 0
    private var calibrationToken: Int32 = 0, heatToken: Int32 = 0, limitToken: Int32 = 0, adapterToken: Int32 = 0
    var openWindowCount = 0 {
        didSet {
            guard openWindowCount > 0 else { return stopRefresh() }
            scheduleRefresh()
            refresh()
        }
    }
    @Published private(set) var lastKnownPowerHistory: [SoCPowerPoint] = []
    @Published private(set) var powerHistoryReceivedAt = Date()
    @Published private(set) var sleepDisabledWithoutReason = false

    init() {
        let watcher = InstallNowUpdateWatcher()
        retainedUpdaterDelegate = watcher
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: watcher, userDriverDelegate: nil)
        watcher.onUpdateWaitingForQuit = { [weak self] in self?.updateWaitingForQuit = UpdateWaitingForQuit(version: $0, install: $1) }
        registerServiceOnFirstLaunch()
        UNUserNotificationCenter.current().delegate = retainedNotificationDelegate
        observeServiceSignals()
        refresh()
    }

    private func registerServiceOnFirstLaunch() {
        if service.status == .notRegistered { enableService() }
    }

    private func observeServiceSignals() {
        notify_register_dispatch(DarwinNotification.calibrationDone.name, &calibrationToken, .main) { [weak self] _ in self?.run(.status()) }
        notify_register_dispatch(DarwinNotification.heatProtect.name, &heatToken, .main) { [weak self] _ in self?.showLiveBanner(for: .heat) }
        notify_register_dispatch(DarwinNotification.limitReached.name, &limitToken, .main) { [weak self] _ in self?.showLiveBanner(for: .limit) }
        notify_register_dispatch(DarwinNotification.calibrationNeedsAdapter.name, &adapterToken, .main) { [weak self] _ in self?.showLiveBanner(for: .adapter) }
    }

    // ponytail: polls the service socket every 1-2 s while a window is open; a push from the service would remove the polling (https://github.com/Vlor999/chargekeeper/issues/53)
    private func scheduleRefresh() {
        guard openWindowCount > 0 else { return }
        let every = appRefreshInterval(status?.config.powerInterval ?? .s5)
        guard timer == nil || every != refreshEvery else { return }
        refreshEvery = every
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func stopRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        run(.status(soc: true))
        let h = powerHistoryIfServiceAnswered
        if h != lastKnownPowerHistory { lastKnownPowerHistory = h }
        powerHistoryReceivedAt = Date()
        serviceStatus = service.status
        let unexplained = unexplainedSleepDisabled(system: systemSleepDisabled(), service: error == nil ? status?.sleepDisabled : nil)
        if unexplained != sleepDisabledWithoutReason { sleepDisabledWithoutReason = unexplained }
    }

    private var powerHistoryIfServiceAnswered: [SoCPowerPoint] { error == nil ? status?.socHistory ?? [] : [] }

    func enableService() {
        do { try service.register() } catch { self.error = error.localizedDescription }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        serviceStatus = service.status
    }

    func run(_ cmd: Command) {
        switch cmd {
        case .calibrate(true) where NoticeKind.calibration.enabled: requestNotificationPermission()
        case .setConfig(let c) where NoticeKind.calibration.enabled && c.tasks.contains { $0.enabled && $0.action == .calibrate }: requestNotificationPermission()
        default: break
        }
        do { status = try send(cmd); error = nil } catch { self.error = error.localizedDescription }
        if let s = status { notifyCalibration(s.lastCalibration) }
    }

    func fetchHealthSeries() -> HealthSeries {
        (try? send(.healthHistory))?.healthHistory.map(HealthSeries.samples) ?? .unavailable
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private let notifiedKey = "lastNotifiedCalibration"
    private var notifying = false

    private func notifyCalibration(_ c: CalibrationResult?) {
        let handled = UserDefaults.standard.object(forKey: notifiedKey) as? Date
        switch calibrationNotice(end: c?.end, handled: handled) {
        case .seed(let d): UserDefaults.standard.set(d, forKey: notifiedKey)
        case .none: break
        case .notify:
            guard let c, !notifying else { return }
            guard NoticeKind.calibration.enabled else { return markCalibrationNotified(c.end) }
            notifying = true
            deliverAfterAskingPermission("calibration", content(c)) {
                switch $0 {
                case .delivered, .denied: self.markCalibrationNotified(c.end)
                case .failed: self.notifying = false
                }
            }
        }
    }

    private func showLiveBanner(for kind: NoticeKind) {
        guard kind.enabled else { return }
        run(.status())
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
            guard s.calibrationWaitsForAdapter else { return }
            n.title = tr("Calibration paused")
            n.body = tr("Plug in the adapter to continue calibration.")
        case .calibration: return
        }
        deliverAfterAskingPermission(kind.rawValue, n) { _ in }
    }

    private enum DeliveryResult { case delivered, denied, failed }

    private func deliverAfterAskingPermission(_ id: String, _ content: UNNotificationContent, done: @escaping (DeliveryResult) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return DispatchQueue.main.async { done(.denied) } }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                DispatchQueue.main.async { done(error == nil ? .delivered : .failed) }
            }
        }
    }

    private func markCalibrationNotified(_ end: Date) {
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

    func config<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.status?.config[keyPath: kp] ?? Config()[keyPath: kp] },
                set: { v in guard var c = self.status?.config else { return }; c[keyPath: kp] = v; self.run(.setConfig(c)) })
    }
}

struct MenuCenteredUnderStatusItem: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        private static var reportedMissing = false
        private var tokens: [NSObjectProtocol] = []
        private weak var observed: NSWindow?
        private var moving = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observed else { return }
            tokens.forEach(NotificationCenter.default.removeObserver)
            observed = window
            // exception: macOS can place the menu window before ordering it in, so didMove fires while it is hidden; didBecomeKey is the first notification once it is on screen (https://github.com/Vlor999/chargekeeper/pull/32)
            tokens = [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: window, queue: nil) { [weak self] _ in self?.center() }
            }
            center()
        }

        private func center() {
            guard let window, window.isVisible, !moving else { return }
            guard let item = Self.statusItemWindowUnderMouse(), let screen = item.screen else {
                if !Self.reportedMissing {
                    Self.reportedMissing = true
                    os_log(.error, "menu centering: status item window not found, menu keeps the default alignment")
                }
                return
            }
            let f = window.frame, i = item.frame, visible = screen.visibleFrame, scale = window.backingScaleFactor
            let raw = centeredMenuX(width: f.width, under: i.minX...i.maxX, in: visible.minX...visible.maxX, margin: menuScreenMarginPoints)
            let x = (raw * scale).rounded() / scale
            guard abs(x - f.minX) > 1 else { return }
            moving = true
            window.setFrameOrigin(NSPoint(x: x, y: f.minY))
            moving = false
        }

        // exception: AppKit draws each menu bar copy in a window of the private class NSStatusBarWindow; if it is renamed, the menu keeps its default left alignment (https://github.com/Vlor999/chargekeeper/pull/32)
        private static func statusItemWindowUnderMouse() -> NSWindow? {
            let items = NSApp.windows.filter { $0.className == statusItemWindowClassName && $0.screen != nil }
            let mouse = NSEvent.mouseLocation
            return items.first(where: { $0.screen!.frame.contains(mouse) }) ?? items.first
        }
    }
}

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

struct UpdateWaitingForQuit {
    let version: String
    let install: () -> Void
}

final class InstallNowUpdateWatcher: NSObject, SPUUpdaterDelegate {
    var onUpdateWaitingForQuit: ((String, @escaping () -> Void) -> Void)?

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        onUpdateWaitingForQuit?(item.displayVersionString, immediateInstallationBlock)
        return true
    }
}

final class ForegroundBannerDelegate: NSObject, UNUserNotificationCenterDelegate {
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
    var calibrationWaitsForAdapter: Bool { calibrationNeedsAdapter(runtime.calibration) && !adapter }

    func eta(toPercent target: Int) -> String? {
        timeToTarget(percent: percent, target: target, capacity: battery?.maxCapacity, amperage: batteryAmperage, watts: batteryWatts)
            .map(approxDuration)
    }

    var headline: (title: String, detail: String?) {
        let r = runtime
        let to = { (t: Int) in eta(toPercent: t).map { tr("%@ to %@ %%", $0, number(Double(t))) } }
        switch r.state {
        case .pause: return (tr("Paused"), tr("%@ %% reached", number(Double(config.limit))))
        case .charging: return (r.state.label, to(config.limit))
        case .topup: return (r.state.label, to(100))
        case .discharging where adapter: return (r.state.label, to(config.limit))
        default: return (r.state.label, nil)
        }
    }

    var calibrationLine: String? {
        guard let p = runtime.calibration else { return nil }
        let (n, of) = calibrationStep(p)
        var parts = [tr("Step %d/%d", n, of), p.label(limit: config.limit)]
        if !calibrationWaitsForAdapter {
            if p == .hold {
                let left = holdRemaining(phaseStart: runtime.phaseStart, now: Date())
                parts.append(tr("%@ min left", number((left / 60).rounded(.up))))
            } else if let t = calibrationTarget(p, limit: config.limit), let e = eta(toPercent: t) {
                parts.append(e)
            }
        }
        return parts.joined(separator: " · ")
    }

    var calibrationBaseline: String? {
        guard runtime.calibration != nil, let b = runtime.calibrationBefore else { return nil }
        let parts = [b.maxCapacity.map { tr("%@ mAh", number(Double($0))) }, b.health.map { tr("health %@ %%", number($0, decimals: 1)) }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : tr("Before: %@", parts.joined(separator: " · "))
    }
}

extension KeepAwakeDuration {
    var label: String {
        switch self {
        case .untilOff: tr("Until turned off")
        case .m30: number(30) + " min"
        default: number(Double(rawValue / 60)) + " h"
        }
    }
}

extension Status {
    var keepAwakeLine: String? {
        guard let until = runtime.keepAwakeUntil else { return nil }
        return until == .distantFuture ? tr("Awake until turned off")
            : tr("Awake until %@", until.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale)))
    }
}

struct MenuView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("flowInMenu") private var flowInMenu = true
    @AppStorage("keepAwakeDuration") private var awakeFor = KeepAwakeDuration.h1
    @State private var limit: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let u = m.updateWaitingForQuit { UpdateBanner(version: u.version, install: u.install); Divider() }
            if m.sleepDisabledWithoutReason { UnexplainedSleepDisabledWarning(); Divider() }
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
        .countedWhileOnScreen(in: m)
    }

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
                if s.calibrationWaitsForAdapter {
                    Label(tr("Plug in the adapter to continue calibration"), systemImage: "powerplug.fill").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
        if r.pastLimitSince != nil && s.adapter {
            Label(r.state == .discharging ? tr("Battery is above the limit while plugged in (macOS charged it). ChargeKeeper discharges it back to the limit.") : tr("Battery is above the limit while plugged in (macOS charged it). ChargeKeeper holds this level and does not discharge. Turn on Automatic discharge to return to the limit."), systemImage: "info.circle")
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(tr("Keep awake"), isOn: Binding(get: { r.keepAwakeUntil != nil }, set: { m.run(.keepAwake($0 ? awakeFor : nil)) }))
                    .fixedSize()
                Spacer(minLength: 8)
                Picker("", selection: Binding(get: { awakeFor }, set: { chooseKeepAwakeDuration($0, restartingFromNowIfOn: r.keepAwakeUntil != nil) })) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            Toggle(tr("Even with the lid closed"), isOn: m.config(\.keepAwakeLidClosed))
            if let line = s.keepAwakeLine { Text(line).font(.caption).foregroundStyle(.secondary) }
        }

        if flowInMenu { PowerFlow(s: s).frame(height: 110) }
        if s.config.powerInterval != .off { PowerGraph(history: m.lastKnownPowerHistory, receivedAt: m.powerHistoryReceivedAt) }
        if !s.nativeLimit { Text(tr("Native limit unavailable: SMC control only")).font(.caption2).foregroundStyle(.secondary) }
    }

    private func chooseKeepAwakeDuration(_ duration: KeepAwakeDuration, restartingFromNowIfOn keepAwakeOn: Bool) {
        awakeFor = duration
        if keepAwakeOn { m.run(.keepAwake(duration)) }
    }
}

// exception: IOPMCopySystemPowerSettings is exported by IOKit but declared only in its private headers, so it is looked up at run time (https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLibPrivate.h)
func systemSleepDisabled() -> Bool? {
    typealias Copy = @convention(c) () -> Unmanaged<CFDictionary>?
    guard let sym = dlsym(rtldDefault, "IOPMCopySystemPowerSettings") else { return nil }
    let settings = unsafeBitCast(sym, to: Copy.self)()?.takeRetainedValue() as? [String: Any]
    return settings?["SleepDisabled"] as? Bool
}

struct UnexplainedSleepDisabledWarning: View {
    @EnvironmentObject var m: AppModel
    static let command = "sudo pmset -a disablesleep 0"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tr("Sleep is disabled for no reason (another tool or left over from a stop)"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            if m.error == nil && m.status != nil {
                Button(tr("Turn Sleep Back On")) { m.run(.resetSleep); m.refresh() }
            } else {
                Text(tr("Run in Terminal:")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(Self.command).font(.caption.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button(tr("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.command, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        }
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
    func localized(_ language: String) -> some View {
        id(language).environment(\.locale, appLocale)
    }
}
