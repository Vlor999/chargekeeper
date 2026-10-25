import ServiceManagement
import Sparkle
import SwiftUI

@main
struct JaugeApp: App {
    @StateObject var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            Image(nsImage: {
                let i = NSImage(named: "MenuIcon")!
                i.size = NSSize(width: 18, height: 18)
                i.isTemplate = true
                return i
            }())
        }
        .menuBarExtraStyle(.window)
        Window("Tableau de bord", id: "dashboard") { DashboardView().environmentObject(model) }
            .windowResizability(.contentSize)
        Settings { SettingsView().environmentObject(model) }
    }
}

final class AppModel: ObservableObject {
    @Published var status: Status?
    @Published var error: String?
    @Published var serviceStatus: SMAppService.Status = .notRegistered
    let service = SMAppService.daemon(plistName: "com.vlor999.jauge.daemon.plist")
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var timer: Timer?

    init() {
        // First launch: register the root service; macOS then asks for approval in Login Items.
        if service.status == .notRegistered { enableService() }
        refresh()
        // ponytail: 2s polling of a local socket; push notifications if it ever matters
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
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
        case .charging: "En charge"
        case .pause: "Charge suspendue"
        case .idle: "Au repos"
        case .discharging: "Décharge"
        case .topup: "Charge à 100 %"
        case .heatProtect: "Protection thermique"
        case .calibration: "Calibration"
        case .exit: "Arrêté"
        }
    }
}

extension CalibrationPhase {
    var label: String {
        switch self {
        case .chargeFull: "1/5 Charge à 100 %"
        case .dischargeTo10: "2/5 Décharge à 10 %"
        case .rechargeFull: "3/5 Recharge à 100 %"
        case .hold: "4/5 Pause 1 h à 100 %"
        case .returnToLimit: "5/5 Retour à la limite"
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
                Button("Tableau de bord") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                SettingsLink { Text("Réglages…") }
                Spacer()
                Menu {
                    Button("Rechercher des mises à jour…") { m.updater.checkForUpdates(nil) }
                    Button("Quitter Jauge") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding()
        .frame(width: 320)
    }

    /// The root service controls charging; without it the app is only a remote control.
    @ViewBuilder var serviceSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Service de charge inactif").font(.headline)
            switch m.serviceStatus {
            case .requiresApproval:
                Text("Autorisez « Jauge » dans Réglages Système > Général > Ouverture > Autoriser en arrière-plan.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Ouvrir Réglages Système") { SMAppService.openSystemSettingsLoginItems() }
            case .enabled:
                Text("Démarrage du service…").font(.caption).foregroundStyle(.secondary)
            default:
                Text("Jauge a besoin d'un service système pour piloter la charge.").font(.caption).foregroundStyle(.secondary)
                Button("Activer le service") { m.enableService() }
            }
        }
    }

    @ViewBuilder func content(_ s: Status) -> some View {
        let r = s.runtime
        HStack(alignment: .firstTextBaseline) {
            Text("\(s.percent) %").font(.system(size: 34, weight: .semibold))
            VStack(alignment: .leading) {
                Text(r.state.label).font(.headline)
                Text("Matériel \(s.hardwarePercent.map { "\($0) %" } ?? "--") · \(s.temperature.map { String(format: "%.1f °C", $0) } ?? "--")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if let p = r.calibration { Text(p.label).font(.caption).foregroundStyle(.orange) }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Limite de recharge")
                Spacer()
                TextField("", value: Binding(get: { s.config.limit }, set: { m.run(.setLimit($0)) }), format: .number)
                    .frame(width: 44).multilineTextAlignment(.trailing)
                Text("%")
            }
            Slider(value: Binding(get: { limit ?? Double(s.config.limit) }, set: { limit = $0 }), in: 20...100, step: 1) { editing in
                if !editing, let l = limit { m.run(.setLimit(Int(l))); limit = nil }
            }
            if s.config.idle {
                Text("Repos : \(max(s.config.limit - s.config.idleRange, 0))–\(s.config.limit) %")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        HStack {
            if !s.config.autoDischarge {
                Toggle("Décharge", isOn: Binding(get: { r.discharge }, set: { m.run(.discharge($0)) }))
                    .disabled(s.percent <= s.config.limit && !r.discharge)
            }
            Toggle("Charger à 100 %", isOn: Binding(get: { r.topUp }, set: { m.run(.topUp($0)) }))
        }
        .toggleStyle(.button)
        HStack {
            Button(r.calibration == nil ? "Démarrer la calibration" : "Arrêter la calibration") { m.run(.calibrate(r.calibration == nil)) }
            Button("Suspendre") { m.run(.pause) }
        }

        if flowInMenu { PowerFlow(s: s).frame(height: 110) }
        if !s.nativeLimit { Text("Limite native indisponible : contrôle SMC uniquement").font(.caption2).foregroundStyle(.secondary) }
    }
}
