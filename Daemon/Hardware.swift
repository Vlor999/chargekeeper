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
    var amperage: Int?  // mA, >0 charging
    var ports: [PortPower] = []
    var rawMaxCapacity: Int?  // mAh
    var nominalCapacity: Int?
    var designCapacity: Int?
    var cycleCount: Int?
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
    // Apple Silicon keeps the mAh capacities only in BatteryData; top level first for other models.
    func int(_ k: String) -> Int? { p[k] as? Int ?? data[k] as? Int }
    r.rawMaxCapacity = int("AppleRawMaxCapacity") ?? data["FullChargeCapacity"] as? Int
    r.nominalCapacity = int("NominalChargeCapacity")
    r.designCapacity = int("DesignCapacity")
    r.cycleCount = int("CycleCount")
    if let raw = p["AppleRawCurrentCapacity"] as? Int, let rawMax = p["AppleRawMaxCapacity"] as? Int, rawMax > 0 {
        r.hardwarePercent = raw * 100 / rawMax
    } else if let rem = data["RemainingCapacity"] as? Int, let full = data["FullChargeCapacity"] as? Int, full > 0 {
        r.hardwarePercent = rem * 100 / full
    }
    // Amperage is a signed value stored as unsigned in IORegistry.
    let amps = Double(Int64(truncatingIfNeeded: (p["Amperage"] as? NSNumber)?.int64Value ?? 0))
    let volts = Double(p["Voltage"] as? Int ?? 0)
    r.batteryWatts = amps * volts / 1e6
    r.amperage = p["Amperage"] == nil ? nil : Int(amps)
    let tele = p["PowerTelemetryData"] as? [String: Any] ?? [:]
    r.adapterWatts = r.adapter ? Double(tele["SystemPowerIn"] as? Int ?? 0) / 1000 : 0
    r.adapterRatedWatts = (p["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
    r.systemWatts = Double(tele["SystemLoad"] as? Int ?? 0) / 1000
    // Measured per USB-C port (phone, earbuds charging from the Mac), in mW.
    let out = (p["PowerOutDetails"] as? [[String: Any]] ?? []).compactMap { d in
        (d["PortIndex"] as? Int).map { port in
            // Non-PD devices (AirPods case) report PDPowermW 0: fall back to the configured voltage × current.
            let pd = d["PDPowermW"] as? Int ?? 0
            let mw = pd > 0 ? pd : (d["ConfiguredVoltage"] as? Int ?? 0) * (d["ConfiguredCurrent"] as? Int ?? 0) / 1000
            return (port: port, watts: Double(d["Watts"] as? Int ?? 0) / 1000, max: mw > 0 ? Double(mw) / 1000 : nil)
        }
    }
    // A device draws power before it enumerates: look again while a charging port has no name yet.
    let active = out.filter { $0.watts > 0.1 }.map(\.port)
    if active != portNames.ports || active.contains(where: { portNames.names[$0] == nil }) {
        portNames = (active, active.isEmpty ? [:] : usbPortNames())
    }
    r.ports = out.map { PortPower(name: portNames.names[$0.port], watts: $0.watts, maxWatts: $0.max) }
    r.temperature = smcTemperature()
    return r
}

// ponytail: refreshed when the set of charging ports changes; a device swapped within one tick keeps the old name.
private var portNames: (ports: [Int], names: [Int: String]) = ([], [:])

/// Name of the USB device plugged straight into each USB-C port, keyed by the port number of PowerOutDetails.
// ponytail: direct device only, hubs skipped: a device behind a hub or dock has no name.
// PortIndex matches usb-c-port-number (both from 1) on the Mac checked.
private func usbPortNames() -> [Int: String] {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS else { return [:] }
    defer { IOObjectRelease(it) }
    var names: [Int: String] = [:]
    while case let d = IOIteratorNext(it), d != 0 {
        defer { IOObjectRelease(d) }
        var port: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(d, kIOServicePlane, &port) == KERN_SUCCESS else { continue }
        defer { IOObjectRelease(port) }
        // Only on the XHCI ports of the Mac itself (not hub ports): a little-endian UInt32.
        guard let n = IORegistryEntryCreateCFProperty(port, "usb-c-port-number" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data, n.count >= 4,
              (IORegistryEntryCreateCFProperty(d, "bDeviceClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) != 9,  // hub
              let raw = IORegistryEntryCreateCFProperty(d, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { continue }
        // Device-supplied text: no control characters, bounded length.
        let name = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(64).map(Character.init))
        let index = Int(n.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        names[index] = min(names[index] ?? name, name)  // two devices on one port: same pick whatever the iteration order
    }
    return names
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
    /// The last hold or discharge applied is in effect: every write it needed succeeded and its keys exist.
    private(set) var inControl = false

    func apply(_ a: Action, percent: Int) {
        switch a {
        case .discharge:
            inControl = setDischarge(true)
        case .charge(let t):
            setDischarge(false)
            if inhibitKey != nil { setInhibit(false) } else { setMCL(min(max(t, 80), 100)) }
            inControl = false
        case .hold(let level):
            if inhibitKey != nil { setDischarge(false); inControl = setInhibit(true) }
            else if level >= 80 { setDischarge(false); inControl = setMCL(level) }
            else {  // ponytail: ±1% sawtooth, the only option without an inhibit key
                let mcl = setMCL(80)
                let discharge = setDischarge(percent > level)
                inControl = mcl && discharge && dischargeKey != nil
            }
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

    /// The setters return whether the requested state is in effect. Without the key, "off" is in effect and "on" is not.
    @discardableResult
    func setInhibit(_ on: Bool) -> Bool {
        guard let k = inhibitKey else { return !on }
        guard lastInhibit != on else { return true }
        let ok = k == "CHTE" ? smcWrite(k, [on ? 1 : 0, 0, 0, 0])
                             : smcWrite("CH0B", [on ? 2 : 0]) && smcWrite("CH0C", [on ? 2 : 0])
        if ok { lastInhibit = on }
        return ok
    }

    @discardableResult
    func setDischarge(_ on: Bool) -> Bool {
        guard let k = dischargeKey else { return !on }
        guard lastDischarge != on else { return true }
        let ok = smcWrite(k, [on ? (k == "CHIE" ? 8 : 1) : 0])
        if ok { lastDischarge = on }
        return ok
    }

    @discardableResult
    func setMCL(_ limit: Int) -> Bool {
        guard native else { return false }
        guard lastMCL != limit else { return true }
        let ok = mcl_set(Int32(limit)) == 0
        if ok { lastMCL = limit } else { log("MCL \(limit) failed") }
        return ok
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
