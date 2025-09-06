// ⬇️ ВСТАВЬ ЭТОТ ФАЙЛ ЦЕЛИКОМ (ActivityChartsSectionView.swift)

import SwiftUI

@MainActor
struct ActivityChartsSectionView: View {
    let activity: Activity
    @ObservedObject var vm: WorkoutDetailViewModel
    @Binding var syncEnabled: Bool
    let chartStart: Date
    let totalSeconds: Double

    init(activity: Activity,
         vm: WorkoutDetailViewModel,
         syncEnabled: Binding<Bool>,
         chartStart: Date,
         totalSeconds: Double)
    {
        self.activity = activity
        self._vm = ObservedObject(initialValue: vm)
        self._syncEnabled = syncEnabled
        self.chartStart = chartStart
        self.totalSeconds = totalSeconds
    }

    // Flutter-подобная длительность: максимум из totalSeconds, последнего offset и минут
    private var effectiveTotalSeconds: Double {
        let minutes = Double(vm.preferredDurationMinutes ?? 0) * 60.0
        let lastOffset = vm.timeSeries?.last ?? 0
        let candidates = [totalSeconds, minutes, lastOffset].filter { $0 > 0 }
        return max(60, candidates.max() ?? 0)
    }

    var body: some View {
        let T = effectiveTotalSeconds
        VStack(alignment: .leading, spacing: 18) {
            if vm.isLoading { ProgressView().tint(.white) }
            if let err = vm.errorMessage, !err.isEmpty {
                Text(err).font(.footnote).foregroundColor(.gray)
            }

            Toggle("Синхронизация", isOn: $syncEnabled)
                .toggleStyle(.switch)
                .tint(.green)
                .foregroundColor(.white)

            // ⬇️ ПРОГРЕСС ПОДСЛОЯ (как во Flutter: N/M)
            if let subProgress = vm.subLayerProgressText, !subProgress.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                    Text(subProgress).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // ПУЛЬС
            if let hr = vm.heartRateSeries, !hr.isEmpty {
                NumericChartSectionView(
                    title: "Диаграмма частоты сердцебиения",
                    unit: "bpm",
                    seriesName: "Пульс",
                    values: hr,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    preferredHeight: 240,
                    color: .red,
                    start: chartStart,
                    totalSeconds: T,
                    vm: vm
                )
                // ⬇️ НАКИДЫВАЕМ МАРКЕРЫ ПОДСЛОЁВ ПОВЕРХ ЛЮБОГО ГРАФИКА
                .modifier(SublayerMarkersOverlay(vm: vm, totalSeconds: T))
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("heart") ||
                $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
            }) {
                adSectionTitle("Диаграмма частоты сердцебиения")
                ADFixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            // ВТОРОЙ ГРАФИК (числовой/категориальный) — без разницы, маркеры положим сверху
            switch SecondChartFactory.choice(for: activity, vm: vm) {
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
                    preferredHeight: 220,
                    color: cfg.color,
                    start: chartStart,
                    totalSeconds: T,
                    vm: vm
                )
                .modifier(SublayerMarkersOverlay(vm: vm, totalSeconds: T))

            case .categorical(let cfg):
                CategoricalChartSectionView(
                    title: cfg.title,
                    seriesName: cfg.seriesName,
                    indices: cfg.indices,
                    labels: cfg.labels,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    preferredHeight: 220,
                    color: cfg.color,
                    start: chartStart,
                    totalSeconds: T,
                    vm: vm
                )
                .modifier(SublayerMarkersOverlay(vm: vm, totalSeconds: T))
            }
        }
        .onAppear { debugLog(tag: "onAppear") }
        .onChange(of: vm.metrics, perform: { _ in debugLog(tag: "onChange metrics") })
        .onChange(of: vm.heartRateSeries, perform: { _ in debugLog(tag: "onChange heartRateSeries") })
        .onChange(of: vm.timeSeries, perform: { _ in debugLog(tag: "onChange timeSeries") })
        .onChange(of: vm.preferredDurationMinutes, perform: { _ in debugLog(tag: "onChange preferredMinutes") })
    }

    // MARK: Debug
    private func debugLog(tag: String) {
        print("=== Charts debug [\(tag)] ===")
        print("chartStart =", chartStart)
        print("incoming totalSeconds =", totalSeconds)
        print("preferredMinutes =", vm.preferredDurationMinutes ?? -1,
              "→ seconds =", Double(vm.preferredDurationMinutes ?? 0) * 60.0)
        if let ts = vm.timeSeries {
            let first = Array(ts.prefix(5)).map { String(format: "%.1f", $0) }
            let last  = Array(ts.suffix(5)).map { String(format: "%.1f", $0) }
            print("timeSeries count =", ts.count, "first =", first, "last =", last, "lastOffset =", ts.last ?? -1)
        } else {
            print("timeSeries = nil")
        }
        print("effectiveTotalSeconds =", effectiveTotalSeconds)

        // ⬇️ добавлено: лог по слоям/подслоям
        let lCount = vm.layerSeriesInt?.count ?? 0
        let sCount = vm.subLayerSeriesInt?.count ?? 0
        let rows   = vm.metricObjectsArray?.count ?? 0
        print("🧩 counts: rows=\(rows) layers=\(lCount) sublayers=\(sCount)")

        let transSample = vm.flutterLayerTransitions(isFullScreen: true).prefix(5)
            .map { ($0.timeSeconds, $0.layer, $0.subLayer, $0.isFirstLayer) }
        print("flutter transitions sample =", transSample)
    }
}

// MARK: - Overlay с маркерами подслоёв: совпадает с Flutter-треком (layer, subLayer)
private struct SublayerMarkersOverlay: ViewModifier {
    @ObservedObject var vm: WorkoutDetailViewModel
    let totalSeconds: Double

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height: CGFloat = 22

                    Canvas { ctx, size in
                        // Берём Flutter-подобные переходы подслоёв
                        let marks = vm.flutterLayerTransitions(isFullScreen: true)
                        guard !marks.isEmpty else { return }

                        // Базовая линия
                        var base = Path()
                        base.move(to: CGPoint(x: 0, y: size.height - 1))
                        base.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                        ctx.stroke(base, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

                        func xFor(seconds t: Double) -> CGFloat {
                            guard totalSeconds > 0 else { return 0 }
                            let x01 = max(0, min(1, t / totalSeconds))
                            return CGFloat(x01) * size.width
                        }

                        for m in marks {
                            // m.timeSeconds — уже в секундах от старта графика
                            let x = xFor(seconds: m.timeSeconds)

                            // Вертикальная риска подслоя
                            var tick = Path()
                            tick.move(to: CGPoint(x: x, y: 0))
                            tick.addLine(to: CGPoint(x: x, y: size.height - 1))
                            ctx.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

                            // Подпись: L.S  (можно заменить на имя подслоя, если есть маппер)
                            let label = "\(m.layer).\(m.subLayer)"
                            let text = Text(label)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                            ctx.draw(text, at: CGPoint(x: x + 4, y: 2), anchor: .topLeading)
                        }
                    }
                    .frame(width: width, height: height)
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
                    .accessibilityLabel("Подслои")
                    .accessibilityHint("Переходы подслоёв по времени")
                }
            }
    }
}
