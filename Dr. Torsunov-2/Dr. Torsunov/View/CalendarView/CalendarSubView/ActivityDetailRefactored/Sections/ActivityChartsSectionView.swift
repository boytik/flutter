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
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("heart") ||
                $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
            }) {
                adSectionTitle("Диаграмма частоты сердцебиения")
                ADFixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            // ВТОРОЙ ГРАФИК
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

        let transSample = vm.flutterLayerTransitions(isFullScreen: true).prefix(5)
            .map { ($0.timeSeconds, $0.layer, $0.subLayer, $0.isFirstLayer) }
        print("flutter transitions sample =", transSample)
    }
}
