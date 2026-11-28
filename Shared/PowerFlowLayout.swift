import Foundation

struct FlowSideLayout {
    let shares: [Double]
    let height: Double
    let heights: [Double]
    let pointsPerShare: [Double]
    let tops: [Double]

    init(watts: [Double], totalHeight: Double, gap: Double, minNodeHeight: Double = 0) {
        let total = watts.reduce(0, +)
        let shares = watts.map { $0 / total }
        let sideHeight = totalHeight - gap * Double(watts.count - 1)
        var y = 0.0
        self.shares = shares
        height = sideHeight
        (heights, pointsPerShare) = flowNodeHeights(shares: shares, total: sideHeight, minHeight: minNodeHeight)
        tops = heights.map { let top = y; y += $0 + gap; return top }
    }
}

private func flowNodeHeights(shares: [Double], total: Double, minHeight: Double) -> (heights: [Double], pointsPerShare: [Double]) {
    let floor = min(minHeight, total / Double(2 * shares.count))
    var raised = Set<Int>(), scale = total
    while true {
        let tooThin = shares.indices.filter { !raised.contains($0) && shares[$0] * scale < floor }
        if tooThin.isEmpty {
            return (shares.indices.map { raised.contains($0) ? floor : shares[$0] * scale },
                    shares.indices.map { !raised.contains($0) ? scale : shares[$0] > 0 ? floor / shares[$0] : 0 })
        }
        raised.formUnion(tooThin)
        let freeShares = shares.indices.filter { !raised.contains($0) }.map { shares[$0] }.reduce(0, +)
        scale = (total - Double(raised.count) * floor) / freeShares
    }
}

struct FlowBand: Equatable {
    let source: Int
    let sink: Int
    let sourceTop: Double
    let sourceHeight: Double
    let sinkTop: Double
    let sinkHeight: Double
}

func flowBands(from src: FlowSideLayout, to dst: FlowSideLayout) -> [FlowBand] {
    var offS = src.tops, offD = dst.tops
    var remS = src.shares, remD = dst.shares
    var i = 0, j = 0
    var bands: [FlowBand] = []
    while i < remS.count && j < remD.count {
        let w = min(remS[i], remD[j])
        let ha = w * src.pointsPerShare[i], hb = w * dst.pointsPerShare[j]
        if ha > 0.5 || hb > 0.5 { bands.append(FlowBand(source: i, sink: j, sourceTop: offS[i], sourceHeight: ha, sinkTop: offD[j], sinkHeight: hb)) }
        offS[i] += ha; offD[j] += hb
        remS[i] -= w; remD[j] -= w
        if remS[i] <= 1e-6 { i += 1 }
        if remD[j] <= 1e-6 { j += 1 }
    }
    return bands
}

struct FlowCrest: Equatable {
    let centerX: Double
    let halfWidth: Double
}

func flowCrest(phaseSeconds: Double, fromX x0: Double, toX x1: Double) -> FlowCrest {
    let cycleProgress = (phaseSeconds / flowCrestPeriodSeconds).truncatingRemainder(dividingBy: 1)
    let crest = cycleProgress * flowCrestTravelRatio + flowCrestStartRatio
    return FlowCrest(centerX: x0 + (x1 - x0) * crest, halfWidth: (x1 - x0) * flowCrestHalfWidthRatio)
}
