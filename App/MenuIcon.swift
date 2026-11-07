import AppKit
import IOKit.ps
import SwiftUI

/// Internal battery percent, pushed by IOKit on power source changes: nothing runs in between.
final class BatteryLevel: ObservableObject {
    /// nil without an internal battery (desktop Mac).
    @Published private(set) var percent: Int?

    init() {
        percent = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        // The app lives as long as this object (owned by AppModel), so the source is never removed.
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryLevel>.fromOpaque(context).takeUnretainedValue().update()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func update() {
        let p = Self.read()
        if p != percent { percent = p }
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

/// Menu bar label: a 270° gauge filled to the battery level, full when there is no battery.
struct MenuIconLabel: View {
    @ObservedObject var battery: BatteryLevel

    var body: some View {
        Image(nsImage: menuIcon(level: Double(battery.percent ?? 100) / 100))
    }
}

/// Template image on a 24-unit grid: grey track, solid arc of `level` (0...1) of the track, bolt.
func menuIcon(level: Double) -> NSImage {
    let i = NSImage(size: NSSize(width: menuIconSize, height: menuIconSize), flipped: true) { _ in
        let t = NSAffineTransform(); t.scale(by: menuIconSize / 24); t.concat()
        let color = NSColor.black
        let c = NSPoint(x: 12, y: 12)
        let track = NSBezierPath()
        track.appendArc(withCenter: c, radius: 8, startAngle: 135, endAngle: 405)
        track.lineWidth = 1.6; track.lineCapStyle = .round
        color.withAlphaComponent(0.35).setStroke(); track.stroke()
        let p = min(max(level, 0), 1)
        if p > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: 8, startAngle: 135, endAngle: 135 + 270 * p)
            arc.lineWidth = 2.2; arc.lineCapStyle = .round
            color.setStroke(); arc.stroke()
        }
        color.setFill()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 13, y: 7.2))
        for (x, y) in [(9.4, 12.6), (12.1, 12.6), (11.1, 16.8), (14.7, 11.4), (12, 11.4)] { bolt.line(to: NSPoint(x: x, y: y)) }
        bolt.close(); bolt.fill()
        return true
    }
    i.isTemplate = true
    return i
}
