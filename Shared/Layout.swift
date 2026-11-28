import Foundation

func spreadLabels(_ y: [Double], gap: Double, height: Double) -> [Double] {
    guard Double(y.count) * gap <= height else {
        let slot = height / Double(y.count)
        return y.indices.map { (Double($0) + 0.5) * slot }
    }
    var y = y
    for i in y.indices { y[i] = max(y[i], i == 0 ? gap / 2 : y[i - 1] + gap) }
    for i in y.indices.reversed() { y[i] = min(y[i], i == y.count - 1 ? height - gap / 2 : y[i + 1] - gap) }
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
