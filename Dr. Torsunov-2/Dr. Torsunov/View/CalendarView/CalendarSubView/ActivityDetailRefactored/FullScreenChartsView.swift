import SwiftUI
import Charts

public struct ChartPoint: Identifiable, Hashable {
    public let id = UUID()
    public let time: Date
    public let value: Double
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct ChartSeries: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let points: [ChartPoint]
    public let color: Color
    public init(name: String, points: [ChartPoint], color: Color = .accentColor) {
        self.name = name
        self.points = points
        self.color = color
    }
}

public struct FullScreenChartsView: View {
    public let series: [ChartSeries]
    public var timeFormatter: Date.FormatStyle

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTime: Date? = nil
    @State private var isDragging: Bool = false

    public init(series: [ChartSeries], timeFormatter: Date.FormatStyle = .dateTime.hour().minute()) {
        self.series = series
        self.timeFormatter = timeFormatter
    }

    private var startTime: Date { series.flatMap { $0.points.map(\.time) }.min() ?? Date() }
    private var endTime: Date { series.flatMap { $0.points.map(\.time) }.max() ?? Date() }

    private func valuesAt(time: Date) -> [(String, Double, Color)] {
        series.map { s in
            let pts = s.points.sorted { $0.time < $1.time }
            guard let nearest = nearestPoint(in: pts, to: time) else { return (s.name, .nan, s.color) }
            return (s.name, nearest.value, s.color)
        }
    }

    private func nearestPoint(in points: [ChartPoint], to t: Date) -> ChartPoint? {
        guard !points.isEmpty else { return nil }
        let times = points.map { $0.time.timeIntervalSinceReferenceDate }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < t.timeIntervalSinceReferenceDate { lo = mid + 1 } else { hi = mid }
        }
        let i = lo
        if i == 0 { return points[0] }
        if i >= points.count { return points.last }
        let a = points[i - 1], b = points[i]
        let tt = t.timeIntervalSinceReferenceDate
        return abs(a.time.timeIntervalSinceReferenceDate - tt) <= abs(b.time.timeIntervalSinceReferenceDate - tt) ? a : b
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if let t = selectedTime {
                        SelectionHeaderView(
                            time: t,
                            startTime: startTime,
                            values: valuesAt(time: t),
                            timeFormatter: timeFormatter
                        )
                    } else {
                        Text("Время").font(.footnote).foregroundStyle(.secondary)
                        Text("—").font(.callout.monospacedDigit())
                    }
                    Spacer()
                }
                .padding(.horizontal)

                Chart {
                    ForEach(series) { s in
                        ForEach(s.points) { p in
                            AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("t", p.time), y: .value("v", p.value))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(s.color)
                        }
                    }
                    if let t = selectedTime {
                        RuleMark(x: .value("t", t)).foregroundStyle(Color.white.opacity(0.6))
                        ForEach(series) { s in
                            if let p = nearestPoint(in: s.points, to: t) {
                                PointMark(x: .value("t", p.time), y: .value("v", p.value))
                                    .symbolSize(80).foregroundStyle(s.color)
                            }
                        }
                    }
                }
                
                .chartXScale(domain: startTime...endTime)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in isDragging = true }.onEnded { _ in isDragging = false })
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let origin = geo[proxy.plotAreaFrame].origin
                                        let x = value.location.x - origin.x
                                        if let date: Date = proxy.value(atX: x) { selectedTime = date }
                                    }
                                    .onEnded { _ in isDragging = false }
                            )
                            .onAppear { selectedTime = endTime }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Графики")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

fileprivate struct SelectionHeaderView: View {
    let time: Date
    let startTime: Date
    let values: [(String, Double, Color)]
    let timeFormatter: Date.FormatStyle

    private var elapsedText: String {
        let sec = Int(max(0, time.timeIntervalSince(startTime)))
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(elapsedText).font(.callout.monospacedDigit())
                Text(time.formatted(timeFormatter)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(Array(values.enumerated()), id: \.offset) { (_, v) in
                    HStack(spacing: 6) {
                        Circle().fill(v.2).frame(width: 8, height: 8)
                        Text(v.0).font(.caption).foregroundStyle(.secondary)
                        if v.1.isNaN { Text("—").font(.caption.monospacedDigit()) }
                        else { Text(String(format: "%.2f", v.1)).font(.caption.monospacedDigit()) }
                    }
                }
            }
        }
    }
}
