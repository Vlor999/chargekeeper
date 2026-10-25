import Foundation
import IOKit
import IOKit.pwr_mgt

struct Reading {
    var percent = 0
    var hardwarePercent: Int?
    var adapter = false
    var temperature: Double?
    var adapterWatts = 0.0
    var adapterRatedWatts: Int?
    var systemWatts = 0.0
    var batteryWatts = 0.0
}

func readBattery() -> Reading? {
    let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard s != 0 else { return nil }
    defer { IOObjectRelease(s) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let p = props?.takeRetainedValue() as? [String: Any] else { return nil }

    var r = Reading()
    let cur = p["CurrentCapacity"] as? Int ?? 0, max = p["MaxCapacity"] as? Int ?? 100
    r.percent = max > 0 ? cur * 100 / max : cur  // Intel reports mAh, Apple Silicon percent
    r.adapter = p["ExternalConnected"] as? Bool ?? false
    let data = p["BatteryData"] as? [String: Any] ?? [:]
    if let raw = p["AppleRawCurrentCapacity"] as? Int, let rawMax = p["AppleRawMaxCapacity"] as? Int, rawMax > 0 {
        r.hardwarePercent = raw * 100 / rawMax
    } else if let rem = data["RemainingCapacity"] as? Int, let full = data["FullChargeCapacity"] as? Int, full > 0 {
        r.hardwarePercent = rem * 100 / full
    }
    // Amperage is a signed value stored as unsigned in IORegistry.
    let amps = Double(Int64(truncatingIfNeeded: (p["Amperage"] as? NSNumber)?.int64Value ?? 0))
    let volts = Double(p["Voltage"] as? Int ?? 0)
    r.batteryWatts = amps * volts / 1e6
    let tele = p["PowerTelemetryData"] as? [String: Any] ?? [:]
    r.adapterWatts = r.adapter ? Double(tele["SystemPowerIn"] as? Int ?? 0) / 1000 : 0
    r.adapterRatedWatts = (p["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
    r.systemWatts = Double(tele["SystemLoad"] as? Int ?? 0) / 1000
    r.temperature = smcTemperature()
    return r
}

private func smcRead(_ key: String) -> [UInt8]? {
    var buf = [UInt8](repeating: 0, count: 32)
    var len: UInt32 = 0
    return smc_read(key, &buf, &len) == 0 ? Array(buf.prefix(Int(len))) : nil
}

@discardableResult
private func smcWrite(_ key: String, _ bytes: [UInt8]) -> Bool {
    let ok = smc_write(key, bytes, UInt32(bytes.count)) == 0
    if !ok { log("SMC write \(key) failed (root?)") }
    return ok
}

/// Battery temperature: TB0T is a little-endian float on Apple Silicon, sp78 on Intel.
func smcTemperature() -> Double? {
    guard let b = smcRead("TB0T") else { return nil }
    if b.count == 4 { return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)) }
    if b.count == 2 { return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 }
    return nil
}

/// Applies Action to the hardware. SMC keys used by charge limiters on Apple Silicon:
///  CHTE (4 bytes, macOS 15+) or CH0B+CH0C (1 byte) inhibit charging; CHIE or CH0I force discharge.
///  macOS 26+ without inhibit key: native MCL (80-100) via PowerUI, below 80 emulated by discharge pulses.
final class Backend {
    let inhibitKey: String? = ["CHTE", "CH0B"].first { smc_has($0) != 0 }
    let dischargeKey: String? = ["CHIE", "CH0I"].first { smc_has($0) != 0 }
    let native = mcl_available() != 0
    private var lastMCL: Int?
    private var lastInhibit: Bool?
    private var lastDischarge: Bool?
    private var lastLED: LEDColor?

    func apply(_ a: Action, percent: Int) {
        switch a {
        case .discharge:
            setDischarge(true)
        case .charge(let t):
            setDischarge(false)
            if inhibitKey != nil { setInhibit(false) } else { setMCL(min(max(t, 80), 100)) }
        case .hold(let level):
            if inhibitKey != nil { setDischarge(false); setInhibit(true) }
            else if level >= 80 { setDischarge(false); setMCL(level) }
            else { setMCL(80); setDischarge(percent > level) }  // ponytail: ±1% sawtooth, the only option without an inhibit key
        }
    }

    /// Called when the daemon stops ("Keep the limit when the service stops").
    func shutdown(keepLimit: Bool, limit: Int) {
        setDischarge(false)
        if keepLimit {
            if inhibitKey == nil { setMCL(min(max(limit, 80), 100)) }
        } else {
            if inhibitKey != nil { setInhibit(false) } else { setMCL(100) }
        }
        setLED(.system)
    }

    func setInhibit(_ on: Bool) {
        guard let k = inhibitKey, lastInhibit != on else { return }
        let ok = k == "CHTE" ? smcWrite(k, [on ? 1 : 0, 0, 0, 0])
                             : smcWrite("CH0B", [on ? 2 : 0]) && smcWrite("CH0C", [on ? 2 : 0])
        if ok { lastInhibit = on }
    }

    func setDischarge(_ on: Bool) {
        guard let k = dischargeKey, lastDischarge != on else { return }
        if smcWrite(k, [on ? (k == "CHIE" ? 8 : 1) : 0]) { lastDischarge = on }
    }

    func setMCL(_ limit: Int) {
        guard native, lastMCL != limit else { return }
        if mcl_set(Int32(limit)) == 0 { lastMCL = limit } else { log("MCL \(limit) failed") }
    }

    // ponytail: ACLC blink value (6) unverified on MagSafe 2, adjust here if colors are off.
    func setLED(_ c: LEDColor) {
        guard lastLED != c, smc_has("ACLC") != 0 else { return }
        let v: UInt8 = switch c { case .system: 0; case .off: 1; case .green: 3; case .orange: 4; case .orangeBlink: 6 }
        if smcWrite("ACLC", [v]) { lastLED = c }
    }
}

/// pmset disablesleep equivalent; keeps a closed lid awake while charging to limit or discharging.
func setSleepDisabled(_ on: Bool) -> Bool {
    IOPMSetSystemPowerSetting("SleepDisabled" as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse)) == kIOReturnSuccess
}

func pmset(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = args
    do { try p.run(); p.waitUntilExit() } catch { log("pmset failed: \(error)") }
}

func log(_ s: String) {
    print("\(ISO8601DateFormatter().string(from: Date())) \(s)")
    fflush(stdout)
}
