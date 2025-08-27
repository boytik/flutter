import SwiftUI
import Charts

// MARK: - Универсальная модель данных графиков

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
    public init(name: String, points: [ChartPoint]) {
        self.name = name
        self.points = points
    }
}

// MARK: - Фуллскрин графики с “скраббером”

public struct FullScreenChartsView: View {
    @Environment(\.dismiss) private var dismiss

    /// Набор серий (например: ЧСС, Темп, Скорость и т.п.)
    let series: [ChartSeries]

    /// Отформатированное имя X-оси (абсолютное время, для второго ряда)
    let timeFormatter: Date.FormatStyle

    /// Локальное состояние курсора
    @State private var selectedTime: Date? = nil
    @State private var isDragging: Bool = false

    // Вычисленные границы временного диапазона
    private var startTime: Date {
        series.flatMap { $0.points.map(\.time) }.min() ?? Date()
    }
    private var endTime: Date {
        series.flatMap { $0.points.map(\.time) }.max() ?? Date()
    }
    private var totalDurationSeconds: Int {
        max(0, Int(endTime.timeIntervalSince(startTime)))
    }
    private var totalHHmm: String {
        let h = totalDurationSeconds / 3600
        let m = (totalDurationSeconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    public init(
        series: [ChartSeries],
        timeFormatter: Date.FormatStyle = .dateTime.hour().minute()
    ) {
        self.series = series
        self.timeFormatter = timeFormatter
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Краткая шапка выбранной точки
                HStack(alignment: .firstTextBaseline) {
                    if let t = selectedTime {
                        SelectionHeaderView(
                            time: t,
                            startTime: startTime,
                            values: valuesAt(time: t),
                            timeFormatter: timeFormatter
                        )
                    } else {
                        // Ничего не выбрано — показываем только итог
                        Text("Время").font(.footnote).foregroundStyle(.secondary)
                        Text("—").font(.callout.monospacedDigit())
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Итого:")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(totalHHmm)
                            .font(.callout.monospacedDigit())
                    }
                }
                .padding(.horizontal)

                // Основной чарт
                Chart {
                    ForEach(series) { s in
                        ForEach(s.points) { p in
                            LineMark(
                                x: .value("Time", p.time),
                                y: .value(s.name, p.value)
                            )
                            .interpolationMethod(.monotone)
                        }

                        // Точка в месте курсора
                        if let t = selectedTime,
                           let p = nearestPoint(in: s.points, to: t) {
                            PointMark(
                                x: .value("Time", p.time),
                                y: .value(s.name, p.value)
                            )
                            .symbolSize(80)
                        }
                    }

                    // Вертикальная линия-правило (курсор)
                    if let t = selectedTime {
                        RuleMark(x: .value("Time", t))
                            .annotation(position: .top, alignment: .leading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(elapsedString(from: startTime, to: t))
                                        .font(.caption2.monospacedDigit())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.ultraThinMaterial, in: Capsule())
                                    Text(t.formatted(timeFormatter))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }
                .chartScrollableAxes(.horizontal)
                .chartXScale(domain: startTime...endTime)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let x = value.location.x - geo[proxy.plotAreaFrame].origin.x
                                        if let t = proxy.value(atX: x) as Date? {
                                            selectedTime = t
                                        }
                                    }
                                    .onEnded { _ in isDragging = false }
                            )
                            .onAppear {
                                // По умолчанию ставим курсор в конец
                                selectedTime = endTime
                            }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Графики")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .statusBarHidden(true) // фуллскрин-ощущение
    }

    // MARK: - Хелперы выборки

    private func valuesAt(time: Date) -> [(name: String, value: Double, time: Date)] {
        series.compactMap { s in
            if let p = nearestPoint(in: s.points, to: time) {
                return (s.name, p.value, p.time)
            }
            return nil
        }
        .sorted { $0.name < $1.name }
    }

    private func nearestPoint(in points: [ChartPoint], to t: Date) -> ChartPoint? {
        guard !points.isEmpty else { return nil }
        // Бинарный поиск по времени
        let sorted = points.sorted { $0.time < $1.time }
        var lo = 0
        var hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].time < t {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // lo — первый >= t; сравним с предыдущим
        let i = lo
        if i == 0 { return sorted.first }
        if i >= sorted.count { return sorted.last }
        let a = sorted[i - 1], b = sorted[i]
        return abs(a.time.timeIntervalSince(t)) <= abs(b.time.timeIntervalSince(t)) ? a : b
    }

    // MARK: - Время: форматирование

    /// Строка прошедшего времени от `start` до `to` как mm:ss / HH:mm:ss
    private func elapsedString(from start: Date, to: Date) -> String {
        let sec = max(0, Int(to.timeIntervalSince(start)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Шапка выбранной точки

fileprivate struct SelectionHeaderView: View {
    let time: Date
    let startTime: Date
    let values: [(name: String, value: Double, time: Date)]
    let timeFormatter: Date.FormatStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1) Время по курсору как elapsed
            Text(elapsedString(from: startTime, to: time))
                .font(.headline.monospacedDigit())

            // 2) Абсолютное время точкой
            Text(time.formatted(timeFormatter))
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Табличка значений всех серий в точке
            VStack(spacing: 8) {
                ForEach(values, id: \.name) { item in
                    HStack {
                        Text(item.name).font(.callout)
                        Spacer()
                        Text(Self.valueFormatter(item.value))
                            .font(.callout.monospacedDigit())
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private static func valueFormatter(_ v: Double) -> String {
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 100  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    private func elapsedString(from start: Date, to: Date) -> String {
        let sec = max(0, Int(to.timeIntervalSince(start)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Превью

#Preview {
    let now = Date()
    let s1 = ChartSeries(
        name: "ЧСС",
        points: (0..<600).map { i in
            let t = now.addingTimeInterval(Double(i) * 5)
            let val = 120 + 20 * sin(Double(i) / 20)
            return ChartPoint(time: t, value: val)
        }
    )
    let s2 = ChartSeries(
        name: "Темп",
        points: (0..<600).map { i in
            let t = now.addingTimeInterval(Double(i) * 5)
            let val = 6.0 - 0.5 * sin(Double(i) / 15)
            return ChartPoint(time: t, value: val)
        }
    )
    return FullScreenChartsView(series: [s1, s2])
}
