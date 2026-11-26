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
    var batteryChargeMilliamps: Int?
    var ports: [PortPower] = []
    var rawMaxCapacityMAh: Int?
    var nominalCapacityMAh: Int?
    var designCapacityMAh: Int?
    var cycleCount: Int?
}

private func watts(milliwatts: Int) -> Double { Double(milliwatts) / 1000 }

private func signedIORegistryValue(_ v: Any?) -> Int64 { Int64(truncatingIfNeeded: (v as? NSNumber)?.int64Value ?? 0) }

private func negotiatedMilliwatts(_ port: [String: Any]) -> Int {
    let pdMilliwatts = port["PDPowermW"] as? Int ?? 0
    let configuredMilliwatts = (port["ConfiguredVoltage"] as? Int ?? 0) * (port["ConfiguredCurrent"] as? Int ?? 0) / 1000
    return pdMilliwatts > 0 ? pdMilliwatts : configuredMilliwatts
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
    r.percent = max > 0 ? cur * 100 / max : cur
    r.adapter = p["ExternalConnected"] as? Bool ?? false
    let data = p["BatteryData"] as? [String: Any] ?? [:]
    func topLevelOrBatteryData(_ k: String) -> Int? { p[k] as? Int ?? data[k] as? Int }
    r.rawMaxCapacityMAh = topLevelOrBatteryData("AppleRawMaxCapacity") ?? data["FullChargeCapacity"] as? Int
    r.nominalCapacityMAh = topLevelOrBatteryData("NominalChargeCapacity")
    r.designCapacityMAh = topLevelOrBatteryData("DesignCapacity")
    r.cycleCount = topLevelOrBatteryData("CycleCount")
    if let raw = p["AppleRawCurrentCapacity"] as? Int, let rawMax = p["AppleRawMaxCapacity"] as? Int, rawMax > 0 {
        r.hardwarePercent = raw * 100 / rawMax
    } else if let rem = data["RemainingCapacity"] as? Int, let full = data["FullChargeCapacity"] as? Int, full > 0 {
        r.hardwarePercent = rem * 100 / full
    }
    let milliamps = Double(signedIORegistryValue(p["Amperage"]))
    let millivolts = Double(p["Voltage"] as? Int ?? 0)
    r.batteryWatts = milliamps * millivolts / 1e6
    r.batteryChargeMilliamps = p["Amperage"] == nil ? nil : Int(milliamps)
    let tele = p["PowerTelemetryData"] as? [String: Any] ?? [:]
    r.adapterWatts = r.adapter ? watts(milliwatts: tele["SystemPowerIn"] as? Int ?? 0) : 0
    r.adapterRatedWatts = (p["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
    r.systemWatts = watts(milliwatts: tele["SystemLoad"] as? Int ?? 0)
    let usbCOutputs = (p["PowerOutDetails"] as? [[String: Any]] ?? []).compactMap { d in
        (d["PortIndex"] as? Int).map { port in
            let mw = negotiatedMilliwatts(d)
            return (port: port, watts: watts(milliwatts: d["Watts"] as? Int ?? 0), max: mw > 0 ? watts(milliwatts: mw) : nil)
        }
    }
    let active = usbCOutputs.filter { $0.watts > 0.1 }.map(\.port)
    if portNamesNeedRefresh(activePorts: active) {
        portNames = (active, active.isEmpty ? [:] : usbDeviceNamesByPortIndex())
    }
    r.ports = usbCOutputs.map { PortPower(deviceName: portNames.names[$0.port], watts: $0.watts, negotiatedWatts: $0.max) }
    r.temperature = smcTemperature()
    return r
}

// ponytail: names are refreshed only when the set of charging ports changes, so a device swapped within one tick keeps the old name (ticket to open)
private var portNames: (ports: [Int], names: [Int: String]) = ([], [:])

private func portNamesNeedRefresh(activePorts: [Int]) -> Bool {
    let activePortStillUnnamed = activePorts.contains { portNames.names[$0] == nil }
    return activePorts != portNames.ports || activePortStillUnnamed
}

private func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

private func macUSBCPortNumber(_ port: io_registry_entry_t) -> Int? {
    guard let n = registryProperty(port, "usb-c-port-number") as? Data, n.count >= 4 else { return nil }
    return Int(n.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
}

private func isUSBHub(_ device: io_registry_entry_t) -> Bool { registryProperty(device, "bDeviceClass") as? Int == usbHubDeviceClass }

private func sanitizedDeviceName(_ raw: String) -> String {
    String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(usbDeviceNameMaxLength).map(Character.init))
}

private func iterationOrderIndependentPick(_ existing: String?, _ new: String) -> String { min(existing ?? new, new) }

// ponytail: only devices plugged straight into a Mac port are named; a device behind a hub or dock has none (ticket to open)
// ponytail: PortIndex of PowerOutDetails is assumed equal to usb-c-port-number (both from 1), checked on one Mac only (ticket to open)
private func usbDeviceNamesByPortIndex() -> [Int: String] {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS else { return [:] }
    defer { IOObjectRelease(it) }
    var names: [Int: String] = [:]
    while case let d = IOIteratorNext(it), d != 0 {
        defer { IOObjectRelease(d) }
        var port: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(d, kIOServicePlane, &port) == KERN_SUCCESS else { continue }
        defer { IOObjectRelease(port) }
        guard let index = macUSBCPortNumber(port), !isUSBHub(d),
              let raw = registryProperty(d, "USB Product Name") as? String else { continue }
        names[index] = iterationOrderIndependentPick(names[index], sanitizedDeviceName(raw))
    }
    return names
}

private func smcRead(_ key: String) -> [UInt8]? {
    var buf = [UInt8](repeating: 0, count: kSMCBytesSize)
    var len: UInt32 = 0
    return smc_read(key, &buf, &len) == 0 ? Array(buf.prefix(Int(len))) : nil
}

private var smcKeysLoggedAsFailing: Set<String> = []

@discardableResult
private func smcWrite(_ key: String, _ bytes: [UInt8]) -> Bool {
    let ok = smc_write(key, bytes, UInt32(bytes.count)) == 0
    if ok { smcKeysLoggedAsFailing.remove(key) } else if smcKeysLoggedAsFailing.insert(key).inserted { log("SMC write \(key) failed (root?)", .error) }
    return ok
}

private func float32LittleEndian(_ b: [UInt8]) -> Double {
    Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
}

private func fixedPointSP78(_ b: [UInt8]) -> Double { Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 }

func smcTemperature() -> Double? {
    guard let b = smcRead(SMCKey.batteryTemperature) else { return nil }
    switch b.count {
    case 4: return float32LittleEndian(b)
    case 2: return fixedPointSP78(b)
    default: return nil
    }
}

enum LimitStrategy { case smcInhibit, nativeLimit }

final class Backend {
    let inhibitKey: String? = [SMCKey.chargeInhibit, SMCKey.chargeInhibitLegacyB].first { smc_has($0) != 0 }
    let dischargeKey: String? = [SMCKey.forceDischarge, SMCKey.forceDischargeLegacy].first { smc_has($0) != 0 }
    let native = mcl_available() != 0
    private var lastMCL: Int?
    private var lastInhibit: Bool?
    private var lastDischarge: Bool?
    private var lastLED: LEDColor?
    private(set) var limitIsEnforced = false

    var limitStrategy: LimitStrategy { inhibitKey != nil ? .smcInhibit : .nativeLimit }
    var nativeLimitBelongsToUser: Bool { native && limitStrategy == .smcInhibit }

    func apply(_ a: Action, percent: Int) {
        switch a {
        case .discharge:
            limitIsEnforced = setDischarge(true)
        case .charge(let t):
            setDischarge(false)
            switch limitStrategy {
            case .smcInhibit: setInhibit(false)
            case .nativeLimit: setMCL(clamp(t, to: nativeChargeLimitPercentRange))
            }
            limitIsEnforced = false
        case .hold(let level):
            switch limitStrategy {
            case .smcInhibit: setDischarge(false); limitIsEnforced = setInhibit(true)
            case .nativeLimit where level >= nativeChargeLimitPercentRange.lowerBound: setDischarge(false); limitIsEnforced = setMCL(level)
            case .nativeLimit: limitIsEnforced = holdBelowNativeLimitByDischargePulses(level: level, percent: percent)
            }
        }
    }

    private func holdBelowNativeLimitByDischargePulses(level: Int, percent: Int) -> Bool {
        let mcl = setMCL(nativeChargeLimitPercentRange.lowerBound)
        let discharge = setDischarge(percent > level)
        return mcl && discharge && dischargeKey != nil
    }

    func shutdown(keepLimit: Bool, limit: Int) {
        setDischarge(false)
        switch (keepLimit, limitStrategy) {
        case (true, .smcInhibit): break
        case (true, .nativeLimit): setMCL(clamp(limit, to: nativeChargeLimitPercentRange))
        case (false, .smcInhibit): setInhibit(false)
        case (false, .nativeLimit): setMCL(Int(kMCLDisabledLimit))
        }
        setLED(.system)
    }

    private func inEffectWithoutKey(_ on: Bool) -> Bool { !on }

    @discardableResult
    func setInhibit(_ on: Bool) -> Bool {
        guard let k = inhibitKey else { return inEffectWithoutKey(on) }
        guard lastInhibit != on else { return true }
        let legacyValue: UInt8 = on ? SMCValue.chargeInhibitLegacyOn : 0
        let ok = k == SMCKey.chargeInhibit ? smcWrite(k, [on ? 1 : 0, 0, 0, 0])
                                           : smcWrite(SMCKey.chargeInhibitLegacyB, [legacyValue]) && smcWrite(SMCKey.chargeInhibitLegacyC, [legacyValue])
        if ok { lastInhibit = on }
        return ok
    }

    @discardableResult
    func setDischarge(_ on: Bool) -> Bool {
        guard let k = dischargeKey else { return inEffectWithoutKey(on) }
        guard lastDischarge != on else { return true }
        let onValue = k == SMCKey.forceDischarge ? SMCValue.forceDischargeOn : SMCValue.forceDischargeLegacyOn
        let ok = smcWrite(k, [on ? onValue : 0])
        if ok { lastDischarge = on }
        return ok
    }

    @discardableResult
    func setMCL(_ limit: Int) -> Bool {
        guard native else { return false }
        guard lastMCL != limit else { return true }
        let ok = mcl_set(Int32(limit)) == 0
        if ok { lastMCL = limit } else { log("MCL \(limit) failed", .error) }
        return ok
    }

    // ponytail: the ACLC value for orangeBlink (6) is unverified on MagSafe 2 (ticket to open)
    func setLED(_ c: LEDColor) {
        guard lastLED != c, smc_has(SMCKey.chargerLED) != 0 else { return }
        let v: UInt8 = switch c { case .system: 0; case .off: 1; case .green: 3; case .orange: 4; case .orangeBlink: 6 }
        if smcWrite(SMCKey.chargerLED, [v]) { lastLED = c }
    }
}

func setSystemSleepDisabled(_ on: Bool) -> Bool {
    IOPMSetSystemPowerSetting("SleepDisabled" as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse)) == kIOReturnSuccess
}

final class KeepAwakeAssertion {
    private var id: IOPMAssertionID = 0
    private(set) var on = false

    @discardableResult
    func setHeld(_ on: Bool) -> Bool {
        guard on != self.on else { return true }
        if on {
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "ChargeKeeper keep awake" as CFString, &id)
            guard r == kIOReturnSuccess else { log("keep awake assertion failed: \(r)", .error); return false }
        } else {
            IOPMAssertionRelease(id)
            id = 0
        }
        self.on = on
        log("keep awake \(on ? "on" : "off")")
        return true
    }
}

func pmset(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = args
    do { try p.run(); p.waitUntilExit() } catch { log("pmset failed: \(error)", .error) }
}
