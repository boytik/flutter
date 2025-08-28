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
        .task {
            await vm.load()
#if DEBUG
            debugPrintActivity(activity)
            debugListVMSets(vm)
            debugPrintKnownSeries(vm)
            debugFindYogaPositions(vm)
#endif
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Charts

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

            // 1) ЧСС
            if let hr = vm.heartRateSeries, !hr.isEmpty {
                NumericChartSectionView(
                    title: "Диаграмма частоты сердцебиения",
                    unit: "bpm",
                    seriesName: "Пульс",
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

            // 2) Второй график «как во Flutter»
            switch secondChartChoice() {
            case .none:
                EmptyView()

            case .numeric(let cfg):
                NumericChartSectionView(
                    title: cfg.title,
                    unit: cfg.unit,
                    seriesName: cfg.seriesName,
                    values: cfg.values,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 220
                )

            case .categorical(let cfg):
                CategoricalChartSectionView(
                    title: cfg.title,
                    seriesName: cfg.seriesName,
                    indices: cfg.indices,
                    labels: cfg.labels,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 220
                )
            }
        }
    }

    private enum SecondChart {
        struct NumericCfg { let title, unit, seriesName: String; let values: [Double] }
        struct CategoricalCfg { let title, seriesName: String; let indices: [Double]; let labels: [String] }
        case numeric(NumericCfg)
        case categorical(CategoricalCfg)
        case none
    }

    private func secondChartChoice() -> SecondChart {
        let base = ((activity.name ?? "") + " " + (activity.description ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let t = canonicalType(inferType(from: base))

        if ["yoga", "meditation"].contains(t) {
            if let (idx, labels) = findYogaPositions(in: vm) {
                return .categorical(.init(title: "Диаграмма позиций йоги",
                                          seriesName: "Position",
                                          indices: idx, labels: labels))
            }
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды", unit: "°C", seriesName: "Температура воды", values: v))
            }
            return .none
        }

        if ["run", "walk", "run_walk", "bike"].contains(t) {
            if let v = vm.speedSeries, !v.isEmpty {
                return .numeric(.init(title: "Скорость", unit: "km/h", seriesName: "Скорость", values: v))
            }
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды", unit: "°C", seriesName: "Температура воды", values: v))
            }
            return .none
        }

        if ["water", "swim", "sauna"].contains(t) {
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды", unit: "°C", seriesName: "Температура воды", values: v))
            }
            return .none
        }

        if let v = vm.speedSeries, !v.isEmpty {
            return .numeric(.init(title: "Скорость", unit: "km/h", seriesName: "Скорость", values: v))
        }
        return .none
    }

    private func findYogaPositions(in vm: WorkoutDetailViewModel) -> (indices: [Double], labels: [String])? {
        let mir = Mirror(reflecting: vm)
        var idxByName: [Double]?
        var labelsByName: [String]?

        for ch in mir.children {
            guard let name = ch.label?.lowercased() else { continue }
            if name.contains("pose") || name.contains("position") {
                if let arr = asDoubleArray(ch.value), (vm.timeSeries?.count ?? arr.count) == arr.count {
                    idxByName = arr
                } else if let arrS = ch.value as? [String], !arrS.isEmpty {
                    labelsByName = arrS
                }
            }
        }
        if let idx = idxByName {
            return (idx, labelsByName ?? defaultYogaLabels())
        }

        if let step = firstStepLikeSeries(in: vm) {
            return (step, defaultYogaLabels())
        }
        return nil
    }

    private func firstStepLikeSeries(in vm: WorkoutDetailViewModel) -> [Double]? {
        let mir = Mirror(reflecting: vm)
        for ch in mir.children {
            guard let arr = asDoubleArray(ch.value) else { continue }
            guard (vm.timeSeries?.count ?? arr.count) == arr.count else { continue }
            let uniq = Set(arr.map { round($0) })
            if uniq.count > 1 && uniq.count <= 12 && arr.allSatisfy({ abs($0 - round($0)) < 0.001 }) {
                return arr
            }
        }
        return nil
    }

    private func defaultYogaLabels() -> [String] {
        ["Lotus", "Half lotus", "Diamond", "Standing", "Kneeling", "butterfly", "Other"]
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            headerIcon(for: activity).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(titleEN(for: activity)).font(.headline).foregroundColor(.white)
                if let date = activity.createdAt {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
    }

    // MARK: Review

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("comment_label")).foregroundColor(.white).font(.subheadline)
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

    // MARK: Icon & title helpers

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
        [
            "swim":"Swim","water":"Water","bike":"Cycling",
            "run":"Run","walk":"Walk","run_walk":"Run/Walk",
            "yoga":"Yoga","strength":"Strength","sauna":"Sauna",
            "fasting":"Fasting","triathlon":"Triathlon"
        ][type]
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

        if s.contains("swim")                   { return "swim" }
        if s.contains("water")                  { return "water" }
        if s.contains("bike") || s.contains("cycl") { return "bike" }
        if s.contains("running") || s == "run"  { return "run" }
        if s.contains("walking") || s == "walk" { return "walk" }
        if s.contains("yoga")                   { return "yoga" }
        if s.contains("strength") || s.contains("gym") { return "strength" }
        if s.contains("sauna")                  { return "sauna" }
        if s.contains("fast") || s.contains("fasting") || s.contains("active") { return "fasting" }
        if s.contains("triathlon")              { return "triathlon" }
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

// MARK: —— ГРАФИКИ ——

private struct NumericChartSectionView: View {
    let title: String
    let unit: String
    let seriesName: String

    let values: [Double]
    let timeOffsets: [Double]?
    let totalMinutes: Int?
    let layer: Int?
    let subLayer: Int?
    let subLayerProgress: String?

    var preferredHeight: CGFloat = 220

    @State private var selectedIndex: Int? = nil
    @State private var showFull = false

    private var vMin: Double { values.min() ?? 0 }
    private var vMax: Double { values.max() ?? 1 }
    private var yDomain: ClosedRange<Double> {
        let pad = max(0.001, (vMax - vMin) * 0.08)
        return (vMin - pad)...(vMax + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
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
        let i = selectedIndex ?? (values.indices.last ?? 0)
        return HStack(spacing: 16) {
            metric("Время", selectedElapsedTimeString() ?? formatDuration(totalMinutes), boldLeft: true)
            Divider().frame(height: 16).background(Color.white.opacity(0.2))
            metric("Слой", layer.map(String.init) ?? "—", highlight: true)
            metric("Подслой", subLayerProgress ?? subLayer.map(String.init) ?? "—", subdued: layer == nil)
            Spacer()
            metric(seriesName, valueString(at: i), highlight: true, unitSuffix: unit)
        }
        .font(.footnote).foregroundColor(.white).padding(.vertical, 4)
    }

    private var chart: some View {
        Chart {
            let pts = makePoints()

            // данные
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [.green.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.green)
            }

            // пунктирные сетки (RuleMark вместо lineStyle у Axis)
            if let first = pts.first?.time, let last = pts.last?.time {
                let total = last.timeIntervalSince(first)
                let xMarks = [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(total * $0) }
                ForEach(xMarks, id: \.self) { d in
                    RuleMark(x: .value("t", d))
                        .foregroundStyle(Color.white.opacity(0.12))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
                }
            }
            let yVals = stride(from: yDomain.lowerBound, through: yDomain.upperBound, by: max( (yDomain.upperBound - yDomain.lowerBound)/4, 0.0001))
            ForEach(Array(yVals), id: \.self) { y in
                RuleMark(y: .value("v", y))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
            }

            // курсор
            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time)).foregroundStyle(Color.white.opacity(0.55))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value))
                    .symbolSize(80).foregroundStyle(.green)
            }
        }
        .chartYScale(domain: yDomain)
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
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisTick().foregroundStyle(Color.white.opacity(0.40))
                AxisValueLabel().foregroundStyle(.white.opacity(0.85)).font(.caption2)
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

    // helpers (numeric)
    private func metric(_ title: String, _ value: String, boldLeft: Bool = false, highlight: Bool = false, subdued: Bool = false, unitSuffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(boldLeft ? .subheadline.bold() : .subheadline).foregroundColor(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.semibold)).foregroundColor(highlight ? .green : (subdued ? .white.opacity(0.6) : .white))
                if let unitSuffix { Text(unitSuffix).font(.caption).foregroundColor(.white.opacity(0.7)) }
            }
        }
    }
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
        return [0,0.25,0.5,0.75,1].map { first.addingTimeInterval(total * Double($0)) }
    }
    private func elapsedText(for date: Date) -> String {
        let pts = makePoints()
        guard let first = pts.first?.time else { return "0:00" }
        let sec = Int(max(0, date.timeIntervalSince(first)))
        return formatElapsed(seconds: sec)
    }
    private func selectedElapsedTimeString() -> String? {
        let pts = makePoints()
        guard let idx = selectedIndex, pts.indices.contains(idx), let first = pts.first?.time else { return nil }
        let sec = Int(max(0, pts[idx].time.timeIntervalSince(first)))
        return formatElapsed(seconds: sec)
    }
    private func formatDuration(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "—" }
        let h = m / 60, mm = m % 60
        return String(format: "%02d:%02d", h, mm)
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

private struct CategoricalChartSectionView: View {
    let title: String
    let seriesName: String
    let indices: [Double]
    let labels: [String]
    let timeOffsets: [Double]?
    let totalMinutes: Int?
    let layer: Int?
    let subLayer: Int?
    let subLayerProgress: String?
    var preferredHeight: CGFloat = 220

    @State private var selectedIndex: Int? = nil
    @State private var showFull = false

    private var yDomain: ClosedRange<Double> {
        (-0.5)...(Double(max(labels.count-1, 0)) + 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
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

            // данные
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.stepCenter)
                    .foregroundStyle(.linearGradient(colors: [.purple.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
            }
            ForEach(pts) { p in
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.stepCenter)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.purple)
            }

            // сетка: вертикальные деления + горизонтали по категориям
            if let first = pts.first?.time, let last = pts.last?.time {
                let total = last.timeIntervalSince(first)
                let xMarks = [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(total * $0) }
                ForEach(xMarks, id: \.self) { d in
                    RuleMark(x: .value("t", d))
                        .foregroundStyle(Color.white.opacity(0.12))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
                }
            }
            ForEach(Array(0..<max(labels.count, 1)), id: \.self) { i in
                RuleMark(y: .value("v", Double(i)))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,3]))
            }

            // курсор
            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time)).foregroundStyle(Color.white.opacity(0.55))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value))
                    .symbolSize(80).foregroundStyle(.purple)
            }
        }
        .chartYScale(domain: yDomain)
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

    // helpers (categorical)
    private func metric(_ title: String, _ value: String, boldLeft: Bool = false, highlight: Bool = false, subdued: Bool = false, unitSuffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(boldLeft ? .subheadline.bold() : .subheadline).foregroundColor(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.semibold)).foregroundColor(highlight ? .green : (subdued ? .white.opacity(0.6) : .white))
                if let unitSuffix { Text(unitSuffix).font(.caption).foregroundColor(.white.opacity(0.7)) }
            }
        }
    }
    private func makePoints() -> [ChartPoint] {
        let start = Date()
        let vals = indices.map { round($0) }
        if let t = timeOffsets, !t.isEmpty {
            let n = min(t.count, vals.count)
            return (0..<n).map { i in ChartPoint(time: start.addingTimeInterval(t[i]), value: vals[i]) }
        } else {
            return vals.enumerated().map { (i, v) in ChartPoint(time: start.addingTimeInterval(Double(i)), value: v) }
        }
    }
    private func xAxisMarks() -> [Date] {
        let pts = makePoints()
        guard let first = pts.first?.time, let last = pts.last?.time, last > first else { return pts.map{$0.time} }
        let total = last.timeIntervalSince(first)
        return [0,0.25,0.5,0.75,1].map { first.addingTimeInterval(total * Double($0)) }
    }
    private func elapsedText(for date: Date) -> String {
        let pts = makePoints()
        guard let first = pts.first?.time else { return "0:00" }
        let sec = Int(max(0, date.timeIntervalSince(first)))
        return formatElapsed(seconds: sec)
    }
    private func selectedElapsedTimeString() -> String? {
        let pts = makePoints()
        guard let idx = selectedIndex, pts.indices.contains(idx), let first = pts.first?.time else { return nil }
        let sec = Int(max(0, pts[idx].time.timeIntervalSince(first)))
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

// MARK: — вспомогательное

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

private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.headline).foregroundColor(.white)
}

private func asDoubleArray(_ any: Any) -> [Double]? {
    if let d = any as? [Double] { return d }
    if let i = any as? [Int]    { return i.map(Double.init) }
    let m = Mirror(reflecting: any)
    if m.displayStyle == .optional, let c = m.children.first { return asDoubleArray(c.value) }
    return nil
}

private extension Array {
    subscript(safe i: Index) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

// ===== DEBUG =====
#if DEBUG
@MainActor func debugListVMSets(_ vm: WorkoutDetailViewModel) {
    print("⚙️ VM series available:")
    let mir = Mirror(reflecting: vm)
    for child in mir.children {
        guard let label = child.label else { continue }
        if let arr = asDoubleArray(child.value), !arr.isEmpty {
            print(" • \(label): \(arr.count) points")
        } else if let urls = child.value as? [URL], !urls.isEmpty {
            print(" • \(label): \(urls.count) urls")
        }
    }
    print(" • timeSeries.count:", vm.timeSeries?.count as Any)
    print(" • preferredDurationMinutes:", vm.preferredDurationMinutes as Any)
    print(" • currentLayerCheckedInt:", vm.currentLayerCheckedInt as Any)
    print(" • currentSubLayerCheckedInt:", vm.currentSubLayerCheckedInt as Any)
    print(" • subLayerProgressText:", vm.subLayerProgressText as Any)
}

private func debugPrintActivity(_ a: Activity) {
    print("""
    === ACTIVITY ===
      id=\(a.id)
      name=\(a.name ?? "nil")
      isCompleted=\(a.isCompleted)
      createdAt=\(String(describing: a.createdAt))
      userEmail=\(a.userEmail ?? "nil")
    """)
}

@MainActor private func debugPrintKnownSeries(_ vm: WorkoutDetailViewModel) {
    let hr = vm.heartRateSeries?.count ?? 0
    let wt = vm.waterTempSeries?.count ?? 0
    let sp = vm.speedSeries?.count ?? 0
    let urls = vm.diagramImageURLs.count
    print("""
    📊📊📊 Known series:
      heartRateSeries.count=\(hr)
      waterTempSeries.count=\(wt)
      speedSeries.count=\(sp)
      diagramImageURLs.count=\(urls)
      timeSeries.count=\(vm.timeSeries?.count ?? 0)
      preferredDurationMinutes=\(vm.preferredDurationMinutes as Any)
      currentLayerCheckedInt=\(vm.currentLayerCheckedInt as Any)
      currentSubLayerCheckedInt=\(vm.currentSubLayerCheckedInt as Any)
      subLayerProgressText=\(vm.subLayerProgressText as Any)
    """)
}

@MainActor private func debugFindYogaPositions(_ vm: WorkoutDetailViewModel) {
    let mir = Mirror(reflecting: vm)
    var found = false
    for ch in mir.children {
        guard let name = ch.label?.lowercased() else { continue }
        if name.contains("pose") || name.contains("position") || name.contains("label") {
            found = true
            if let arr = asDoubleArray(ch.value) {
                print("🧘 positions series candidate '\(name)' — \(arr.count) pts; uniq:", Set(arr.map{Int(round($0))}).sorted())
            } else if let s = ch.value as? [String] {
                print("🧘 position labels '\(name)' —", s)
            }
        }
    }
    if !found { print("🧘 no explicit yoga positions fields in VM — will try step-like inference") }
}
#endif
