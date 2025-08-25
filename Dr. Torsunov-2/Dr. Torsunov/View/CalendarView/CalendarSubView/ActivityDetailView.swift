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
                    InspectorPhotosView(activity: activity)
                        .background(Color.clear)

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
        .task { await vm.load()
#if DEBUG
debugDumpVM(vm) // если добавлял мой VMIntrospectionDebug.swift
print("durationMinutesInt:", vm.durationMinutesInt as Any)
print("currentLayerCheckedInt:", vm.currentLayerCheckedInt as Any)
print("currentSubLayerCheckedInt:", vm.currentSubLayerCheckedInt as Any)
print("subLayerProgressText:", vm.subLayerProgressText as Any)
#endif

        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.2))
                Text("✅").font(.title2)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name ?? "Activity")
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

            // 1) Пульс
            if let hr = vm.heartRateSeries, !hr.isEmpty {
                ChartSectionView(
                    title: "Диаграмма частоты сердцебиения",
                    unit: "bpm",
                    seriesName: "ЧСС",
                    values: hr,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.durationMinutesInt,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 240
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("heart")
                || $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
            }) {
                sectionTitle("Диаграмма частоты сердцебиения")
                FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            // 2) Температура воды / позы
            if let wt = vm.waterTempSeries, !wt.isEmpty {
                ChartSectionView(
                    title: "Диаграмма температуры воды",
                    unit: "°C",
                    seriesName: "Температура воды",
                    values: wt,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.durationMinutesInt,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 220
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("temp")
                || $0.absoluteString.localizedCaseInsensitiveContains("water")
            }) {
                sectionTitle("Диаграмма температуры воды")
                FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            // 3) Скорость (если есть)
            if let spd = vm.speedSeries, !spd.isEmpty {
                ChartSectionView(
                    title: "Скорость, км/ч",
                    unit: "km/h",
                    seriesName: "Скорость",
                    values: spd,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.durationMinutesInt,
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
}

// === Локальные хелперы для выбора фото (user) ===
private struct PhotoPickRow: View {
    @Binding var beforeImage: UIImage?
    @Binding var afterImage: UIImage?
    let onPickBefore: () -> Void
    let onPickAfter: () -> Void
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 18
    var spacing: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            PhotoPickTileSimple(title: L("photo_before"), image: beforeImage, action: onPickBefore, aspect: aspect, corner: corner, accent: Color.white.opacity(0.14))
            PhotoPickTileSimple(title: L("photo_after"),  image: afterImage,  action: onPickAfter,  aspect: aspect, corner: corner, accent: .green)
        }
    }
}

private struct PhotoPickTileSimple: View {
    let title: String
    let image: UIImage?
    let action: () -> Void
    var aspect: CGFloat
    var corner: CGFloat
    var accent: Color

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill().clipped().compositingGroup()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28, weight: .semibold))
                        Text("Выберите фото").font(.footnote).foregroundColor(.white.opacity(0.7))
                    }.foregroundColor(.white.opacity(0.6))
                }
                HStack {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(8)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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

// === Общий компонент графика с разворотом и метриками ===
private struct ChartSectionView: View {
    let title: String
    let unit: String
    let seriesName: String

    let values: [Double]
    /// секунды от старта (если окажется unix, замените на Date(timeIntervalSince1970:))
    let timeOffsets: [Double]?

    /// Время тренировки общее (мин)
    let totalMinutes: Int?

    /// слой/подслой (и формат 6/7)
    let layer: Int?
    let subLayer: Int?
    let subLayerProgress: String?

    var preferredHeight: CGFloat = 220

    @State private var selectedIndex: Int? = nil
    @State private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)

            metricsHeader

            ZStack(alignment: .topTrailing) {
                chart.frame(height: preferredHeight)

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

    private var metricsHeader: some View {
        let i = selectedIndex ?? (values.indices.last ?? 0)
        let val = valueString(at: i)

        return HStack(spacing: 16) {
            metric("Время", (totalMinutes != nil ? "\(totalMinutes!)  мин" : "—"), boldLeft: true)
            Divider().frame(height: 16).background(Color.white.opacity(0.2))
            metric("Слой", layer.map(String.init) ?? "—", highlight: true)
            metric("Подслой", subLayerProgress ?? subLayer.map(String.init) ?? "—", subdued: layer == nil)
            Spacer()
            metric(seriesName, val, highlight: true, unitSuffix: unit)
        }
        .font(.footnote)
        .foregroundColor(.white)
        .padding(.vertical, 4)
    }

    private var chart: some View {
        Chart {
            let pts = makePoints()
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [.green.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
            }
            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value)).symbolSize(80)
            }
        }
        .chartScrollableAxes(.horizontal)
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

    // Helpers
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
            let cnt = min(t.count, values.count)
            return (0..<cnt).map { i in ChartPoint(time: start.addingTimeInterval(t[i]), value: values[i]) }
        } else {
            return values.enumerated().map { (i, v) in ChartPoint(time: start.addingTimeInterval(Double(i)), value: v) }
        }
    }

    private func valueString(at index: Int) -> String {
        guard index < values.count else { return "—" }
        let v = values[index]
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
}

private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.headline).foregroundColor(.white)
}
