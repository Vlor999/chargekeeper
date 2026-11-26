import SwiftUI

struct LineKey: View {
    let color: Color
    let dash: [CGFloat]
    var width: CGFloat = 16

    var body: some View {
        Path { $0.move(to: CGPoint(x: 1, y: 1)); $0.addLine(to: CGPoint(x: width - 1, y: 1)) }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
            .frame(width: width, height: 2)
    }
}

extension View {
    func chartAsSingleAccessibilityElement(label: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

extension Color {
    static func viz(light: UInt32, dark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light) })
    }
}
