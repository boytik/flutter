import SwiftUI
import Charts

@MainActor

struct CategoricalChartSectionView: View {
    public let title: String
    public let seriesName: String
    public let indices: [Double]
    public let labels: [String]
    public let timeOffsets: [Double]?
    public let totalMinutes: Int?
    public let layer: Int?
    public let subLayer: Int?
    public let subLayerProgress: String?
    var preferredHeight: CGFloat = 220
    var color: Color = .purple
    var start: Date = Date()
    var totalSeconds: Double = 1

    @State private var selectedIndex: Int? = nil
    @State private var showFull = false

    private var yDomain: ClosedRange<Double> { (-0.5)...(Double(max(labels.count-1, 0)) + 0.5) }

    init(title: String, seriesName: String, indices: [Double], labels: [String], timeOffsets: [Double]?, totalMinutes: Int?, layer: Int?, subLayer: Int?, subLayerProgress: String?, preferredHeight: CGFloat = 220, color: Color = .purple, start: Date = Date(), totalSeconds: Double = 1) {
        self.title = title; self.seriesName = seriesName; self.indices = indices; self.labels = labels
        self.timeOffsets = timeOffsets; self.totalMinutes = totalMinutes
        self.layer = layer; self.subLayer = subLayer; self.subLayerProgress = subLayerProgress
        self.preferredHeight = preferredHeight; self.color = color; self.start = start; self.totalSeconds = totalSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            adSectionTitle(title)
            header
            ZStack(alignment: .topTrailing) {
                chart
                    .frame(height: preferredHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
                Button {
                    showFull = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.padding(6)
            }
        }
        .fullScreenCover(isPresented: $showFull) {
            FullScreenChartsView(series: [ChartSeries(name: seriesName, points: makePoints())])
        }
    }

    private var header: some View {
        let i = selectedIndex ?? (indices.indices.last ?? 0)
        let currentLabel = labels[safe: Int(round(indices[safe: i] ?? 0))] ?? "—"
        return HStack(spacing: 16) {
            metric("Время", selectedElapsedTimeString() ?? formatDuration(totalMinutes), boldLeft: true)
            Divider().frame(height: 16).background(Color.white.opacity(0.2))
            metric("Слой", layer.map(String.init) ?? "—", highlight: true)
            metric("Подслой", subLayerProgress ?? subLayer.map(String.init) ?? "—", subdued: layer == nil)
            Spacer()
            metric(seriesName, currentLabel, highlight: true)
        }
        .font(.footnote).foregroundColor(.white).padding(.vertical, 4)
    }

    private var chart: some View {
        Chart {
            let pts = makePoints()

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
            let last  = start.addingTimeInterval(totalSeconds)
            let total = max(1, last.timeIntervalSince(first))
            let xMarks = [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(total * $0) }
            ForEach(xMarks, id: \.self) { d in
                RuleMark(x: .value("t", d))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
            }
            ForEach(Array(0..<max(labels.count, 1)), id: \.self) { i in
                RuleMark(y: .value("v", Double(i)))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
            }

            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time)).foregroundStyle(Color.white.opacity(0.55))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value))
                    .symbolSize(80).foregroundStyle(color)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: start...start.addingTimeInterval(totalSeconds))
        .chartXAxis {
            AxisMarks(values: xAxisMarks()) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel {
                    if let d: Date = v.as(Date.self) { Text(elapsedText(for: d)) }
                }
                .foregroundStyle(.white.opacity(0.85)).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: Array(0..<max(labels.count, 1)).map { Double($0) }) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisTick().foregroundStyle(Color.white.opacity(0.35))
                AxisValueLabel {
                    let i = Int(round(v.as(Double.self) ?? -1))
                    Text(labels[safe: i] ?? "")
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
                                    let pts = makePoints()
                                    if let idx = nearestIndex(in: pts, to: date) { selectedIndex = idx }
                                }
                            }
                    )
            }
        }
        .chartScrollableAxes(.horizontal)
    }

    private func metric(_ title: String, _ value: String, boldLeft: Bool = false, highlight: Bool = false, subdued: Bool = false, unitSuffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(boldLeft ? .subheadline.bold() : .subheadline).foregroundColor(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.semibold)).foregroundColor(highlight ? color : (subdued ? .white.opacity(0.6) : .white))
                if let unitSuffix { Text(unitSuffix).font(.caption).foregroundColor(.white.opacity(0.7)) }
            }
        }
    }
    private func makePoints() -> [ChartPoint] {
        let vals = indices.map { round($0) }
        if let t = timeOffsets, !t.isEmpty {
            let n = min(t.count, vals.count)
            return (0..<n).map { i in ChartPoint(time: start.addingTimeInterval(t[i]), value: vals[i]) }
        } else {
            return vals.enumerated().map { (i, v) in ChartPoint(time: start.addingTimeInterval(Double(i)), value: v) }
        }
    }
    private func xAxisMarks() -> [Date] {
        let first = start
        let last  = start.addingTimeInterval(totalSeconds)
        let total = max(1, last.timeIntervalSince(first))
        return [0,0.25,0.5,0.75,1].map { first.addingTimeInterval(total * Double($0)) }
    }
    private func elapsedText(for date: Date) -> String {
        let sec = Int(max(0, date.timeIntervalSince(start)))
        return formatElapsed(seconds: sec)
    }
    private func selectedElapsedTimeString() -> String? {
        guard let idx = selectedIndex else { return nil }
        let pts = makePoints()
        guard pts.indices.contains(idx) else { return nil }
        let sec = Int(max(0, pts[idx].time.timeIntervalSince(start)))
        return formatElapsed(seconds: sec)
    }
    private func formatDuration(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "—" }
        let h = m / 60, mm = m % 60
        return String(format: "%02d:%02d", h, mm)
    }
    private func nearestIndex(in points: [ChartPoint], to t: Date) -> Int? {
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
        return (abs(a - t.timeIntervalSinceReferenceDate) <= abs(b - t.timeIntervalSinceReferenceDate)) ? (i - 1) : i
    }
    private func formatElapsed(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
