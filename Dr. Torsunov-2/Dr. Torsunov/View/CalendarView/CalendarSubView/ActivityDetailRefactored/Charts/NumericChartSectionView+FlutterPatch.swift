//// NumericChartSectionView+FlutterPatch.swift
////
//// Overlay + header helpers to replicate Flutter layer logic on iOS.
//// No `public` here (uses internal WorkoutDetailViewModel). Marked @MainActor to
//// access main-actor-isolated view model safely.
//
//import SwiftUI
//
//@MainActor
//struct FlutterLayerOverlay: View {
//    let viewModel: WorkoutDetailViewModel
//    var isFullScreen: Bool
//    var leftPadding: CGFloat
//    var rightPadding: CGFloat
//    var topPadding: CGFloat
//    var bottomPadding: CGFloat
//    var lineColor: Color = .secondary
//    var lineWidth: CGFloat = 1
//    var dash: [CGFloat] = [4, 4]
//    var firstLayerLabelColor: Color = .secondary
//    var firstLayerLabelFont: Font = .system(size: 10, weight: .semibold)
//
//    init(viewModel: WorkoutDetailViewModel,
//         isFullScreen: Bool,
//         leftPadding: CGFloat,
//         rightPadding: CGFloat,
//         topPadding: CGFloat,
//         bottomPadding: CGFloat,
//         lineColor: Color = .secondary,
//         lineWidth: CGFloat = 1,
//         dash: [CGFloat] = [4, 4],
//         firstLayerLabelColor: Color = .secondary,
//         firstLayerLabelFont: Font = .system(size: 10, weight: .semibold)) {
//        self.viewModel = viewModel
//        self.isFullScreen = isFullScreen
//        self.leftPadding = leftPadding
//        self.rightPadding = rightPadding
//        self.topPadding = topPadding
//        self.bottomPadding = bottomPadding
//        self.lineColor = lineColor
//        self.lineWidth = lineWidth
//        self.dash = dash
//        self.firstLayerLabelColor = firstLayerLabelColor
//        self.firstLayerLabelFont = firstLayerLabelFont
//    }
//
//    var body: some View {
//        GeometryReader { geo in
//            let width = geo.size.width
//            let height = geo.size.height
//            let plotWidth = max(0, width - leftPadding - rightPadding)
//            let plotHeight = max(0, height - topPadding - bottomPadding)
//            let transitions = viewModel.flutterLayerTransitions(isFullScreen: isFullScreen)
//            let total = viewModel.totalDurationSeconds ?? 0
//
//            ZStack(alignment: .topLeading) {
//                Canvas { ctx, size in
//                    guard total > 0, plotWidth > 0 else { return }
//
//                    for tr in transitions {
//                        let frac = max(0, min(1, tr.timeSeconds / total))
//                        let x = leftPadding + frac * plotWidth
//
//                        // dashed vertical
//                        var path = Path()
//                        path.move(to: CGPoint(x: x, y: topPadding))
//                        path.addLine(to: CGPoint(x: x, y: topPadding + plotHeight))
//
//                        ctx.stroke(path,
//                                   with: .color(lineColor),
//                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash))
//
//                        // "Layer N" only for first entries
//                        if tr.isFirstLayer {
//                            let text = Text("Layer \(tr.layer)")
//                                .font(firstLayerLabelFont)
//                                .foregroundColor(firstLayerLabelColor)
//                            let resolved = ctx.resolve(text)
//                            let textSize = resolved.measure(in: size)
//                            let tx = min(max(leftPadding, x + 4), leftPadding + plotWidth - textSize.width)
//                            let ty = topPadding + plotHeight - textSize.height
//                            ctx.draw(resolved, at: CGPoint(x: tx, y: ty), anchor: .topLeading)
//                        }
//
//                        // Optional: small sublayer badge near the top (Flutter fullscreen feel)
//                        if isFullScreen {
//                            let badge = Text("\(tr.layer).\(tr.subLayer)")
//                                .font(.system(size: 9, weight: .medium, design: .rounded))
//                                .foregroundColor(.secondary)
//                            let resolved = ctx.resolve(badge)
//                            ctx.draw(resolved, at: CGPoint(x: x + 4, y: topPadding + 2), anchor: .topLeading)
//                        }
//                    }
//                }
//            }
//        }
//        .allowsHitTesting(false)
//    }
//}
//
//// MARK: - Header helper (index-based like Flutter)
//
//enum SubLayerTotalMode {
//    case hardcoded7          // Flutter-like hardcoded "/7"
//    case seriesMaxFallback   // Use series max (or 7) when header needs a total
//}
//
//struct FlutterHeader {
//    let layer: Int?
//    let subLayer: Int?
//    let layerText: String
//    let subLayerText: String
//}
//
//enum FlutterHeaderHelper {
//
//    /// Compute header strings from a cursor pixel X.
//    /// - Parameters:
//    ///   - cursorX: pixel X inside the whole chart view (nil means no cursor)
//    ///   - plotWidth: inner plot width (without paddings)
//    ///   - leftPadding/rightPadding: paddings used for the plot area
//    ///   - sublayerTotalMode: see SubLayerTotalMode
//    @MainActor
//    static func values(viewModel: WorkoutDetailViewModel,
//                       cursorX: CGFloat?,
//                       plotWidth: CGFloat,
//                       leftPadding: CGFloat,
//                       rightPadding: CGFloat,
//                       sublayerTotalMode: SubLayerTotalMode = .seriesMaxFallback) -> FlutterHeader {
//        guard let rows = viewModel.metricObjectsArray, rows.count > 0 else {
//            return .init(layer: nil, subLayer: nil, layerText: "Layer —", subLayerText: "—/7")
//        }
//
//        // Normalized X in [0,1] by index (Flutter does floor on (x / xStep))
//        var x01: Double = 1.0
//        if let cx = cursorX {
//            let xInside = max(0, min(plotWidth, Double(cx - leftPadding)))
//            x01 = plotWidth > 0 ? xInside / Double(plotWidth) : 1.0
//        }
//
//        let layer = viewModel.layerAtNormalizedX(x01)
//        let sub = viewModel.subLayerAtNormalizedX(x01)
//
//        // Layer text
//        let layerText = layer.map { "Layer \($0)" } ?? "Layer —"
//
//        // SubLayer text
//        let total: Int = {
//            switch sublayerTotalMode {
//            case .hardcoded7:
//                return 7
//            case .seriesMaxFallback:
//                return max(viewModel.subLayerSeriesInt?.max() ?? 7, 1)
//            }
//        }()
//        let subText: String = {
//            if let s = sub { return "\(s)/\(total)" }
//            return "—/\(total)"
//        }()
//
//        return .init(layer: layer, subLayer: sub, layerText: layerText, subLayerText: subText)
//    }
//}
