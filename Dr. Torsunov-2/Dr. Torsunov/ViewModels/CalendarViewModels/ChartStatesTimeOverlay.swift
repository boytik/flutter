import SwiftUI

fileprivate func __stateColor(_ key: String) -> Color {
    switch key {
    case "1": return Color(red: 0.31, green: 0.84, blue: 0.39)
    case "2": return .yellow.opacity(0.9)
    case "3": return .orange
    case "4": return Color(red: 1.0, green: 0.35, blue: 0.35)
    case "5": return .red
    default:  return .gray.opacity(0.7)
    }
}

/// Простая накладка со слоями (вертикальные линии), не зависящая от VM.
/// Передай сюда transitions и общую длительность в секундах.
public struct ChartStatesTimeOverlay: View {
    public let transitions: [StateTransition]
    public let totalSeconds: Double
    public var firstLayerLineWidth: CGFloat = 1.6
    public var otherLayerLineWidth: CGFloat = 1.0

    public init(
        transitions: [StateTransition],
        totalSeconds: Double,
        firstLayerLineWidth: CGFloat = 1.6,
        otherLayerLineWidth: CGFloat = 1.0
    ) {
        self.transitions = transitions
        self.totalSeconds = max(1, totalSeconds)
        self.firstLayerLineWidth = firstLayerLineWidth
        self.otherLayerLineWidth = otherLayerLineWidth
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(Array(transitions.enumerated()), id: \.offset) { (_, tr) in
                    let ratio = max(0, min(1, tr.timeSeconds / totalSeconds))
                    let x = CGFloat(ratio) * width
                    let color = __stateColor(tr.stateKey).opacity(tr.isFirstLayer ? 0.95 : 0.55)
                    let style = StrokeStyle(lineWidth: tr.isFirstLayer ? firstLayerLineWidth : otherLayerLineWidth,
                                            dash: tr.isFirstLayer ? [] : [3,3])
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: height))
                    }
                    .stroke(color, style: style)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
