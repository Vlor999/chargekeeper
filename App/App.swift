import ServiceManagement
import Sparkle
import SwiftUI

@main
struct JaugeApp: App {
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
        Settings { SettingsView().environmentObject(model).localized(language) }
    }
}

final class AppModel: ObservableObject {
    @Published var status: Status?
    @Published var error: String?
    @Published var serviceStatus: SMAppService.Status = .notRegistered
    let service = SMAppService.daemon(plistName: "com.vlor999.jauge.daemon.plist")
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var timer: Timer?
    /// Open windows showing live data; polling and animation only run while > 0.
    var visible = 0 { didSet { if visible > 0 { refresh() } } }

    init() {
        // First launch: register the root service; macOS then asks for approval in Login Items.
        if service.status == .notRegistered { enableService() }
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
        do { status = try send(cmd); error = nil } catch { self.error = error.localizedDescription }
    }

    /// Binding into the daemon's config; every edit is pushed immediately.
    func config<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.status?.config[keyPath: kp] ?? Config()[keyPath: kp] },
                set: { v in guard var c = self.status?.config else { return }; c[keyPath: kp] = v; self.run(.setConfig(c)) })
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
    var label: String {
        switch self {
        case .chargeFull: tr("1/5 Charging to 100%")
        case .dischargeTo10: tr("2/5 Discharging to 10%")
        case .rechargeFull: tr("3/5 Recharging to 100%")
        case .hold: tr("4/5 Resting 1 h at 100%")
        case .returnToLimit: tr("5/5 Back to the limit")
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("flowInMenu") private var flowInMenu = true
    @State private var limit: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = m.status, m.error == nil { content(s) } else { serviceSetup }
            Divider()
            HStack {
                Button(tr("Dashboard")) { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                SettingsLink { Text(tr("Settings…")) }
                Spacer()
                Menu {
                    Button(tr("Check for Updates…")) { m.updater.checkForUpdates(nil) }
                    Button(tr("Quit Jauge")) { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
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
                Text(tr("Allow “Jauge” in System Settings > General > Login Items > Allow in the Background."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(tr("Open System Settings")) { SMAppService.openSystemSettingsLoginItems() }
            case .enabled:
                Text(tr("Starting the service…")).font(.caption).foregroundStyle(.secondary)
            default:
                Text(tr("Jauge needs a system service to control charging.")).font(.caption).foregroundStyle(.secondary)
                Button(tr("Turn On Service")) { m.enableService() }
            }
        }
    }

    @ViewBuilder func content(_ s: Status) -> some View {
        let r = s.runtime
        HStack(alignment: .firstTextBaseline) {
            Text("\(s.percent) %").font(.system(size: 34, weight: .semibold))
            VStack(alignment: .leading) {
                Text(r.state.label).font(.headline)
                Text(tr("Hardware %@ · %@", s.hardwarePercent.map { "\($0) %" } ?? "--", s.temperature.map { String(format: "%.1f °C", $0) } ?? "--"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if let p = r.calibration { Text(p.label).font(.caption).foregroundStyle(.orange) }

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

extension View {
    /// Rebuilds the view tree when the language changes and formats dates in that language.
    func localized(_ language: String) -> some View {
        id(language).environment(\.locale, Locale(identifier: appLanguage))
    }
}
