import AppKit
import IOKit.ps
import SwiftUI

final class BatteryLevel: ObservableObject {
    @Published private(set) var internalBatteryPercent: Int?
    private var powerSourceChanges: CFRunLoopSource?

    init() {
        internalBatteryPercent = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryLevel>.fromOpaque(context).takeUnretainedValue().update()
        }, context)?.takeRetainedValue() else { return }
        powerSourceChanges = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    deinit {
        if let powerSourceChanges { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceChanges, .defaultMode) }
    }

    private func update() {
        let p = Self.read()
        if p != internalBatteryPercent { internalBatteryPercent = p }
    }

    private static func read() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let full = d[kIOPSMaxCapacityKey] as? Int, full > 0
            else { continue }
            return min(max(cur * 100 / full, 0), 100)
        }
        return nil
    }
}

struct MenuIconLabel: View {
    @ObservedObject var battery: BatteryLevel

    var body: some View {
        Image(nsImage: menuIcon(fillRatio: Double(battery.internalBatteryPercent ?? 100) / 100))
    }
}

func menuIcon(fillRatio: Double) -> NSImage {
    let i = NSImage(size: NSSize(width: menuIconSidePoints, height: menuIconSidePoints), flipped: true) { _ in
        let t = NSAffineTransform(); t.scale(by: menuIconSidePoints / menuIconGridUnits); t.concat()
        drawGaugeTrack()
        drawGaugeArc(fillRatio: min(max(fillRatio, 0), 1))
        drawBolt()
        return true
    }
    i.isTemplate = true
    return i
}

private let gaugeCenter = NSPoint(x: menuIconGridUnits / 2, y: menuIconGridUnits / 2)
private let gaugeRadius: CGFloat = 8

private func drawGaugeTrack() {
    let track = NSBezierPath()
    track.appendArc(withCenter: gaugeCenter, radius: gaugeRadius, startAngle: menuIconGaugeStartDegrees, endAngle: menuIconGaugeStartDegrees + menuIconGaugeSweepDegrees)
    track.lineWidth = 1.6; track.lineCapStyle = .round
    NSColor.black.withAlphaComponent(0.35).setStroke(); track.stroke()
}

private func drawGaugeArc(fillRatio: Double) {
    guard fillRatio > 0 else { return }
    let arc = NSBezierPath()
    arc.appendArc(withCenter: gaugeCenter, radius: gaugeRadius, startAngle: menuIconGaugeStartDegrees, endAngle: menuIconGaugeStartDegrees + menuIconGaugeSweepDegrees * fillRatio)
    arc.lineWidth = 2.2; arc.lineCapStyle = .round
    NSColor.black.setStroke(); arc.stroke()
}

private func drawBolt() {
    NSColor.black.setFill()
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 13, y: 7.2))
    for (x, y) in [(9.4, 12.6), (12.1, 12.6), (11.1, 16.8), (14.7, 11.4), (12, 11.4)] { bolt.line(to: NSPoint(x: x, y: y)) }
    bolt.close(); bolt.fill()
}
