import SwiftUI
import Charts

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

fileprivate struct CPoint: Identifiable, Hashable {
    let id = UUID()
    let time: Date
    let value: Double
}

@MainActor
struct CategoricalChartSectionView: View {
    let title: String
    let seriesName: String
    let indices: [Double]
    let labels: [String]
    let timeOffsets: [Double]?        // Flutter minutes → seconds
    let totalMinutes: Int?
    let layer: Int?
    let subLayer: Int?
    let subLayerProgress: String?
    let transitions: [StateTransition]

    var preferredHeight: CGFloat = 220
    var color: Color = .blue
    var start: Date = Date()
    var totalSeconds: Double = 1

    @State private var selectedIndex: Int? = nil

    private var offsetsSeconds: [Double]? {
        guard let t = timeOffsets, !t.isEmpty else { return nil }
        if let mx = t.max(), mx > 10_000 { return t.map { $0 / 1000.0 } } // ms→s
        return t.map { $0 * 60.0 }                                        // minutes→seconds
    }
    private var effectiveTotalSeconds: Double {
        var candidates: [Double] = []
        if totalSeconds > 1 { candidates.append(totalSeconds) }
        if let t = offsetsSeconds, let last = t.last { candidates.append(last) }
        if let m = totalMinutes, m > 0 { candidates.append(Double(m) * 60.0) }
        return max(60, candidates.max() ?? 60)
    }

    var body: some View {
        let T = effectiveTotalSeconds
        VStack(alignment: .leading, spacing: 10) {
            header(T: T)
            ZStack(alignment: .topTrailing) {
                chart(T: T)
                    .frame(height: preferredHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
            }
        }
        .id("cat-\(Int(T.rounded()))")
    }

    private func header(T: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 16) {
                metric("Время", selectedElapsedTimeString() ?? totalMinutesText(T: T), boldLeft: true)
                metric("Слой", layer.map { "\($0)" } ?? "—")
                metric("Подслой", subLayer.map { "\($0)" } ?? "—")
                metric(seriesName, currentLabelText(), highlight: true)
            }
        }
    }

    private func chart(T: Double) -> some View {
        let pts = makePoints(T: T)
        let yDomain = makeYDomain(from: pts)

        return Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.stepCenter)
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.22), .clear],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(pts) { p in
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.stepCenter)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            }

            let first = start
            let xMarks = [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(T * $0) }
            ForEach(Array(xMarks.enumerated()), id: \.offset) { (_, d) in
                RuleMark(x: .value("t", d))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
            }
            ForEach(Array((0..<max(labels.count, 1)).enumerated()), id: \.offset) { (_, i) in
                RuleMark(y: .value("v", Double(i)))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
            }

            ForEach(Array(transitions.enumerated()), id: \.offset) { (_, tr) in
                let d = start.addingTimeInterval(tr.timeSeconds)
                RuleMark(x: .value("t", d))
                    .foregroundStyle(__stateColor(tr.stateKey).opacity(tr.isFirstLayer ? 0.95 : 0.55))
                    .lineStyle(StrokeStyle(lineWidth: tr.isFirstLayer ? 1.6 : 1.0,
                                           dash: tr.isFirstLayer ? [] : [3,3]))
            }

            RuleMark(y: .value("baseline", yDomain.lowerBound))
                .foregroundStyle(Color.green)
                .lineStyle(StrokeStyle(lineWidth: 1.4))

            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time)).foregroundStyle(Color.white.opacity(0.55))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value))
                    .symbolSize(80).foregroundStyle(color)
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
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel {
                    if let i = v.as(Double.self) {
                        let idx = max(0, min(labels.count - 1, Int(i.rounded())))
                        Text(labels[idx])
                    }
                }
                .foregroundStyle(.white.opacity(0.85)).font(.caption2)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let x = value.location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    if let idx = nearestIndex(in: pts, to: date) { selectedIndex = idx }
                                }
                            }
                    )
            }
        }
    }

    private func makeYDomain(from pts: [CPoint]) -> ClosedRange<Double> {
        let minV = pts.map(\.value).min() ?? 0
        let maxV = pts.map(\.value).max() ?? 1
        let span = max(1, maxV - minV)
        let bottomPad = span * 0.10 + 0.2
        let topPad    = span * 0.16 + 0.2
        return (minV - bottomPad)...(maxV + topPad)
    }

    private func metric(_ title: String, _ value: String, boldLeft: Bool = false, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(boldLeft ? .subheadline.bold() : .subheadline).foregroundColor(.white.opacity(0.75))
            Text(value).font(.body.weight(.semibold)).foregroundStyle(highlight ? color : .white)
        }
    }

    private func makePoints(T: Double) -> [CPoint] {
        if let t = offsetsSeconds {
            let n = min(t.count, indices.count)
            return (0..<n).map { i in CPoint(time: start.addingTimeInterval(t[i]), value: indices[i]) }
        } else {
            let n = indices.count
            if n <= 1 { return [CPoint(time: start, value: indices.first ?? 0)] }
            let step = T / Double(n - 1)
            return indices.enumerated().map { (i, v) in CPoint(time: start.addingTimeInterval(Double(i) * step), value: v) }
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

    private func totalMinutesText(T: Double) -> String {
        let sec = Int(T)
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%02d", m)
    }

    private func selectedElapsedTimeString() -> String? {
        guard let idx = selectedIndex else { return nil }
        let pts = makePoints(T: effectiveTotalSeconds)
        guard pts.indices.contains(idx) else { return nil }
        let sec = Int(max(0, pts[idx].time.timeIntervalSince(start)))
        return formatElapsed(seconds: sec)
    }

    private func currentLabelText() -> String {
        if let idx = selectedIndex, indices.indices.contains(idx) {
            let i = max(0, min(labels.count - 1, Int(indices[idx].rounded())))
            return labels[i]
        }
        if let last = indices.last {
            let i = max(0, min(labels.count - 1, Int(last.rounded())))
            return labels[i]
        }
        return "—"
    }

    private func nearestIndex(in points: [CPoint], to t: Date) -> Int? {
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
}
