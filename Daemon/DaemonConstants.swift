import Foundation

let stateDir = "/Library/Application Support/Jauge"
let statePath = stateDir + "/state.json"
let serviceTickInterval: TimeInterval = 5
let appleLimitReadInterval: TimeInterval = 10 * 60
let nativeChargeLimitPercentRange = 80...100

let socketMode: mode_t = 0o660
let adminGroupName = "admin"
let adminGroupFallbackGID: gid_t = 80
let socketClientStallLimitSeconds = 2

let logFileMode: mode_t = 0o644
let logFolderMode: mode_t = 0o755
let permissionBitsMask: mode_t = 0o7777

let usbHubDeviceClass = 9
let usbDeviceNameMaxLength = 64

enum SystemPowerMessage: UInt32 {
    case canSystemSleep = 0xe000_0270
    case systemWillSleep = 0xe000_0280
    case systemHasPoweredOn = 0xe000_0300
}

enum SMCKey {
    static let chargeInhibit = "CHTE"
    static let chargeInhibitLegacyB = "CH0B"
    static let chargeInhibitLegacyC = "CH0C"
    static let forceDischarge = "CHIE"
    static let forceDischargeLegacy = "CH0I"
    static let batteryTemperature = "TB0T"
    static let chargerLED = "ACLC"
}

enum SMCValue {
    static let chargeInhibitLegacyOn: UInt8 = 2
    static let forceDischargeOn: UInt8 = 8
    static let forceDischargeLegacyOn: UInt8 = 1
}

let stopSignals = [SIGTERM, SIGINT]
let signalsIgnoredByService = [SIGPIPE] + stopSignals
