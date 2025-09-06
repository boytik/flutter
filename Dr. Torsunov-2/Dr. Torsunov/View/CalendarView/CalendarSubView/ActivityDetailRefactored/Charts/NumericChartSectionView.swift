// DROP-IN REPLACEMENT
import SwiftUI
import Charts

fileprivate func __colorForLayer(_ layer: Int) -> Color {
    switch layer {
    case 1: return Color(red: 0.31, green: 0.84, blue: 0.39) // зелёный
    case 2: return .yellow.opacity(0.9)
    case 3: return .orange
    case 4: return Color(red: 1.0, green: 0.35, blue: 0.35)
    case 5: return .red
    default: return .gray.opacity(0.6)
    }
}

fileprivate struct NPoint: Identifiable, Hashable {
    let id = UUID()
    let time: Date
    let value: Double
}

@MainActor
struct NumericChartSectionView: View {
    // ДАННЫЕ
    let title: String
    let unit: String
    let seriesName: String
    let values: [Double]
    let timeOffsets: [Double]?        // как во Flutter — могут быть минуты/сек/мс → ниже нормализуем
    let totalMinutes: Int?

    // ОФОРМЛЕНИЕ
    var preferredHeight: CGFloat = 220
    var color: Color = .green
    var start: Date = Date()
    var totalSeconds: Double = 1

    // VM — чтобы брать слой/подслой и вертикали слоёв
    @ObservedObject var vm: WorkoutDetailViewModel

    // КУРСОР
    @State private var selectedIndex: Int? = nil
    @State private var cursorX01: Double? = nil       // 0…1 как во Flutter

    // ===== нормализация времени =====
    /// Нормализация like Flutter: ms → s; sec остаются sec; min → s.
    /// Эвристика:
    /// - max > 12ч → это миллисекунды
    /// - max > 6 мин (360с) → это секунды
    /// - иначе смотрим средний шаг: если шаг < 2 → секунды, иначе — минуты.
    private var offsetsSeconds: [Double]? {
        guard let t = timeOffsets, !t.isEmpty else { return nil }
        let maxV = t.max() ?? 0
        if maxV > 12 * 3600 { return t.map { $0 / 1000.0 } }    // ms → s
        if maxV > 360 { return t }                              // уже секунды (длина > 6 мин)
        // оценим шаг
        if t.count >= 2 {
            var diffs: [Double] = []
            diffs.reserveCapacity(t.count - 1)
            for i in 1..<t.count { diffs.append(abs(t[i] - t[i-1])) }
            let avgStep = (diffs.reduce(0,+) / Double(max(1, diffs.count)))
            if avgStep < 2.0 { return t }                       // похоже на секунды/доли секунд
        }
        return t.map { $0 * 60.0 }                              // считаем минуты → секунды
    }

    /// Итоговая длительность по тем же правилам, что и Flutter/внешняя секция
    private var effectiveTotalSeconds: Double {
        var candidates: [Double] = []
        if totalSeconds > 1 { candidates.append(totalSeconds) }                 // из родителя
        if let t = offsetsSeconds, let last = t.last { candidates.append(last) } // из собственных offsets
        if let m = totalMinutes, m > 0 { candidates.append(Double(m) * 60.0) }   // из DTO
        return max(60, candidates.max() ?? 60)
    }

    var body: some View {
        let T = effectiveTotalSeconds
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 2)

            header(T: T)

            ZStack(alignment: .topTrailing) {
                chart(T: T)
                    .frame(height: preferredHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))

                Button {
                    showFullScreen(T: T)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(8)
                .accessibilityLabel("Открыть во весь экран")
            }
        }
        .id("num-\(Int(T.rounded()))")
    }

    // MARK: Header

    private func header(T: Double) -> some View {
        let (layerText, subText) = headerLayerTexts()
        return HStack(spacing: 16) {
            metric("Время", selectedElapsedTimeString(T: T) ?? totalMinutesText(T: T), boldLeft: true)
            metric("Слой", layerText)
            metric("Подслой", subText)
            metric(seriesName, currentValueText(), highlight: true, unitSuffix: unit)
        }
    }

    private func headerLayerTexts() -> (String, String) {
        // Слои
        let layerNow: Int = {
            if let x = cursorX01, let l = vm.layerAtNormalizedX(x) { return l }
            return vm.layerSeriesInt?.last ?? 0
        }()

        // Подслои: 1-based представление
        if let series = vm.subLayerSeriesInt, !series.isEmpty {
            let minV = series.min() ?? 0
            let maxV = series.max() ?? 0
            let isZeroBased = (minV == 0 && maxV >= 1)

            let totalHuman = isZeroBased ? (maxV + 1) : maxV

            let subRaw: Int = {
                if let x = cursorX01, let s = vm.subLayerAtNormalizedX(x) { return s }
                return series.last ?? 0
            }()
            let subHuman = isZeroBased ? (subRaw + 1) : subRaw

            return ("\(layerNow)", totalHuman > 0 ? "\(subHuman)/\(totalHuman)" : "\(subHuman)")
        } else {
            // нет серии подслоев
            if let x = cursorX01, let s = vm.subLayerAtNormalizedX(x) {
                return ("\(layerNow)", "\(s)")
            }
            return ("\(layerNow)", "0")
        }
    }


    // MARK: Chart

    private func chart(T: Double) -> some View {
        let pts = makePoints(T: T)
        let yDomain = makeYDomain(from: pts)
        let transitions = vm.flutterLayerTransitions(isFullScreen: true) // слои+подслои

        return Chart {
            // линия/площадь
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.22), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            }

            // фикс-деления по времени
            let first = start
            let xMarks = [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(T * $0) }
            ForEach(xMarks, id: \.self) { d in
                RuleMark(x: .value("t", d))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
            }

            // Слои/подслои — Flutter transitions (используем ту же шкалу T!)
            if !transitions.isEmpty {
                ForEach(transitions, id: \.self) { tr in
                    RuleMark(x: .value("t", start.addingTimeInterval(tr.timeSeconds)))
                        .foregroundStyle(__colorForLayer(tr.layer).opacity(tr.isFirstLayer ? 0.95 : 0.55))
                        .lineStyle(StrokeStyle(lineWidth: tr.isFirstLayer ? 1.6 : 1.0,
                                               dash: tr.isFirstLayer ? [] : [3,3]))
                }
            }

            // Базовая линия
            RuleMark(y: .value("baseline", yDomain.lowerBound))
                .foregroundStyle(Color.green)
                .lineStyle(StrokeStyle(lineWidth: 1.4))

            // Курсор
            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time)).foregroundStyle(Color.white.opacity(0.7))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value))
                    .symbolSize(90).foregroundStyle(color)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: start...start.addingTimeInterval(T))
        .chartXAxis {
            AxisMarks(values: xAxisMarks(T: T)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel {
                    if let d: Date = v.as(Date.self) { Text(elapsedText(for: d)) }
                }
                .foregroundStyle(.white.opacity(0.85)).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel().foregroundStyle(.white.opacity(0.85)).font(.caption2)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let frame = geo[proxy.plotAreaFrame]
                                let xLocal = value.location.x - frame.minX
                                let x01 = max(0, min(1, xLocal / max(1, frame.width)))
                                self.cursorX01 = x01     // ← как во Flutter
                                // для точки/времени оставим прежнюю логику:
                                if let date: Date = proxy.value(atX: value.location.x - frame.minX) {
                                    let pts = makePoints(T: T)
                                    if let idx = nearestIndex(in: pts, to: date) { self.selectedIndex = idx }
                                }
                            }
                            .onEnded { _ in }
                    )
            }
        }
    }

    // MARK: helpers (UI)

    private func makeYDomain(from pts: [NPoint]) -> ClosedRange<Double> {
        let minV = pts.map(\.value).min() ?? 0
        let maxV = pts.map(\.value).max() ?? 1
        let span = max(1, maxV - minV)
        let bottomPad = span * 0.08 + 1
        let topPad    = span * 0.14 + 2
        return (minV - bottomPad)...(maxV + topPad)
    }

    private func metric(_ title: String, _ value: String,
                        boldLeft: Bool = false, highlight: Bool = false,
                        unitSuffix: String? = nil) -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(boldLeft ? .subheadline.bold() : .subheadline)
                .foregroundColor(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.semibold))
                    .foregroundStyle(highlight ? color : .white)
                if let unitSuffix { Text(unitSuffix).font(.caption).foregroundColor(.white.opacity(0.7)) }
            }
        }
    }

    private func makePoints(T: Double) -> [NPoint] {
        if let t = offsetsSeconds {
            let n = min(t.count, values.count)
            return (0..<n).map { i in NPoint(time: start.addingTimeInterval(t[i]), value: values[i]) }
        } else {
            let n = values.count
            if n <= 1 { return [NPoint(time: start, value: values.first ?? 0)] }
            let step = T / Double(n - 1)
            return values.enumerated().map { (i, v) in NPoint(time: start.addingTimeInterval(Double(i) * step), value: v) }
        }
    }

    private func xAxisMarks(T: Double) -> [Date] {
        let first = start
        return [0,0.25,0.5,0.75,1].map { first.addingTimeInterval(T * Double($0)) }
    }

    private func elapsedText(for date: Date) -> String {
        let sec = Int(max(0, date.timeIntervalSince(start)))
        return formatElapsed(seconds: sec)
    }

    private func selectedElapsedTimeString(T: Double) -> String? {
        guard let idx = selectedIndex else { return nil }
        let pts = makePoints(T: T)
        guard pts.indices.contains(idx) else { return nil }
        let sec = Int(max(0, pts[idx].time.timeIntervalSince(start)))
        return formatElapsed(seconds: sec)
    }

    private func totalMinutesText(T: Double) -> String {
        let sec = Int(T)
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%02d", m)
    }

    private func currentValueText() -> String {
        if let idx = selectedIndex, values.indices.contains(idx) {
            return String(format: "%.2f", values[idx])
        }
        return values.last.map { String(format: "%.2f", $0) } ?? "—"
    }

    private func nearestIndex(in points: [NPoint], to t: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        let times = points.map { $0.time.timeIntervalSinceReferenceDate }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < t.timeIntervalSinceReferenceDate { lo = mid + 1 } else { hi = mid }
        }
        let i = lo
        if i == 0 { return 0 }
        if i >= times.count { return times.count - 1 }
        let a = times[i - 1], b = times[i]
        let tt = t.timeIntervalSinceReferenceDate
        return (abs(a - tt) <= abs(b - tt)) ? (i - 1) : i
    }

    private func formatElapsed(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: Sheet
    @State private var showFull = false
    private func showFullScreen(T: Double) { showFull = true }

    @ViewBuilder
    private var fullScreen: some View { EmptyView() }
}

// NumericChartSectionView+FlutterPatch.swift
//
// Overlay + header helpers to replicate Flutter layer logic on iOS.
// No `public` here (uses internal WorkoutDetailViewModel). Marked @MainActor to
// access main-actor-isolated view model safely.

import SwiftUI

@MainActor
struct FlutterLayerOverlay: View {
    let viewModel: WorkoutDetailViewModel
    var isFullScreen: Bool
    var leftPadding: CGFloat
    var rightPadding: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var lineColor: Color = .secondary
    var lineWidth: CGFloat = 1
    var dash: [CGFloat] = [4, 4]
    var firstLayerLabelColor: Color = .secondary
    var firstLayerLabelFont: Font = .system(size: 10, weight: .semibold)

    init(viewModel: WorkoutDetailViewModel,
         isFullScreen: Bool,
         leftPadding: CGFloat,
         rightPadding: CGFloat,
         topPadding: CGFloat,
         bottomPadding: CGFloat,
         lineColor: Color = .secondary,
         lineWidth: CGFloat = 1,
         dash: [CGFloat] = [4, 4],
         firstLayerLabelColor: Color = .secondary,
         firstLayerLabelFont: Font = .system(size: 10, weight: .semibold)) {
        self.viewModel = viewModel
        self.isFullScreen = isFullScreen
        self.leftPadding = leftPadding
        self.rightPadding = rightPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.lineColor = lineColor
        self.lineWidth = lineWidth
        self.dash = dash
        self.firstLayerLabelColor = firstLayerLabelColor
        self.firstLayerLabelFont = firstLayerLabelFont
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let plotWidth = max(0, width - leftPadding - rightPadding)
            let plotHeight = max(0, height - topPadding - bottomPadding)

            // ⬇️ ФОЛБЭК ДЛЯ total — используем ту же длительность, что и график
            let totalFromTimeSeries = (viewModel.timeSeries?.last).flatMap { $0 > 0 ? $0 : nil }
            let totalFromMinutes = (Double(viewModel.preferredDurationMinutes ?? 0) * 60.0)
            let total = max(1, (viewModel.totalDurationSeconds ?? 0) > 0
                                ? (viewModel.totalDurationSeconds ?? 0)
                                : max(totalFromTimeSeries ?? 0, totalFromMinutes))

            let transitions = viewModel.flutterLayerTransitions(isFullScreen: isFullScreen)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    guard total > 0, plotWidth > 0, !transitions.isEmpty else { return }

                    for tr in transitions {
                        let frac = max(0, min(1, tr.timeSeconds / total))
                        let x = leftPadding + frac * plotWidth

                        // dashed vertical
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: topPadding))
                        path.addLine(to: CGPoint(x: x, y: topPadding + plotHeight))

                        ctx.stroke(path,
                                   with: .color(lineColor),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash))

                        // "Layer N" only for first entries
                        if tr.isFirstLayer {
                            let text = Text("Layer \(tr.layer)")
                                .font(firstLayerLabelFont)
                                .foregroundColor(firstLayerLabelColor)
                            let resolved = ctx.resolve(text)
                            let textSize = resolved.measure(in: size)
                            let tx = min(max(leftPadding, x + 4), leftPadding + plotWidth - textSize.width)
                            let ty = topPadding + plotHeight - textSize.height
                            ctx.draw(resolved, at: CGPoint(x: tx, y: ty), anchor: .topLeading)
                        }

                        // Optional: small sublayer badge near the top (Flutter fullscreen feel)
                        if isFullScreen {
                            let badge = Text("\(tr.layer).\(tr.subLayer)")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                            let resolved = ctx.resolve(badge)
                            ctx.draw(resolved, at: CGPoint(x: x + 4, y: topPadding + 2), anchor: .topLeading)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header helper (index-based like Flutter)

enum SubLayerTotalMode {
    case hardcoded7          // Flutter-like hardcoded "/7"
    case seriesMaxFallback   // Use series max (or 7) when header needs a total
}

struct FlutterHeader {
    let layer: Int?
    let subLayer: Int?
    let layerText: String
    let subLayerText: String
}

enum FlutterHeaderHelper {

    /// Compute header strings from a cursor pixel X.
    /// - Parameters:
    ///   - cursorX: pixel X inside the whole chart view (nil means no cursor)
    ///   - plotWidth: inner plot width (without paddings)
    ///   - leftPadding/rightPadding: paddings used for the plot area
    ///   - sublayerTotalMode: see SubLayerTotalMode
    @MainActor
    static func values(viewModel: WorkoutDetailViewModel,
                       cursorX: CGFloat?,
                       plotWidth: CGFloat,
                       leftPadding: CGFloat,
                       rightPadding: CGFloat,
                       sublayerTotalMode: SubLayerTotalMode = .seriesMaxFallback) -> FlutterHeader {
        guard let rows = viewModel.metricObjectsArray, rows.count > 0 else {
            return .init(layer: nil, subLayer: nil, layerText: "Layer —", subLayerText: "—/7")
        }

        // Normalized X in [0,1] by index (Flutter does floor on (x / xStep))
        var x01: Double = 1.0
        if let cx = cursorX {
            let xInside = max(0, min(plotWidth, Double(cx - leftPadding)))
            x01 = plotWidth > 0 ? xInside / Double(plotWidth) : 1.0
        }

        let layer = viewModel.layerAtNormalizedX(x01)
        let sub = viewModel.subLayerAtNormalizedX(x01)

        // Layer text
        let layerText = layer.map { "Layer \($0)" } ?? "Layer —"

        // SubLayer text
        let total: Int = {
            switch sublayerTotalMode {
            case .hardcoded7:
                return 7
            case .seriesMaxFallback:
                return max(viewModel.subLayerSeriesInt?.max() ?? 7, 1)
            }
        }()
        let subText: String = {
            if let s = sub { return "\(s)/\(total)" }
            return "—/\(total)"
        }()

        return .init(layer: layer, subLayer: sub, layerText: layerText, subLayerText: subText)
    }
}
