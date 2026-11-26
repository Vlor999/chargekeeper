import Foundation

func printStatus(_ s: Status) {
    let r = s.runtime
    print("battery \(s.percent)% (hardware \(s.hardwarePercent.map { "\($0)%" } ?? "--")), \(s.adapter ? "adapter" : "battery"), \(s.temperature.map { String(format: "%.1f°C", $0) } ?? "--")")
    print("state \(r.state.rawValue), limit \(s.config.limit)%\(r.discharge ? ", discharge" : "")\(r.topUp ? ", top-up" : "")\(r.calibration.map { ", calibration \($0.rawValue)" } ?? "")")
    print(String(format: "power: adapter %.1fW, system %.1fW, battery %+.1fW", s.adapterWatts, s.systemWatts, s.batteryChargeWatts))
    let ports = (s.usbCOutputPorts ?? []).filter { $0.watts > 0.1 }
    if !ports.isEmpty {
        print("usb-c: " + ports.map { "\($0.deviceName ?? "device") \(String(format: "%.1fW", $0.watts))\($0.negotiatedWatts.map { String(format: "/%gW", $0) } ?? "")" }.joined(separator: ", "))
    }
    if let b = s.battery {
        print("health: \(calibrationSummary(before: nil, after: b))\(b.nominalHealthPercent.map { String(format: " (nominal %.1f %%)", $0) } ?? ""), design \(b.designCapacityMAh.map { "\($0) mAh" } ?? "--")")
    }
    if let c = s.lastCalibration {
        print("last calibration \(c.end.formatted(date: .abbreviated, time: .shortened)): \(calibrationSummary(before: c.before, after: c.after))")
    }
}

func cli(_ a: [String]) -> Int32 {
    let on = a.count > 1 && a[1] == "on"
    let n = a.count > 1 ? Int(a[1]) : nil
    let cmd: Command
    switch (a.first ?? "status", n) {
    case ("status", _): cmd = .status()
    case ("limit", let n?): cmd = .setLimit(n)
    case ("discharge", let n?): cmd = .dischargeTo(n)
    case ("discharge", nil) where a.count > 1: cmd = .discharge(on)
    case ("full", _) where a.count > 1: cmd = .topUp(on)
    case ("calibrate", _) where a.count > 1: cmd = .calibrate(on)
    case ("pause", _): cmd = .pause
    case ("led", _) where a.count > 1:
        guard let c = a[1] == "auto" ? .some(nil) : LEDColor(rawValue: a[1]).map(Optional.some) else { return usage() }
        cmd = .led(c)
    case ("lowpower", _) where a.count > 1: cmd = .lowPower(on)
    case ("highpower", _) where a.count > 1: cmd = .highPower(on)
    default: return usage()
    }
    do { printStatus(try send(cmd)); return 0 } catch { print(error.localizedDescription); return 1 }
}

func usage() -> Int32 {
    print("""
    usage: chargekeeperctl daemon
           chargekeeperctl status | limit <20-100> | pause | discharge on|off|<n> | full on|off | calibrate on|off
           chargekeeperctl led auto|system|off|green|orange|orangeBlink | lowpower on|off | highpower on|off
    """)
    return 1
}
