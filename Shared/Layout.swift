import Foundation

// ponytail: only the last centre is clamped, to height - gap / 2; a crowded column pushes the first centres below 0 (https://github.com/Vlor999/chargekeeper/issues/69)
func spreadLabels(_ y: [Double], gap: Double, height: Double) -> [Double] {
    var y = y
    for i in y.indices.dropFirst() { y[i] = max(y[i], y[i - 1] + gap) }
    if let last = y.indices.last { y[last] = min(y[last], height - gap / 2) }
    for i in y.indices.dropLast().reversed() { y[i] = min(y[i], y[i + 1] - gap) }
    return y
}

func centeredMenuX(width: Double, under statusItemSpan: ClosedRange<Double>, in visibleScreenSpan: ClosedRange<Double>, margin: Double) -> Double {
    let x = (statusItemSpan.lowerBound + statusItemSpan.upperBound - width) / 2
    return max(min(x, visibleScreenSpan.upperBound - margin - width), visibleScreenSpan.lowerBound + margin)
}

func deviceIcon(_ name: String?) -> String {
    let lowercasedName = name?.lowercased() ?? ""
    return usbDeviceSymbolsByNameFragment.first { lowercasedName.contains($0.fragment) }?.symbol ?? genericUSBDeviceSymbol
}
