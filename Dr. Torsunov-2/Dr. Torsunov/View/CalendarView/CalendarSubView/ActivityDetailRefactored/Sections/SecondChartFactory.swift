import SwiftUI

@MainActor

enum SecondChart {
    struct NumericCfg {
        public let title, unit, seriesName: String
        public let values: [Double]
        public let color: Color
        init(title: String, unit: String, seriesName: String, values: [Double], color: Color) {
            self.title = title; self.unit = unit; self.seriesName = seriesName; self.values = values; self.color = color
        }
    }
    struct CategoricalCfg {
        public let title, seriesName: String
        public let indices: [Double]
        public let labels: [String]
        public let color: Color
        init(title: String, seriesName: String, indices: [Double], labels: [String], color: Color) {
            self.title = title; self.seriesName = seriesName; self.indices = indices; self.labels = labels; self.color = color
        }
    }
    case numeric(NumericCfg)
    case categorical(CategoricalCfg)
    case none
}

@MainActor

struct SecondChartFactory {
    @MainActor static func choice(for activity: Activity, vm: WorkoutDetailViewModel) -> SecondChart {
        let base = ((activity.name ?? "") + " " + (activity.description ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let t = canonicalType(inferType(from: base))

        if ["yoga", "meditation"].contains(t) {
            if !vm.yogaPoseIndices.isEmpty, !vm.yogaPoseLabels.isEmpty {
                return .categorical(.init(title: "Диаграмма позиций йоги",
                                          seriesName: "Position",
                                          indices: vm.yogaPoseIndices.map { round($0) },
                                          labels: vm.yogaPoseLabels,
                                          color: .purple))
            }
            if let (idx, labels) = findYogaPositionsSoft(in: vm) {
                return .categorical(.init(title: "Диаграмма позиций йоги",
                                          seriesName: "Position",
                                          indices: idx,
                                          labels: labels,
                                          color: .purple))
            }
            if let v = vm.speedSeries, !v.isEmpty {
                return .numeric(.init(title: "Скорость",
                                      unit: "km/h",
                                      seriesName: "Скорость",
                                      values: v,
                                      color: .pink))
            }
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды",
                                      unit: "°C",
                                      seriesName: "Температура воды",
                                      values: v,
                                      color: .blue))
            }
            return .none
        }

        if ["run", "walk", "run_walk", "bike"].contains(t) {
            if let v = vm.speedSeries, !v.isEmpty {
                return .numeric(.init(title: "Скорость",
                                      unit: "km/h",
                                      seriesName: "Скорость",
                                      values: v,
                                      color: .pink))
            }
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды",
                                      unit: "°C",
                                      seriesName: "Температура воды",
                                      values: v,
                                      color: .blue))
            }
            return .none
        }

        if ["water", "swim"].contains(t) {
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды",
                                      unit: "°C",
                                      seriesName: "Температура воды",
                                      values: v,
                                      color: .blue))
            }
            return .none
        }

        if ["sauna"].contains(t) {
            if let v = vm.waterTempSeries, !v.isEmpty {
                return .numeric(.init(title: "Диаграмма температуры воды",
                                      unit: "°C",
                                      seriesName: "Температура воды",
                                      values: v,
                                      color: .yellow))
            }
            return .none
        }

        if let v = vm.speedSeries, !v.isEmpty {
            return .numeric(.init(title: "Скорость",
                                  unit: "km/h",
                                  seriesName: "Скорость",
                                  values: v,
                                  color: .pink))
        }
        return .none
    }
}
