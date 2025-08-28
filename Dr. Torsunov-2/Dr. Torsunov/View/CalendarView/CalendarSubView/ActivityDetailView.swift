import SwiftUI
import UIKit
import Charts

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ActivityDetailView: View {
    let activity: Activity
    let role: PersonalViewModel.Role

    enum Tab: String, Hashable { case charts, photos, review }
    @State private var tab: Tab = .charts

    @State private var comment = ""
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var showBeforePicker = false
    @State private var showAfterPicker  = false
    @State private var isSubmitting = false
    @State private var submissionSuccess: Bool?

    @StateObject private var vm: WorkoutDetailViewModel
    @State private var syncEnabled = false

    init(activity: Activity, role: PersonalViewModel.Role) {
        self.activity = activity
        self.role = role
        let key = ActivityDetailView.extractWorkoutKey(from: activity) ?? activity.id
        _vm = StateObject(wrappedValue: WorkoutDetailViewModel(workoutID: key))
    }

    private var availableTabs: [Tab] { role == .inspector ? [.charts, .photos] : [.charts, .review] }
    private func tabTitle(_ t: Tab) -> String { t == .charts ? "Графики" : (t == .photos ? "Фото" : "На проверку") }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection

                Picker("", selection: $tab) {
                    ForEach(availableTabs, id: \.self) { Text(tabTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .tint(.green)
                .zIndex(3)

                switch tab {
                case .charts:
                    chartsSection
                case .photos:
                    InspectorPhotosView(activity: activity).background(Color.clear)
                case .review:
                    PhotoPickRow(
                        beforeImage: $beforeImage,
                        afterImage:  $afterImage,
                        onPickBefore: { showBeforePicker = true },
                        onPickAfter:  { showAfterPicker  = true },
                        aspect: 3.0/4.0,
                        corner: 18
                    )
                    commentSection
                    submitButton
                }

                if let success = submissionSuccess, role != .inspector {
                    Text(success ? L("submit_success") : L("submit_error"))
                        .foregroundColor(success ? .green : .red)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showBeforePicker) { ImagePicker(image: $beforeImage) }
        .sheet(isPresented: $showAfterPicker)  { ImagePicker(image: $afterImage) }
        .onAppear { comment = activity.description ?? "" }
        .task { await vm.load() }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header (иконка/имя как в WorkoutDetailView)
    private var headerSection: some View {
        HStack(spacing: 12) {
            headerIcon(for: activity)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleEN(for: activity))
                    .font(.headline)
                    .foregroundColor(.white)

                if let date = activity.createdAt {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
    }

    // MARK: Charts (Flutter-like)
    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if vm.isLoading { ProgressView().tint(.white) }
            if let err = vm.errorMessage, !err.isEmpty {
                Text(err).font(.footnote).foregroundColor(.gray)
            }

            Toggle("Синхронизация", isOn: $syncEnabled)
                .toggleStyle(.switch)
                .tint(.green)
                .foregroundColor(.white)

            if let hr = vm.heartRateSeries, !hr.isEmpty {
                EnhancedChartSectionView(
                    title: "Диаграмма частоты сердцебиения",
                    unit: "bpm",
                    seriesName: "ЧСС",
                    values: hr,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 240
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("heart") ||
                $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
            }) {
                sectionTitle("Диаграмма частоты сердцебиения")
                FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            if let wt = vm.waterTempSeries, !wt.isEmpty {
                EnhancedChartSectionView(
                    title: "Диаграмма температуры воды",
                    unit: "°C",
                    seriesName: "Температура воды",
                    values: wt,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 220
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("temp") ||
                $0.absoluteString.localizedCaseInsensitiveContains("water")
            }) {
                sectionTitle("Диаграмма температуры воды")
                FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            if let spd = vm.speedSeries, !spd.isEmpty {
                EnhancedChartSectionView(
                    title: "Скорость, км/ч",
                    unit: "km/h",
                    seriesName: "Скорость",
                    values: spd,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 200
                )
            }
        }
    }

    // MARK: Review
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("comment_label"))
                .foregroundColor(.white)
                .font(.subheadline)

            TextField(L("enter_comment_placeholder"), text: $comment, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }

    private var submitButton: some View {
        Button {
            guard !isSubmitting else { return }
            isSubmitting = true
            submissionSuccess = nil
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    isSubmitting = false
                    submissionSuccess = true
                }
            }
        } label: {
            Text(L("submit"))
                .frame(maxWidth: .infinity)
                .padding()
                .background((beforeImage != nil && afterImage != nil) ? Color.green : Color.gray,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
        }
        .disabled(beforeImage == nil || afterImage == nil || isSubmitting)
    }

    private static func extractWorkoutKey(from activity: Activity) -> String? {
        let mirror = Mirror(reflecting: activity)
        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            let isCandidate =
            (label.contains("workout") && (label.contains("key") || label.contains("uuid") || label.hasSuffix("id")))
            || label == "id" || label == "uuid"
            if isCandidate, let s = child.value as? String, !s.isEmpty { return s }
        }
        return nil
    }

    // MARK: - Icon & title helpers (как в WorkoutDetailView)

    @ViewBuilder
    private func headerIcon(for activity: Activity) -> some View {
        let base = ((activity.name ?? "") + " " + (activity.description ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let t = canonicalType(inferType(from: base))

        if let asset = iconAssetName(for: t), UIImage(named: asset) != nil {
            circleIcon(image: Image(asset), bg: colorByType(t))
        } else {
            circleIcon(system: glyphSymbolByType(t), bg: colorByType(t))
        }
    }

    private func titleEN(for activity: Activity) -> String {
        let base = ((activity.name ?? "") + " " + (activity.description ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let t = canonicalType(inferType(from: base))
        return enName(for: t) ?? (activity.name ?? "Activity")
    }

    private func enName(for type: String) -> String? {
        let map: [String: String] = [
            "swim":"Swim","water":"Water","bike":"Cycling",
            "run":"Run","walk":"Walk","run_walk":"Run/Walk",
            "yoga":"Yoga","strength":"Strength","sauna":"Sauna",
            "fasting":"Fasting","triathlon":"Triathlon"
        ]
        return map[type]
    }

    private func iconAssetName(for type: String) -> String? {
        switch type {
        case "yoga": return "ic_workout_yoga"
        case "run": return "ic_workout_run"
        case "walk": return "ic_workout_walk"
        case "run_walk": return "ic_workout_run"
        case "bike": return "ic_workout_bike"
        case "swim": return "ic_workout_swim"
        case "water": return "ic_workout_water"
        case "strength": return "ic_workout_strength"
        case "sauna": return "ic_workout_sauna"
        case "fasting": return "ic_workout_fast"
        default: return nil
        }
    }

    private func glyphSymbolByType(_ type: String) -> String {
        switch type {
        case "yoga": return "figure.mind.and.body"
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "run_walk": return "figure.run"
        case "bike": return "bicycle"
        case "swim", "water": return "drop.fill"
        case "strength":
            if #available(iOS 16.0, *) { return "dumbbell.fill" } else { return "bolt.heart" }
        case "sauna": return "flame.fill"
        case "fasting": return "fork.knife"
        default: return "checkmark.seal.fill"
        }
    }

    private func colorByType(_ type: String) -> Color {
        switch type {
        case "yoga": return .purple
        case "run": return .pink
        case "walk": return .orange
        case "run_walk": return .pink
        case "bike": return .mint
        case "swim", "water": return .blue
        case "strength": return .green
        case "sauna": return .red
        case "fasting": return .yellow
        default: return .gray
        }
    }

    private func canonicalType(_ raw: String) -> String {
        let s = raw.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if (s.contains("run") || s.contains("running")) &&
           (s.contains("walk") || s.contains("walking")) { return "run_walk" }

        if s.contains("swim") { return "swim" }
        if s.contains("water") { return "water" }
        if s.contains("bike") || s.contains("cycl") { return "bike" }
        if s.contains("running") || s == "run" { return "run" }
        if s.contains("walking") || s == "walk" { return "walk" }
        if s.contains("yoga") { return "yoga" }
        if s.contains("strength") || s.contains("gym") { return "strength" }
        if s.contains("sauna") { return "sauna" }
        if s.contains("fast") || s.contains("fasting") || s.contains("active") { return "fasting" }
        if s.contains("triathlon") { return "triathlon" }
        return s
    }

    private func inferType(from name: String) -> String {
        let s = name.lowercased()
        if (s.contains("run") || s.contains("бег")) &&
           (s.contains("walk") || s.contains("ходь")) { return "run_walk" }
        if s.contains("yoga") || s.contains("йога") { return "yoga" }
        if s.contains("run") || s.contains("бег") { return "run" }
        if s.contains("walk") || s.contains("ходь") { return "walk" }
        if s.contains("bike") || s.contains("velo") || s.contains("вел") || s.contains("cycl") { return "bike" }
        if s.contains("swim") || s.contains("плав") { return "swim" }
        if s.contains("water") || s.contains("вода") { return "water" }
        if s.contains("sauna") || s.contains("сауна") { return "sauna" }
        if s.contains("fast") || s.contains("пост") || s.contains("active") { return "fasting" }
        if s.contains("strength") || s.contains("силов") || s.contains("gym") { return "strength" }
        if s.contains("triathlon") { return "triathlon" }
        return ""
    }

    // кружки-иконки
    private func circleIcon(system: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system).font(.system(size: 18, weight: .semibold)).foregroundColor(bg)
        }
    }
    private func circleIcon(image: Image, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            image.resizable().scaledToFit().padding(8)
        }
    }
}

// === Безопасная удалённая картинка для fallback-графиков ===
private struct FixedRemoteImage: View {
    let url: URL?
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty: ProgressView().tint(.white)
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(0.06))
            Image(systemName: "photo").font(.system(size: 22, weight: .semibold)).foregroundColor(.white.opacity(0.6))
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

// === Улучшенный график (как во Flutter) ===
private struct EnhancedChartSectionView: View {
    let title: String
    let unit: String
    let seriesName: String

    let values: [Double]
    let timeOffsets: [Double]?      // секунды от старта
    let totalMinutes: Int?          // длительность, мин
    let layer: Int?
    let subLayer: Int?
    let subLayerProgress: String?

    var preferredHeight: CGFloat = 220

    @State private var selectedIndex: Int? = nil
    @State private var showFull = false

    // stats
    private var vMin: Double { values.min() ?? 0 }
    private var vMax: Double { values.max() ?? 1 }
    private var vAvg: Double { values.isEmpty ? 0 : values.reduce(0,+)/Double(values.count) }
    private var yDomain: ClosedRange<Double> {
        let pad = max(0.001, (vMax - vMin) * 0.08)
        return (vMin - pad)...(vMax + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)

            // Flutter-like header with stats
            HStack(spacing: 12) {
                StatChip(label: "min", value: vMin, unit: unit)
                StatChip(label: "avg", value: vAvg, unit: unit)
                StatChip(label: "max", value: vMax, unit: unit)
                Spacer()
                // live value & time from selection / end
                let i = selectedIndex ?? (values.indices.last ?? 0)
                HStack(spacing: 8) {
                    Text("\(seriesName): \(valueString(at: i))")
                        .font(.footnote.weight(.semibold))
                    Text(timeStringForIndex(i))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .foregroundColor(.white)
            .padding(.bottom, 2)

            ZStack(alignment: .topTrailing) {
                chart
                    .frame(height: preferredHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )

                Button {
                    showFull = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(6)
            }
        }
        .fullScreenCover(isPresented: $showFull) {
            FullScreenChartsView(series: [ChartSeries(name: seriesName, points: makePoints())])
        }
    }

    private var chart: some View {
        Chart {
            let pts = makePoints()

            // fill
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [.green.opacity(0.22), .clear],
                        startPoint: .top, endPoint: .bottom)
                    )
            }
            // line
            ForEach(pts) { p in
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.green)
            }

            // selection
            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time))
                    .foregroundStyle(Color.white.opacity(0.55))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value))
                    .symbolSize(80)
                    .foregroundStyle(.green)
                    .annotation(position: .top) {
                        // small value bubble above point
                        Text("\(valueString(at: idx)) \(unit)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisMarks()) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.10))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel {
                    if let d: Date = v.as(Date.self) {
                        Text(elapsedText(for: d))
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.10))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel().foregroundStyle(.white.opacity(0.8)).font(.caption2)
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
                                    if let idx = nearestIndex(in: pts, to: date) {
                                        selectedIndex = idx
                                    }
                                }
                            }
                    )
            }
        }
    }

    // MARK: helpers
    private func makePoints() -> [ChartPoint] {
        let start = Date()
        if let t = timeOffsets, !t.isEmpty {
            let n = min(t.count, values.count)
            return (0..<n).map { i in ChartPoint(time: start.addingTimeInterval(t[i]), value: values[i]) }
        } else {
            return values.enumerated().map { (i, v) in ChartPoint(time: start.addingTimeInterval(Double(i)), value: v) }
        }
    }

    private func xAxisMarks() -> [Date] {
        let pts = makePoints()
        guard let first = pts.first?.time, let last = pts.last?.time, last > first else { return pts.map{$0.time} }
        let total = last.timeIntervalSince(first)
        let steps = [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(total * $0) }
        return steps
    }

    private func elapsedText(for date: Date) -> String {
        let pts = makePoints()
        guard let first = pts.first?.time else { return "0:00" }
        let sec = Int(max(0, date.timeIntervalSince(first)))
        return formatElapsed(seconds: sec)
    }

    private func timeStringForIndex(_ i: Int) -> String {
        let pts = makePoints()
        guard pts.indices.contains(i), let first = pts.first?.time else { return "—" }
        let sec = Int(max(0, pts[i].time.timeIntervalSince(first)))
        return formatElapsed(seconds: sec)
    }

    private func valueString(at i: Int) -> String {
        guard values.indices.contains(i) else { return "—" }
        let v = values[i]
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 100  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
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

// small stat chip
private struct StatChip: View {
    let label: String
    let value: Double
    let unit: String
    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).opacity(0.7)
            Text(short(value)).font(.caption.weight(.semibold))
            Text(unit).font(.caption2).opacity(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .foregroundColor(.white)
    }
    private func short(_ v: Double) -> String {
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 100  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}

private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.headline).foregroundColor(.white)
}
