import Foundation

/// Label centres pushed apart by at least gap, kept inside 0...height while they fit.
func spreadLabels(_ y: [Double], gap: Double, height: Double) -> [Double] {
    var y = y
    for i in y.indices.dropFirst() { y[i] = max(y[i], y[i - 1] + gap) }
    if let last = y.indices.last { y[last] = min(y[last], height - gap / 2) }
    for i in y.indices.dropLast().reversed() { y[i] = min(y[i], y[i + 1] - gap) }
    return y
}

/// Left edge of a menu window of `width` centred under `anchor` (the status item's x span), kept `margin` inside `screen`
/// (the x span of the screen's visible frame, global coordinates). Wider than the screen: pinned to the left margin.
func centeredMenuX(width: Double, under anchor: ClosedRange<Double>, in screen: ClosedRange<Double>, margin: Double) -> Double {
    let x = (anchor.lowerBound + anchor.upperBound - width) / 2
    return max(min(x, screen.upperBound - margin - width), screen.lowerBound + margin)
}

/// SF Symbol for a USB device name.
// ponytail: substring match on Apple product names; anything else gets the generic connector.
func deviceIcon(_ name: String?) -> String {
    let d = name?.lowercased() ?? ""
    return d.contains("iphone") ? "iphone" : d.contains("ipad") ? "ipad" : d.contains("airpods") ? "airpods" : "cable.connector"
}
