import Foundation

struct FlowSideLayout {
    let shares: [Double]
    let height: Double
    let tops: [Double]

    init(watts: [Double], totalHeight: Double, gap: Double) {
        let total = watts.reduce(0, +)
        let shares = watts.map { $0 / total }
        let sideHeight = totalHeight - gap * Double(watts.count - 1)
        var y = 0.0
        self.shares = shares
        height = sideHeight
        tops = shares.map { let top = y; y += $0 * sideHeight + gap; return top }
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
        let ha = w * src.height, hb = w * dst.height
        if ha > 0.5 { bands.append(FlowBand(source: i, sink: j, sourceTop: offS[i], sourceHeight: ha, sinkTop: offD[j], sinkHeight: hb)) }
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
