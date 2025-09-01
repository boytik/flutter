import SwiftUI

@MainActor

struct ActivityChartsSectionView: View {
    let activity: Activity
    @ObservedObject var vm: WorkoutDetailViewModel
    @Binding var syncEnabled: Bool
    let chartStart: Date
    let totalSeconds: Double

    init(activity: Activity, vm: WorkoutDetailViewModel, syncEnabled: Binding<Bool>, chartStart: Date, totalSeconds: Double) {
        self.activity = activity
        self._vm = ObservedObject(initialValue: vm)
        self._syncEnabled = syncEnabled
        self.chartStart = chartStart
        self.totalSeconds = totalSeconds
    }

    var body: some View {
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
                    preferredHeight: 240,
                    color: .red,
                    start: chartStart,
                    totalSeconds: totalSeconds
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("heart") ||
                $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
            }) {
                adSectionTitle("Диаграмма частоты сердцебиения")
                ADFixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

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
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 220,
                    color: cfg.color,
                    start: chartStart,
                    totalSeconds: totalSeconds
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
                    preferredHeight: 220,
                    color: cfg.color,
                    start: chartStart,
                    totalSeconds: totalSeconds
                )
            }
        }
    }
}
